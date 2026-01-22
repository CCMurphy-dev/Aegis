import Foundation

/// Checks if yabai integration is properly configured for Aegis
struct YabaiSetupChecker {

    enum SetupStatus {
        case ready                      // Everything configured
        case yabaiNotInstalled          // yabai binary not found
        case signalsNotConfigured       // yabai signals not registered
        case notifyScriptMissing        // aegis-yabai-notify script not installed
    }

    enum SAStatus {
        case loaded                     // SA is loaded and working
        case notLoaded                  // SA not loaded (needs sudo yabai --load-sa)
        case notInstalled               // SA not installed at all
        case unknown                    // Could not determine status
    }

    private static let yabaiPath = "/opt/homebrew/bin/yabai"
    private static var notifyScriptPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/aegis/aegis-yabai-notify"
    }
    private static let saPath = "/Library/ScriptingAdditions/yabai.osax"
    private static let aegisMarker = "AEGIS_INTEGRATION_START"

    /// Check full setup status
    static func check() -> SetupStatus {
        // 1. Check if yabai is installed
        guard FileManager.default.fileExists(atPath: yabaiPath) else {
            logWarning("Yabai not found at \(yabaiPath)")
            return .yabaiNotInstalled
        }

        // 2. Check if notify script exists
        guard FileManager.default.fileExists(atPath: notifyScriptPath) else {
            logWarning("Notify script not found at \(notifyScriptPath)")
            return .notifyScriptMissing
        }

        // 3. Check if signals are registered (runtime check)
        guard areSignalsConfigured() else {
            logWarning("Yabai signals not configured")
            return .signalsNotConfigured
        }

        logInfo("Yabai setup check: ready")
        return .ready
    }

    /// Quick check - just verify signals are configured (assumes yabai is installed)
    static func isConfigured() -> Bool {
        return check() == .ready
    }

    /// Check if Aegis integration is persisted in yabairc (survives yabai restart)
    static func isPersisted() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let yabairc = "\(home)/.config/yabai/yabairc"

        guard let contents = try? String(contentsOfFile: yabairc, encoding: .utf8) else {
            return false
        }

        return contents.contains(aegisMarker)
    }

    /// Check if aegis signals are registered in yabai (runtime)
    private static func areSignalsConfigured() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: yabaiPath)
        task.arguments = ["-m", "signal", "--list"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: data, as: UTF8.self)

            // Check for at least one aegis signal
            return output.contains("aegis_space_changed") || output.contains("aegis_window_focused")
        } catch {
            return false
        }
    }

    /// Check if yabai scripting addition (SA) is loaded
    static func checkSA() -> SAStatus {
        // First check if SA is installed
        guard FileManager.default.fileExists(atPath: saPath) else {
            logInfo("SA not installed at \(saPath)")
            return .notInstalled
        }

        // Check if yabai is installed
        guard FileManager.default.fileExists(atPath: yabaiPath) else {
            return .unknown
        }

        // Try to query spaces - this requires SA to be loaded
        // If SA is not loaded, yabai will return an error or empty result
        let task = Process()
        task.executableURL = URL(fileURLWithPath: yabaiPath)
        task.arguments = ["-m", "query", "--spaces"]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        task.standardOutput = stdoutPipe
        task.standardError = stderrPipe

        do {
            try task.run()
            task.waitUntilExit()

            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrOutput = String(decoding: stderrData, as: UTF8.self)

            // Check for SA-specific error messages
            if stderrOutput.contains("scripting-addition") ||
               stderrOutput.contains("payload") ||
               stderrOutput.contains("load-sa") {
                logWarning("SA not loaded: \(stderrOutput.trimmingCharacters(in: .whitespacesAndNewlines))")
                return .notLoaded
            }

            // If command succeeded with exit code 0, SA is loaded
            if task.terminationStatus == 0 {
                logInfo("SA check: loaded")
                return .loaded
            }

            // Non-zero exit but no SA error - might be other issue
            logWarning("SA check failed with exit code \(task.terminationStatus)")
            return .notLoaded
        } catch {
            logError("SA check error: \(error)")
            return .unknown
        }
    }

    /// Get user-friendly description of SA status
    static func saStatusDescription(_ status: SAStatus) -> String {
        switch status {
        case .loaded:
            return "Scripting addition loaded"
        case .notLoaded:
            return "Scripting addition not loaded (run: sudo yabai --load-sa)"
        case .notInstalled:
            return "Scripting addition not installed"
        case .unknown:
            return "Scripting addition status unknown"
        }
    }

    /// Get the path to the setup script bundled in the app
    static func getSetupScriptPath() -> String? {
        // First try the bundle resources
        if let bundlePath = Bundle.main.path(forResource: "setup-aegis-yabai", ofType: "sh") {
            return bundlePath
        }

        // Fallback: look in the AegisYabaiIntegration folder relative to executable
        let executableURL = Bundle.main.executableURL
        let appContentsURL = executableURL?.deletingLastPathComponent().deletingLastPathComponent()
        let resourcesPath = appContentsURL?.appendingPathComponent("Resources/setup-aegis-yabai.sh").path

        if let path = resourcesPath, FileManager.default.fileExists(atPath: path) {
            return path
        }

        return nil
    }

    /// Get user-friendly description of the setup status
    static func statusDescription(_ status: SetupStatus) -> String {
        switch status {
        case .ready:
            return "Yabai integration is configured and ready."
        case .yabaiNotInstalled:
            return "Yabai is not installed. Install it with: brew install koekeishiya/formulae/yabai"
        case .notifyScriptMissing:
            return "The Aegis notification script is not installed."
        case .signalsNotConfigured:
            return "Yabai signals are not configured for Aegis."
        }
    }

    /// Get the yabairc snippet for manual installation
    static func getYabaiRcSnippet() -> String {
        return """
        # AEGIS_INTEGRATION_START
        # Aegis window manager integration - add this to your ~/.config/yabai/yabairc
        AEGIS_NOTIFY="$HOME/.config/aegis/aegis-yabai-notify"
        yabai -m signal --remove aegis_space_changed 2>/dev/null || true
        yabai -m signal --remove aegis_space_destroyed 2>/dev/null || true
        yabai -m signal --remove aegis_window_focused 2>/dev/null || true
        yabai -m signal --remove aegis_window_created 2>/dev/null || true
        yabai -m signal --remove aegis_window_destroyed 2>/dev/null || true
        yabai -m signal --remove aegis_window_moved 2>/dev/null || true
        yabai -m signal --remove aegis_application_front_switched 2>/dev/null || true
        yabai -m signal --add event=space_changed action="YABAI_EVENT_TYPE=space_changed $AEGIS_NOTIFY" label=aegis_space_changed
        yabai -m signal --add event=space_destroyed action="YABAI_EVENT_TYPE=space_destroyed $AEGIS_NOTIFY" label=aegis_space_destroyed
        yabai -m signal --add event=window_focused action="YABAI_EVENT_TYPE=window_focused $AEGIS_NOTIFY" label=aegis_window_focused
        yabai -m signal --add event=window_created action="YABAI_EVENT_TYPE=window_created $AEGIS_NOTIFY" label=aegis_window_created
        yabai -m signal --add event=window_destroyed action="YABAI_EVENT_TYPE=window_destroyed $AEGIS_NOTIFY" label=aegis_window_destroyed
        yabai -m signal --add event=window_moved action="YABAI_EVENT_TYPE=window_moved $AEGIS_NOTIFY" label=aegis_window_moved
        yabai -m signal --add event=application_front_switched action="YABAI_EVENT_TYPE=application_front_switched $AEGIS_NOTIFY" label=aegis_application_front_switched
        # AEGIS_INTEGRATION_END
        """
    }
}
