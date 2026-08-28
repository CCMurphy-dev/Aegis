import XCTest
@testable import Aegis

@MainActor
private final class FakePreviewPermissionRuntime: AppSwitcherPreviewPermissionRuntime {
    var authorized = false
    var requestCount = 0

    func screenCaptureAccessIsGranted() -> Bool { authorized }

    func requestScreenCaptureAccess() {
        requestCount += 1
    }
}

@MainActor
final class AppSwitcherPreviewPermissionCoordinatorTests: XCTestCase {
    func testDeniedPermissionRequestsOnlyOnceAndFallsBackToIcons() {
        let runtime = FakePreviewPermissionRuntime()
        let coordinator = AppSwitcherPreviewPermissionCoordinator(runtime: runtime)

        XCTAssertFalse(coordinator.prepareForCapture(enabled: true))
        XCTAssertFalse(coordinator.prepareForCapture(enabled: true))
        XCTAssertEqual(runtime.requestCount, 1)
        XCTAssertEqual(coordinator.health, .permissionRequired)
    }

    func testGrantedPermissionAllowsCaptureWithoutRequest() {
        let runtime = FakePreviewPermissionRuntime()
        runtime.authorized = true
        let coordinator = AppSwitcherPreviewPermissionCoordinator(runtime: runtime)

        XCTAssertTrue(coordinator.prepareForCapture(enabled: true))
        XCTAssertEqual(runtime.requestCount, 0)
        XCTAssertEqual(coordinator.health, .active)
    }

    func testActivationRecheckRestoresCaptureAfterGrant() {
        let runtime = FakePreviewPermissionRuntime()
        let coordinator = AppSwitcherPreviewPermissionCoordinator(runtime: runtime)

        XCTAssertFalse(coordinator.prepareForCapture(enabled: true))
        runtime.authorized = true
        coordinator.recheck(enabled: true)

        XCTAssertEqual(coordinator.health, .active)
        XCTAssertTrue(coordinator.prepareForCapture(enabled: true))
        XCTAssertEqual(runtime.requestCount, 1)
    }

    func testCaptureFailureUsesIconsUntilExplicitRetry() {
        let runtime = FakePreviewPermissionRuntime()
        runtime.authorized = true
        let coordinator = AppSwitcherPreviewPermissionCoordinator(runtime: runtime)

        XCTAssertTrue(coordinator.prepareForCapture(enabled: true))
        coordinator.captureFailed()
        XCTAssertFalse(coordinator.prepareForCapture(enabled: true))
        XCTAssertEqual(coordinator.health, .failed)

        coordinator.retry(enabled: true)
        XCTAssertEqual(coordinator.health, .active)
    }

    func testRetryRechecksWithoutAnotherPrompt() {
        let runtime = FakePreviewPermissionRuntime()
        let coordinator = AppSwitcherPreviewPermissionCoordinator(runtime: runtime)

        XCTAssertFalse(coordinator.prepareForCapture(enabled: true))
        coordinator.retry(enabled: true)

        XCTAssertEqual(runtime.requestCount, 1)
        XCTAssertEqual(coordinator.health, .permissionRequired)
    }

    func testDisabledPreviewsNeverRequestOrCapture() {
        let runtime = FakePreviewPermissionRuntime()
        let coordinator = AppSwitcherPreviewPermissionCoordinator(runtime: runtime)

        XCTAssertFalse(coordinator.prepareForCapture(enabled: false))
        XCTAssertEqual(runtime.requestCount, 0)
        XCTAssertEqual(coordinator.health, .disabled)
    }
}
