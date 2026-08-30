import CoreGraphics
import XCTest
@testable import Aegis

final class AppSwitcherShortcutMatcherTests: XCTestCase {
    func testCapturesCmdTab() {
        XCTAssertEqual(
            AppSwitcherShortcutMatcher.reverseDirection(
                for: AppSwitcherShortcutMatcher.tabKeyCode,
                flags: [.maskCommand]
            ),
            false
        )
    }

    func testCapturesCmdShiftTabInReverse() {
        XCTAssertEqual(
            AppSwitcherShortcutMatcher.reverseDirection(
                for: AppSwitcherShortcutMatcher.tabKeyCode,
                flags: [.maskCommand, .maskShift]
            ),
            true
        )
    }

    func testIgnoresCapsLockAndFn() {
        XCTAssertEqual(
            AppSwitcherShortcutMatcher.reverseDirection(
                for: AppSwitcherShortcutMatcher.tabKeyCode,
                flags: [.maskCommand, .maskAlphaShift, .maskSecondaryFn]
            ),
            false
        )
    }

    func testPassesThroughModifiedShortcuts() {
        let cases: [CGEventFlags] = [
            [.maskCommand, .maskControl, .maskAlternate], // Meh+Tab
            [.maskCommand, .maskShift, .maskControl, .maskAlternate], // Hyper+Tab
            [.maskCommand, .maskAlternate],
            [.maskCommand, .maskControl],
        ]

        for flags in cases {
            XCTAssertNil(
                AppSwitcherShortcutMatcher.reverseDirection(
                    for: AppSwitcherShortcutMatcher.tabKeyCode,
                    flags: flags
                ),
                "Unexpected capture for flags: \(flags)"
            )
        }
    }

    func testIgnoresBareTabAndOtherKeys() {
        XCTAssertNil(
            AppSwitcherShortcutMatcher.reverseDirection(
                for: AppSwitcherShortcutMatcher.tabKeyCode,
                flags: []
            )
        )
        XCTAssertNil(
            AppSwitcherShortcutMatcher.reverseDirection(for: 0, flags: [.maskCommand])
        )
    }
}
