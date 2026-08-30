import XCTest
@testable import Aegis

@MainActor
final class AccessibilityPermissionTests: XCTestCase {
    func testTrustedStartupChecksSilentlyWithoutPrompting() {
        let runtime = FakeAppSwitcherRuntime()
        runtime.trusted = true
        let coordinator = AppSwitcherRecoveryCoordinator(runtime: runtime)

        coordinator.start(enabled: true)

        XCTAssertEqual(runtime.prompts, [false])
        XCTAssertEqual(runtime.createCount, 1)
        XCTAssertEqual(coordinator.health, .running)
    }

    func testDeniedStartupPromptsOnceAfterSilentCheck() {
        let runtime = FakeAppSwitcherRuntime()
        let scheduler = RecoveryTestScheduler()
        let coordinator = AppSwitcherRecoveryCoordinator(
            runtime: runtime,
            schedule: { delay, action in scheduler.schedule(delay: delay, action: action) }
        )

        coordinator.start(enabled: true)

        XCTAssertEqual(runtime.prompts, [false, true])
        XCTAssertEqual(coordinator.health, .permissionRequired)
    }

    func testRepeatedRetryAndActivationStartsNeverPromptAgain() {
        let runtime = FakeAppSwitcherRuntime()
        let scheduler = RecoveryTestScheduler()
        let coordinator = AppSwitcherRecoveryCoordinator(
            runtime: runtime,
            schedule: { delay, action in scheduler.schedule(delay: delay, action: action) }
        )

        coordinator.start(enabled: true)
        coordinator.retry(enabled: true)
        coordinator.start(enabled: true)
        coordinator.retry(enabled: true)

        XCTAssertEqual(runtime.prompts.filter { $0 }.count, 1)
        XCTAssertEqual(runtime.prompts, [false, true, false, false, false])
        XCTAssertEqual(coordinator.health, .permissionRequired)
    }
}
