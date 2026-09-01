import XCTest
@testable import Aegis

final class RiftRefreshCoordinatorTests: XCTestCase {
    func testStrongestPendingRequestIsDeferredAndRunsAfterActiveSequence() {
        let scheduler = TestRiftRefreshScheduler()
        var calls: [(RiftRefreshScope, String, UInt64)] = []
        var finishes: [() -> Void] = []
        var activeActionCount = 0
        var maxActiveActionCount = 0
        let coordinator = RiftRefreshCoordinator(
            scheduler: scheduler,
            coalesceDelay: 0,
            debounceInterval: 0.1
        ) { scope, source, generation, finish in
            calls.append((scope, source, generation))
            activeActionCount += 1
            maxActiveActionCount = max(maxActiveActionCount, activeActionCount)
            finishes.append {
                activeActionCount -= 1
                finish()
            }
        }

        coordinator.request(scope: .windowsOnly, source: "subscription")
        scheduler.advance(to: 0)
        XCTAssertEqual(calls.map(\.0), [.windowsOnly])

        // Both requests arrive while the first sequence is active. The weaker
        // request is merged, the stronger one wins, and neither is dropped.
        coordinator.request(scope: .windowsOnly, source: "fallback")
        coordinator.request(scope: .all, source: "space")
        XCTAssertEqual(activeActionCount, 1)
        XCTAssertEqual(maxActiveActionCount, 1)
        finishes[0]()
        scheduler.advance(to: 0.099)
        XCTAssertEqual(calls.count, 1)
        scheduler.advance(to: 0.1)
        XCTAssertEqual(calls.map(\.0), [.windowsOnly, .all])
        XCTAssertEqual(calls[1].1, "space")
        XCTAssertEqual(calls[1].2, calls[0].2 + 1)
        XCTAssertEqual(maxActiveActionCount, 1)
    }

    func testRequestInsideDebounceWindowIsNotDropped() {
        let scheduler = TestRiftRefreshScheduler()
        var calls: [RiftRefreshScope] = []
        var finishes: [() -> Void] = []
        let coordinator = RiftRefreshCoordinator(
            scheduler: scheduler,
            coalesceDelay: 0,
            debounceInterval: 0.1
        ) { scope, _, _, finish in
            calls.append(scope)
            finishes.append(finish)
        }

        coordinator.request(scope: .all, source: "startup")
        scheduler.advance(to: 0)
        finishes[0]()

        scheduler.advance(to: 0.05)
        coordinator.request(scope: .windowsOnly, source: "subscription")
        scheduler.advance(to: 0.099)
        XCTAssertEqual(calls, [.all])
        scheduler.advance(to: 0.1)
        XCTAssertEqual(calls, [.all, .windowsOnly])
    }

    func testStoppingInvalidatesActiveGeneration() {
        let scheduler = TestRiftRefreshScheduler()
        var generation: UInt64?
        var finish: (() -> Void)?
        let coordinator = RiftRefreshCoordinator(scheduler: scheduler, coalesceDelay: 0) {
            _, _, receivedGeneration, receivedFinish in
            generation = receivedGeneration
            finish = receivedFinish
        }

        coordinator.request(scope: .all)
        scheduler.advance(to: 0)
        XCTAssertTrue(coordinator.isCurrent(generation!))
        coordinator.stop()
        XCTAssertFalse(coordinator.isCurrent(generation!))
        finish?()
        XCTAssertTrue(generation != nil)
    }
}

final class RiftActiveSpaceRetryPolicyTests: XCTestCase {
    func testNewTransitionAndStopInvalidateOlderRetries() {
        let tracker = RiftTransitionGenerationTracker()
        let first = tracker.begin()
        let second = tracker.begin()

        XCTAssertFalse(tracker.isCurrent(first))
        XCTAssertTrue(tracker.isCurrent(second))
        tracker.stop()
        XCTAssertFalse(tracker.isCurrent(first))
        XCTAssertFalse(tracker.isCurrent(second))
    }

    func testAllRefreshesRunDisplaysBeforeWorkspaces() {
        XCTAssertEqual(
            RiftRefreshOperationPlan.operations(for: .all),
            [.displays, .workspaces]
        )
    }

    func testRetryStopsWhenDisplaySnapshotChanges() {
        let baseline = RiftDisplayChangeSnapshot(
            display: makeRiftDisplay(space: 10, isActiveSpace: true)
        )
        let changed = RiftDisplayChangeSnapshot(
            display: makeRiftDisplay(space: 11, isActiveSpace: true)
        )

        XCTAssertFalse(RiftActiveSpaceRetryPolicy.shouldRetry(
            baseline: [1: baseline], current: [1: changed]
        ))
    }

    func testRetryContinuesForUnchangedOrUnknownSnapshot() {
        let baseline = RiftDisplayChangeSnapshot(
            display: makeRiftDisplay(space: 10, isActiveSpace: true)
        )
        let unknown = RiftDisplayChangeSnapshot(
            display: makeRiftDisplay(
                screenId: 0,
                uuid: "",
                space: nil,
                isActiveSpace: false,
                activeSpaceIds: [],
                inactiveSpaceIds: []
            )
        )

        XCTAssertTrue(RiftActiveSpaceRetryPolicy.shouldRetry(
            baseline: [1: baseline], current: [1: baseline]
        ))
        XCTAssertTrue(RiftActiveSpaceRetryPolicy.shouldRetry(
            baseline: [1: baseline], current: [0: unknown]
        ))
    }

    private func makeRiftDisplay(
        screenId: UInt32 = 1,
        uuid: String = "display",
        space: UInt64?,
        isActiveSpace: Bool,
        activeSpaceIds: [UInt64] = [10],
        inactiveSpaceIds: [UInt64] = [11]
    ) -> RiftDisplay {
        RiftDisplay(
            uuid: uuid,
            name: nil,
            screenId: screenId,
            frame: RiftFrame(
                origin: RiftPoint(x: 0, y: 0),
                size: RiftSize(width: 1, height: 1)
            ),
            space: space,
            isActiveSpace: isActiveSpace,
            isActiveContext: true,
            activeSpaceIds: activeSpaceIds,
            inactiveSpaceIds: inactiveSpaceIds
        )
    }
}

private final class TestRiftRefreshScheduler: RiftRefreshScheduler {
    private final class Entry {
        let due: TimeInterval
        let action: () -> Void
        var cancelled = false

        init(due: TimeInterval, action: @escaping () -> Void) {
            self.due = due
            self.action = action
        }
    }

    private(set) var now: TimeInterval = 0
    private var entries: [Entry] = []

    func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) -> RiftRefreshScheduledTask {
        let entry = Entry(due: now + max(0, delay), action: action)
        entries.append(entry)
        return RiftRefreshScheduledTask { entry.cancelled = true }
    }

    func advance(to target: TimeInterval) {
        now = target
        while let index = entries.indices
            .filter({ entries[$0].due <= now })
            .min(by: { entries[$0].due < entries[$1].due }) {
            let entry = entries.remove(at: index)
            if !entry.cancelled {
                entry.action()
            }
        }
    }
}
