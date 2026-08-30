import XCTest
@testable import Aegis

@MainActor
final class SwitcherWorkspaceLabelTests: XCTestCase {
    private func space(id: Int, index: Int, label: String) -> WMSpace {
        WMSpace(
            id: id,
            index: index,
            display: 1,
            label: label,
            workspaceName: label,
            layoutType: .scrolling,
            isFocused: false,
            isFullscreen: false
        )
    }

    func testSwitcherUsesConfiguredLabelInsteadOfWindowManagerIndex() {
        let group = SpaceGroup(spaceIndex: 4, spaceLabel: "E", isFocused: false, windows: [])
        XCTAssertEqual(group.displayLabel, "E")
    }

    func testSwitcherFallsBackToWindowManagerIndexWithoutDisplayLabel() {
        let group = SpaceGroup(spaceIndex: 1, spaceLabel: nil, isFocused: true, windows: [])
        XCTAssertEqual(group.displayLabel, "1")
    }

    func testSwitcherFallsBackToWindowManagerIndexForEmptyDisplayLabel() {
        let group = SpaceGroup(spaceIndex: 9, spaceLabel: "", isFocused: false, windows: [])
        XCTAssertEqual(group.displayLabel, "9")
    }

    func testYabaiSwitcherLabelsApplyOverrides() {
        let labels = SwitcherSpaceLabelResolver.labels(
            for: [space(id: 1, index: 1, label: "1")],
            style: .index,
            overrides: ["1": "Flow"]
        )

        XCTAssertEqual(labels[1], "Flow")
    }

    func testLabelColumnExpandsForMultiCharacterLabels() {
        XCTAssertGreaterThan(
            SwitcherSpaceLabelLayout.columnWidth(for: ["Flow"]),
            SwitcherSpaceLabelLayout.minimumColumnWidth
        )
    }

    func testLabelColumnCapsVeryLongLabels() {
        XCTAssertEqual(
            SwitcherSpaceLabelLayout.columnWidth(for: [String(repeating: "Workspace", count: 30)]),
            SwitcherSpaceLabelLayout.maximumColumnWidth
        )
    }
}
