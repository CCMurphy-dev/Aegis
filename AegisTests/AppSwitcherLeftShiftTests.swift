import CoreGraphics
import XCTest
@testable import Aegis

final class AppSwitcherLeftShiftTapPolicyTests: XCTestCase {
    private let command: CGEventFlags = [.maskCommand]
    private let commandAndShift: CGEventFlags = [.maskCommand, .maskShift]

    func testLeftShiftTapReversesOnce() {
        var policy = AppSwitcherLeftShiftTapPolicy()
        XCTAssertEqual(policy.flagsChanged(keyCode: AppSwitcherLeftShiftTapPolicy.leftShiftKeyCode, flags: commandAndShift, enabled: true, switcherIsActive: true), .consume)
        XCTAssertEqual(policy.flagsChanged(keyCode: AppSwitcherLeftShiftTapPolicy.leftShiftKeyCode, flags: command, enabled: true, switcherIsActive: true), .reverse)
        XCTAssertEqual(policy.flagsChanged(keyCode: AppSwitcherLeftShiftTapPolicy.leftShiftKeyCode, flags: command, enabled: true, switcherIsActive: true), .ignored)
    }

    func testDisabledAndRightShiftDoNothing() {
        var policy = AppSwitcherLeftShiftTapPolicy()
        XCTAssertEqual(policy.flagsChanged(keyCode: AppSwitcherLeftShiftTapPolicy.leftShiftKeyCode, flags: commandAndShift, enabled: false, switcherIsActive: true), .ignored)
        XCTAssertEqual(policy.flagsChanged(keyCode: AppSwitcherLeftShiftTapPolicy.rightShiftKeyCode, flags: commandAndShift, enabled: true, switcherIsActive: true), .ignored)
    }

    func testAnotherKeyCancelsReverseButStillConsumesLeftShiftRelease() {
        var policy = AppSwitcherLeftShiftTapPolicy()
        _ = policy.flagsChanged(keyCode: AppSwitcherLeftShiftTapPolicy.leftShiftKeyCode, flags: commandAndShift, enabled: true, switcherIsActive: true)
        policy.keyPressedWhileHeld()
        XCTAssertEqual(policy.flagsChanged(keyCode: AppSwitcherLeftShiftTapPolicy.leftShiftKeyCode, flags: command, enabled: true, switcherIsActive: true), .consume)
    }

    func testOtherModifierChangesCancelPendingTap() {
        let modifiers: [(Int64, CGEventFlags)] = [
            (59, [.maskCommand, .maskShift, .maskControl]),
            (58, [.maskCommand, .maskShift, .maskAlternate]),
            (AppSwitcherLeftShiftTapPolicy.rightShiftKeyCode, [.maskCommand, .maskShift])
        ]
        for (keyCode, flags) in modifiers {
            var policy = AppSwitcherLeftShiftTapPolicy()
            _ = policy.flagsChanged(
                keyCode: AppSwitcherLeftShiftTapPolicy.leftShiftKeyCode,
                flags: commandAndShift,
                enabled: true,
                switcherIsActive: true
            )
            XCTAssertEqual(
                policy.flagsChanged(
                    keyCode: keyCode,
                    flags: flags,
                    enabled: true,
                    switcherIsActive: true
                ),
                .ignored
            )
            XCTAssertEqual(
                policy.flagsChanged(
                    keyCode: AppSwitcherLeftShiftTapPolicy.leftShiftKeyCode,
                    flags: command,
                    enabled: true,
                    switcherIsActive: true
                ),
                .consume
            )
        }
    }

    func testPreheldModifiersDoNotStartStandaloneTap() {
        let controlAndShift: CGEventFlags = [.maskCommand, .maskControl, .maskShift]
        let optionAndShift: CGEventFlags = [.maskCommand, .maskAlternate, .maskShift]

        for flags in [controlAndShift, optionAndShift] {
            var policy = AppSwitcherLeftShiftTapPolicy()
            XCTAssertEqual(
                policy.flagsChanged(
                    keyCode: AppSwitcherLeftShiftTapPolicy.leftShiftKeyCode,
                    flags: flags,
                    enabled: true,
                    switcherIsActive: true
                ),
                .ignored
            )
            XCTAssertEqual(
                policy.flagsChanged(
                    keyCode: AppSwitcherLeftShiftTapPolicy.leftShiftKeyCode,
                    flags: command,
                    enabled: true,
                    switcherIsActive: true
                ),
                .ignored
            )
        }

        var policy = AppSwitcherLeftShiftTapPolicy()
        XCTAssertEqual(
            policy.flagsChanged(
                keyCode: AppSwitcherLeftShiftTapPolicy.leftShiftKeyCode,
                flags: commandAndShift,
                enabled: true,
                switcherIsActive: true,
                rightShiftIsHeld: true
            ),
            .ignored
        )
        XCTAssertEqual(
            policy.flagsChanged(
                keyCode: AppSwitcherLeftShiftTapPolicy.leftShiftKeyCode,
                flags: command,
                enabled: true,
                switcherIsActive: true
            ),
            .ignored
        )
    }

    func testCommandReleaseCancelsTap() {
        var policy = AppSwitcherLeftShiftTapPolicy()
        _ = policy.flagsChanged(keyCode: AppSwitcherLeftShiftTapPolicy.leftShiftKeyCode, flags: commandAndShift, enabled: true, switcherIsActive: true)
        XCTAssertEqual(policy.flagsChanged(keyCode: 55, flags: [.maskShift], enabled: true, switcherIsActive: true), .ignored)
        XCTAssertEqual(policy.flagsChanged(keyCode: AppSwitcherLeftShiftTapPolicy.leftShiftKeyCode, flags: [], enabled: true, switcherIsActive: true), .consume)
    }
}

final class AppSwitcherLeftShiftConfigurationTests: XCTestCase {
    func testLeftShiftSettingRoundTripsThroughJSON() throws {
        let input = Data(#"{"appSwitcherLeftShiftReverseEnabled":true}"#.utf8)
        let decoded = try JSONDecoder().decode(AegisConfigData.self, from: input)
        XCTAssertEqual(decoded.appSwitcherLeftShiftReverseEnabled, true)

        let exported = try JSONEncoder().encode(decoded)
        let roundTripped = try JSONDecoder().decode(AegisConfigData.self, from: exported)
        XCTAssertEqual(roundTripped.appSwitcherLeftShiftReverseEnabled, true)
    }
}
