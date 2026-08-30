import XCTest
@testable import Aegis

final class AppSwitcherRecoveryPolicyTests: XCTestCase {
    func testRecoveryTimingsAreBounded() {
        XCTAssertEqual(AppSwitcherRecoveryPolicy.permissionPollInterval, 2)
        XCTAssertEqual(AppSwitcherRecoveryPolicy.permissionPollDuration, 60)
        XCTAssertEqual(AppSwitcherRecoveryPolicy.tapRecoveryDelays, [1, 2, 4])
        XCTAssertEqual(AppSwitcherRecoveryCoordinator.watchdogInterval, 5)
    }
}

@MainActor
final class FakeAppSwitcherRuntime: AppSwitcherRecoveryRuntime {
    var eventTapIsInstalled = false
    var eventTapIsUsable = false
    var trusted = false
    var createResult = true
    var reenableResult = true
    var prompts: [Bool] = []
    var createCount = 0
    var teardownCount = 0

    func accessibilityTrusted(prompt: Bool) -> Bool {
        prompts.append(prompt)
        return trusted
    }

    func createEventTap() -> Bool {
        createCount += 1
        eventTapIsInstalled = createResult
        eventTapIsUsable = createResult
        return createResult
    }

    func reenableEventTap() -> Bool {
        eventTapIsUsable = reenableResult
        return reenableResult
    }

    func teardownEventTap() {
        teardownCount += 1
        eventTapIsInstalled = false
        eventTapIsUsable = false
    }
}

@MainActor
final class RecoveryTestScheduler {
    struct Entry {
        let delay: TimeInterval
        let task: DispatchWorkItem
    }

    var entries: [Entry] = []

    func schedule(delay: TimeInterval, action: @escaping () -> Void) -> DispatchWorkItem {
        let task = DispatchWorkItem(block: action)
        entries.append(Entry(delay: delay, task: task))
        return task
    }

    func runNext() {
        guard !entries.isEmpty else { return }
        let entry = entries.removeFirst()
        if !entry.task.isCancelled {
            entry.task.perform()
        }
    }
}

@MainActor
final class AppSwitcherRecoveryCoordinatorTests: XCTestCase {
    func testDeniedPermissionPollsThenCreatesTap() {
        let runtime = FakeAppSwitcherRuntime()
        let scheduler = RecoveryTestScheduler()
        let coordinator = AppSwitcherRecoveryCoordinator(
            runtime: runtime,
            schedule: { delay, action in scheduler.schedule(delay: delay, action: action) }
        )

        coordinator.start(enabled: true)
        XCTAssertEqual(coordinator.health, .permissionRequired)
        XCTAssertEqual(runtime.prompts, [false, true])
        XCTAssertEqual(scheduler.entries.first?.delay, 2)

        runtime.trusted = true
        scheduler.runNext()
        XCTAssertEqual(coordinator.health, .running)
        XCTAssertEqual(runtime.prompts, [false, true, false, false])
        XCTAssertEqual(runtime.createCount, 1)
    }

    func testTapDisabledRecreatesAndStopCancelsWork() {
        let runtime = FakeAppSwitcherRuntime()
        runtime.trusted = true
        runtime.eventTapIsInstalled = true
        runtime.eventTapIsUsable = true
        runtime.reenableResult = false
        let scheduler = RecoveryTestScheduler()
        let coordinator = AppSwitcherRecoveryCoordinator(
            runtime: runtime,
            schedule: { delay, action in scheduler.schedule(delay: delay, action: action) }
        )

        coordinator.tapDisabled(enabled: true)
        XCTAssertEqual(coordinator.health, .recovering)
        XCTAssertEqual(runtime.teardownCount, 1)
        XCTAssertEqual(scheduler.entries.map(\.delay), [1, 2, 4, 4.05])

        coordinator.stop()
        XCTAssertEqual(coordinator.health, .disabled)
        XCTAssertTrue(scheduler.entries.allSatisfy(\.task.isCancelled))
    }

    func testWatchdogRecoversSilentDeadTap() {
        let runtime = FakeAppSwitcherRuntime()
        runtime.trusted = true
        let scheduler = RecoveryTestScheduler()
        let coordinator = AppSwitcherRecoveryCoordinator(
            runtime: runtime,
            schedule: { delay, action in scheduler.schedule(delay: delay, action: action) }
        )

        coordinator.start(enabled: true)
        runtime.eventTapIsUsable = false
        scheduler.runNext()
        XCTAssertEqual(coordinator.health, .recovering)
        XCTAssertEqual(runtime.teardownCount, 1)
    }

    func testStartTearsDownStaleTapBeforeCreatingReplacement() {
        let runtime = FakeAppSwitcherRuntime()
        runtime.trusted = true
        runtime.eventTapIsInstalled = true
        let coordinator = AppSwitcherRecoveryCoordinator(runtime: runtime)

        coordinator.start(enabled: true)

        XCTAssertEqual(runtime.teardownCount, 1)
        XCTAssertEqual(runtime.createCount, 1)
        XCTAssertEqual(coordinator.health, .running)
    }

    func testFailedAfterAllRecreationAttempts() {
        let runtime = FakeAppSwitcherRuntime()
        runtime.trusted = true
        runtime.createResult = false
        let scheduler = RecoveryTestScheduler()
        let coordinator = AppSwitcherRecoveryCoordinator(
            runtime: runtime,
            schedule: { delay, action in scheduler.schedule(delay: delay, action: action) }
        )

        coordinator.start(enabled: true)
        scheduler.runNext()
        scheduler.runNext()
        scheduler.runNext()
        scheduler.runNext()
        XCTAssertEqual(coordinator.health, .failed)
    }

    func testPermissionPollingExpiresWithoutChangingPermissionState() {
        let runtime = FakeAppSwitcherRuntime()
        let scheduler = RecoveryTestScheduler()
        var now = Date(timeIntervalSince1970: 0)
        let coordinator = AppSwitcherRecoveryCoordinator(
            runtime: runtime,
            schedule: { delay, action in scheduler.schedule(delay: delay, action: action) },
            clock: { now }
        )

        coordinator.start(enabled: true)
        scheduler.runNext()
        now = now.addingTimeInterval(61)
        scheduler.runNext()

        XCTAssertEqual(coordinator.health, .permissionRequired)
        XCTAssertTrue(scheduler.entries.isEmpty)
    }
}
