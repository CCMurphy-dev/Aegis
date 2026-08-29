import XCTest
@testable import Aegis

final class RiftReliabilityTests: XCTestCase {
    func testActiveEmptyWorkspaceIsIncludedInRefreshCoverage() {
        let activeEmptyWorkspace = RiftWorkspace(
            id: "VirtualWorkspaceId(1v1)",
            index: 4,
            name: "4",
            layoutMode: "scrolling",
            isActive: true,
            windowCount: 0,
            windows: []
        )

        XCTAssertEqual(RiftWorkspaceRefreshCoverage.workspaceIndices([activeEmptyWorkspace]), [5])
    }

    func testInactiveEmptyWorkspaceIsExcludedFromRefreshCoverage() {
        let inactiveEmptyWorkspace = RiftWorkspace(
            id: "VirtualWorkspaceId(1v1)",
            index: 4,
            name: "4",
            layoutMode: "scrolling",
            isActive: false,
            windowCount: 0,
            windows: []
        )

        XCTAssertEqual(RiftWorkspaceRefreshCoverage.workspaceIndices([inactiveEmptyWorkspace]), [])
    }
}
