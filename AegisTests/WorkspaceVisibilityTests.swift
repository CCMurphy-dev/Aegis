import XCTest
@testable import Aegis

@MainActor
final class WorkspaceVisibilityPolicyTests: XCTestCase {
    private func space(_ id: Int, occupied: Int, focused: Bool = false) -> WMSpace {
        WMSpace(id: id, index: id, display: 1, label: "\(id)", workspaceName: nil, layoutType: .scrolling, isFocused: focused, isFullscreen: false, windowCount: occupied, windowCountIsKnown: true)
    }

    func testDisabledShowsAllSpaces() {
        XCTAssertEqual(WorkspaceVisibilityPolicy.visibleSpaces([space(0, occupied: 0), space(1, occupied: 2)], hideEmpty: false).map(\.id), [0, 1])
    }

    func testEnabledKeepsOccupiedAndFocusedEmptySpaces() {
        XCTAssertEqual(WorkspaceVisibilityPolicy.visibleSpaces([space(0, occupied: 0), space(1, occupied: 3), space(2, occupied: 0, focused: true)], hideEmpty: true).map(\.id), [1, 2])
    }

    func testExcludedIconsDoNotAffectOccupancy() {
        XCTAssertEqual(WorkspaceVisibilityPolicy.visibleSpaces([space(0, occupied: 1)], hideEmpty: true).map(\.id), [0])
    }

    func testUnknownRefreshRetainsPreviouslyOccupiedSpace() {
        let unknown = WMSpace(id: 3, index: 3, display: 2, label: "3", workspaceName: "Ops", layoutType: .scrolling, isFocused: false, isFullscreen: false, windowCount: 0, windowCountIsKnown: false)
        XCTAssertEqual(WorkspaceVisibilityPolicy.visibleSpaces([unknown], hideEmpty: true, previousCounts: [3: 1]).map(\.id), [3])
    }

    func testUnknownEmptySpaceRemainsHiddenUntilOccupied() {
        let unknown = WMSpace(id: 4, index: 4, display: 1, label: "4", workspaceName: "Media", layoutType: .scrolling, isFocused: false, isFullscreen: false, windowCount: 0, windowCountIsKnown: false)
        XCTAssertTrue(WorkspaceVisibilityPolicy.visibleSpaces([unknown], hideEmpty: true).isEmpty)
    }

    func testSpaceAppearsAndDisappearsAsOccupancyChanges() {
        let empty = space(5, occupied: 0)
        let occupied = space(5, occupied: 1)
        XCTAssertTrue(WorkspaceVisibilityPolicy.visibleSpaces([empty], hideEmpty: true).isEmpty)
        XCTAssertEqual(WorkspaceVisibilityPolicy.visibleSpaces([occupied], hideEmpty: true).map(\.id), [5])
        XCTAssertTrue(WorkspaceVisibilityPolicy.visibleSpaces([empty], hideEmpty: true).isEmpty)
    }

    func testFilteringOneDisplayDoesNotPullInFocusedSpaceFromAnother() {
        let local = space(1, occupied: 0)
        let remoteFocused = WMSpace(id: 2, index: 2, display: 2, label: "2", workspaceName: "ChatGPT", layoutType: .scrolling, isFocused: true, isFullscreen: false, windowCount: 0, windowCountIsKnown: true)
        let displayOne = [local, remoteFocused].filter { $0.display == 1 }
        XCTAssertTrue(WorkspaceVisibilityPolicy.visibleSpaces(displayOne, hideEmpty: true).isEmpty)
    }

    func testOptimisticReorderDoesNotRenumberVisibleSubset() {
        let store = SpaceViewModelStore()
        let first = space(1, occupied: 1)
        let third = WMSpace(
            id: 3,
            index: 3,
            display: 1,
            label: "3",
            workspaceName: nil,
            layoutType: .scrolling,
            isFocused: false,
            isFullscreen: false,
            windowCount: 1,
            windowCountIsKnown: true
        )
        store.update(
            spaces: [first, third],
            displayLabelsBySpaceId: [1: "1", 3: "3"],
            windowIconsBySpace: [:],
            allWindowIconsBySpace: [:],
            focusedIndexBySpace: [:],
            activeSpaceIndices: []
        )

        store.reorderSpace(fromDisplayIndex: 1, toDisplayIndex: 3)

        XCTAssertEqual(store.spaceIds, [3, 1])
        XCTAssertEqual(store.viewModel(for: 3)?.space.index, 3)
        XCTAssertEqual(store.viewModel(for: 1)?.space.index, 1)
    }

    func testAuthoritativeEmptyRiftWorkspaceClearsCachedWindowFallback() {
        let staleWindow = RiftWindow(
            id: RiftWindowId(pid: 1, idx: 1),
            title: "Stale",
            frame: RiftFrame(
                origin: RiftPoint(x: 0, y: 0),
                size: RiftSize(width: 1, height: 1)
            ),
            isFloating: false,
            isFocused: false,
            bundleId: nil,
            appName: nil,
            windowServerId: 1
        )
        let workspace = RiftWorkspace(
            id: "VirtualWorkspaceId(1)",
            index: 0,
            name: "Empty",
            layoutMode: "bsp",
            isActive: false,
            windowCount: 0,
            windows: [staleWindow]
        )

        XCTAssertTrue(RiftWorkspaceWindowCachePolicy.hasAuthoritativeWindowData(for: workspace))
        let space = workspace.toWMSpace()
        XCTAssertEqual(space.windowCount, 0)
        XCTAssertTrue(WorkspaceVisibilityPolicy.visibleSpaces([space], hideEmpty: true).isEmpty)
    }

    func testIncompleteRiftWorkspaceKeepsCachedWindowFallback() {
        let workspace = RiftWorkspace(
            id: "VirtualWorkspaceId(2)",
            index: 1,
            name: "Inactive",
            layoutMode: "bsp",
            isActive: false,
            windowCount: 2,
            windows: []
        )

        XCTAssertFalse(RiftWorkspaceWindowCachePolicy.hasAuthoritativeWindowData(for: workspace))
    }
}

@MainActor
final class HideEmptyWorkspacesPreferenceTests: XCTestCase {
    private let suiteName = "AegisTests.HideEmptyWorkspacesPreference"

    func testMissingPreferenceUsesFalseDefault() {
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)
        XCTAssertFalse(HideEmptyWorkspacesPreference.load(from: defaults))
    }

    func testStoredPreferenceLoadsTrue() {
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: HideEmptyWorkspacesPreference.key)
        XCTAssertTrue(HideEmptyWorkspacesPreference.load(from: defaults))
    }
}

@MainActor
final class HideEmptyWorkspacesConfigTests: XCTestCase {
    func testHideEmptyWorkspacesDecodesAndRoundTrips() throws {
        let decoded = try JSONDecoder().decode(AegisConfigData.self, from: Data(#"{"hideEmptyWorkspaces":true}"#.utf8))
        XCTAssertEqual(decoded.hideEmptyWorkspaces, true)
        let roundTripped = try JSONDecoder().decode(AegisConfigData.self, from: JSONEncoder().encode(decoded))
        XCTAssertEqual(roundTripped.hideEmptyWorkspaces, true)
    }
}
