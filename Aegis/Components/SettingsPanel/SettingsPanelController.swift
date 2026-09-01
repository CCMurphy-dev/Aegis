import SwiftUI
import AppKit

/// Window controller for displaying the Settings Panel
class SettingsPanelController {
    static let shared = SettingsPanelController()
    private lazy var settingsWindow: NSWindow = createSettingsWindow()

    private init() {}

    private func createSettingsWindow() -> NSWindow {
        let settingsView = SettingsPanelView()
        let hostingController = NSHostingController(rootView: settingsView)

        let window = AegisOverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Aegis Settings"
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.level = .floating
        Self.configureSettingsWindow(window)
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 600, height: 700)
        window.maxSize = NSSize(width: 900, height: 1200)
        window.setContentSize(NSSize(width: 700, height: 800))
        window.center()

        return window
    }

    /// Keep the panel opaque and let AppKit resolve the native dynamic colors.
    /// The nil appearance is important: the settings window follows macOS,
    /// independently of Aegis's menu-bar theme.
    static func configureSettingsWindow(_ window: NSWindow) {
        window.backgroundColor = SettingsPalette.windowBackground
        window.isOpaque = true
        window.alphaValue = 1
        window.appearance = nil
    }

    /// Shows the Settings Panel window
    func showSettings() {
        settingsWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Hides the Settings Panel window
    func hideSettings() {
        settingsWindow.close()
    }

    /// Toggles the Settings Panel visibility
    func toggleSettings() {
        if settingsWindow.isVisible {
            hideSettings()
        } else {
            showSettings()
        }
    }
}
