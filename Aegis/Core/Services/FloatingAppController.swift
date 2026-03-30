import Cocoa

// MARK: - Floating App Definition
// Apps that can be quickly toggled from the menu bar

struct FloatingApp: Equatable {
    let name: String
    let bundleIdentifier: String

    var icon: NSImage {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }
        return NSWorkspace.shared.icon(forFileType: "app")
    }

    /// Create a FloatingApp from a bundle identifier
    /// Returns nil if the app is not installed
    static func from(bundleIdentifier: String) -> FloatingApp? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }

        // Use CFBundleName for accurate app name matching (same as yabai reports)
        // This fixes apps like iTerm2 where path is "iTerm.app" but name is "iTerm2"
        let name: String
        if let bundle = Bundle(url: appURL),
           let bundleName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
            name = bundleName
        } else {
            // Fallback to path-based name
            name = appURL.deletingPathExtension().lastPathComponent
        }

        return FloatingApp(name: name, bundleIdentifier: bundleIdentifier)
    }

    /// Get apps from config's launcherApps bundle identifiers
    /// Filters out any apps that aren't installed
    static func appsFromConfig() -> [FloatingApp] {
        let config = AegisConfig.shared
        return config.launcherApps.compactMap { FloatingApp.from(bundleIdentifier: $0) }
    }

    static func == (lhs: FloatingApp, rhs: FloatingApp) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier
    }
}

// MARK: - Floating App Controller
// Manages toggling floating utility apps - reuses existing window or opens new one

class FloatingAppController {
    private let windowManager: WindowManagerProtocol

    init(windowManager: WindowManagerProtocol) {
        self.windowManager = windowManager
    }

    /// Toggle app: focus existing window (moving to current space) or open/activate
    func toggle(_ app: FloatingApp) {
        if let windowId = findExistingWindow(for: app) {
            focusAndMoveToCurrentSpace(windowId: windowId)
        } else {
            openApp(app)
        }
    }

    /// Find an existing window ID for the app
    private func findExistingWindow(for app: FloatingApp) -> Int? {
        let windows = windowManager.getAllWindows()

        // Find first window for this app
        // For Finder: exclude empty titles and progress dialogs
        // For other apps: allow empty titles (e.g., System Settings has empty title)
        let appWindow = windows.first { window in
            guard window.app == app.name else { return false }

            // Finder-specific filters
            if app.bundleIdentifier == "com.apple.finder" {
                return window.title != "" &&
                       !window.title.contains("Moving") &&
                       !window.title.contains("Copying")
            }

            // Other apps: just match by name
            return true
        }

        return appWindow?.id
    }

    /// Focus window, move it to current space, and ensure it floats
    private func focusAndMoveToCurrentSpace(windowId: Int) {
        let spaces = windowManager.getCurrentSpaces()
        guard let currentSpace = spaces.first(where: { $0.isFocused }) else {
            windowManager.focusWindow(windowId)
            return
        }

        // Move to current space as floating window
        windowManager.moveWindowToSpaceFloatAndFocus(windowId, spaceIndex: currentSpace.index)
    }

    /// Open/activate the app, then float and center its window
    private func openApp(_ app: FloatingApp) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) else {
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.createsNewApplicationInstance = false

        // For Finder, open home directory to ensure a window opens
        if app.bundleIdentifier == "com.apple.finder" {
            let homeURL = FileManager.default.homeDirectoryForCurrentUser
            NSWorkspace.shared.open([homeURL], withApplicationAt: appURL, configuration: config) { [weak self] _, _ in
                self?.waitAndFloatCenterWindow(for: app)
            }
        } else {
            NSWorkspace.shared.openApplication(at: appURL, configuration: config) { [weak self] _, _ in
                self?.waitAndFloatCenterWindow(for: app)
            }
        }
    }

    /// Wait for the app's window to appear, then float and center it
    private func waitAndFloatCenterWindow(for app: FloatingApp) {
        // Poll for the window to appear (up to 2 seconds)
        var attempts = 0
        let maxAttempts = 20

        func checkForWindow() {
            attempts += 1
            if let windowId = findExistingWindow(for: app) {
                windowManager.floatAndCenterWindow(windowId)
            } else if attempts < maxAttempts {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    checkForWindow()
                }
            }
        }

        // Start checking after a short delay to let the app launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            checkForWindow()
        }
    }
}
