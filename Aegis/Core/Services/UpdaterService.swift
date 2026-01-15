import Foundation
import Combine
import Sparkle
import AppKit

/// Delegate to customize Sparkle's user driver behavior (window levels, etc.)
final class SparkleUserDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    /// Make Sparkle windows appear above floating windows like our Settings panel
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        // When Sparkle shows its window, ensure it appears above our floating windows
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for window in NSApp.windows {
                // Find Sparkle's update window by checking for its class name
                let className = String(describing: type(of: window))
                if className.contains("SPU") || window.title.contains("Update") || window.title.contains("Aegis") && window.title != "Aegis Settings" {
                    window.level = .modalPanel
                    window.orderFrontRegardless()
                }
            }
        }
    }
}

/// Manages automatic updates using Sparkle framework
/// Provides a simple interface to check for updates and configure update behavior
@MainActor
final class UpdaterService: ObservableObject {

    static let shared = UpdaterService()

    /// The Sparkle updater controller
    private let updaterController: SPUStandardUpdaterController

    /// User driver delegate for window level customization
    private let userDriverDelegate = SparkleUserDriverDelegate()

    /// Published state for UI binding
    @Published var canCheckForUpdates: Bool = false
    @Published var lastUpdateCheck: Date?

    private init() {
        // Initialize the updater controller with our custom delegate
        // startingUpdater: true starts checking for updates automatically based on Info.plist settings
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: userDriverDelegate
        )

        // Bind canCheckForUpdates to the updater's state
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
    }

    /// Manually check for updates
    /// Shows the update UI if an update is available
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
        lastUpdateCheck = Date()
        logInfo("Manual update check initiated")
    }

    /// Get the current app version
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    /// Check if automatic update checks are enabled
    var automaticChecksEnabled: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    /// The update check interval in seconds (default: 1 day)
    var updateCheckInterval: TimeInterval {
        get { updaterController.updater.updateCheckInterval }
        set { updaterController.updater.updateCheckInterval = newValue }
    }
}
