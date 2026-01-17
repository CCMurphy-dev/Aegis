import Cocoa
import SwiftUI
import Combine

class NotchHUDController: ObservableObject {
    private let systemInfoService: SystemInfoService
    private let musicService: MediaService
    private let eventRouter: EventRouter
    private weak var yabaiService: YabaiService?

    // Separate windows for music, volume/brightness, device connection, and focus
    private var musicWindow: NSWindow!
    private var overlayWindow: NSWindow!
    private var deviceWindow: NSWindow!
    private var focusWindow: NSWindow!

    private var hideTimer: Timer?
    private var hideDeadline: TimeInterval = 0  // Timestamp when overlay should hide
    private var isAnimatingOverlay = false  // Track if overlay is mid-animation

    // Auto-hide timer for music HUD
    private var musicAutoHideTimer: Timer?
    private var lastTrackIdentifier: String?  // Track changes to detect new songs

    // Auto-hide timer for device HUD
    private var deviceAutoHideTimer: Timer?

    // Auto-hide timer for focus HUD
    private var focusAutoHideTimer: Timer?

    // Config observation
    private var cancellables = Set<AnyCancellable>()

    // View models that persist across updates
    private let overlayViewModel = OverlayHUDViewModel()
    private let musicViewModel = MusicHUDViewModel()
    private let deviceViewModel = DeviceHUDViewModel()
    private let focusViewModel = FocusHUDViewModel()

    /// Published property for music HUD visibility (forwarded from view model)
    @Published var isMusicHUDVisible: Bool = false

    /// Published property for overlay HUD visibility (forwarded from view model)
    @Published var isOverlayHUDVisible: Bool = false

    // Reference to menu bar view model for layout coordination
    private weak var menuBarViewModel: MenuBarViewModel?

    // Notch dimensions for width calculations
    private var notchDimensions: NotchDimensions?

    init(systemInfoService: SystemInfoService,
         musicService: MediaService,
         eventRouter: EventRouter) {
        self.systemInfoService = systemInfoService
        self.musicService = musicService
        self.eventRouter = eventRouter

        // Set up bindings to forward view model changes
        overlayViewModel.$isVisible.assign(to: &$isOverlayHUDVisible)
        musicViewModel.$isVisible.assign(to: &$isMusicHUDVisible)

        // Observe config changes for showMusicHUD
        AegisConfig.shared.$showMusicHUD
            .dropFirst()  // Skip initial value
            .sink { [weak self] showMusic in
                guard let self = self else { return }
                if !showMusic && self.musicViewModel.isVisible {
                    print("🎵 Config changed: hiding music HUD")
                    self.hideMusicHUD()
                }
            }
            .store(in: &cancellables)
    }

    /// Connect to menu bar view model for layout coordination
    func connectMenuBarViewModel(_ viewModel: MenuBarViewModel) {
        self.menuBarViewModel = viewModel
    }

    /// Connect to yabai service for fullscreen detection
    func connectYabaiService(_ service: YabaiService) {
        self.yabaiService = service
    }

    // MARK: - Window Preparation (called once at app startup)

    /// Prepare windows at app startup - MUST be called before any HUD interactions
    func prepareWindows() {
        prepareOverlayWindow()
        prepareMusicWindow()
        prepareDeviceWindow()
        prepareFocusWindow()
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
        // Use mainMenu level + 1 to appear above the menu bar blur layer
        overlayWindow.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
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

        // Calculate HUD dimensions
        // sideMaxWidth = notchHeight * 4 on each side
        let sideMaxWidth = notchDimensions.height * 4
        let totalHUDWidth = sideMaxWidth + notchDimensions.width + sideMaxWidth

        // Window frame: full screen (needed for proper SwiftUI layout)
        let windowFrame = screen.frame

        // Create the persistent view ONCE with the view model
        let hudView = MusicHUDView(
            viewModel: musicViewModel,
            notchDimensions: notchDimensions,
            isVisible: Binding(
                get: { [weak self] in self?.isMusicHUDVisible ?? false },
                set: { [weak self] in self?.isMusicHUDVisible = $0 }
            )
        )

        // Center the HUD at top of screen
        let wrappedView = VStack {
            hudView
                .frame(width: totalHUDWidth, height: notchHeight)
            Spacer()
        }
        .frame(maxWidth: .infinity)

        let hostingView = NSHostingView(rootView: wrappedView)
        hostingView.frame = NSRect(origin: .zero, size: windowFrame.size)

        // Create main display window (ignores mouse events)
        musicWindow = NSWindow(
            contentRect: windowFrame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        musicWindow.isOpaque = false
        musicWindow.backgroundColor = .clear
        musicWindow.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        musicWindow.ignoresMouseEvents = true  // Display only - no interference
        musicWindow.hasShadow = false
        musicWindow.collectionBehavior = [.canJoinAllSpaces, .stationary]
        musicWindow.isReleasedWhenClosed = false
        musicWindow.contentView = hostingView
        musicWindow.alphaValue = 0
        musicWindow.orderOut(nil)

        // NOTE: Interaction window removed - was causing mouse event blocking issues
        // The tap-to-toggle feature is disabled for now
        // TODO: Consider alternative approaches like keyboard shortcut or menu item
    }

    private func prepareDeviceWindow() {
        guard let screen = NSScreen.main else {
            assertionFailure("No main screen available during device window preparation")
            return
        }

        let notchHeight = screen.safeAreaInsets.top
        let notchDimensions = NotchDimensions.calculate(for: screen)

        // Calculate HUD dimensions - wider to fit device name
        let panelWidth = notchDimensions.height * 3.5
        let totalHUDWidth = panelWidth + notchDimensions.width + panelWidth

        let windowFrame = screen.frame

        // Create the persistent view ONCE with the view model
        let hudView = DeviceHUDView(
            viewModel: deviceViewModel,
            notchDimensions: notchDimensions
        )

        // Center the HUD at top of screen
        let wrappedView = VStack {
            hudView
                .frame(width: totalHUDWidth, height: notchHeight)
            Spacer()
        }
        .frame(maxWidth: .infinity)

        let hostingView = NSHostingView(rootView: wrappedView)
        hostingView.frame = NSRect(origin: .zero, size: windowFrame.size)

        deviceWindow = NSWindow(
            contentRect: windowFrame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        deviceWindow.isOpaque = false
        deviceWindow.backgroundColor = .clear
        deviceWindow.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        deviceWindow.ignoresMouseEvents = true
        deviceWindow.hasShadow = false
        deviceWindow.collectionBehavior = [.canJoinAllSpaces, .stationary]
        deviceWindow.isReleasedWhenClosed = false
        deviceWindow.contentView = hostingView
        deviceWindow.alphaValue = 0
        deviceWindow.orderOut(nil)

        print("🎧 prepareDeviceWindow: Device HUD window prepared")
    }

    private func prepareFocusWindow() {
        guard let screen = NSScreen.main else {
            assertionFailure("No main screen available during focus window preparation")
            return
        }

        let notchHeight = screen.safeAreaInsets.top
        let notchDimensions = NotchDimensions.calculate(for: screen)

        // Calculate HUD dimensions - same as device HUD
        let panelWidth = notchDimensions.height * 3.5
        let totalHUDWidth = panelWidth + notchDimensions.width + panelWidth

        let windowFrame = screen.frame

        // Create the persistent view ONCE with the view model
        let hudView = FocusHUDView(
            viewModel: focusViewModel,
            notchDimensions: notchDimensions
        )

        // Center the HUD at top of screen
        let wrappedView = VStack {
            hudView
                .frame(width: totalHUDWidth, height: notchHeight)
            Spacer()
        }
        .frame(maxWidth: .infinity)

        let hostingView = NSHostingView(rootView: wrappedView)
        hostingView.frame = NSRect(origin: .zero, size: windowFrame.size)

        focusWindow = NSWindow(
            contentRect: windowFrame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        focusWindow.isOpaque = false
        focusWindow.backgroundColor = .clear
        focusWindow.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        focusWindow.ignoresMouseEvents = true
        focusWindow.hasShadow = false
        focusWindow.collectionBehavior = [.canJoinAllSpaces, .stationary]
        focusWindow.isReleasedWhenClosed = false
        focusWindow.contentView = hostingView
        focusWindow.alphaValue = 0
        focusWindow.orderOut(nil)

        print("🎯 prepareFocusWindow: Focus HUD window prepared")
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
        let config = AegisConfig.shared
        print("🎵 NotchHUDController.showMusic: isPlaying=\(info.isPlaying), currentlyVisible=\(musicViewModel.isVisible), isDismissed=\(musicViewModel.isDismissed)")

        // Check if music HUD is disabled in config
        if !config.showMusicHUD {
            // If HUD is visible, hide it
            if musicViewModel.isVisible {
                print("🎵 NotchHUDController: Music HUD disabled, hiding")
                hideMusicHUD()
            }
            return
        }

        // If not playing, hide the music HUD
        if !info.isPlaying {
            print("🎵 NotchHUDController: Playback stopped, hiding music HUD")
            hideMusicHUD()
            lastTrackIdentifier = nil
            return
        }

        // Check if fullscreen app matches the now-playing app (suppress HUD for video players in fullscreen)
        if let nowPlayingBundleId = info.bundleIdentifier,
           shouldSuppressMusicHUDForFullscreen(nowPlayingBundleId: nowPlayingBundleId) {
            print("🎵 NotchHUDController: Suppressing music HUD - fullscreen app matches now-playing app (\(nowPlayingBundleId))")
            if musicViewModel.isVisible {
                hideMusicHUD()
            }
            return
        }

        // Check if this is a new track
        let isNewTrack = info.trackIdentifier != lastTrackIdentifier
        lastTrackIdentifier = info.trackIdentifier

        // Update the music view model with new info (this also resets isDismissed on track change)
        musicViewModel.updateInfo(info)

        // Don't show if user dismissed (until track changes)
        if musicViewModel.isDismissed {
            print("🎵 NotchHUDController: HUD dismissed by user, not showing")
            return
        }

        // Show HUD if not already visible OR if track changed (to bring it back)
        if !musicViewModel.isVisible || isNewTrack {
            print("🎵 NotchHUDController: Showing music HUD (isNewTrack: \(isNewTrack))")
            showMusicHUD()

            // Schedule auto-hide if enabled
            if config.musicHUDAutoHide {
                scheduleMusicAutoHide()
            }
        } else {
            print("🎵 NotchHUDController: Music HUD already visible, just updated info")
        }
    }

    /// Schedule the music HUD to auto-hide after the configured delay
    private func scheduleMusicAutoHide() {
        let config = AegisConfig.shared
        musicAutoHideTimer?.invalidate()

        print("🎵 Scheduling music HUD auto-hide in \(config.musicHUDAutoHideDelay)s")
        musicAutoHideTimer = Timer.scheduledTimer(withTimeInterval: config.musicHUDAutoHideDelay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            print("🎵 Auto-hide timer fired, hiding music HUD")
            self.hideMusicHUD()
        }
    }

    func showDeviceConnected(device: BluetoothDeviceInfo) {
        let config = AegisConfig.shared

        // Check if device HUD is disabled in config
        guard config.showDeviceHUD else {
            print("🎧 NotchHUDController: Device HUD disabled in config")
            return
        }

        print("🎧 NotchHUDController.showDeviceConnected: \(device.name)")

        // Update view model
        deviceViewModel.show(device: device, isConnecting: true)

        // Show the HUD
        showDeviceHUD()

        // Schedule auto-hide
        scheduleDeviceAutoHide()
    }

    func showDeviceDisconnected(device: BluetoothDeviceInfo) {
        let config = AegisConfig.shared

        // Check if device HUD is disabled in config
        guard config.showDeviceHUD else {
            print("🎧 NotchHUDController: Device HUD disabled in config")
            return
        }

        print("🎧 NotchHUDController.showDeviceDisconnected: \(device.name)")

        // Update view model
        deviceViewModel.show(device: device, isConnecting: false)

        // Show the HUD
        showDeviceHUD()

        // Schedule auto-hide
        scheduleDeviceAutoHide()
    }

    private func scheduleDeviceAutoHide() {
        let config = AegisConfig.shared
        deviceAutoHideTimer?.invalidate()

        let delay = config.deviceHUDAutoHideDelay
        print("🎧 Scheduling device HUD auto-hide in \(delay)s")
        deviceAutoHideTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            print("🎧 Auto-hide timer fired, hiding device HUD")
            self.hideDeviceHUD()
        }
    }

    func showFocusChanged(status: FocusStatus) {
        let config = AegisConfig.shared

        // Check if focus HUD is disabled in config
        guard config.showFocusHUD else {
            print("🎯 NotchHUDController: Focus HUD disabled in config")
            return
        }

        print("🎯 NotchHUDController.showFocusChanged: \(status.focusName ?? "Off") (enabled: \(status.isEnabled))")

        // Update view model
        focusViewModel.show(status: status)

        // Show the HUD
        showFocusHUD()

        // Schedule auto-hide
        scheduleFocusAutoHide()
    }

    private func scheduleFocusAutoHide() {
        let config = AegisConfig.shared
        focusAutoHideTimer?.invalidate()

        let delay = config.focusHUDAutoHideDelay
        print("🎯 Scheduling focus HUD auto-hide in \(delay)s")
        focusAutoHideTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            print("🎯 Auto-hide timer fired, hiding focus HUD")
            self.hideFocusHUD()
        }
    }

    // MARK: - Private helpers - Device HUD

    private func showDeviceHUD() {
        print("🎧 showDeviceHUD() called - currentlyVisible: \(deviceViewModel.isVisible)")

        // Tell music HUD to hide its right panel (to avoid overlap)
        musicViewModel.isOverlayActive = true

        // Order window front with full opacity immediately
        deviceWindow.alphaValue = 1
        deviceWindow.orderFrontRegardless()

        // Force a layout pass
        deviceWindow.layoutIfNeeded()

        // Animate to visible state
        DispatchQueue.main.async {
            print("🎧 showDeviceHUD: Setting deviceViewModel.isVisible = true (triggering slide-in animation)")
            self.deviceViewModel.isVisible = true
        }
    }

    private func hideDeviceHUD() {
        print("🎧 hideDeviceHUD() called - currentlyVisible: \(deviceViewModel.isVisible)")

        if !deviceViewModel.isVisible {
            print("🎧 hideDeviceHUD: Already hidden, nothing to do")
            return
        }

        // Cancel auto-hide timer
        deviceAutoHideTimer?.invalidate()
        deviceAutoHideTimer = nil

        print("🎧 hideDeviceHUD: Setting deviceViewModel.isVisible = false (triggering slide-out animation)")
        deviceViewModel.isVisible = false

        // After animation completes, hide the window and restore music panel
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if !self.deviceViewModel.isVisible {
                print("🎧 hideDeviceHUD: Animation complete, hiding window")
                self.deviceWindow.alphaValue = 0
                self.deviceWindow.orderOut(nil)

                // Restore music HUD right panel
                self.musicViewModel.isOverlayActive = false
            }
        }
    }

    // MARK: - Private helpers - Focus HUD

    private func showFocusHUD() {
        print("🎯 showFocusHUD() called - currentlyVisible: \(focusViewModel.isVisible)")

        // Tell music HUD to hide its right panel (to avoid overlap)
        musicViewModel.isOverlayActive = true

        // Order window front with full opacity immediately
        focusWindow.alphaValue = 1
        focusWindow.orderFrontRegardless()

        // Force a layout pass
        focusWindow.layoutIfNeeded()

        // Animate to visible state
        DispatchQueue.main.async {
            print("🎯 showFocusHUD: Setting focusViewModel.isVisible = true (triggering slide-in animation)")
            self.focusViewModel.isVisible = true
        }
    }

    private func hideFocusHUD() {
        print("🎯 hideFocusHUD() called - currentlyVisible: \(focusViewModel.isVisible)")

        if !focusViewModel.isVisible {
            print("🎯 hideFocusHUD: Already hidden, nothing to do")
            return
        }

        // Cancel auto-hide timer
        focusAutoHideTimer?.invalidate()
        focusAutoHideTimer = nil

        print("🎯 hideFocusHUD: Setting focusViewModel.isVisible = false (triggering slide-out animation)")
        focusViewModel.isVisible = false

        // After animation completes, hide the window and restore music panel
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if !self.focusViewModel.isVisible {
                print("🎯 hideFocusHUD: Animation complete, hiding window")
                self.focusWindow.alphaValue = 0
                self.focusWindow.orderOut(nil)

                // Restore music HUD right panel
                self.musicViewModel.isOverlayActive = false
            }
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

        // Cancel auto-hide timer
        musicAutoHideTimer?.invalidate()
        musicAutoHideTimer = nil

        print("🎵 hideMusicHUD: Setting musicViewModel.isVisible = false (triggering slide-out animation)")
        // Trigger slide-out animation via view model
        // MinimalHUDSide components will slide back under the notch
        musicViewModel.isVisible = false

        // Update layout coordinator - Music HUD is hiding
        updateMusicHUDLayout(isVisible: false)

        // After animation completes, hide the windows
        // Allow extra time for spring animation to finish (0.3s spring response + buffer)
        print("🎵 hideMusicHUD: Scheduled window hiding in 0.4s")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            // Only hide if still supposed to be hidden
            if !self.musicViewModel.isVisible {
                print("🎵 hideMusicHUD: Animation complete, hiding windows (alphaValue: 0, orderOut)")
                self.musicWindow.alphaValue = 0
                self.musicWindow.orderOut(nil)
            } else {
                print("🎵 hideMusicHUD: Animation complete but HUD is visible again, keeping windows shown")
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

        // Tell music HUD to hide its right panel (to avoid overlap)
        musicViewModel.isOverlayActive = true

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

        // After animation completes, fade window and restore music panel
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // Only hide if still supposed to be hidden
            if !self.overlayViewModel.isVisible {
                self.overlayWindow.alphaValue = 0
                self.overlayWindow.orderOut(nil)

                // Restore music HUD right panel
                self.musicViewModel.isOverlayActive = false
            }
            self.isAnimatingOverlay = false
        }
    }

    // MARK: - Public hide (for app termination)

    func hide() {
        hideMusicHUD()
        hideOverlayHUD()
        hideDeviceHUD()
        hideFocusHUD()
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

    // MARK: - Fullscreen Suppression

    /// Check if the music HUD should be suppressed because the fullscreen app matches the now-playing app
    /// This prevents the music HUD from appearing over video players when they're in fullscreen
    private func shouldSuppressMusicHUDForFullscreen(nowPlayingBundleId: String) -> Bool {
        guard let yabaiService = yabaiService else {
            return false
        }

        // Get current spaces to find the focused one
        let spaces = yabaiService.getCurrentSpaces()
        guard let focusedSpace = spaces.first(where: { $0.focused }) else {
            return false
        }

        // Get windows in the focused space
        let windows = yabaiService.getWindowIconsForSpace(focusedSpace.index)

        // Check if any window in the current space is in native fullscreen
        for windowIcon in windows {
            if let windowInfo = yabaiService.getWindow(windowIcon.id),
               windowInfo.isNativeFullscreen {
                // Found a native fullscreen window - check if its app matches the now-playing app
                let fullscreenAppBundleId = getBundleIdentifier(forAppNamed: windowInfo.app)
                if fullscreenAppBundleId == nowPlayingBundleId {
                    return true
                }
            }
        }

        return false
    }

    /// Get bundle identifier for an app by its name
    private func getBundleIdentifier(forAppNamed appName: String) -> String? {
        let runningApps = NSWorkspace.shared.runningApplications
        if let app = runningApps.first(where: { $0.localizedName == appName }) {
            return app.bundleIdentifier
        }
        return nil
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
