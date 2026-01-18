import Cocoa
import SwiftUI
import Combine

// MARK: - MenuBarWindowController
// Manages the menu bar window lifecycle and visibility

class MenuBarWindowController: ObservableObject {
    private var menuBarWindow: MenuBarWindow?
    private let config = AegisConfig.shared

    // Window levels - computed once to avoid repeated CGWindowLevelForKey calls
    private let normalLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)))
    private let hiddenLevel = NSWindow.Level(rawValue: -1)

    /// Published fullscreen state that other components can observe
    @Published private(set) var currentSpaceIsFullscreen = false

    // MARK: - Window Creation

    func createWindow<Content: View>(with content: Content) {
        guard let screen = NSScreen.main else { return }

        // Menu bar window - only the interactive 40px area
        // Clicks below this window naturally pass through to windows underneath
        let frame = NSRect(
            x: 0,
            y: screen.frame.height - config.menuBarHeight,
            width: screen.frame.width,
            height: config.menuBarHeight
        )

        // Create custom window subclass that prevents becoming key
        menuBarWindow = MenuBarWindow(
            contentRect: frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        configureWindow()

        let hostingView = NSHostingView(rootView: content)
        menuBarWindow?.contentView = hostingView
        menuBarWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Window Configuration

    private func configureWindow() {
        menuBarWindow?.isOpaque = false
        menuBarWindow?.backgroundColor = .clear
        // Use mainMenu level (24) which is below notifications but above normal windows
        menuBarWindow?.level = normalLevel

        // Keep .canJoinAllSpaces so window appears on all normal Spaces
        // We'll hide it explicitly when entering fullscreen Spaces
        menuBarWindow?.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        menuBarWindow?.ignoresMouseEvents = false
        menuBarWindow?.hasShadow = false
    }

    // MARK: - Space-Based Visibility Control

    func updateVisibilityForSpace(isFullscreen: Bool) {
        currentSpaceIsFullscreen = isFullscreen

        if isFullscreen {
            // Hide in fullscreen by setting alpha to 0 and ignoring mouse events
            // This is better than orderOut() which doesn't work well with .canJoinAllSpaces
            print("🔒 Space is fullscreen - hiding Aegis menu bar")
            menuBarWindow?.alphaValue = 0
            menuBarWindow?.ignoresMouseEvents = true
        } else {
            // Show in normal spaces
            print("🌐 Space is normal - showing Aegis menu bar")
            menuBarWindow?.alphaValue = 1
            menuBarWindow?.ignoresMouseEvents = false
        }
    }

    // MARK: - Native Menu Bar Detection
    // Only hide when native menu is active, not based on mouse position

    func setVisibilityForNativeMenu(_ nativeMenuActive: Bool) {
        // Only apply this logic if we're not in a fullscreen space
        guard !currentSpaceIsFullscreen else { return }

        if nativeMenuActive {
            // Native menu is active, hide behind it
            if menuBarWindow?.level != hiddenLevel {
                menuBarWindow?.level = hiddenLevel
            }
        } else {
            // Native menu is not active, show normally
            if menuBarWindow?.level != normalLevel {
                menuBarWindow?.level = normalLevel
            }
            // Ensure ignoresMouseEvents is false when showing (in case it was set to true)
            if menuBarWindow?.ignoresMouseEvents == true {
                menuBarWindow?.ignoresMouseEvents = false
            }
        }
    }

    // MARK: - Window Ordering

    /// Re-assert window visibility after space transitions
    /// Call this when a space change is detected to ensure the custom menu bar
    /// stays above the native menu bar during the transition animation
    func reorderWindowForSpaceTransition() {
        guard let window = menuBarWindow else { return }
        guard !currentSpaceIsFullscreen else { return }

        // Re-order window to ensure it's properly attached to new space
        window.orderFront(nil)

        // Re-assert the window level to ensure it's above native menu bar
        if window.level != normalLevel {
            window.level = normalLevel
        }
    }

    // MARK: - Cleanup

    func hide() {
        menuBarWindow?.orderOut(nil)
        menuBarWindow = nil
    }

    // MARK: - Accessors

    var window: MenuBarWindow? {
        return menuBarWindow
    }

    var isInFullscreenSpace: Bool {
        return currentSpaceIsFullscreen
    }
}

// MARK: - Custom Window Class

// Custom window that prevents becoming key window (avoids focus stealing)
class MenuBarWindow: NSWindow {
    override var canBecomeKey: Bool {
        return false
    }

    override var canBecomeMain: Bool {
        return false
    }

    override var acceptsFirstResponder: Bool {
        return false
    }

    override func makeKey() {
        // Prevent becoming key window
    }

    override func becomeKey() {
        // Prevent becoming key window
    }

    override func makeMain() {
        // Prevent becoming main window
    }
}
