import CoreGraphics
import XCTest
@testable import Aegis

final class MenuBarFullscreenVisibilityPolicyTests: XCTestCase {
    func testManagedDisplayUsesNativeFullscreenFromFocusedWorkspace() {
        XCTAssertTrue(MenuBarFullscreenVisibilityPolicy.shouldHide(
            displayState: .managed,
            focusedSpaceIsFullscreen: true,
            hasFocusedSpace: true,
            previousValue: false
        ))
        XCTAssertFalse(MenuBarFullscreenVisibilityPolicy.shouldHide(
            displayState: .managed,
            focusedSpaceIsFullscreen: false,
            hasFocusedSpace: true,
            previousValue: true
        ))
    }

    func testManagedDisplayDoesNotHideRiftFullscreenWithinGaps() {
        // Rift's `.fullscreen` layout is a managed virtual layout, not native
        // macOS fullscreen. WMSpace.isFullscreen remains false in this case.
        XCTAssertFalse(MenuBarFullscreenVisibilityPolicy.shouldHide(
            displayState: .managed,
            focusedSpaceIsFullscreen: false,
            hasFocusedSpace: true,
            previousValue: false
        ))
    }

    func testNativeFullscreenAndUnmanagedStatesHideOnlyTheirDisplay() {
        XCTAssertTrue(MenuBarFullscreenVisibilityPolicy.shouldHide(
            displayState: .nativeFullscreen,
            focusedSpaceIsFullscreen: false,
            hasFocusedSpace: false,
            previousValue: false
        ))
        XCTAssertTrue(MenuBarFullscreenVisibilityPolicy.shouldHide(
            displayState: .unmanaged,
            focusedSpaceIsFullscreen: false,
            hasFocusedSpace: false,
            previousValue: false
        ))

        // A second managed display remains visible even while display one is
        // in a native fullscreen space.
        XCTAssertFalse(MenuBarFullscreenVisibilityPolicy.shouldHide(
            displayState: .managed,
            focusedSpaceIsFullscreen: false,
            hasFocusedSpace: true,
            previousValue: false
        ))
    }

    func testUnknownWithoutFocusedSpacePreservesPreviousDecision() {
        XCTAssertTrue(MenuBarFullscreenVisibilityPolicy.shouldHide(
            displayState: .unknown,
            focusedSpaceIsFullscreen: false,
            hasFocusedSpace: false,
            previousValue: true
        ))
        XCTAssertFalse(MenuBarFullscreenVisibilityPolicy.shouldHide(
            displayState: .unknown,
            focusedSpaceIsFullscreen: false,
            hasFocusedSpace: false,
            previousValue: false
        ))
    }

    func testUnknownWithFocusedSpaceUsesFocusedSpace() {
        XCTAssertTrue(MenuBarFullscreenVisibilityPolicy.shouldHide(
            displayState: .unknown,
            focusedSpaceIsFullscreen: true,
            hasFocusedSpace: true,
            previousValue: false
        ))
        XCTAssertFalse(MenuBarFullscreenVisibilityPolicy.shouldHide(
            displayState: .unknown,
            focusedSpaceIsFullscreen: false,
            hasFocusedSpace: true,
            previousValue: true
        ))
    }
}

final class RiftDisplaySpaceStateTests: XCTestCase {
    private func display(
        screenId: UInt32 = 42,
        space: UInt64? = 100,
        isActiveSpace: Bool = true,
        isActiveContext: Bool = true,
        activeSpaceIds: [UInt64] = [100],
        inactiveSpaceIds: [UInt64] = [101]
    ) -> RiftDisplay {
        RiftDisplay(
            uuid: "display-\(screenId)",
            name: nil,
            screenId: screenId,
            frame: RiftFrame(
                origin: RiftPoint(x: 0, y: 0),
                size: RiftSize(width: 1920, height: 1080)
            ),
            space: space,
            isActiveSpace: isActiveSpace,
            isActiveContext: isActiveContext,
            activeSpaceIds: activeSpaceIds,
            inactiveSpaceIds: inactiveSpaceIds
        )
    }

    func testRiftClassificationMatchesNativeSpaceFields() {
        XCTAssertEqual(
            RiftDisplaySpaceStateClassifier.state(space: nil, isActiveSpace: false),
            .nativeFullscreen
        )
        XCTAssertEqual(
            RiftDisplaySpaceStateClassifier.state(space: 100, isActiveSpace: false),
            .unmanaged
        )
        XCTAssertEqual(
            RiftDisplaySpaceStateClassifier.state(space: 100, isActiveSpace: true),
            .managed
        )
    }

    func testCompletelyEmptyRiftDisplayIsUnknown() {
        let placeholder = display(
            screenId: 0,
            space: nil,
            isActiveSpace: false,
            isActiveContext: false,
            activeSpaceIds: [],
            inactiveSpaceIds: []
        )
        let emptyPlaceholder = RiftDisplay(
            uuid: "",
            name: nil,
            screenId: placeholder.screenId,
            frame: placeholder.frame,
            space: placeholder.space,
            isActiveSpace: placeholder.isActiveSpace,
            isActiveContext: placeholder.isActiveContext,
            activeSpaceIds: placeholder.activeSpaceIds,
            inactiveSpaceIds: placeholder.inactiveSpaceIds
        )

        XCTAssertEqual(RiftDisplaySpaceStateClassifier.state(for: emptyPlaceholder), .unknown)
        XCTAssertEqual(RiftDisplaySpaceStateClassifier.state(for: display(space: nil)), .nativeFullscreen)
    }

    func testRiftDisplayConvertsToWMDisplayState() {
        XCTAssertEqual(display(space: nil).toWMDisplay(index: 1).spaceState, .nativeFullscreen)
        XCTAssertEqual(display(isActiveSpace: false).toWMDisplay(index: 1).spaceState, .unmanaged)
        XCTAssertEqual(display().toWMDisplay(index: 1).spaceState, .managed)
    }

    func testWMDisplayDefaultsToUnknown() {
        let display = WMDisplay(
            id: 1,
            uuid: "unknown",
            index: 1,
            frame: .zero,
            spaces: [],
            hasFocus: false
        )
        XCTAssertEqual(display.spaceState, .unknown)
    }
}

final class RiftDisplayChangeDetectorTests: XCTestCase {
    private func snapshot(
        screenId: UInt32 = 42,
        space: UInt64? = 100,
        isActiveSpace: Bool = true,
        isActiveContext: Bool = true,
        activeSpaceIds: [UInt64] = [100],
        inactiveSpaceIds: [UInt64] = [101]
    ) -> RiftDisplayChangeSnapshot {
        RiftDisplayChangeSnapshot(display: RiftDisplay(
            uuid: "display-\(screenId)",
            name: nil,
            screenId: screenId,
            frame: RiftFrame(
                origin: RiftPoint(x: 0, y: 0),
                size: RiftSize(width: 1920, height: 1080)
            ),
            space: space,
            isActiveSpace: isActiveSpace,
            isActiveContext: isActiveContext,
            activeSpaceIds: activeSpaceIds,
            inactiveSpaceIds: inactiveSpaceIds
        ))
    }

    func testSpaceAndActivityChangesAreDetected() {
        let previous = [1: snapshot()]
        XCTAssertTrue(RiftDisplayChangeDetector.hasChanges(
            previous: previous,
            current: [1: snapshot(space: nil)]
        ))
        XCTAssertTrue(RiftDisplayChangeDetector.hasChanges(
            previous: previous,
            current: [1: snapshot(isActiveSpace: false)]
        ))
        XCTAssertTrue(RiftDisplayChangeDetector.hasChanges(
            previous: previous,
            current: [1: snapshot(isActiveContext: false)]
        ))
    }

    func testActiveAndInactiveSpaceIdSetsAreComparedOrderIndependently() {
        let previous = [1: snapshot(activeSpaceIds: [100, 101], inactiveSpaceIds: [102, 103])]
        XCTAssertFalse(RiftDisplayChangeDetector.hasChanges(
            previous: previous,
            current: [1: snapshot(activeSpaceIds: [101, 100], inactiveSpaceIds: [103, 102])]
        ))
        XCTAssertTrue(RiftDisplayChangeDetector.hasChanges(
            previous: previous,
            current: [1: snapshot(activeSpaceIds: [100], inactiveSpaceIds: [102, 103])]
        ))
    }

    func testDisplayIdentitySetChangesAreDetected() {
        XCTAssertTrue(RiftDisplayChangeDetector.hasChanges(
            previous: [1: snapshot(screenId: 42)],
            current: [1: snapshot(screenId: 43)]
        ))
        XCTAssertTrue(RiftDisplayChangeDetector.hasChanges(
            previous: [1: snapshot(screenId: 42)],
            current: [2: snapshot(screenId: 42)]
        ))
    }
}
