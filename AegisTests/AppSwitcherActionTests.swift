import AppKit
import CoreGraphics
import XCTest
@testable import Aegis

final class AppSwitcherActionKeyPolicyTests: XCTestCase {
    func testActionModeMapsExactCmdWAndCmdQ() {
        XCTAssertEqual(AppSwitcherActionKeyPolicy.decision(for: AppSwitcherActionKeyPolicy.wKeyCode, flags: [.maskCommand], mode: .actions, isCommandMode: false, isAutorepeat: false), .perform(.close))
        XCTAssertEqual(AppSwitcherActionKeyPolicy.decision(for: AppSwitcherActionKeyPolicy.qKeyCode, flags: [.maskCommand], mode: .actions, isCommandMode: false, isAutorepeat: false), .perform(.quit))
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

    func testCloseCommandsTargetOneWindow() {
        XCTAssertEqual(WindowManagerCloseCommand.rift(42).arguments, ["execute", "window", "close", "--window-id", "42"])
        XCTAssertEqual(WindowManagerCloseCommand.aeroSpace(42).arguments, ["close", "--window-id", "42"])
        XCTAssertEqual(WindowManagerCloseCommand.yabai(42).arguments, ["-m", "window", "42", "--close"])
    }

    func testQuitRejectsReusedPIDAndConsumedKeyUpIsOneShot() {
        XCTAssertTrue(AppSwitcherQuitTargetPolicy.pidMatches(expectedBundleIdentifier: "com.example.Expected", actualBundleIdentifier: "com.example.Expected"))
        XCTAssertFalse(AppSwitcherQuitTargetPolicy.pidMatches(expectedBundleIdentifier: "com.example.Expected", actualBundleIdentifier: "com.example.ReusedPID"))
        XCTAssertFalse(AppSwitcherQuitTargetPolicy.pidMatches(expectedBundleIdentifier: nil, actualBundleIdentifier: "com.example.Any"))
        XCTAssertFalse(AppSwitcherQuitTargetPolicy.mayUseBundleFallback(processIdentifier: 42))
        XCTAssertTrue(AppSwitcherQuitTargetPolicy.mayUseBundleFallback(processIdentifier: 0))

        var policy = AppSwitcherConsumedKeyUpPolicy()
        policy.consume(AppSwitcherActionKeyPolicy.wKeyCode)
        XCTAssertTrue(policy.shouldSuppressKeyUp(AppSwitcherActionKeyPolicy.wKeyCode))
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
}

final class AppSwitcherActionRefreshCoordinatorTests: XCTestCase {
    func testCoordinatorAllowsOneActionAndCancelsStaleWork() throws {
        let coordinator = AppSwitcherActionRefreshCoordinator()
        let token = try XCTUnwrap(coordinator.begin())
        XCTAssertNil(coordinator.begin())
        XCTAssertTrue(coordinator.isCurrent(token))
        coordinator.cancel()
        XCTAssertFalse(coordinator.isCurrent(token))

        var refreshes = 0
        coordinator.scheduleRefreshes(for: token) { finished in
            refreshes += 1
            finished()
        }
        XCTAssertEqual(refreshes, 0)
    }
}

final class AppSwitcherWindowIdentityTests: XCTestCase {
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

    func testActionRefreshPreservesThumbnailsForSurvivingWindows() {
        let thumbnail = NSImage(size: NSSize(width: 1, height: 1))
        let refreshed = AppSwitcherThumbnailPolicy.merge(
            [makeWindow(id: 20), makeWindow(id: 30)],
            thumbnailsByID: [20: thumbnail]
        )

        XCTAssertNotNil(refreshed.first?.thumbnail)
        XCTAssertNil(refreshed.last?.thumbnail)
    }

    private func makeWindow(id: Int) -> SwitcherWindow {
        SwitcherWindow(
            id: id,
            windowManagerID: id,
            pid: pid_t(id),
            bundleIdentifier: "com.example.App",
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
