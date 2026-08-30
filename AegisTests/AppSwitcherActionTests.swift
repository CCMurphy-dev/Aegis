import AppKit
import CoreGraphics
import XCTest
@testable import Aegis

final class AppSwitcherActionKeyPolicyTests: XCTestCase {
    func testPendingActivationQueuesEveryCmdTabCycleInOrder() {
        var policy = AppSwitcherPendingCyclePolicy()
        policy.enqueue(reverse: false)
        policy.enqueue(reverse: false)
        policy.enqueue(reverse: true)

        XCTAssertEqual(policy.applying(to: 1, windowCount: 5), 2)
        XCTAssertEqual(policy.applying(to: 1, windowCount: 5), 1)
    }

    func testCommandReleaseDefersUntilWindowActionSettles() {
        var policy = AppSwitcherDeferredConfirmation()

        XCTAssertFalse(policy.commandReleased(actionInFlight: true))
        XCTAssertTrue(policy.actionSettled())
        XCTAssertFalse(policy.actionSettled())

        XCTAssertTrue(policy.commandReleased(actionInFlight: false))
        XCTAssertFalse(policy.actionSettled())
    }

    func testActionModeMapsExactCmdWAndCmdQ() {
        XCTAssertEqual(AppSwitcherActionKeyPolicy.decision(for: AppSwitcherActionKeyPolicy.wKeyCode, flags: [.maskCommand], mode: .actions, isCommandMode: false, isAutorepeat: false), .perform(.close))
        XCTAssertEqual(AppSwitcherActionKeyPolicy.decision(for: AppSwitcherActionKeyPolicy.qKeyCode, flags: [.maskCommand], mode: .actions, isCommandMode: false, isAutorepeat: false), .perform(.quit))
    }

    func testActionModeUsesLayoutAwareCharacters() {
        XCTAssertEqual(
            AppSwitcherActionKeyPolicy.decision(
                for: 0,
                characters: "w",
                flags: [.maskCommand],
                mode: .actions,
                isCommandMode: false,
                isAutorepeat: false
            ),
            .perform(.close)
        )
        XCTAssertEqual(
            AppSwitcherActionKeyPolicy.decision(
                for: 0,
                characters: "Q",
                flags: [.maskCommand],
                mode: .actions,
                isCommandMode: false,
                isAutorepeat: false
            ),
            .perform(.quit)
        )
        XCTAssertEqual(
            AppSwitcherActionKeyPolicy.decision(
                for: AppSwitcherActionKeyPolicy.wKeyCode,
                characters: "z",
                flags: [.maskCommand],
                mode: .actions,
                isCommandMode: false,
                isAutorepeat: false
            ),
            .consume
        )
    }

    func testCommandPaletteUsesLayoutAwareColon() {
        XCTAssertEqual(
            AppSwitcherActionKeyPolicy.decision(
                for: 0,
                characters: ":",
                flags: [.maskCommand, .maskShift],
                mode: .actions,
                isCommandMode: false,
                isAutorepeat: false
            ),
            .enterCommandPalette
        )
        XCTAssertEqual(
            AppSwitcherActionKeyPolicy.decision(
                for: AppSwitcherActionKeyPolicy.semicolonKeyCode,
                characters: "+",
                flags: [.maskCommand, .maskShift],
                mode: .actions,
                isCommandMode: false,
                isAutorepeat: false
            ),
            .consume
        )
    }

    func testModifiedActionsAreConsumed() {
        for flags: CGEventFlags in [[.maskCommand, .maskShift], [.maskCommand, .maskAlternate], [.maskCommand, .maskControl]] {
            XCTAssertEqual(AppSwitcherActionKeyPolicy.decision(for: AppSwitcherActionKeyPolicy.wKeyCode, flags: flags, mode: .actions, isCommandMode: false, isAutorepeat: false), .consume)
        }
    }

    func testAutorepeatedActionsAreConsumed() {
        for keyCode in [AppSwitcherActionKeyPolicy.wKeyCode, AppSwitcherActionKeyPolicy.qKeyCode] {
            XCTAssertEqual(AppSwitcherActionKeyPolicy.decision(for: keyCode, flags: [.maskCommand], mode: .actions, isCommandMode: false, isAutorepeat: true), .consume)
        }
    }

    func testPendingActivationConsumesActionKeysWithoutPerformingThem() {
        XCTAssertFalse(AppSwitcherActivationPolicy.shouldHandleActionKeys(
            isSwitcherActive: false,
            isActivationPending: false
        ))
        XCTAssertTrue(AppSwitcherActivationPolicy.shouldHandleActionKeys(
            isSwitcherActive: false,
            isActivationPending: true
        ))

        XCTAssertTrue(AppSwitcherActivationPolicy.shouldBeginActivation(
            isSwitcherActive: false,
            isActivationPending: false
        ))
        XCTAssertFalse(AppSwitcherActivationPolicy.shouldBeginActivation(
            isSwitcherActive: true,
            isActivationPending: false
        ))
        XCTAssertFalse(AppSwitcherActivationPolicy.shouldBeginActivation(
            isSwitcherActive: false,
            isActivationPending: true
        ))

        for keyCode in [AppSwitcherActionKeyPolicy.wKeyCode, AppSwitcherActionKeyPolicy.qKeyCode] {
            XCTAssertEqual(
                AppSwitcherActionKeyPolicy.decision(
                    for: keyCode,
                    flags: [.maskCommand],
                    mode: .actions,
                    isCommandMode: false,
                    isAutorepeat: false,
                    isActivationPending: true
                ),
                .consume
            )
            XCTAssertEqual(
                AppSwitcherActionKeyPolicy.decision(
                    for: keyCode,
                    flags: [.maskCommand],
                    mode: .actions,
                    isCommandMode: false,
                    isAutorepeat: false
                ),
                .perform(keyCode == AppSwitcherActionKeyPolicy.wKeyCode ? .close : .quit)
            )
        }
        XCTAssertEqual(
            AppSwitcherActionKeyPolicy.decision(
                for: AppSwitcherActionKeyPolicy.wKeyCode,
                flags: [.maskCommand],
                mode: .filter,
                isCommandMode: false,
                isAutorepeat: false,
                isActivationPending: true
            ),
            .passThrough
        )
    }

    func testColonOpensCommandsAndCommandsKeepTyping() {
        XCTAssertEqual(AppSwitcherActionKeyPolicy.decision(for: AppSwitcherActionKeyPolicy.semicolonKeyCode, flags: [.maskCommand, .maskShift], mode: .actions, isCommandMode: false, isAutorepeat: false), .enterCommandPalette)
        XCTAssertEqual(AppSwitcherActionKeyPolicy.decision(for: AppSwitcherActionKeyPolicy.wKeyCode, flags: [.maskCommand], mode: .actions, isCommandMode: true, isAutorepeat: false), .passThrough)
    }

    func testFilterModePassesThroughAndActionModeConsumesOtherPrintableKeys() {
        XCTAssertEqual(AppSwitcherActionKeyPolicy.decision(for: 0, flags: [.maskCommand], mode: .filter, isCommandMode: false, isAutorepeat: false), .passThrough)
        XCTAssertEqual(AppSwitcherActionKeyPolicy.decision(for: 0, flags: [.maskCommand], mode: .actions, isCommandMode: false, isAutorepeat: false), .consume)
    }

    func testActionModeConsumesAllPrintablePunctuation() {
        for keyCode: Int64 in [24, 33, 30, 39, 42, 50] {
            XCTAssertTrue(AppSwitcherActionKeyPolicy.isPrintableKey(keyCode))
            XCTAssertEqual(AppSwitcherActionKeyPolicy.decision(for: keyCode, flags: [.maskCommand], mode: .actions, isCommandMode: false, isAutorepeat: false), .consume)
        }
    }

    func testActionModeConsumesPrintableCharactersOutsideANSIKeyCodes() {
        for keyCode: Int64 in [93, 94] {
            XCTAssertEqual(
                AppSwitcherActionKeyPolicy.decision(
                    for: keyCode,
                    characters: "¥",
                    flags: [.maskCommand],
                    mode: .actions,
                    isCommandMode: false,
                    isAutorepeat: false
                ),
                .consume
            )
        }
    }

    func testCloseCommandsTargetOneWindow() {
        XCTAssertEqual(WindowManagerCloseCommand.rift(42).arguments, ["execute", "window", "close", "--window-id", "42"])
        XCTAssertEqual(WindowManagerCloseCommand.aeroSpace(42).arguments, ["close", "--window-id", "42"])
        XCTAssertEqual(WindowManagerCloseCommand.yabai(42).arguments, ["-m", "window", "42", "--close"])

        switch YabaiCLIExecutionPolicy.result(YabaiCLIResult(
            output: "cannot close window",
            terminationStatus: 1
        )) {
        case .success:
            XCTFail("nonzero yabai status must not report close success")
        case .failure(let error):
            XCTAssertTrue(error.localizedDescription.contains("cannot close window"))
        }
    }

    func testQuitRejectsReusedPIDAndConsumedKeyUpIsOneShot() {
        XCTAssertTrue(AppSwitcherQuitTargetPolicy.pidMatches(expectedBundleIdentifier: "com.example.Expected", actualBundleIdentifier: "com.example.Expected"))
        XCTAssertFalse(AppSwitcherQuitTargetPolicy.pidMatches(expectedBundleIdentifier: "com.example.Expected", actualBundleIdentifier: "com.example.ReusedPID"))
        XCTAssertFalse(AppSwitcherQuitTargetPolicy.pidMatches(expectedBundleIdentifier: nil, actualBundleIdentifier: "com.example.Any"))
        XCTAssertFalse(AppSwitcherQuitTargetPolicy.mayUseBundleFallback(processIdentifier: 42))
        XCTAssertTrue(AppSwitcherQuitTargetPolicy.mayUseBundleFallback(processIdentifier: 0))

        var policy = AppSwitcherConsumedKeyUpPolicy()
        policy.consume(AppSwitcherActionKeyPolicy.wKeyCode)
        XCTAssertTrue(policy.shouldSuppressRepeatedKeyDown(
            AppSwitcherActionKeyPolicy.wKeyCode,
            isAutorepeat: true
        ))
        XCTAssertFalse(policy.shouldSuppressRepeatedKeyDown(
            AppSwitcherActionKeyPolicy.wKeyCode,
            isAutorepeat: false
        ))
        XCTAssertTrue(policy.shouldSuppressKeyUp(AppSwitcherActionKeyPolicy.wKeyCode))
        XCTAssertFalse(policy.shouldSuppressRepeatedKeyDown(
            AppSwitcherActionKeyPolicy.wKeyCode,
            isAutorepeat: true
        ))
        XCTAssertFalse(policy.shouldSuppressKeyUp(AppSwitcherActionKeyPolicy.wKeyCode))
    }

    func testEveryConsumedActionKeySuppressesItsKeyUp() {
        var policy = AppSwitcherConsumedKeyUpPolicy()
        for keyCode in [AppSwitcherActionKeyPolicy.qKeyCode, 24, AppSwitcherActionKeyPolicy.semicolonKeyCode] {
            policy.consume(keyCode)
        }
        XCTAssertTrue(policy.shouldSuppressKeyUp(AppSwitcherActionKeyPolicy.qKeyCode))
        XCTAssertTrue(policy.shouldSuppressKeyUp(24))
        XCTAssertTrue(policy.shouldSuppressKeyUp(AppSwitcherActionKeyPolicy.semicolonKeyCode))
    }

    func testConfirmedCloseFiltersOnlyTheExactWindow() {
        let target = makeActionTestWindow(id: 42, pid: 101, bundle: "com.example.Editor")
        let other = makeActionTestWindow(id: 99, pid: 202, bundle: "com.example.Editor")
        let content = SwitcherContent(
            spaceGroups: [SpaceGroup(spaceIndex: 1, spaceLabel: nil, isFocused: true, windows: [target, other])],
            allWindows: [target, other]
        )

        let filtered = AppSwitcherActionContentPolicy.removeConfirmedTarget(
            from: content,
            target: .window(windowManagerID: 42),
            check: .absent
        )

        XCTAssertEqual(filtered.allWindows.map(\.id), [99])
        XCTAssertEqual(filtered.spaceGroups.first?.windows.map(\.id), [99])
    }

    func testConfirmedQuitFiltersAllSelectedProcessWindowsOnly() {
        let first = makeActionTestWindow(id: 10, pid: 101, bundle: "com.example.Editor")
        let second = makeActionTestWindow(id: 11, pid: 101, bundle: "com.example.Editor")
        let otherProcess = makeActionTestWindow(id: 12, pid: 202, bundle: "com.example.Editor")
        let target = AppSwitcherActionTarget.application(
            processIdentifier: 101,
            bundleIdentifier: "com.example.Editor"
        )
        let content = SwitcherContent(
            spaceGroups: [SpaceGroup(spaceIndex: 1, spaceLabel: nil, isFocused: true, windows: [first, second, otherProcess])],
            allWindows: [first, second, otherProcess]
        )

        let filtered = AppSwitcherActionContentPolicy.removeConfirmedTarget(
            from: content,
            target: target,
            check: .absent
        )

        XCTAssertEqual(filtered.allWindows.map(\.id), [12])
        XCTAssertEqual(
            AppSwitcherActionContentPolicy.checkPresence(target, in: [first, second]),
            .present
        )
    }

    func testConfirmedQuitRemovesUnresolvedStaleRowsButKeepsReusedPID() {
        let stale = makeActionTestWindow(id: 20, pid: 101, bundle: nil)
        let reused = makeActionTestWindow(
            id: 21,
            pid: 101,
            bundle: "com.example.Reused"
        )
        let content = SwitcherContent(spaceGroups: [], allWindows: [stale, reused])

        let result = AppSwitcherActionContentPolicy.removeConfirmedTarget(
            from: content,
            target: .application(
                processIdentifier: 101,
                bundleIdentifier: "com.example.Editor"
            ),
            check: .absent
        )

        XCTAssertEqual(result.allWindows.map(\.id), [21])
    }

    func testPresentAndUnavailableKeepRowsForSavePromptsOrRetry() {
        let rows = [makeActionTestWindow(id: 42, pid: 101, bundle: "com.example.Editor")]
        let content = SwitcherContent(
            spaceGroups: [SpaceGroup(spaceIndex: 1, spaceLabel: nil, isFocused: true, windows: rows)],
            allWindows: rows
        )
        let target = AppSwitcherActionTarget.window(windowManagerID: 42)

        for check in [WMAppSwitcherTargetCheck.present, .unavailable] {
            let unchanged = AppSwitcherActionContentPolicy.removeConfirmedTarget(
                from: content,
                target: target,
                check: check
            )
            XCTAssertEqual(unchanged.allWindows.map(\.id), [42])
        }
    }

    func testPresentOrUnavailableRestoresTargetMissingFromCachedRefresh() {
        let targetWindow = makeActionTestWindow(
            id: 41,
            pid: 444,
            bundle: "com.example.Editor"
        )
        let unrelatedWindow = makeActionTestWindow(
            id: 52,
            pid: 555,
            bundle: "com.example.Other"
        )
        let previous = SwitcherContent(
            spaceGroups: [SpaceGroup(
                spaceIndex: 3,
                spaceLabel: "E",
                isFocused: true,
                windows: [targetWindow, unrelatedWindow]
            )],
            allWindows: [targetWindow, unrelatedWindow]
        )
        let staleRefresh = SwitcherContent(
            spaceGroups: [SpaceGroup(
                spaceIndex: 3,
                spaceLabel: "E",
                isFocused: true,
                windows: [unrelatedWindow]
            )],
            allWindows: [unrelatedWindow]
        )
        let target = AppSwitcherActionTarget.window(windowManagerID: 41)

        for check in [WMAppSwitcherTargetCheck.present, .unavailable] {
            let reconciled = AppSwitcherActionContentPolicy.reconciledContent(
                refreshed: staleRefresh,
                previous: previous,
                target: target,
                check: check
            )
            XCTAssertEqual(reconciled.allWindows.map(\.id), [41, 52])
            XCTAssertEqual(reconciled.spaceGroups.first?.windows.map(\.id), [41, 52])
        }
    }

    func testPartialQuitDoesNotRestoreClosedWindows() {
        let previous = SwitcherContent(
            spaceGroups: [],
            allWindows: [
                makeActionTestWindow(id: 20, pid: 101, bundle: "com.example.Editor"),
                makeActionTestWindow(id: 21, pid: 101, bundle: "com.example.Editor")
            ]
        )
        let savePrompt = makeActionTestWindow(
            id: 21,
            pid: 101,
            bundle: "com.example.Editor"
        )
        let refreshed = SwitcherContent(spaceGroups: [], allWindows: [savePrompt])

        let result = AppSwitcherActionContentPolicy.reconciledContent(
            refreshed: refreshed,
            previous: previous,
            target: .application(
                processIdentifier: 101,
                bundleIdentifier: "com.example.Editor"
            ),
            check: .present
        )

        XCTAssertEqual(result.allWindows.map(\.id), [21])
    }

    func testPartialRiftQuitRemovesExactlyConfirmedAbsentCachedRows() {
        let closed = makeActionTestWindow(
            id: 20,
            pid: 101,
            bundle: "com.example.Editor"
        )
        let savePrompt = makeActionTestWindow(
            id: 21,
            pid: 101,
            bundle: "com.example.Editor"
        )
        let staleCache = SwitcherContent(
            spaceGroups: [],
            allWindows: [closed, savePrompt]
        )

        let result = AppSwitcherActionContentPolicy.reconciledContent(
            refreshed: staleCache,
            previous: staleCache,
            target: .application(
                processIdentifier: 101,
                bundleIdentifier: "com.example.Editor"
            ),
            check: .present,
            absentWindowManagerIDs: [20]
        )

        XCTAssertEqual(result.allWindows.map(\.id), [21])
    }

    func testConfirmedAbsentIDDoesNotRemoveAReusedWindowIdentity() {
        let replacement = makeActionTestWindow(
            id: 42,
            pid: 202,
            bundle: "com.example.Replacement"
        )
        let refreshed = SwitcherContent(spaceGroups: [], allWindows: [replacement])

        let result = AppSwitcherActionContentPolicy.reconciledContent(
            refreshed: refreshed,
            previous: SwitcherContent(spaceGroups: [], allWindows: []),
            target: .window(
                windowManagerID: 42,
                processIdentifier: 101,
                bundleIdentifier: "com.example.Editor"
            ),
            check: .absent,
            absentWindowManagerIDs: [42]
        )

        XCTAssertEqual(result.allWindows.map(\.id), [42])
        XCTAssertEqual(result.allWindows.first?.pid, 202)
    }

    func testYabaiPresenceUsesRawWindowsBeforeDisplayFiltering() {
        let rawWindows: [(id: Int, pid: pid_t)] = [(42, 101), (43, 202)]

        XCTAssertEqual(
            YabaiAppSwitcherTargetPolicy.check(
                .window(id: 42),
                rawWindows: rawWindows
            ).check,
            .present
        )
        XCTAssertEqual(
            YabaiAppSwitcherTargetPolicy.check(
                .application(
                    processIdentifier: 101,
                    bundleIdentifier: "com.example.Editor",
                    windowManagerIDs: [42]
                ),
                rawWindows: rawWindows
            ).check,
            .present
        )
        XCTAssertEqual(
            YabaiAppSwitcherTargetPolicy.check(
                .window(id: 99),
                rawWindows: rawWindows
            ).check,
            .absent
        )
    }

    func testRunningQuitProcessKeepsReplacementSavePromptVisible() {
        let target = AppSwitcherActionTarget.application(
            processIdentifier: 444,
            bundleIdentifier: "com.example.Editor"
        )

        XCTAssertEqual(
            AppSwitcherActionContentPolicy.confirmedCheck(
                .absent,
                target: target,
                runningBundleIdentifier: "com.example.Editor"
            ),
            .present
        )
        XCTAssertEqual(
            AppSwitcherActionContentPolicy.confirmedCheck(
                .unavailable,
                target: target,
                runningBundleIdentifier: nil
            ),
            .absent,
            "a terminated fallback app must clear even while its WM is unavailable"
        )
        XCTAssertEqual(
            AppSwitcherActionContentPolicy.confirmedCheck(
                .absent,
                target: target,
                runningBundleIdentifier: "com.example.Other"
            ),
            .absent,
            "PID reuse by another bundle must not keep the old application row"
        )
        XCTAssertEqual(
            AppSwitcherActionContentPolicy.refreshResult(for: .present),
            .targetStillPresent
        )
        XCTAssertEqual(
            AppSwitcherActionContentPolicy.refreshResult(for: .unavailable),
            .targetStillPresent,
            "filtered or unavailable rows must not end confirmed-state polling"
        )
        XCTAssertEqual(
            AppSwitcherActionContentPolicy.refreshResult(for: .absent),
            .targetGone
        )
    }
}

final class RiftTargetCheckPolicyTests: XCTestCase {
    func testRiftCLIExecutionRejectsNonzeroStatus() throws {
        switch RiftCLIExecutionPolicy.result(RiftCLIResult(
            output: "window close failed",
            terminationStatus: 1
        )) {
        case .success:
            XCTFail("nonzero rift-cli status must not report command success")
        case .failure(let error):
            XCTAssertTrue(error.localizedDescription.contains("window close failed"))
        }

        XCTAssertEqual(
            try RiftCLIExecutionPolicy.result(RiftCLIResult(
                output: "ok",
                terminationStatus: 0
            )).get(),
            "ok"
        )
    }

    func testInactiveWorkspaceExactResultsAggregateSafely() {
        XCTAssertEqual(
            RiftWindowTargetCheckPolicy.aggregate([.absent, .absent]),
            .absent
        )
        XCTAssertEqual(
            RiftWindowTargetCheckPolicy.aggregate([.absent, .present]),
            .present
        )
        XCTAssertEqual(
            RiftWindowTargetCheckPolicy.aggregate([.absent, .unavailable]),
            .unavailable
        )
        let partial = RiftWindowTargetCheckPolicy.result([
            (windowManagerID: 20, check: .absent),
            (windowManagerID: 21, check: .present)
        ])
        XCTAssertEqual(partial.check, .present)
        XCTAssertEqual(partial.absentWindowManagerIDs, [20])
    }
}

final class AppSwitcherActionRefreshCoordinatorTests: XCTestCase {
    func testFallbackDelaysReachTheDocumentedAbsoluteOffsets() {
        let intervals = AppSwitcherActionRefreshCoordinator.refreshDelays.indices.dropFirst().map {
            AppSwitcherActionRefreshCoordinator.fallbackDelay(at: $0)
        }
        let expected = [0.15, 0.30, 0.45, 0.60, 1.0]
        for (actual, expected) in zip(intervals, expected) {
            XCTAssertEqual(actual, expected, accuracy: 0.0001)
        }
        XCTAssertEqual(intervals.reduce(0, +), 2.5, accuracy: 0.0001)
    }

    /// Regression: a stale command-time snapshot must be replaced by the
    /// window-manager event while Cmd remains held, without waiting for the
    /// next switcher activation.
    func testWindowManagerEventRefreshesRowsAfterStalePoll() throws {
        let scheduler = TestActionRefreshScheduler()
        let coordinator = AppSwitcherActionRefreshCoordinator(now: { scheduler.now }) { delay, action in
            scheduler.schedule(delay: delay, action: action)
        }
        let token = try XCTUnwrap(coordinator.begin(target: .window(windowManagerID: 42)))
        var snapshots: [[Int]] = [[42, 99], [42, 99], [42, 99], [99]]
        var committed: [[Int]] = []

        coordinator.startWaiting(for: token, refresh: { finish in
            let rows = snapshots.removeFirst()
            committed.append(rows)
            finish(rows.contains(42) ? .targetStillPresent : .targetGone)
        }, onConfirmed: {})

        XCTAssertEqual(committed, [[42, 99]])
        XCTAssertEqual(scheduler.pendingDelays, [0.15])
        scheduler.fireNext()
        XCTAssertEqual(committed, [[42, 99], [42, 99]])
        XCTAssertEqual(scheduler.pendingDelays, [0.30])
        scheduler.fireNext()
        XCTAssertEqual(committed, [[42, 99], [42, 99], [42, 99]])
        XCTAssertTrue(coordinator.isCurrent(token))
        XCTAssertEqual(scheduler.pendingDelays, [0.45])

        coordinator.windowManagerDidChange(token: token)
        XCTAssertEqual(scheduler.pendingDelays, [AppSwitcherActionRefreshCoordinator.eventDebounceDelay])
        scheduler.fireNext()

        XCTAssertEqual(committed, [[42, 99], [42, 99], [42, 99], [99]])
        XCTAssertFalse(coordinator.isCurrent(token))
    }

    func testEventsCoalesceWhileRefreshIsInFlight() throws {
        let scheduler = TestActionRefreshScheduler()
        let coordinator = AppSwitcherActionRefreshCoordinator(now: { scheduler.now }) { delay, action in
            scheduler.schedule(delay: delay, action: action)
        }
        let token = try XCTUnwrap(coordinator.begin(target: .window(windowManagerID: 42)))
        var refreshes = 0
        var completion: ((AppSwitcherActionRefreshResult) -> Void)?
        var confirmed = false

        coordinator.startWaiting(for: token, refresh: { done in
            refreshes += 1
            completion = done
        }, onConfirmed: { confirmed = true })

        coordinator.windowManagerDidChange(token: token)
        coordinator.windowManagerDidChange(token: token)
        XCTAssertEqual(refreshes, 1)

        completion?(.targetStillPresent)
        XCTAssertEqual(scheduler.pendingDelays, [0])
        scheduler.fireNext()
        XCTAssertEqual(refreshes, 2)

        completion?(.targetGone)
        XCTAssertTrue(confirmed)
        XCTAssertFalse(coordinator.isCurrent(token))
    }

    func testEventRefreshDoesNotConsumeTheNextFallbackSlot() throws {
        let scheduler = TestActionRefreshScheduler()
        let coordinator = AppSwitcherActionRefreshCoordinator(now: { scheduler.now }) { delay, action in
            scheduler.schedule(delay: delay, action: action)
        }
        let token = try XCTUnwrap(coordinator.begin(target: .window(windowManagerID: 42)))
        var refreshes = 0

        coordinator.startWaiting(for: token, refresh: { done in
            refreshes += 1
            done(.targetStillPresent)
        }, onConfirmed: {})

        XCTAssertEqual(scheduler.pendingDelays, [0.15])
        coordinator.windowManagerDidChange(token: token)
        XCTAssertEqual(scheduler.pendingDelays, [AppSwitcherActionRefreshCoordinator.eventDebounceDelay])
        scheduler.fireNext()

        XCTAssertEqual(refreshes, 2)
        XCTAssertEqual(scheduler.pendingDelays, [0.13])
    }

    func testEventsCannotExtendTheAbsoluteActionDeadline() throws {
        let scheduler = TestActionRefreshScheduler()
        let coordinator = AppSwitcherActionRefreshCoordinator(
            now: { scheduler.now },
            deadlineSchedule: { delay, action in
                scheduler.scheduleDeadline(delay: delay, action: action)
            }
        ) { delay, action in
            scheduler.schedule(delay: delay, action: action)
        }
        let token = try XCTUnwrap(coordinator.begin(target: .window(windowManagerID: 42)))
        var timedOut = false
        var confirmed = false
        var targetGone = false

        coordinator.startWaiting(for: token, refresh: { done in
            done(targetGone ? .targetGone : .targetStillPresent)
        }, onConfirmed: { confirmed = true }, onTimedOut: { timedOut = true })

        scheduler.advance(by: AppSwitcherActionRefreshCoordinator.actionDeadline)
        coordinator.windowManagerDidChange(token: token)

        XCTAssertTrue(timedOut)
        XCTAssertFalse(coordinator.hasActiveMutation)
        XCTAssertTrue(coordinator.isCurrent(token))
        XCTAssertTrue(coordinator.isWaitingForEvent)
        XCTAssertEqual(scheduler.pendingDelays, [0])

        targetGone = true
        scheduler.fireNext()

        XCTAssertTrue(confirmed)
        XCTAssertFalse(coordinator.isCurrent(token))
    }

    func testInFlightRefreshCannotOutliveTheActionDeadline() throws {
        let scheduler = TestActionRefreshScheduler()
        let coordinator = AppSwitcherActionRefreshCoordinator(
            now: { scheduler.now },
            deadlineSchedule: { delay, action in
                scheduler.scheduleDeadline(delay: delay, action: action)
            }
        ) { delay, action in
            scheduler.schedule(delay: delay, action: action)
        }
        let token = try XCTUnwrap(coordinator.begin(target: .window(windowManagerID: 42)))
        var completions: [(AppSwitcherActionRefreshResult) -> Void] = []
        var refreshes = 0
        var timedOut = false
        var confirmed = false

        coordinator.startWaiting(for: token, refresh: { done in
            refreshes += 1
            completions.append(done)
        }, onConfirmed: { confirmed = true }, onTimedOut: { timedOut = true })

        coordinator.windowManagerDidChange(token: token)
        scheduler.fireDeadline()

        XCTAssertTrue(timedOut)
        XCTAssertFalse(coordinator.hasActiveMutation)
        XCTAssertTrue(coordinator.isWaitingForEvent)

        XCTAssertEqual(refreshes, 1)

        completions.removeFirst()(.targetStillPresent)
        XCTAssertEqual(scheduler.pendingDelays, [0])
        scheduler.fireNext()
        XCTAssertEqual(refreshes, 2)

        completions.removeFirst()(.targetGone)

        XCTAssertTrue(confirmed)
        XCTAssertFalse(coordinator.isCurrent(token))
    }

    func testActionDeadlineDoesNotWaitForCloseCompletion() throws {
        let scheduler = TestActionRefreshScheduler()
        let coordinator = AppSwitcherActionRefreshCoordinator(
            now: { scheduler.now },
            deadlineSchedule: { delay, action in
                scheduler.scheduleDeadline(delay: delay, action: action)
            }
        ) { delay, action in
            scheduler.schedule(delay: delay, action: action)
        }
        let token = try XCTUnwrap(coordinator.begin(target: .window(windowManagerID: 42)))
        var timedOut = false

        // The refresh stands in for a close CLI that never invokes its
        // completion. Ownership must still expire from action start time.
        coordinator.startWaiting(for: token, refresh: { _ in }, onConfirmed: {}, onTimedOut: {
            timedOut = true
        })
        scheduler.fireDeadline()

        XCTAssertTrue(timedOut)
        XCTAssertFalse(coordinator.hasActiveMutation)
        XCTAssertTrue(coordinator.isWaitingForEvent)
    }

    func testTerminationNotificationTriggersOnlyMatchingQuitTarget() throws {
        let scheduler = TestActionRefreshScheduler()
        let coordinator = AppSwitcherActionRefreshCoordinator(now: { scheduler.now }) { delay, action in
            scheduler.schedule(delay: delay, action: action)
        }
        let token = try XCTUnwrap(coordinator.begin(target: .application(
            processIdentifier: 101,
            bundleIdentifier: "com.example.Editor"
        )))
        var refreshes = 0
        var completion: ((AppSwitcherActionRefreshResult) -> Void)?

        coordinator.startWaiting(for: token, refresh: { done in
            refreshes += 1
            completion = done
        }, onConfirmed: {})
        coordinator.applicationDidTerminate(
            processIdentifier: 202,
            bundleIdentifier: "com.example.Editor"
        )
        XCTAssertEqual(refreshes, 1)

        coordinator.applicationDidTerminate(
            processIdentifier: 101,
            bundleIdentifier: "com.example.Editor"
        )
        XCTAssertEqual(refreshes, 1)
        completion?(.targetStillPresent)
        scheduler.fireNext()
        XCTAssertEqual(refreshes, 2)
    }

    func testBurstEventsKeepOneTrailingEventRefresh() throws {
        let scheduler = TestActionRefreshScheduler()
        let coordinator = AppSwitcherActionRefreshCoordinator(now: { scheduler.now }) { delay, action in
            scheduler.schedule(delay: delay, action: action)
        }
        let token = try XCTUnwrap(coordinator.begin(target: .window(windowManagerID: 42)))
        var refreshes = 0
        var completion: ((AppSwitcherActionRefreshResult) -> Void)?

        coordinator.startWaiting(for: token, refresh: { done in
            refreshes += 1
            completion = done
        }, onConfirmed: {})
        for _ in 0..<20 {
            coordinator.windowManagerDidChange(token: token)
        }
        XCTAssertEqual(refreshes, 1)
        XCTAssertTrue(scheduler.pendingDelays.isEmpty)

        completion?(.targetStillPresent)
        XCTAssertEqual(scheduler.pendingDelays, [0])
        for _ in 0..<20 {
            coordinator.windowManagerDidChange(token: token)
        }
        XCTAssertEqual(scheduler.pendingDelays, [0])
        scheduler.fireNext()
        XCTAssertEqual(refreshes, 2)
        completion?(.targetStillPresent)

        // An event burst replaces the fallback timer with one short event
        // debounce, never one timer per event.
        XCTAssertEqual(scheduler.pendingDelays, [0.15])
        for _ in 0..<20 {
            coordinator.windowManagerDidChange(token: token)
        }
        XCTAssertEqual(scheduler.pendingDelays, [AppSwitcherActionRefreshCoordinator.eventDebounceDelay])
    }

    func testFallbackPollingContinuesUntilTargetDisappears() throws {
        let scheduler = TestActionRefreshScheduler()
        let coordinator = AppSwitcherActionRefreshCoordinator(now: { scheduler.now }) { delay, action in
            scheduler.schedule(delay: delay, action: action)
        }
        let token = try XCTUnwrap(coordinator.begin(target: .window(windowManagerID: 42)))
        var results: [AppSwitcherActionRefreshResult] = [
            .targetStillPresent, .targetStillPresent, .targetGone
        ]
        var refreshes = 0

        coordinator.startWaiting(for: token, refresh: { done in
            refreshes += 1
            done(results.removeFirst())
        }, onConfirmed: {})

        XCTAssertEqual(refreshes, 1)
        XCTAssertEqual(scheduler.pendingDelays, [0.15])
        scheduler.fireNext()
        XCTAssertEqual(refreshes, 2)
        XCTAssertEqual(scheduler.pendingDelays, [0.30])
        scheduler.fireNext()
        XCTAssertEqual(refreshes, 3)
        XCTAssertFalse(coordinator.isCurrent(token))
    }

    func testFallbackAuthoritativeRefreshUpdatesStaleCachedRowsWithoutEvent() throws {
        let scheduler = TestActionRefreshScheduler()
        let coordinator = AppSwitcherActionRefreshCoordinator(now: { scheduler.now }) { delay, action in
            scheduler.schedule(delay: delay, action: action)
        }
        let token = try XCTUnwrap(coordinator.begin(target: .window(windowManagerID: 42)))
        var cachedRows = [42, 99]
        var authoritativeRefreshes = 0
        var renderedRows: [[Int]] = []

        coordinator.startWaiting(for: token, refresh: { done in
            authoritativeRefreshes += 1
            if authoritativeRefreshes == 2 {
                // Simulate the WM's cache catching up during the fallback
                // query, without delivering a windowsChanged event.
                cachedRows = [99]
            }
            renderedRows.append(cachedRows)
            done(cachedRows.contains(42) ? .targetStillPresent : .targetGone)
        }, onConfirmed: {})

        XCTAssertEqual(renderedRows, [[42, 99]])
        XCTAssertEqual(scheduler.pendingDelays, [0.15])
        scheduler.fireNext()

        XCTAssertEqual(renderedRows, [[42, 99], [99]])
        XCTAssertEqual(authoritativeRefreshes, 2)
        XCTAssertFalse(coordinator.isCurrent(token))
    }

    func testSavePromptTimesOutWithoutRemovingRows() throws {
        let scheduler = TestActionRefreshScheduler()
        let coordinator = AppSwitcherActionRefreshCoordinator(now: { scheduler.now }) { delay, action in
            scheduler.schedule(delay: delay, action: action)
        }
        let token = try XCTUnwrap(coordinator.begin(target: .application(
            processIdentifier: 101,
            bundleIdentifier: "com.example.Editor"
        )))
        var rows = [[101, 202]]
        var refreshes = 0
        var confirmed = false
        var timedOut = false

        coordinator.startWaiting(for: token, refresh: { done in
            refreshes += 1
            let snapshot = rows.last ?? []
            done(snapshot.contains(101) ? .targetStillPresent : .targetGone)
        }, onConfirmed: { confirmed = true }, onTimedOut: { timedOut = true })

        while scheduler.pendingDelays.first != nil {
            scheduler.fireNext()
        }

        XCTAssertEqual(refreshes, AppSwitcherActionRefreshCoordinator.refreshDelays.count)
        XCTAssertFalse(confirmed)
        XCTAssertTrue(timedOut)
        XCTAssertFalse(coordinator.hasActiveMutation)
        XCTAssertTrue(coordinator.isCurrent(token))
        XCTAssertTrue(coordinator.isWaitingForEvent)
        let replacementToken = try XCTUnwrap(
            coordinator.begin(target: .window(windowManagerID: 303))
        )
        XCTAssertFalse(coordinator.isCurrent(token))
        XCTAssertTrue(coordinator.isCurrent(replacementToken))
        XCTAssertEqual(rows, [[101, 202]])
    }

    func testQuitTargetsProcessAndBundleNotASecondProcessWithSameBundle() {
        let target = AppSwitcherActionTarget.application(
            processIdentifier: 101,
            bundleIdentifier: "com.example.Editor"
        )
        let selectedProcessWindows = [
            makeActionTestWindow(id: 20, pid: 101, bundle: "com.example.Editor"),
            makeActionTestWindow(id: 21, pid: 101, bundle: "com.example.Editor"),
            makeActionTestWindow(id: 22, pid: 202, bundle: "com.example.Editor")
        ]
        XCTAssertFalse(AppSwitcherActionTargetPolicy.isGone(target, from: selectedProcessWindows))
        XCTAssertTrue(AppSwitcherActionTargetPolicy.isGone(target, from: [
            makeActionTestWindow(id: 22, pid: 202, bundle: "com.example.Editor")
        ]))
    }

    func testCancelledRefreshIgnoresStaleCompletionAndEvents() throws {
        let scheduler = TestActionRefreshScheduler()
        let coordinator = AppSwitcherActionRefreshCoordinator(now: { scheduler.now }) { delay, action in
            scheduler.schedule(delay: delay, action: action)
        }
        let token = try XCTUnwrap(coordinator.begin(target: .window(windowManagerID: 42)))
        var completion: ((AppSwitcherActionRefreshResult) -> Void)?
        var refreshes = 0
        var confirmed = false

        coordinator.startWaiting(for: token, refresh: { done in
            refreshes += 1
            completion = done
        }, onConfirmed: { confirmed = true })
        coordinator.cancel()
        completion?(.targetGone)
        coordinator.windowManagerDidChange(token: token)

        XCTAssertEqual(refreshes, 1)
        XCTAssertFalse(confirmed)
        XCTAssertFalse(coordinator.isCurrent(token))
        XCTAssertTrue(scheduler.pendingDelays.isEmpty)
    }

    func testCoordinatorAllowsOneActionAndCancelsStaleWork() throws {
        let coordinator = AppSwitcherActionRefreshCoordinator()
        let token = try XCTUnwrap(coordinator.begin())
        XCTAssertTrue(coordinator.hasActiveMutation)
        XCTAssertNil(coordinator.begin())
        XCTAssertTrue(coordinator.isCurrent(token))
        coordinator.cancel()
        XCTAssertFalse(coordinator.hasActiveMutation)
        XCTAssertFalse(coordinator.isCurrent(token))

        var refreshes = 0
        coordinator.startWaiting(for: token, refresh: { done in
            refreshes += 1
            done(.targetStillPresent)
        }, onConfirmed: {})
        XCTAssertEqual(refreshes, 0)
    }

    func testRejectedSecondActionLeavesOriginalActionActive() throws {
        let coordinator = AppSwitcherActionRefreshCoordinator()
        let original = try XCTUnwrap(coordinator.begin(target: .window(windowManagerID: 42)))

        XCTAssertNil(coordinator.begin(target: .application(
            processIdentifier: 100,
            bundleIdentifier: "com.example.Other"
        )))
        XCTAssertTrue(coordinator.hasActiveMutation)
        XCTAssertTrue(coordinator.isCurrent(original))
    }

    func testCancelInvalidatesCompletionBeforeCommandModeCanRetry() throws {
        let coordinator = AppSwitcherActionRefreshCoordinator()
        let token = try XCTUnwrap(coordinator.begin())
        var refreshes = 0
        var completion: (() -> Void)?

        coordinator.startWaiting(for: token, refresh: { done in
            refreshes += 1
            completion = { done(.targetStillPresent) }
        }, onConfirmed: {})
        XCTAssertEqual(refreshes, 1)

        coordinator.cancel()
        completion?()
        XCTAssertEqual(refreshes, 1)
    }
}

private final class TestActionRefreshScheduler {
    private(set) var scheduled: [(TimeInterval, DispatchWorkItem)] = []
    private(set) var deadlines: [(TimeInterval, DispatchWorkItem)] = []
    private(set) var now: TimeInterval = 0

    var pendingDelays: [TimeInterval] {
        scheduled.filter { !$0.1.isCancelled }.map(\.0)
    }

    func schedule(delay: TimeInterval, action: @escaping () -> Void) -> DispatchWorkItem {
        let work = DispatchWorkItem(block: action)
        scheduled.append((delay, work))
        return work
    }

    func scheduleDeadline(
        delay: TimeInterval,
        action: @escaping () -> Void
    ) -> DispatchWorkItem {
        let work = DispatchWorkItem(block: action)
        deadlines.append((delay, work))
        return work
    }

    func fireNext() {
        guard let index = scheduled.firstIndex(where: { !$0.1.isCancelled }) else {
            XCTFail("expected a pending action refresh")
            return
        }
        let scheduledItem = scheduled.remove(at: index)
        now += scheduledItem.0
        let work = scheduledItem.1
        work.perform()
    }

    func advance(by interval: TimeInterval) {
        now += interval
    }

    func fireDeadline() {
        guard let index = deadlines.firstIndex(where: { !$0.1.isCancelled }) else {
            XCTFail("expected an action refresh deadline")
            return
        }
        let scheduledItem = deadlines.remove(at: index)
        now += scheduledItem.0
        scheduledItem.1.perform()
    }
}

private func makeActionTestWindow(
    id: Int,
    pid: pid_t,
    bundle: String?
) -> SwitcherWindow {
    SwitcherWindow(
        id: id,
        windowManagerID: id,
        pid: pid,
        bundleIdentifier: bundle,
        title: "Example",
        appName: "Example",
        spaceIndex: 1,
        icon: nil,
        hasFocus: false,
        isMinimized: false,
        isHidden: false
    )
}

final class AppSwitcherWindowIdentityTests: XCTestCase {
    func testYabaiWindowBundleIdentityComesFromWindowProcess() {
        XCTAssertEqual(
            YabaiWindowBundleResolver.resolve(processIdentifier: 101) { pid in
                pid == 101 ? "com.example.Editor" : nil
            },
            "com.example.Editor"
        )
        XCTAssertNil(
            YabaiWindowBundleResolver.resolve(processIdentifier: 101) { _ in nil }
        )
        XCTAssertNil(
            YabaiWindowBundleResolver.resolve(processIdentifier: 0) { _ in
                XCTFail("invalid PIDs must not be looked up")
                return "com.example.Editor"
            }
        )
    }

    func testFallbackApplicationRowCannotTargetAWindowManagerWindow() {
        let row = SwitcherWindow(
            id: 123,
            windowManagerID: nil,
            pid: 123,
            bundleIdentifier: nil,
            title: "Example",
            appName: "Example",
            spaceIndex: 1,
            icon: nil,
            hasFocus: false,
            isMinimized: false,
            isHidden: false
        )
        XCTAssertNil(row.windowManagerID)
    }

    func testAeroSpaceOwnerResolutionFailsClosedForAmbiguousBundle() {
        XCTAssertEqual(
            AeroSpaceWindowOwnerPolicy.resolve(
                bundleIdentifier: "com.example.App",
                processIdentifiers: [101, 202]
            ),
            AeroSpaceWindowOwner(pid: 0, bundleIdentifier: nil)
        )
        XCTAssertEqual(
            AeroSpaceWindowOwnerPolicy.resolve(
                bundleIdentifier: "com.example.App",
                processIdentifiers: [101]
            ),
            AeroSpaceWindowOwner(pid: 101, bundleIdentifier: "com.example.App")
        )
    }

    func testActionRefreshKeepsCurrentNavigationWhenRowsChange() {
        let windows = [makeWindow(id: 20), makeWindow(id: 30)]
        XCTAssertEqual(
            AppSwitcherActionSelectionPolicy.index(
                in: windows,
                retaining: 30,
                nearestTo: 0
            ),
            1
        )
        XCTAssertEqual(
            AppSwitcherActionSelectionPolicy.index(
                in: windows,
                retaining: 10,
                nearestTo: 3
            ),
            1
        )
    }

    func testRefreshUsesSelectionAtCommitTimeAfterUserNavigates() {
        let actionTarget = 20
        let initialWindows = [
            makeWindow(id: actionTarget),
            makeWindow(id: 30),
            makeWindow(id: 40)
        ]
        let currentSelection = initialWindows[2]
        let refreshedWindows = [makeWindow(id: actionTarget), makeWindow(id: 40)]

        let selectedAfterRefresh = AppSwitcherActionSelectionPolicy.index(
            in: refreshedWindows,
            retaining: currentSelection.id,
            nearestTo: 2
        )

        XCTAssertEqual(selectedAfterRefresh, 1)
        XCTAssertNotEqual(currentSelection.id, actionTarget)
    }

    func testActionRefreshPreservesThumbnailsForSurvivingWindows() {
        let thumbnail = NSImage(size: NSSize(width: 1, height: 1))
        let refreshed = AppSwitcherThumbnailPolicy.merge(
            [makeWindow(id: 20), makeWindow(id: 30)],
            thumbnailsByID: [20: thumbnail]
        )

        XCTAssertNotNil(refreshed.first?.thumbnail)
        XCTAssertNil(refreshed.last?.thumbnail)
    }

    private func makeWindow(
        id: Int,
        pid: pid_t = 20,
        bundle: String = "com.example.App"
    ) -> SwitcherWindow {
        SwitcherWindow(
            id: id,
            windowManagerID: id,
            pid: pid,
            bundleIdentifier: bundle,
            title: "Example",
            appName: "Example",
            spaceIndex: 1,
            icon: nil,
            hasFocus: false,
            isMinimized: false,
            isHidden: false
        )
    }
}

final class AppSwitcherActionConfigurationTests: XCTestCase {
    func testKeyboardModeRoundTripsThroughJSON() throws {
        let input = Data(#"{"appSwitcherKeyboardMode":"actions"}"#.utf8)
        let decoded = try JSONDecoder().decode(AegisConfigData.self, from: input)
        XCTAssertEqual(decoded.appSwitcherKeyboardMode, AppSwitcherKeyboardMode.actions.rawValue)

        let exported = try JSONEncoder().encode(decoded)
        let roundTripped = try JSONDecoder().decode(AegisConfigData.self, from: exported)
        XCTAssertEqual(roundTripped.appSwitcherKeyboardMode, AppSwitcherKeyboardMode.actions.rawValue)
    }
}
