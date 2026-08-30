import XCTest
@testable import Aegis

@MainActor
final class WorkspaceLabelFormatterTests: XCTestCase {
    private func space(_ id: Int, _ index: Int, _ name: String?, label: String? = nil) -> WMSpace {
        WMSpace(id: id, index: index, display: 1, label: label ?? "\(index)", workspaceName: name, layoutType: .scrolling, isFocused: false, isFullscreen: false)
    }

    private func labels(for spaces: [WMSpace], style: WorkspaceLabelStyle = .nameInitial, overrides: [String: String] = [:]) -> [String] {
        let labels = WorkspaceLabelFormatter.labels(for: spaces, style: style, overrides: overrides)
        return spaces.map { labels[$0.id]! }
    }

    func testCurrentNamedWorkspacesUseShortestUniquePrefixes() {
        let spaces = [space(1, 1, "Flow", label: "0"), space(2, 2, "Thesis", label: "1"), space(3, 3, "ChatGPT", label: "2"), space(4, 4, "Comms", label: "3"), space(5, 5, "Media", label: "4"), space(6, 6, "Ops", label: "5"), space(7, 7, "Browser Hub", label: "6"), space(8, 8, "Terminal Hub", label: "7")]
        XCTAssertEqual(labels(for: spaces), ["F", "Th", "Ch", "Co", "M", "O", "B", "Te"])
    }

    func testOrdinaryUniqueInitialsRemainOneGrapheme() {
        XCTAssertEqual(labels(for: [space(1, 1, "Alpha"), space(2, 2, "Beta")]), ["A", "B"])
    }

    func testShortNameStaysShortWhenLongerNameCanBeExtended() {
        XCTAssertEqual(labels(for: [space(1, 1, "A"), space(2, 2, "AB")]), ["A", "AB"])
    }

    func testCaseInsensitiveCollisionsGrowUntilUnique() {
        XCTAssertEqual(labels(for: [space(1, 1, "apple"), space(2, 2, "Apricot")]), ["app", "Apr"])
    }

    func testWhitespaceIsTrimmedAndUnicodeGraphemesArePreserved() {
        XCTAssertEqual(labels(for: [space(1, 1, "  👨‍👩‍👧‍👦 Family  "), space(2, 2, "🚀 Launch")]), ["👨‍👩‍👧‍👦", "🚀"])
    }

    func testEmptyAndIdenticalNamesFallBackToExistingNumericLabels() {
        XCTAssertEqual(labels(for: [space(1, 1, "", label: "0"), space(2, 2, "Same", label: "1"), space(3, 3, "Same", label: "2")]), ["0", "1", "2"])
    }

    func testGeneratedPrefixesAvoidOriginalFallbackLabels() {
        let spaces = [
            space(1, 1, "", label: "0"),
            space(2, 2, "Same", label: "1"),
            space(3, 3, "Same", label: "2"),
            space(4, 4, "0Ops", label: "3")
        ]

        XCTAssertEqual(labels(for: spaces), ["0", "1", "2", "0O"])
    }

    func testWhitespaceOnlyOriginalLabelFallsBackToIndex() {
        XCTAssertEqual(labels(for: [space(1, 7, "", label: "  ")]), ["7"])
    }

    func testIndexStylePreservesExistingDisplayLabels() {
        XCTAssertEqual(labels(for: [space(1, 8, "Flow", label: "0"), space(2, 9, nil, label: nil)], style: .index), ["0", "9"])
    }

    func testOverridesWinInBothStylesAndTrimWhitespace() {
        let spaces = [space(1, 1, "Flow", label: "0"), space(2, 2, "Thesis", label: "1"), space(3, 3, nil, label: "2")]
        let overrides = ["0": "  Focus  ", "1": "   ", "unknown": "Ignored"]
        XCTAssertEqual(labels(for: spaces, style: .nameInitial, overrides: overrides), ["Focus", "T", "2"])
        XCTAssertEqual(labels(for: spaces, style: .index, overrides: overrides), ["Focus", "1", "2"])
    }

    func testNilAndEmptyOriginalLabelsUseEffectiveNumericKey() {
        XCTAssertEqual(labels(for: [space(1, 1, "Flow", label: nil), space(2, 2, "Thesis", label: "")], style: .nameInitial, overrides: ["1": "Flow", "2": "Thesis"]), ["Flow", "Thesis"])
    }

    func testChangingOverridesChangesLabelsWithoutChangingWorkspaces() {
        let spaces = [space(1, 1, "Flow", label: "0")]
        XCTAssertEqual(labels(for: spaces), ["F"])
        XCTAssertEqual(labels(for: spaces, overrides: ["0": "Task"]), ["Task"])
    }
}

@MainActor
final class WorkspaceLabelStylePreferenceTests: XCTestCase {
    private let suiteName = "AegisTests.WorkspaceLabelStylePreference"

    func testMissingPreferenceUsesIndexDefault() {
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)
        XCTAssertEqual(WorkspaceLabelStylePreference.load(from: defaults), .index)
    }

    func testStoredPreferenceLoadsNameInitial() {
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(WorkspaceLabelStyle.nameInitial.rawValue, forKey: WorkspaceLabelStylePreference.key)
        XCTAssertEqual(WorkspaceLabelStylePreference.load(from: defaults), .nameInitial)
    }

    func testInvalidPreferenceUsesIndexDefault() {
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("unexpected", forKey: WorkspaceLabelStylePreference.key)
        XCTAssertEqual(WorkspaceLabelStylePreference.load(from: defaults), .index)
    }

    func testStoredOverridesLoadAsStringDictionary() {
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(["0": "Flow", "1": "Thesis"], forKey: WorkspaceLabelOverridesPreference.key)
        XCTAssertEqual(WorkspaceLabelOverridesPreference.load(from: defaults), ["0": "Flow", "1": "Thesis"])
    }

    func testEmptyStoredOverridesLoadEmpty() {
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set([String: String](), forKey: WorkspaceLabelOverridesPreference.key)
        XCTAssertEqual(WorkspaceLabelOverridesPreference.load(from: defaults), [:])
        XCTAssertEqual(WorkspaceLabelOverridesPreference.defaultValue, [:])
    }
}

@MainActor
final class WorkspaceLabelConfigDataTests: XCTestCase {
    func testNameInitialDecodesAndRoundTrips() throws {
        let input = Data(#"{"workspaceLabelStyle":"nameInitial","workspaceLabelOverrides":{"0":"Flow"}}"#.utf8)
        let decoded = try JSONDecoder().decode(AegisConfigData.self, from: input)
        XCTAssertEqual(decoded.workspaceLabelStyle, WorkspaceLabelStyle.nameInitial.rawValue)
        XCTAssertEqual(decoded.workspaceLabelOverrides, ["0": "Flow"])
        let exported = try JSONEncoder().encode(decoded)
        let roundTripped = try JSONDecoder().decode(AegisConfigData.self, from: exported)
        XCTAssertEqual(roundTripped.workspaceLabelStyle, WorkspaceLabelStyle.nameInitial.rawValue)
        XCTAssertEqual(roundTripped.workspaceLabelOverrides, ["0": "Flow"])
    }

    func testEmptyOverridesDecodeAndRoundTripAsEmptyMap() throws {
        let decoded = try JSONDecoder().decode(AegisConfigData.self, from: Data(#"{"workspaceLabelOverrides":{}}"#.utf8))
        XCTAssertEqual(decoded.workspaceLabelOverrides ?? ["unexpected": "value"], [:])
        let exported = try JSONEncoder().encode(decoded)
        let roundTripped = try JSONDecoder().decode(AegisConfigData.self, from: exported)
        XCTAssertEqual(roundTripped.workspaceLabelOverrides ?? ["unexpected": "value"], [:])
    }
}

@MainActor
final class RiftWorkspaceChangeDetectorTests: XCTestCase {
    private func snapshot(index: Int = 0, name: String = "Flow", layoutMode: String = "scrolling", isActive: Bool = true) -> RiftWorkspaceChangeSnapshot {
        RiftWorkspaceChangeSnapshot(index: index, name: name, layoutMode: layoutMode, isActive: isActive)
    }

    func testWorkspaceNameChangeIsDetected() {
        XCTAssertTrue(RiftWorkspaceChangeDetector.hasChanges(previous: [1: snapshot(name: "Flow")], current: [1: snapshot(name: "Renamed")]))
    }

    func testWindowCountChangeIsDetected() {
        let previous = [1: RiftWorkspaceChangeSnapshot(index: 0, name: "Flow", layoutMode: "scrolling", isActive: true, windowCount: 0)]
        let current = [1: RiftWorkspaceChangeSnapshot(index: 0, name: "Flow", layoutMode: "scrolling", isActive: true, windowCount: 1)]
        XCTAssertTrue(RiftWorkspaceChangeDetector.hasChanges(previous: previous, current: current))
    }

    func testIdenticalWorkspaceDataIsStable() {
        XCTAssertFalse(RiftWorkspaceChangeDetector.hasChanges(previous: [1: snapshot()], current: [1: snapshot()]))
    }
}
