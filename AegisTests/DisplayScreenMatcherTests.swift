import XCTest
@testable import Aegis

final class DisplayScreenMatcherTests: XCTestCase {
    func testHardwareNotchIsAlwaysIncluded() {
        XCTAssertTrue(DisplayScreenMatcher.shouldIncludeScreen(
            hasHardwareNotch: true,
            showVirtualNotch: false
        ))
        XCTAssertTrue(DisplayScreenMatcher.shouldIncludeScreen(
            hasHardwareNotch: true,
            showVirtualNotch: true
        ))
    }

    func testNotchlessDisplayRequiresVirtualNotchSetting() {
        XCTAssertFalse(DisplayScreenMatcher.shouldIncludeScreen(
            hasHardwareNotch: false,
            showVirtualNotch: false
        ))
        XCTAssertTrue(DisplayScreenMatcher.shouldIncludeScreen(
            hasHardwareNotch: false,
            showVirtualNotch: true
        ))
    }

    func testExternalOnlyTopologyHasNoTargetWhenVirtualNotchIsOff() {
        let targets = [false].filter {
            DisplayScreenMatcher.shouldIncludeScreen(
                hasHardwareNotch: $0,
                showVirtualNotch: false
            )
        }

        XCTAssertTrue(targets.isEmpty)
    }

    func testMixedTopologyKeepsOnlyHardwareNotchWhenVirtualNotchIsOff() {
        let targets = [true, false].filter {
            DisplayScreenMatcher.shouldIncludeScreen(
                hasHardwareNotch: $0,
                showVirtualNotch: false
            )
        }

        XCTAssertEqual(targets, [true])
    }
}
