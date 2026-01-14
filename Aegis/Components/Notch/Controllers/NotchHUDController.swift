import Cocoa
import SwiftUI
import Combine

class NotchHUDController: ObservableObject {
    private let systemInfoService: SystemInfoService
    private let musicService: MediaRemoteService
    private let eventRouter: EventRouter

    // Separate windows for music and volume/brightness
    private var musicWindow: NSWindow!
    private var overlayWindow: NSWindow!

    private var hideTimer: Timer?
    private var hideDeadline: TimeInterval = 0  // Timestamp when overlay should hide
    private var isAnimatingOverlay = false  // Track if overlay is mid-animation

    // View models that persist across updates
    private let overlayViewModel = OverlayHUDViewModel()
    private let musicViewModel = MusicHUDViewModel()

    /// Published property for music HUD visibility (forwarded from view model)
    @Published var isMusicHUDVisible: Bool = false

    /// Published property for overlay HUD visibility (forwarded from view model)
    @Published var isOverlayHUDVisible: Bool = false

    // Reference to menu bar view model for layout coordination
    private weak var menuBarViewModel: MenuBarViewModel?

    // Notch dimensions for width calculations
    private var notchDimensions: NotchDimensions?

    init(systemInfoService: SystemInfoService,
         musicService: MediaRemoteService,
         eventRouter: EventRouter) {
        self.systemInfoService = systemInfoService
        self.musicService = musicService
        self.eventRouter = eventRouter

        // Set up bindings to forward view model changes
        overlayViewModel.$isVisible.assign(to: &$isOverlayHUDVisible)
        musicViewModel.$isVisible.assign(to: &$isMusicHUDVisible)
    }

    /// Connect to menu bar view model for layout coordination
    func connectMenuBarViewModel(_ viewModel: MenuBarViewModel) {
        self.menuBarViewModel = viewModel
    }

    // MARK: - Window Preparation (called once at app startup)

    /// Prepare windows at app startup - MUST be called before any HUD interactions
    func prepareWindows() {
        prepareOverlayWindow()
        prepareMusicWindow()
    }

    private func prepareOverlayWindow() {
        guard let screen = NSScreen.main else {
            assertionFailure("No main screen available during overlay window preparation")
            return
        }

        let notchHeight = screen.safeAreaInsets.top
        let notchDimensions = NotchDimensions.calculate(for: screen)
        self.notchDimensions = notchDimensions  // Store for width calculations

        print("🪟 prepareOverlayWindow: notchHeight=\(notchHeight), notchWidth=\(notchDimensions.width), screen=\(screen.frame)")

        // Create the view ONCE with the persistent view model
        let hudView = MinimalHUDWrapper(
            viewModel: overlayViewModel,
            notchDimensions: notchDimensions,
            isVisible: Binding(
                get: { [weak self] in self?.overlayViewModel.isVisible ?? false },
                set: { [weak self] in self?.overlayViewModel.isVisible = $0 }
            )
        )

        // Simple centered layout without GeometryReader
        let wrappedView = ZStack {
            Color.clear
            VStack {
                hudView
                    .frame(height: notchHeight)
                Spacer()
            }
        }

        let hostingView = NSHostingView(rootView: wrappedView)
        hostingView.frame = screen.frame

        // Create window ONCE at startup
        overlayWindow = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        overlayWindow.isOpaque = false
        overlayWindow.backgroundColor = .clear
        overlayWindow.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        overlayWindow.ignoresMouseEvents = true
        overlayWindow.hasShadow = false
        overlayWindow.collectionBehavior = [.canJoinAllSpaces, .stationary]
        overlayWindow.isReleasedWhenClosed = false
        overlayWindow.contentView = hostingView

        // Order front immediately but invisible - this ensures proper initialization
        overlayWindow.orderFront(nil)
        overlayWindow.alphaValue = 0

        // Force initial layout pass
        overlayWindow.layoutIfNeeded()
    }

    private func prepareMusicWindow() {
        guard let screen = NSScreen.main else {
            assertionFailure("No main screen available during music window preparation")
            return
        }

        let notchHeight = screen.safeAreaInsets.top
        let notchDimensions = NotchDimensions.calculate(for: screen)

        // Create the persistent view ONCE with the view model
        let hudView = MusicHUDView(
            viewModel: musicViewModel,
            notchDimensions: notchDimensions,
            isVisible: Binding(
                get: { [weak self] in self?.isMusicHUDVisible ?? false },
                set: { [weak self] in self?.isMusicHUDVisible = $0 }
            )
        )

        // Simple centered layout matching overlay window approach
        let wrappedView = ZStack {
            Color.clear
            VStack {
                hudView
                    .frame(height: notchHeight)
                Spacer()
            }
        }

        let hostingView = NSHostingView(rootView: wrappedView)
        hostingView.frame = screen.frame

        // Create window ONCE at startup
        musicWindow = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        musicWindow.isOpaque = false
        musicWindow.backgroundColor = .clear
        musicWindow.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)))
        musicWindow.ignoresMouseEvents = true
        musicWindow.hasShadow = false
        musicWindow.collectionBehavior = [.canJoinAllSpaces, .stationary]
        musicWindow.isReleasedWhenClosed = false
        musicWindow.contentView = hostingView
        musicWindow.alphaValue = 0
        musicWindow.orderOut(nil)
    }

    // MARK: - Show HUDs

    func showVolume(level: Float, isMuted: Bool = false) {
        // CRITICAL: Only update animator target, not ViewModel level
        // This prevents SwiftUI re-renders on every event
        overlayViewModel.progressAnimator.setTarget(isMuted ? 0.0 : Double(level))

        let icon = isMuted ? "speaker.slash.fill" : MinimalHUDWrapper.volumeIcon(for: level)

        // Only update ViewModel on first show (for icon setup)
        if !overlayViewModel.isVisible {
            overlayViewModel.level = level
            overlayViewModel.isMuted = isMuted
            overlayViewModel.iconName = icon
            showOverlayHUD()
            updateOverlayHUDLayout(isVisible: true, isVolume: true)
        } else {
            // If already visible but switching modes (e.g., volume -> brightness -> volume),
            // update the icon without triggering full re-render
            if overlayViewModel.iconName != icon {
                overlayViewModel.iconName = icon
            }
        }

        // Bump hide deadline (lightweight timestamp update)
        bumpHideDeadline()
    }

    func showBrightness(level: Float) {
        // CRITICAL: Only update animator target, not ViewModel level
        // This prevents SwiftUI re-renders on every event
        overlayViewModel.progressAnimator.setTarget(Double(level))

        // Only update ViewModel on first show (for icon setup)
        if !overlayViewModel.isVisible {
            overlayViewModel.level = level
            overlayViewModel.isMuted = false
            overlayViewModel.iconName = "sun.max.fill"
            showOverlayHUD()
            updateOverlayHUDLayout(isVisible: true, isVolume: false)
        } else {
            // If already visible but switching from volume to brightness,
            // update the icon without triggering full re-render
            if overlayViewModel.iconName != "sun.max.fill" {
                overlayViewModel.iconName = "sun.max.fill"
            }
        }

        // Bump hide deadline (lightweight timestamp update)
        bumpHideDeadline()
    }

    func showMusic(info: MusicInfo) {
        print("🎵 NotchHUDController.showMusic: isPlaying=\(info.isPlaying), currentlyVisible=\(musicViewModel.isVisible)")

        // If not playing, hide the music HUD
        if !info.isPlaying {
            print("🎵 NotchHUDController: Playback stopped, hiding music HUD")
            hideMusicHUD()
            return
        }

        // Update the music view model with new info
        musicViewModel.updateInfo(info)

        // Show HUD if not already visible
        if !musicViewModel.isVisible {
            print("🎵 NotchHUDController: Showing music HUD")
            showMusicHUD()
        } else {
            print("🎵 NotchHUDController: Music HUD already visible, just updated info")
        }
    }

    // MARK: - Private helpers - Music HUD

    private func showMusicHUD() {
        print("🎵 showMusicHUD() called - currentlyVisible: \(musicViewModel.isVisible)")

        // If already visible, nothing to do (data already updated in ViewModel)
        guard !musicViewModel.isVisible else {
            // Ensure window is actually visible (might have been hidden)
            if musicWindow.alphaValue < 1 || !musicWindow.isVisible {
                print("🎵 showMusicHUD: Window was hidden, bringing back - alphaValue: \(musicWindow.alphaValue), isVisible: \(musicWindow.isVisible)")
                musicWindow.alphaValue = 1
                musicWindow.orderFrontRegardless()
            } else {
                print("🎵 showMusicHUD: Already visible and window is properly shown")
            }
            return
        }

        print("🎵 showMusicHUD: Ordering window front with full opacity")
        // Order window front with full opacity immediately
        musicWindow.alphaValue = 1
        musicWindow.orderFrontRegardless()

        // Force a layout pass with initial state (isVisible = false)
        // This ensures the view starts in its hidden position
        musicWindow.layoutIfNeeded()
        print("🎵 showMusicHUD: Layout forced, scheduling animation")

        // Update layout coordinator - Music HUD is showing
        updateMusicHUDLayout(isVisible: true)

        // Then animate to visible state
        // The MinimalHUDSide components will slide in smoothly
        DispatchQueue.main.async {
            print("🎵 showMusicHUD: Setting musicViewModel.isVisible = true (triggering slide-in animation)")
            self.musicViewModel.isVisible = true
        }
    }

    private func hideMusicHUD() {
        print("🎵 hideMusicHUD() called - currentlyVisible: \(musicViewModel.isVisible)")

        // Check if already hidden
        if !musicViewModel.isVisible {
            print("🎵 hideMusicHUD: Already hidden, nothing to do")
            return
        }

        print("🎵 hideMusicHUD: Setting musicViewModel.isVisible = false (triggering slide-out animation)")
        // Trigger slide-out animation via view model
        // MinimalHUDSide components will slide back under the notch
        musicViewModel.isVisible = false

        // Update layout coordinator - Music HUD is hiding
        updateMusicHUDLayout(isVisible: false)

        // After animation completes, hide the window
        // Allow extra time for spring animation to finish (0.3s spring response + buffer)
        print("🎵 hideMusicHUD: Scheduled window hiding in 0.4s")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            // Only hide if still supposed to be hidden
            if !self.musicViewModel.isVisible {
                print("🎵 hideMusicHUD: Animation complete, hiding window (alphaValue: 0, orderOut)")
                self.musicWindow.alphaValue = 0
                self.musicWindow.orderOut(nil)
            } else {
                print("🎵 hideMusicHUD: Animation complete but HUD is visible again, keeping window shown")
            }
        }
    }

    // MARK: - Private helpers - Overlay HUD (volume/brightness)

    private func showOverlayHUD() {
        // If already visible, nothing to do (data already updated in ViewModel)
        guard !overlayViewModel.isVisible else {
            // Ensure window is actually visible (might have been hidden by animation)
            overlayWindow.alphaValue = 1
            overlayWindow.orderFrontRegardless()
            return
        }

        // Order window front and make visible
        overlayWindow.alphaValue = 1
        overlayWindow.orderFrontRegardless()

        // Force a layout pass with isVisible = false (before animation)
        overlayWindow.layoutIfNeeded()

        // CRITICAL: Trigger animation on next run loop to ensure view is ready
        DispatchQueue.main.async {
            // Set visible to trigger slide-in animation
            self.overlayViewModel.isVisible = true
            self.isAnimatingOverlay = true

            // Clear animation flag after animation completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.isAnimatingOverlay = false
            }
        }

        // Start hide timer if not already running
        if hideTimer == nil {
            startHideTimer()
        }
    }

    // MARK: - Auto-hide

    /// Bump the hide deadline (lightweight - just updates timestamp)
    private func bumpHideDeadline() {
        hideDeadline = Date().timeIntervalSinceReferenceDate + 1.5
    }

    /// Start the hide timer (only called once when showing)
    private func startHideTimer() {
        hideTimer?.invalidate()
        // Check every 0.1s if we've passed the deadline
        hideTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if Date().timeIntervalSinceReferenceDate >= self.hideDeadline {
                self.hideOverlayHUD()
            }
        }
    }

    private func hideOverlayHUD() {
        // Stop the timer
        hideTimer?.invalidate()
        hideTimer = nil

        // Only hide if still past deadline (could have been bumped)
        guard Date().timeIntervalSinceReferenceDate >= hideDeadline else {
            return
        }

        // Mark as animating
        isAnimatingOverlay = true

        // Animate out by setting view model
        overlayViewModel.isVisible = false

        // Update layout coordinator - determine which type based on icon
        let isVolume = overlayViewModel.iconName.contains("speaker")
        updateOverlayHUDLayout(isVisible: false, isVolume: isVolume)

        // After animation completes, fade window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // Only hide if still supposed to be hidden
            if !self.overlayViewModel.isVisible {
                self.overlayWindow.alphaValue = 0
                self.overlayWindow.orderOut(nil)
            }
            self.isAnimatingOverlay = false
        }
    }

    // MARK: - Public hide (for app termination)

    func hide() {
        hideMusicHUD()
        hideOverlayHUD()
    }

    // MARK: - Diagnostics

    /// Enable frame-by-frame animation diagnostics
    func enableAnimationDiagnostics(_ enabled: Bool = true) {
        overlayViewModel.progressAnimator.enableDiagnosticLogging(enabled)
    }

    /// Reset animation diagnostic counters
    func resetAnimationDiagnostics() {
        overlayViewModel.progressAnimator.resetDiagnostics()
    }

    // MARK: - Layout Coordination

    /// Update the layout coordinator with the music HUD dimensions
    private func updateMusicHUDLayout(isVisible: Bool) {
        guard let notchDimensions = notchDimensions else { return }

        // Calculate ACTUAL visible width of the music HUD components
        // Left side: Album art thumbnail = notchDimensions.height (square)
        // Right side: Visualizer = notchDimensions.height (square) OR track info = notchDimensions.height * 4
        // For now, use the compact size (visualizer mode) - track info is temporary
        let leftSideWidth = notchDimensions.height + notchDimensions.padding / 2
        let rightSideWidth = notchDimensions.height + notchDimensions.padding / 2
        let totalWidth = leftSideWidth + notchDimensions.width + rightSideWidth

        // Update coordinator
        menuBarViewModel?.hudLayoutCoordinator?.setModule(
            type: .music,
            isVisible: isVisible,
            width: totalWidth
        )

        print("🎨 Layout Coordinator: Music HUD \(isVisible ? "shown" : "hidden"), width: \(totalWidth) (left: \(leftSideWidth), notch: \(notchDimensions.width), right: \(rightSideWidth))")
    }

    /// Update the layout coordinator with the overlay HUD dimensions (volume/brightness)
    private func updateOverlayHUDLayout(isVisible: Bool, isVolume: Bool) {
        guard let notchDimensions = notchDimensions else { return }

        // Calculate ACTUAL visible width of the overlay HUD
        // These are compact indicators on one side of the notch
        let sideWidth = notchDimensions.height + notchDimensions.padding / 2
        let totalWidth = sideWidth + notchDimensions.width + sideWidth

        // Update coordinator
        menuBarViewModel?.hudLayoutCoordinator?.setModule(
            type: isVolume ? .volume : .brightness,
            isVisible: isVisible,
            width: totalWidth
        )

        print("🎨 Layout Coordinator: \(isVolume ? "Volume" : "Brightness") HUD \(isVisible ? "shown" : "hidden"), width: \(totalWidth)")
    }
}
