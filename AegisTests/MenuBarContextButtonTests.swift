import XCTest
@testable import Aegis

@MainActor
final class ContextButtonInteractionPolicyTests: XCTestCase {
    func testNormalPrimaryClickExecutesSelectedAction() {
        XCTAssertEqual(ContextButtonInteractionPolicy.primaryClick(menuOnly: false), .selectAction)
    }

    func testMenuOnlyPrimaryClickRequestsMenu() {
        XCTAssertEqual(ContextButtonInteractionPolicy.primaryClick(menuOnly: true), .requestMenu)
    }

    func testRightClickAlwaysRequestsMenu() {
        XCTAssertEqual(ContextButtonInteractionPolicy.rightClick(), .requestMenu)
    }

    func testMenuOnlyScrollIsIgnored() {
        XCTAssertEqual(ContextButtonInteractionPolicy.scroll(menuOnly: true), .ignore)
    }

    func testNormalScrollSelectsAction() {
        XCTAssertEqual(ContextButtonInteractionPolicy.scroll(menuOnly: false), .selectAction)
    }
}

@MainActor
final class ContextButtonConfigTests: XCTestCase {
    func testMenuOnlyDecodesAndRoundTrips() throws {
        let input = Data(#"{"contextButtonMenuOnly":true}"#.utf8)
        let decoded = try JSONDecoder().decode(AegisConfigData.self, from: input)
        XCTAssertEqual(decoded.contextButtonMenuOnly, true)

        let exported = try JSONEncoder().encode(decoded)
        let roundTripped = try JSONDecoder().decode(AegisConfigData.self, from: exported)
        XCTAssertEqual(roundTripped.contextButtonMenuOnly, true)
    }
}

@MainActor
final class ContextButtonMenuOnlyPreferenceTests: XCTestCase {
    private let suiteName = "AegisTests.ContextButtonMenuOnlyPreference"

    func testMissingPreferenceUsesFalseDefault() {
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)

        XCTAssertFalse(ContextButtonMenuOnlyPreference.load(from: defaults))
    }

    func testStoredPreferenceLoadsTrue() {
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: ContextButtonMenuOnlyPreference.key)

        XCTAssertTrue(ContextButtonMenuOnlyPreference.load(from: defaults))
    }
}
