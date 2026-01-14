import SwiftUI
import AppKit

/// Window controller for displaying the Settings Panel
class SettingsPanelController {
    static let shared = SettingsPanelController()
    private var settingsWindow: NSWindow?

    private init() {}

    /// Shows the Settings Panel window, creating it if needed
    func showSettings() {
        // If window already exists and is visible, just bring it to front
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Create the SwiftUI view
        let settingsView = SettingsPanelView()

        // Wrap in NSHostingController
        let hostingController = NSHostingController(rootView: settingsView)

        // Create window with larger default size
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Aegis Settings"
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.backgroundColor = NSColor.black.withAlphaComponent(0.95)
        window.isMovableByWindowBackground = true

        // Set minimum and maximum sizes
        window.minSize = NSSize(width: 600, height: 700)
        window.maxSize = NSSize(width: 900, height: 1200)

        // Set content size explicitly to ensure it renders at the correct size
        window.setContentSize(NSSize(width: 700, height: 800))

        // Center after setting size
        window.center()

        // Store reference
        settingsWindow = window

        // Show window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Hides the Settings Panel window
    func hideSettings() {
        settingsWindow?.close()
    }

    /// Toggles the Settings Panel visibility
    func toggleSettings() {
        if let window = settingsWindow, window.isVisible {
            hideSettings()
        } else {
            showSettings()
        }
    }
}
