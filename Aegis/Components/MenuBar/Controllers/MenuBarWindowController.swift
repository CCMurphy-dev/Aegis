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

    /// Native-menu visibility changes must not make an unresolved window
    /// interactive before its first coherent space update.
    private var hasResolvedSpaceState = false
    private var nativeMenuActive = false

    /// The screen this menu bar is displayed on
    private var targetScreen: NSScreen?

    // MARK: - Window Creation

    func createWindow<Content: View>(with content: Content, for screen: NSScreen? = nil) {
        let targetScreen = screen ?? NSScreen.main
        guard let screen = targetScreen else { return }
        self.targetScreen = screen
        hasResolvedSpaceState = false
        nativeMenuActive = false

        // Menu bar window - only the interactive 40px area
        // Clicks below this window naturally pass through to windows underneath
        let frame = NSRect(
            x: screen.frame.origin.x,
            y: screen.frame.origin.y + screen.frame.height - config.menuBarHeight,
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
        if #available(macOS 13, *) { hostingView.sceneBridgingOptions = [] }
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        menuBarWindow?.contentView = hostingView
        menuBarWindow?.makeKeyAndOrderFront(nil)
        // Re-assert after orderFront — macOS can reset collection behavior during window server registration
        menuBarWindow?.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
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
        // Keep a newly created window inert until the view model resolves the
        // display's fullscreen state. This covers launch and rebuilds that
        // happen while the display is already in native fullscreen.
        menuBarWindow?.alphaValue = 0
        menuBarWindow?.ignoresMouseEvents = true
        menuBarWindow?.hasShadow = false
    }

    // MARK: - Space-Based Visibility Control

    func updateVisibilityForSpace(isFullscreen: Bool) {
        currentSpaceIsFullscreen = isFullscreen

        if isFullscreen {
            // Hide in fullscreen by setting alpha to 0 and ignoring mouse events
            // This is better than orderOut() which doesn't work well with .canJoinAllSpaces
            menuBarWindow?.alphaValue = 0
            menuBarWindow?.ignoresMouseEvents = true
        } else {
            // Show in normal spaces
            menuBarWindow?.alphaValue = 1
            menuBarWindow?.ignoresMouseEvents = false
        }
        hasResolvedSpaceState = true
        applyNativeMenuVisibility()
    }

    // MARK: - Native Menu Bar Detection
    // Only hide when native menu is active, not based on mouse position

    func setVisibilityForNativeMenu(_ nativeMenuActive: Bool) {
        self.nativeMenuActive = nativeMenuActive
        applyNativeMenuVisibility()
    }

    private func applyNativeMenuVisibility() {
        // Only apply this logic after the fullscreen state is resolved and if
        // we're not in a fullscreen space.
        guard hasResolvedSpaceState, !currentSpaceIsFullscreen else { return }

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
        // Move off-screen and make invisible before orderOut to cleanly
        // deregister from window server without breaking newly created windows
        menuBarWindow?.alphaValue = 0
        menuBarWindow?.setFrame(NSRect(x: -10000, y: -10000, width: 1, height: 1), display: false)
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

    /// Check if the window is in a healthy visible state
    var isHealthy: Bool {
        guard let window = menuBarWindow else { return false }
        return window.isVisible
            && window.alphaValue > 0
            && window.frame.origin.x >= -1000
            && window.collectionBehavior.contains(.canJoinAllSpaces)
            && (!window.ignoresMouseEvents || currentSpaceIsFullscreen)
    }
}

// MARK: - Custom Window Class

// Custom window that prevents becoming key window (avoids focus stealing)
class MenuBarWindow: AegisOverlayWindow {
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
