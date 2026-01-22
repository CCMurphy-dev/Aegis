import Cocoa
import SwiftUI
import Combine

class NotchHUDController: ObservableObject {
    private let systemInfoService: SystemInfoService
    private let musicService: MediaService
    private let eventRouter: EventRouter
    private let yabaiService: YabaiService

    // Separate windows for music, volume/brightness, device connection, focus, and notifications
    private var mediaWindow: NSWindow!
    private var overlayWindow: NSWindow!
    private var deviceWindow: NSWindow!
    private var focusWindow: NSWindow!
    private var notificationWindow: NSWindow!

    private var hideWorkItem: DispatchWorkItem?  // Scheduled hide for overlay HUD
    private var isAnimatingOverlay = false  // Track if overlay is mid-animation

    // Auto-hide timer for media HUD
    private var mediaAutoHideTimer: Timer?
    private var lastTrackIdentifier: String?  // Track changes to detect new songs

    // Auto-hide timer for device HUD
    private var deviceAutoHideTimer: Timer?

    // Auto-hide timer for focus HUD
    private var focusAutoHideTimer: Timer?

    // Auto-hide timer for notification HUD
    private var notificationAutoHideTimer: Timer?

    // Custom hosting view for notification HUD (allows click pass-through outside panels)
    private var notificationHostingView: NotificationHUDHostingView<AnyView>?

    // Config observation
    private var cancellables = Set<AnyCancellable>()

    // View models that persist across updates
    private let overlayViewModel = OverlayHUDViewModel()
    private let mediaViewModel = MediaHUDViewModel()
    private let deviceViewModel = DeviceHUDViewModel()
    private let focusViewModel = FocusHUDViewModel()
    private let notificationViewModel = NotificationHUDViewModel()

    /// Published property for media HUD visibility (forwarded from view model)
    @Published var isMediaHUDVisible: Bool = false

    /// Published property for overlay HUD visibility (forwarded from view model)
    @Published var isOverlayHUDVisible: Bool = false

    // Reference to menu bar view model for layout coordination
    private weak var menuBarViewModel: MenuBarViewModel?

    // Notch dimensions for width calculations
    private var notchDimensions: NotchDimensions?

    // Fullscreen state from menu bar (used to suppress media HUD in fullscreen)
    private var isInFullscreenSpace = false
    // Track if we're showing a brief track change notification in fullscreen
    // When true, skip the collapse animation on hide (just slide out directly)
    private var isFullscreenTrackChangeMode = false

    init(systemInfoService: SystemInfoService,
         musicService: MediaService,
         eventRouter: EventRouter,
         yabaiService: YabaiService) {
        self.systemInfoService = systemInfoService
        self.musicService = musicService
        self.eventRouter = eventRouter
        self.yabaiService = yabaiService

        // Set up Yabai integration for notification clicks
        notificationViewModel.openAppHandler = { [weak self] appName, bundleIdentifier in
            self?.focusOrLaunchApp(appName: appName, bundleIdentifier: bundleIdentifier)
        }

        // Set up bindings to forward view model changes
        overlayViewModel.$isVisible.assign(to: &$isOverlayHUDVisible)
        mediaViewModel.$isVisible.assign(to: &$isMediaHUDVisible)

        // Observe config changes for showMediaHUD
        AegisConfig.shared.$showMediaHUD
            .dropFirst()  // Skip initial value
            .sink { [weak self] showMusic in
                guard let self = self else { return }
                if !showMusic && self.mediaViewModel.isVisible {
                    self.hideMediaHUD()
                }
            }
            .store(in: &cancellables)

    }

    deinit {
        // Clean up all timers to prevent leaks
        mediaAutoHideTimer?.invalidate()
        deviceAutoHideTimer?.invalidate()
        focusAutoHideTimer?.invalidate()
        notificationAutoHideTimer?.invalidate()
        hideWorkItem?.cancel()
    }

    /// Connect to menu bar view model for layout coordination
    func connectMenuBarViewModel(_ viewModel: MenuBarViewModel) {
        self.menuBarViewModel = viewModel
    }

    /// Observe fullscreen state from menu bar window controller
    /// When menu bar hides (fullscreen), hide media HUD after a short delay
    /// When menu bar shows (exiting fullscreen), re-show media HUD if music is still playing
    func observeFullscreenState(from windowController: MenuBarWindowController) {
        windowController.$currentSpaceIsFullscreen
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isFullscreen in
                guard let self = self else { return }

                let wasInFullscreen = self.isInFullscreenSpace
                // Store the fullscreen state
                self.isInFullscreenSpace = isFullscreen

                if isFullscreen && self.mediaViewModel.isVisible {
                    // Menu bar is hiding (fullscreen) - hide media HUD after a short delay
                    // This allows the transition to complete before hiding
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        // Only hide if still in fullscreen (user might have exited quickly)
                        if self.isInFullscreenSpace && self.mediaViewModel.isVisible {
                            self.hideMediaHUD()
                        }
                    }
                } else if !isFullscreen && wasInFullscreen {
                    // Exiting fullscreen - re-show media HUD if music is still playing
                    // Small delay to allow the transition to complete
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        // Only show if still not in fullscreen and media is playing
                        if !self.isInFullscreenSpace &&
                           self.mediaViewModel.info.isPlaying &&
                           !self.mediaViewModel.isDismissed &&
                           AegisConfig.shared.showMediaHUD {
                            self.showMediaHUD()
                            // Schedule auto-hide if enabled
                            if AegisConfig.shared.mediaHUDAutoHide {
                                self.scheduleMediaAutoHide()
                            }
                        }
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Window Preparation (called once at app startup)

    /// Prepare windows at app startup - MUST be called before any HUD interactions
    func prepareWindows() {
        prepareOverlayWindow()
        prepareMediaWindow()
        prepareDeviceWindow()
        prepareFocusWindow()
        prepareNotificationWindow()
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
            mediaViewModel: mediaViewModel,
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
            ),
            isFullscreenTrackChangeMode: Binding(
                get: { [weak self] in self?.isFullscreenTrackChangeMode ?? false },
                set: { [weak self] in self?.isFullscreenTrackChangeMode = $0 }
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

    private func prepareNotificationWindow() {
        guard let screen = NSScreen.main else {
            assertionFailure("No main screen available during notification window preparation")
            return
        }

        let notchHeight = screen.safeAreaInsets.top
        let notchDimensions = NotchDimensions.calculate(for: screen)

        // Calculate HUD dimensions - match actual view panel widths
        // Left panel: square for icon (notchDimensions.height)
        // Right panel: reasonable max for text content
        let leftPanelWidth = notchDimensions.height
        let rightPanelWidth = min(notchDimensions.height * 3, 150)
        let totalHUDWidth = leftPanelWidth + notchDimensions.width + rightPanelWidth

        // Create window sized to exactly fit the HUD area, centered on the notch
        // This allows clicks outside the HUD to pass through to the menu bar
        let hudCenterX = screen.frame.midX
        let windowFrame = NSRect(
            x: hudCenterX - totalHUDWidth / 2,
            y: screen.frame.origin.y + screen.frame.height - notchHeight,
            width: totalHUDWidth,
            height: notchHeight
        )

        // Create the persistent view ONCE with the view model
        let hudView = NotificationHUDView(
            viewModel: notificationViewModel,
            notchDimensions: notchDimensions
        )

        // Window is now sized to the HUD, so no centering needed
        let wrappedView = hudView
            .frame(width: totalHUDWidth, height: notchHeight)

        // Use custom hosting view that passes through clicks outside the HUD panels
        let hostingView = NotificationHUDHostingView(rootView: AnyView(wrappedView))
        hostingView.frame = NSRect(origin: .zero, size: windowFrame.size)
        self.notificationHostingView = hostingView

        // Set up click callback to open source app
        hostingView.onPanelClick = { [weak self] in
            print("🔔 NotificationHUD panel clicked - opening source app")
            self?.notificationViewModel.openSourceApp()
            self?.hideNotificationHUD()
        }

        notificationWindow = NotificationHUDWindow(
            contentRect: windowFrame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        notificationWindow.isOpaque = false
        notificationWindow.backgroundColor = .clear
        notificationWindow.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        // Start with ignoresMouseEvents = true, only enable when visible
        notificationWindow.ignoresMouseEvents = true
        notificationWindow.hasShadow = false
        notificationWindow.collectionBehavior = [.canJoinAllSpaces, .stationary]
        notificationWindow.isReleasedWhenClosed = false
        notificationWindow.contentView = hostingView

        // Initialize panel bounds (not visible initially)
        hostingView.updatePanelBounds(notchDimensions: notchDimensions, isVisible: false)

        // CRITICAL: Ensure window is completely invisible and non-blocking when not showing
        // 1. Set alpha to 0
        // 2. Order out of window server
        // 3. Move off-screen as extra safety (in case orderOut fails for some reason)
        notificationWindow.alphaValue = 0
        notificationWindow.ignoresMouseEvents = true
        notificationWindow.orderOut(nil)
        notificationWindow.setFrameOrigin(NSPoint(x: -10000, y: -10000))

        print("🔔 prepareNotificationWindow: Notification HUD window prepared with size \(windowFrame.size)")
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

        // Reschedule auto-hide (cancels previous, starts fresh 1.5s countdown)
        scheduleOverlayHide()
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

        // Reschedule auto-hide (cancels previous, starts fresh 1.5s countdown)
        scheduleOverlayHide()
    }

    func showMedia(info: MediaInfo) {
        let config = AegisConfig.shared

        // Check if media HUD is disabled in config
        if !config.showMediaHUD {
            if mediaViewModel.isVisible {
                hideMediaHUD()
            }
            return
        }

        // If not playing, hide the media HUD
        if !info.isPlaying {
            hideMediaHUD()
            lastTrackIdentifier = nil
            return
        }

        // Check if this is a new track
        let isNewTrack = info.trackIdentifier != lastTrackIdentifier
        lastTrackIdentifier = info.trackIdentifier

        // Update the music view model with new info (this also resets isDismissed on track change)
        mediaViewModel.updateInfo(info)

        // Don't show if user dismissed (until track changes)
        if mediaViewModel.isDismissed {
            return
        }

        // Handle fullscreen mode
        if isInFullscreenSpace {
            // In fullscreen: only show briefly for track changes (background music app)
            if isNewTrack {
                isFullscreenTrackChangeMode = true
                showMediaHUD()
                scheduleMediaAutoHide()
            }
            return
        }

        // Not in fullscreen - ensure flag is cleared
        isFullscreenTrackChangeMode = false

        // Show HUD if not already visible OR if track changed (to bring it back)
        if !mediaViewModel.isVisible || isNewTrack {
            showMediaHUD()
            if config.mediaHUDAutoHide {
                scheduleMediaAutoHide()
            }
        }
    }

    /// Schedule the media HUD to auto-hide after the configured delay
    private func scheduleMediaAutoHide() {
        let config = AegisConfig.shared
        mediaAutoHideTimer?.invalidate()

        mediaAutoHideTimer = Timer.scheduledTimer(withTimeInterval: config.mediaHUDAutoHideDelay, repeats: false) { [weak self] _ in
            self?.hideMediaHUD()
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

    func showNotification(appName: String, title: String, body: String, bundleIdentifier: String) {
        let config = AegisConfig.shared

        // Check if notification HUD is disabled in config
        guard config.showNotificationHUD else {
            print("🔔 NotchHUDController: Notification HUD disabled in config")
            return
        }

        print("🔔 NotchHUDController.showNotification: \(appName) - \(title)")

        // Update view model
        notificationViewModel.show(
            appName: appName,
            title: title,
            body: body,
            bundleIdentifier: bundleIdentifier
        )

        // Show the HUD
        showNotificationHUD()

        // Schedule auto-hide (consistent with device/focus HUDs)
        scheduleNotificationAutoHide()
    }

    private func scheduleNotificationAutoHide() {
        let config = AegisConfig.shared
        guard config.notificationHUDAutoHide else { return }

        notificationAutoHideTimer?.invalidate()

        let delay = config.notificationHUDAutoHideDelay
        print("🔔 Scheduling notification HUD auto-hide in \(delay)s")
        notificationAutoHideTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            print("🔔 Auto-hide timer fired, hiding notification HUD")
            self.hideNotificationHUD()
        }
    }

    // MARK: - Private helpers - Notification HUD

    /// Focus app window via Yabai, or launch/activate via NSWorkspace if not found
    private func focusOrLaunchApp(appName: String, bundleIdentifier: String) {
        // Try Yabai first (respects window management)
        if !appName.isEmpty && yabaiService.focusWindowByAppName(appName) {
            return
        }

        // Yabai didn't find a window - use NSWorkspace to launch/activate
        guard !bundleIdentifier.isEmpty else {
            // Try to activate by app name if no bundle identifier
            if !appName.isEmpty,
               let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName }) {
                app.activate()
            }
            return
        }

        NSWorkspace.shared.launchApplication(
            withBundleIdentifier: bundleIdentifier,
            options: [],
            additionalEventParamDescriptor: nil,
            launchIdentifier: nil
        )
    }

    private func showNotificationHUD() {
        print("🔔 showNotificationHUD() called - currentlyVisible: \(notificationViewModel.isVisible)")

        guard let screen = NSScreen.main, let notchDimensions = notchDimensions else {
            print("🔔 showNotificationHUD: No screen or notch dimensions available")
            return
        }

        // Tell media HUD to hide its right panel (to avoid overlap)
        mediaViewModel.overlayDidShow()

        // Calculate HUD dimensions to resize window to only cover the HUD area
        // This is critical - by limiting the window size, clicks outside the HUD
        // will pass through to the menu bar and other UI elements
        let notchHeight = screen.safeAreaInsets.top
        // Match actual view panel widths - left is icon, right is text
        let leftPanelWidth = notchDimensions.height
        let rightPanelWidth = min(notchDimensions.height * 3, 150)
        let totalHUDWidth = leftPanelWidth + notchDimensions.width + rightPanelWidth

        // Center the window on the notch
        let hudCenterX = screen.frame.midX
        let windowFrame = NSRect(
            x: hudCenterX - totalHUDWidth / 2,
            y: screen.frame.origin.y + screen.frame.height - notchHeight,
            width: totalHUDWidth,
            height: notchHeight
        )

        // Resize window to only cover the HUD area
        notificationWindow.setFrame(windowFrame, display: false)

        // Update the hosting view frame to match
        notificationHostingView?.frame = NSRect(origin: .zero, size: windowFrame.size)

        // Enable mouse events for click handling
        notificationWindow.ignoresMouseEvents = false

        // Order window front with full opacity immediately
        notificationWindow.alphaValue = 1
        notificationWindow.orderFrontRegardless()

        // Update panel bounds so clicks are only captured within the HUD panels
        notificationHostingView?.updatePanelBounds(notchDimensions: notchDimensions, isVisible: true)

        // Force a layout pass
        notificationWindow.layoutIfNeeded()

        // The view model's show() already set isVisible = true, triggering animation
    }

    private func hideNotificationHUD() {
        print("🔔 hideNotificationHUD() called - currentlyVisible: \(notificationViewModel.isVisible)")

        if !notificationViewModel.isVisible {
            print("🔔 hideNotificationHUD: Already hidden, nothing to do")
            return
        }

        // Cancel auto-hide timer
        notificationAutoHideTimer?.invalidate()
        notificationAutoHideTimer = nil

        // Disable mouse events immediately so clicks pass through
        notificationWindow.ignoresMouseEvents = true

        // Update panel bounds to stop capturing clicks during fade-out
        if let notchDimensions = notchDimensions {
            notificationHostingView?.updatePanelBounds(notchDimensions: notchDimensions, isVisible: false)
        }

        // Clear notification data to prevent stale click handling
        // This prevents clicks on other HUDs from opening the previous notification's app
        notificationViewModel.bundleIdentifier = ""
        notificationViewModel.appName = ""

        print("🔔 hideNotificationHUD: Setting notificationViewModel.isVisible = false")
        notificationViewModel.isVisible = false

        // Restore media HUD right panel immediately when hide starts
        // This must happen outside the delayed block to prevent counter mismatch
        // if another show/hide cycle occurs during the animation delay
        mediaViewModel.overlayDidHide()

        // After animation completes, hide the window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if !self.notificationViewModel.isVisible {
                print("🔔 hideNotificationHUD: Animation complete, hiding window")
                self.notificationWindow.alphaValue = 0
                self.notificationWindow.orderOut(nil)
                // Move off-screen as extra safety to ensure no mouse blocking
                self.notificationWindow.setFrameOrigin(NSPoint(x: -10000, y: -10000))
            }
        }
    }

    // MARK: - Private helpers - Device HUD

    private func showDeviceHUD() {
        print("🎧 showDeviceHUD() called - currentlyVisible: \(deviceViewModel.isVisible)")

        // Tell media HUD to hide its right panel (to avoid overlap)
        mediaViewModel.overlayDidShow()

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

        // Restore media HUD right panel immediately when hide starts
        // This must happen outside the delayed block to prevent counter mismatch
        // if another show/hide cycle occurs during the animation delay
        mediaViewModel.overlayDidHide()

        // After animation completes, hide the window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if !self.deviceViewModel.isVisible {
                print("🎧 hideDeviceHUD: Animation complete, hiding window")
                self.deviceWindow.alphaValue = 0
                self.deviceWindow.orderOut(nil)
            }
        }
    }

    // MARK: - Private helpers - Focus HUD

    private func showFocusHUD() {
        print("🎯 showFocusHUD() called - currentlyVisible: \(focusViewModel.isVisible)")

        // Tell media HUD to hide its right panel (to avoid overlap)
        mediaViewModel.overlayDidShow()

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

        // Restore media HUD right panel immediately when hide starts
        // This must happen outside the delayed block to prevent counter mismatch
        // if another show/hide cycle occurs during the animation delay
        mediaViewModel.overlayDidHide()

        // After animation completes, hide the window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if !self.focusViewModel.isVisible {
                print("🎯 hideFocusHUD: Animation complete, hiding window")
                self.focusWindow.alphaValue = 0
                self.focusWindow.orderOut(nil)
            }
        }
    }

    // MARK: - Private helpers - Media HUD

    private func showMediaHUD() {
        // Safety: Reset overlay counter if no overlays are actually visible
        // This prevents stuck state where isOverlayActive is true but no overlay HUDs are showing
        if !overlayViewModel.isVisible && !deviceViewModel.isVisible &&
           !focusViewModel.isVisible && !notificationViewModel.isVisible {
            mediaViewModel.resetOverlayState()
        }

        // If already visible, ensure window is shown
        guard !mediaViewModel.isVisible else {
            if mediaWindow.alphaValue < 1 || !mediaWindow.isVisible {
                mediaWindow.alphaValue = 1
                mediaWindow.orderFrontRegardless()
            }
            return
        }

        // Order window front with full opacity immediately
        mediaWindow.alphaValue = 1
        mediaWindow.orderFrontRegardless()

        // Force a layout pass with initial state (isVisible = false)
        mediaWindow.layoutIfNeeded()

        // Update layout coordinator (skip in fullscreen track change mode)
        if !isFullscreenTrackChangeMode {
            updateMediaHUDLayout(isVisible: true)
        }

        // Animate to visible state
        DispatchQueue.main.async {
            self.mediaViewModel.isVisible = true
        }
    }

    private func hideMediaHUD() {
        // Check if already hidden
        guard mediaViewModel.isVisible else { return }

        // Cancel auto-hide timer
        mediaAutoHideTimer?.invalidate()
        mediaAutoHideTimer = nil

        // Trigger slide-out animation
        mediaViewModel.isVisible = false

        // Update layout coordinator (skip in fullscreen track change mode)
        if isFullscreenTrackChangeMode {
            isFullscreenTrackChangeMode = false
        } else {
            updateMediaHUDLayout(isVisible: false)
        }

        // After animation completes, hide the windows
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if !self.mediaViewModel.isVisible {
                self.mediaWindow.alphaValue = 0
                self.mediaWindow.orderOut(nil)
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

        // CRITICAL: Set visible synchronously FIRST to prevent duplicate calls
        // from rapid events (volume key generates multiple events quickly)
        overlayViewModel.isVisible = true

        // Start the display link for smooth animation (stops when HUD hides)
        overlayViewModel.progressAnimator.start()

        // Tell media HUD to hide its right panel (to avoid overlap)
        mediaViewModel.overlayDidShow()

        // Order window front and make visible
        overlayWindow.alphaValue = 1
        overlayWindow.orderFrontRegardless()

        // Force a layout pass before animation
        overlayWindow.layoutIfNeeded()

        // Mark as animating
        isAnimatingOverlay = true

        // Clear animation flag after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.isAnimatingOverlay = false
        }

        // Schedule auto-hide (cancels any previous schedule)
        scheduleOverlayHide()
    }

    // MARK: - Auto-hide

    /// Schedule overlay HUD to hide after 1.5s
    /// Each call cancels the previous schedule, effectively "bumping" the deadline
    private func scheduleOverlayHide() {
        // Cancel any pending hide
        hideWorkItem?.cancel()

        // Schedule a new hide after 1.5s
        let workItem = DispatchWorkItem { [weak self] in
            self?.hideOverlayHUD()
        }
        hideWorkItem = workItem

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
    }

    private func hideOverlayHUD() {
        // Clear the work item reference
        hideWorkItem = nil

        // Mark as animating
        isAnimatingOverlay = true

        // Animate out by setting view model
        overlayViewModel.isVisible = false

        // Update layout coordinator - determine which type based on icon
        let isVolume = overlayViewModel.iconName.contains("speaker")
        updateOverlayHUDLayout(isVisible: false, isVolume: isVolume)

        // Restore media HUD right panel immediately when hide starts
        // This must happen outside the delayed block to prevent counter mismatch
        // if another show/hide cycle occurs during the animation delay
        mediaViewModel.overlayDidHide()

        // After animation completes, fade window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // Only hide if still supposed to be hidden
            if !self.overlayViewModel.isVisible {
                self.overlayWindow.alphaValue = 0
                self.overlayWindow.orderOut(nil)

                // Stop the display link to save CPU when HUD is hidden
                self.overlayViewModel.progressAnimator.stop()
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
        hideNotificationHUD()
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
        menuBarViewModel?.sharedState.hudLayoutCoordinator?.setModule(
            type: .music,
            isVisible: isVisible,
            width: totalWidth
        )
    }

    /// Update the layout coordinator with the overlay HUD dimensions (volume/brightness)
    private func updateOverlayHUDLayout(isVisible: Bool, isVolume: Bool) {
        guard let notchDimensions = notchDimensions else { return }

        // Calculate ACTUAL visible width of the overlay HUD
        let sideWidth = notchDimensions.height + notchDimensions.padding / 2
        let totalWidth = sideWidth + notchDimensions.width + sideWidth

        // Update coordinator
        menuBarViewModel?.sharedState.hudLayoutCoordinator?.setModule(
            type: isVolume ? .volume : .brightness,
            isVisible: isVisible,
            width: totalWidth
        )
    }
}
