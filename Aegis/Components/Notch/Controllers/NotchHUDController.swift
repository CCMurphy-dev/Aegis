import Cocoa
import SwiftUI
import Combine

class NotchHUDController: ObservableObject {
    private let systemInfoService: SystemInfoService
    private let musicService: MediaService
    private let eventRouter: EventRouter
    private weak var yabaiService: YabaiService?

    // Separate windows for music, volume/brightness, device connection, and focus
    private var mediaWindow: NSWindow!
    private var overlayWindow: NSWindow!
    private var deviceWindow: NSWindow!
    private var focusWindow: NSWindow!

    private var hideTimer: Timer?
    private var hideDeadline: TimeInterval = 0  // Timestamp when overlay should hide
    private var isAnimatingOverlay = false  // Track if overlay is mid-animation

    // Auto-hide timer for media HUD
    private var mediaAutoHideTimer: Timer?
    private var lastTrackIdentifier: String?  // Track changes to detect new songs

    // Auto-hide timer for device HUD
    private var deviceAutoHideTimer: Timer?

    // Auto-hide timer for focus HUD
    private var focusAutoHideTimer: Timer?

    // Config observation
    private var cancellables = Set<AnyCancellable>()

    // View models that persist across updates
    private let overlayViewModel = OverlayHUDViewModel()
    private let mediaViewModel = MediaHUDViewModel()
    private let deviceViewModel = DeviceHUDViewModel()
    private let focusViewModel = FocusHUDViewModel()

    /// Published property for media HUD visibility (forwarded from view model)
    @Published var isMediaHUDVisible: Bool = false

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
        mediaViewModel.$isVisible.assign(to: &$isMediaHUDVisible)

        // Observe config changes for showMediaHUD
        AegisConfig.shared.$showMediaHUD
            .dropFirst()  // Skip initial value
            .sink { [weak self] showMusic in
                guard let self = self else { return }
                if !showMusic && self.mediaViewModel.isVisible {
                    print("🎵 Config changed: hiding media HUD")
                    self.hideMediaHUD()
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
        prepareMediaWindow()
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

    private func prepareMediaWindow() {
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
        let hudView = MediaHUDView(
            viewModel: mediaViewModel,
            notchDimensions: notchDimensions,
            isVisible: Binding(
                get: { [weak self] in self?.isMediaHUDVisible ?? false },
                set: { [weak self] in self?.isMediaHUDVisible = $0 }
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
        mediaWindow = NSWindow(
            contentRect: windowFrame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        mediaWindow.isOpaque = false
        mediaWindow.backgroundColor = .clear
        mediaWindow.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        mediaWindow.ignoresMouseEvents = true  // Display only - no interference
        mediaWindow.hasShadow = false
        mediaWindow.collectionBehavior = [.canJoinAllSpaces, .stationary]
        mediaWindow.isReleasedWhenClosed = false
        mediaWindow.contentView = hostingView
        mediaWindow.alphaValue = 0
        mediaWindow.orderOut(nil)

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

    func showMedia(info: MediaInfo) {
        let config = AegisConfig.shared
        print("🎵 NotchHUDController.showMusic: isPlaying=\(info.isPlaying), currentlyVisible=\(mediaViewModel.isVisible), isDismissed=\(mediaViewModel.isDismissed)")

        // Check if media HUD is disabled in config
        if !config.showMediaHUD {
            // If HUD is visible, hide it
            if mediaViewModel.isVisible {
                print("🎵 NotchHUDController: Media HUD disabled, hiding")
                hideMediaHUD()
            }
            return
        }

        // If not playing, hide the media HUD
        if !info.isPlaying {
            print("🎵 NotchHUDController: Playback stopped, hiding media HUD")
            hideMediaHUD()
            lastTrackIdentifier = nil
            return
        }

        // Check if fullscreen app matches the now-playing app (suppress HUD for video players in fullscreen)
        if let nowPlayingBundleId = info.bundleIdentifier,
           shouldSuppressMediaHUDForFullscreen(nowPlayingBundleId: nowPlayingBundleId) {
            print("🎵 NotchHUDController: Suppressing media HUD - fullscreen app matches now-playing app (\(nowPlayingBundleId))")
            if mediaViewModel.isVisible {
                hideMediaHUD()
            }
            return
        }

        // Check if this is a new track
        let isNewTrack = info.trackIdentifier != lastTrackIdentifier
        lastTrackIdentifier = info.trackIdentifier

        // Update the music view model with new info (this also resets isDismissed on track change)
        mediaViewModel.updateInfo(info)

        // Don't show if user dismissed (until track changes)
        if mediaViewModel.isDismissed {
            print("🎵 NotchHUDController: HUD dismissed by user, not showing")
            return
        }

        // Show HUD if not already visible OR if track changed (to bring it back)
        if !mediaViewModel.isVisible || isNewTrack {
            print("🎵 NotchHUDController: Showing media HUD (isNewTrack: \(isNewTrack))")
            showMediaHUD()

            // Schedule auto-hide if enabled
            if config.mediaHUDAutoHide {
                scheduleMediaAutoHide()
            }
        } else {
            print("🎵 NotchHUDController: Media HUD already visible, just updated info")
        }
    }

    /// Schedule the media HUD to auto-hide after the configured delay
    private func scheduleMediaAutoHide() {
        let config = AegisConfig.shared
        mediaAutoHideTimer?.invalidate()

        print("🎵 Scheduling media HUD auto-hide in \(config.mediaHUDAutoHideDelay)s")
        mediaAutoHideTimer = Timer.scheduledTimer(withTimeInterval: config.mediaHUDAutoHideDelay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            print("🎵 Auto-hide timer fired, hiding media HUD")
            self.hideMediaHUD()
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

        // Tell media HUD to hide its right panel (to avoid overlap)
        mediaViewModel.isOverlayActive = true

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

                // Restore media HUD right panel
                self.mediaViewModel.isOverlayActive = false
            }
        }
    }

    // MARK: - Private helpers - Focus HUD

    private func showFocusHUD() {
        print("🎯 showFocusHUD() called - currentlyVisible: \(focusViewModel.isVisible)")

        // Tell media HUD to hide its right panel (to avoid overlap)
        mediaViewModel.isOverlayActive = true

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

                // Restore media HUD right panel
                self.mediaViewModel.isOverlayActive = false
            }
        }
    }

    // MARK: - Private helpers - Media HUD

    private func showMediaHUD() {
        print("🎵 showMediaHUD() called - currentlyVisible: \(mediaViewModel.isVisible)")

        // If already visible, nothing to do (data already updated in ViewModel)
        guard !mediaViewModel.isVisible else {
            // Ensure window is actually visible (might have been hidden)
            if mediaWindow.alphaValue < 1 || !mediaWindow.isVisible {
                print("🎵 showMediaHUD: Window was hidden, bringing back - alphaValue: \(mediaWindow.alphaValue), isVisible: \(mediaWindow.isVisible)")
                mediaWindow.alphaValue = 1
                mediaWindow.orderFrontRegardless()
            } else {
                print("🎵 showMediaHUD: Already visible and window is properly shown")
            }
            return
        }

        print("🎵 showMediaHUD: Ordering window front with full opacity")
        // Order window front with full opacity immediately
        mediaWindow.alphaValue = 1
        mediaWindow.orderFrontRegardless()

        // Force a layout pass with initial state (isVisible = false)
        // This ensures the view starts in its hidden position
        mediaWindow.layoutIfNeeded()
        print("🎵 showMediaHUD: Layout forced, scheduling animation")

        // Update layout coordinator - Media HUD is showing
        updateMediaHUDLayout(isVisible: true)

        // Then animate to visible state
        // The MinimalHUDSide components will slide in smoothly
        DispatchQueue.main.async {
            print("🎵 showMediaHUD: Setting mediaViewModel.isVisible = true (triggering slide-in animation)")
            self.mediaViewModel.isVisible = true
        }
    }

    private func hideMediaHUD() {
        print("🎵 hideMediaHUD() called - currentlyVisible: \(mediaViewModel.isVisible)")

        // Check if already hidden
        if !mediaViewModel.isVisible {
            print("🎵 hideMediaHUD: Already hidden, nothing to do")
            return
        }

        // Cancel auto-hide timer
        mediaAutoHideTimer?.invalidate()
        mediaAutoHideTimer = nil

        print("🎵 hideMediaHUD: Setting mediaViewModel.isVisible = false (triggering slide-out animation)")
        // Trigger slide-out animation via view model
        // MinimalHUDSide components will slide back under the notch
        mediaViewModel.isVisible = false

        // Update layout coordinator - Media HUD is hiding
        updateMediaHUDLayout(isVisible: false)

        // After animation completes, hide the windows
        // Allow extra time for spring animation to finish (0.3s spring response + buffer)
        print("🎵 hideMediaHUD: Scheduled window hiding in 0.4s")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            // Only hide if still supposed to be hidden
            if !self.mediaViewModel.isVisible {
                print("🎵 hideMediaHUD: Animation complete, hiding windows (alphaValue: 0, orderOut)")
                self.mediaWindow.alphaValue = 0
                self.mediaWindow.orderOut(nil)
            } else {
                print("🎵 hideMediaHUD: Animation complete but HUD is visible again, keeping windows shown")
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

        // Tell media HUD to hide its right panel (to avoid overlap)
        mediaViewModel.isOverlayActive = true

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

                // Restore media HUD right panel
                self.mediaViewModel.isOverlayActive = false
            }
            self.isAnimatingOverlay = false
        }
    }

    // MARK: - Public hide (for app termination)

    func hide() {
        hideMediaHUD()
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

    /// Check if the media HUD should be suppressed because the fullscreen app matches the now-playing app
    /// This prevents the media HUD from appearing over video players when they're in fullscreen
    private func shouldSuppressMediaHUDForFullscreen(nowPlayingBundleId: String) -> Bool {
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

    /// Update the layout coordinator with the media HUD dimensions
    private func updateMediaHUDLayout(isVisible: Bool) {
        guard let notchDimensions = notchDimensions else { return }

        // Calculate ACTUAL visible width of the media HUD components
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

        print("🎨 Layout Coordinator: Media HUD \(isVisible ? "shown" : "hidden"), width: \(totalWidth) (left: \(leftSideWidth), notch: \(notchDimensions.width), right: \(rightSideWidth))")
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
