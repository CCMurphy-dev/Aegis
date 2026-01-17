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
        let name = appURL.deletingPathExtension().lastPathComponent
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
    private let yabaiService: YabaiService

    init(yabaiService: YabaiService) {
        self.yabaiService = yabaiService
    }

    /// Toggle app: focus existing window (moving to current space) or open/activate
    func toggle(_ app: FloatingApp) {
        // Check if app has any windows
        if let windowId = findExistingWindow(for: app) {
            print("📁 FloatingAppController: Found existing \(app.name) window \(windowId), focusing")
            focusAndMoveToCurrentSpace(windowId: windowId)
        } else {
            print("📁 FloatingAppController: No \(app.name) window found, opening")
            openApp(app)
        }
    }

    /// Find an existing window ID for the app
    private func findExistingWindow(for app: FloatingApp) -> Int? {
        let windows = yabaiService.getAllWindows()

        // Find first window for this app that isn't a system/utility window
        let appWindow = windows.first { window in
            window.app == app.name &&
            window.title != "" &&  // Exclude empty title windows
            !window.title.contains("Moving") &&  // Exclude Finder progress dialogs
            !window.title.contains("Copying")
        }

        return appWindow?.id
    }

    /// Focus window and move it to the current space
    private func focusAndMoveToCurrentSpace(windowId: Int) {
        let spaces = yabaiService.getCurrentSpaces()
        guard let currentSpace = spaces.first(where: { $0.focused }) else {
            yabaiService.focusWindow(windowId)
            return
        }

        yabaiService.moveWindowToSpaceAndFocus(windowId, spaceIndex: currentSpace.index)
    }

    /// Open/activate the app
    private func openApp(_ app: FloatingApp) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) else {
            print("⚠️ FloatingAppController: Could not find \(app.name)")
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.createsNewApplicationInstance = false

        // For Finder, open home directory to ensure a window opens
        if app.bundleIdentifier == "com.apple.finder" {
            let homeURL = FileManager.default.homeDirectoryForCurrentUser
            NSWorkspace.shared.open([homeURL], withApplicationAt: appURL, configuration: config) { _, error in
                if let error = error {
                    print("⚠️ FloatingAppController: Failed to open \(app.name): \(error)")
                } else {
                    print("✅ FloatingAppController: Opened \(app.name)")
                }
            }
        } else {
            NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, error in
                if let error = error {
                    print("⚠️ FloatingAppController: Failed to open \(app.name): \(error)")
                } else {
                    print("✅ FloatingAppController: Opened \(app.name)")
                }
            }
        }
    }
}
