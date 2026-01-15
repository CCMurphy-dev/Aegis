import Foundation
import ServiceManagement

/// Service to manage launch at login functionality using SMAppService (macOS 13+)
final class LaunchAtLoginService {
    static let shared = LaunchAtLoginService()

    private init() {}

    /// Check if launch at login is currently enabled
    var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            // Fallback for older macOS - check legacy login items
            return false
        }
    }

    /// Enable or disable launch at login
    func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                    logInfo("Launch at login enabled")
                } else {
                    try SMAppService.mainApp.unregister()
                    logInfo("Launch at login disabled")
                }
            } catch {
                logError("Failed to set launch at login: \(error.localizedDescription)")
            }
        } else {
            logWarning("Launch at login requires macOS 13.0 or later")
        }
    }

    /// Sync the config setting with actual system state
    /// Call this at app startup to ensure UI reflects reality
    func syncWithConfig() {
        let actualState = isEnabled
        if AegisConfig.shared.launchAtLogin != actualState {
            // Update config without triggering didSet (to avoid recursive call)
            DispatchQueue.main.async {
                // Temporarily disable observation
                AegisConfig.shared.launchAtLogin = actualState
            }
        }
    }
}
