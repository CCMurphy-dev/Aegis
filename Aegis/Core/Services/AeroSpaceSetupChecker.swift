import Foundation

/// Checks if AeroSpace FIFO pipe integration is properly configured for Aegis
struct AeroSpaceSetupChecker {

    enum SetupStatus {
        case ready                      // Everything configured
        case aeroSpaceNotInstalled      // aerospace binary not found
        case notifyScriptMissing        // aegis-aerospace-notify script not installed
        case configNotSetUp             // exec-on-workspace-change not in config
    }

    private static let aeroSpacePaths = ["/opt/homebrew/bin/aerospace", "/usr/local/bin/aerospace"]
    private static var notifyScriptPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/aegis/aegis-aerospace-notify"
    }
    private static var aeroSpaceConfigPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.aerospace.toml"
    }

    /// Check full setup status
    static func check() -> SetupStatus {
        // 1. Check if aerospace is installed
        guard aeroSpacePaths.contains(where: { FileManager.default.fileExists(atPath: $0) }) else {
            logWarning("AeroSpace CLI not found")
            return .aeroSpaceNotInstalled
        }

        // 2. Check if notify script exists
        guard FileManager.default.fileExists(atPath: notifyScriptPath) else {
            logWarning("AeroSpace notify script not found at \(notifyScriptPath)")
            return .notifyScriptMissing
        }

        // 3. Check if aerospace config has the exec-on-workspace-change hook
        guard isConfigured() else {
            logWarning("AeroSpace config missing exec-on-workspace-change for Aegis")
            return .configNotSetUp
        }

        logInfo("AeroSpace setup check: ready")
        return .ready
    }

    /// Quick check
    static func isReady() -> Bool {
        return check() == .ready
    }

    /// Check if aerospace config contains the Aegis hook
    private static func isConfigured() -> Bool {
        guard let contents = try? String(contentsOfFile: aeroSpaceConfigPath, encoding: .utf8) else {
            return false
        }
        return contents.contains("aegis-aerospace-notify")
    }

    /// Get user-friendly description
    static func statusDescription(_ status: SetupStatus) -> String {
        switch status {
        case .ready:
            return "AeroSpace integration is configured and ready."
        case .aeroSpaceNotInstalled:
            return "AeroSpace is not installed."
        case .notifyScriptMissing:
            return "The Aegis notification script is not installed."
        case .configNotSetUp:
            return "AeroSpace config needs exec-on-workspace-change hook."
        }
    }
}
