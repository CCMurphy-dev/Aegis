import Foundation
import Combine
import Sparkle

/// Manages automatic updates using Sparkle framework
/// Provides a simple interface to check for updates and configure update behavior
@MainActor
final class UpdaterService: ObservableObject {

    static let shared = UpdaterService()

    /// The Sparkle updater controller
    private let updaterController: SPUStandardUpdaterController

    /// Published state for UI binding
    @Published var canCheckForUpdates: Bool = false
    @Published var lastUpdateCheck: Date?

    private init() {
        // Initialize the updater controller
        // startingUpdater: true starts checking for updates automatically based on Info.plist settings
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
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
