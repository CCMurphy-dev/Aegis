import Cocoa
import SwiftUI

@objc
class AppDelegate: NSObject, NSApplicationDelegate {

    var displayMenuBarManager: DisplayMenuBarManager?
    var notchHUDManager: NotchHUDManager?

    var windowManager: WindowManagerProtocol?
    var systemInfoService: SystemInfoService?
    var musicService: MediaService?
    var bluetoothService: BluetoothDeviceService?
    var focusMonitor: FocusStatusMonitor?
    var notificationService: NotificationService?
    var appSwitcherService: AppSwitcherService?
    var wallpaperBlurService: WallpaperBlurService?
    var eventRouter: EventRouter?

    private var setupWindowController: YabaiSetupWindowController?
    private var aeroSpaceSetupWindowController: AeroSpaceSetupWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let aegisVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        logInfo("Aegis v\(aegisVersion) starting")

        NSApp.setActivationPolicy(.accessory)
        setupServices()
        setupMenuBar()
        setupNotchHUD()
        setupWakeNotification()

        // IMPORTANT: Subscribe to events BEFORE services start publishing
        startEventListening()

        // 🎬 DIAGNOSTICS: Uncomment to enable frame-by-frame animation logging
        notchHUDManager?.enableAnimationDiagnostics(true)

        // Show startup notification with status
        StartupNotificationService.showStartupNotification(windowManagerName: windowManager?.name ?? "Yabai")

        // Sync launch at login setting with actual system state
        LaunchAtLoginService.shared.syncWithConfig()

        // Check if WM setup is needed and show setup window
        if windowManager?.name == "Yabai" {
            checkAndShowSetupIfNeeded()
        } else if windowManager?.name == "AeroSpace" {
            checkAndShowAeroSpaceSetupIfNeeded()
        }

        logInfo("Startup complete")
    }

    // MARK: - Setup Check

    private func checkAndShowSetupIfNeeded() {
        // Skip if user has dismissed setup before
        if UserDefaults.standard.bool(forKey: "aegis.setup.dismissed") {
            logInfo("Setup check: previously dismissed by user")
            return
        }

        let status = YabaiSetupChecker.check()

        // Only show setup window if not ready
        guard status != .ready else {
            logInfo("Setup check: yabai integration is ready")
            return
        }

        logInfo("Setup check: showing setup window (status: \(status))")

        // Delay slightly to let the app fully launch first
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.showSetupWindow(status: status)
        }
    }

    func showSetupWindow(status: YabaiSetupChecker.SetupStatus? = nil) {
        let currentStatus = status ?? YabaiSetupChecker.check()

        setupWindowController = YabaiSetupWindowController(
            status: currentStatus,
            onDismiss: { [weak self] in
                // Mark as dismissed so we don't show again
                UserDefaults.standard.set(true, forKey: "aegis.setup.dismissed")
                self?.setupWindowController = nil
            },
            onRetry: { [weak self] in
                self?.setupWindowController = nil
                // Re-check after a brief delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self?.checkAndShowSetupIfNeeded()
                }
            }
        )
        setupWindowController?.showModal()
    }

    // MARK: - AeroSpace Setup Check

    private func checkAndShowAeroSpaceSetupIfNeeded() {
        if UserDefaults.standard.bool(forKey: "aegis.aerospace.setup.dismissed") {
            logInfo("AeroSpace setup check: previously dismissed by user")
            return
        }

        let status = AeroSpaceSetupChecker.check()

        guard status != .ready else {
            logInfo("AeroSpace setup check: integration is ready")
            return
        }

        logInfo("AeroSpace setup check: showing setup window (status: \(status))")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.showAeroSpaceSetupWindow(status: status)
        }
    }

    func showAeroSpaceSetupWindow(status: AeroSpaceSetupChecker.SetupStatus? = nil) {
        let currentStatus = status ?? AeroSpaceSetupChecker.check()

        aeroSpaceSetupWindowController = AeroSpaceSetupWindowController(
            status: currentStatus,
            onDismiss: { [weak self] in
                UserDefaults.standard.set(true, forKey: "aegis.aerospace.setup.dismissed")
                self?.aeroSpaceSetupWindowController = nil
            },
            onRetry: { [weak self] in
                self?.aeroSpaceSetupWindowController = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self?.showAeroSpaceSetupWindow()
                }
            }
        )
        aeroSpaceSetupWindowController?.showModal()
    }

    func applicationWillTerminate(_ notification: Notification) {
        logInfo("Aegis shutting down")
        displayMenuBarManager?.hide()
        notchHUDManager?.hide()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - Setup Services
    private func setupServices() {
        eventRouter = EventRouter()
        logInfo("WindowManager config: \(AegisConfig.shared.windowManagerType.rawValue)")
        windowManager = WindowManagerFactory.create(type: AegisConfig.shared.windowManagerType, eventRouter: eventRouter!)
        AegisConfig.shared.activeWindowManagerName = windowManager?.name ?? "Yabai"
        logInfo("Active window manager: \(AegisConfig.shared.activeWindowManagerName)")
        systemInfoService = SystemInfoService(eventRouter: eventRouter!)
        musicService = MediaService(eventRouter: eventRouter!)
        bluetoothService = BluetoothDeviceService(eventRouter: eventRouter!)
        focusMonitor = FocusStatusMonitor(eventRouter: eventRouter!)
        notificationService = NotificationService(eventRouter: eventRouter!)

        // Start notification monitoring (event-driven, zero CPU when idle)
        notificationService?.startMonitoring()

        // App Switcher (Cmd+Tab replacement)
        appSwitcherService = AppSwitcherService.shared
        appSwitcherService?.setWindowManager(windowManager!)
        appSwitcherService?.start()

        // Wallpaper blur (desktop blur when windows are focused)
        wallpaperBlurService = WallpaperBlurService(eventRouter: eventRouter!)

        // Wire up SystemStatusMonitor.shared to receive focus events
        // This avoids duplicate file system watchers
        SystemStatusMonitor.shared.subscribeToFocusEvents(eventRouter: eventRouter!)
        SystemStatusMonitor.shared.setInitialFocusStatus(focusMonitor!.focusStatus)
    }

    // MARK: - Setup Menu Bar
    private func setupMenuBar() {
        guard let windowManager, let eventRouter else { return }
        displayMenuBarManager = DisplayMenuBarManager(
            windowManager: windowManager,
            eventRouter: eventRouter
        )
        displayMenuBarManager?.show()
    }

    // MARK: - Setup Notch HUD
    private func setupNotchHUD() {
        guard let systemInfoService, let musicService, let eventRouter, let windowManager else { return }
        notchHUDManager = NotchHUDManager(
            systemInfoService: systemInfoService,
            musicService: musicService,
            eventRouter: eventRouter,
            windowManager: windowManager
        )
        notchHUDManager?.setup()

        // Connect HUD visibility to menu bar (uses primary/hardware-notch controller)
        if let displayMenuBarManager {
            notchHUDManager?.connectHUDVisibility(to: displayMenuBarManager)
        }
    }

    // MARK: - Setup Wake/Unlock Notifications
    private func setupWakeNotification() {
        // Wake from sleep (lid open without login required)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleScreenWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        // Screen unlock after login - fires when user authenticates after lid open
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleScreenUnlock),
            name: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )

        // Display configuration changed - fires when displays are added/removed/reconfigured
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDisplayConfigChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func handleScreenWake(_ notification: Notification) {
        logInfo("Screen woke from sleep - rebuilding menu bars and checking media HUD state")
        // Rebuild menu bar windows so positions match the (potentially shifted) NSScreen frames
        displayMenuBarManager?.rebuildAllMenuBars()
        // Small delay to let system fully wake before restoring HUD
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.notchHUDManager?.handleScreenWake()
        }
    }

    @objc private func handleScreenUnlock(_ notification: Notification) {
        logInfo("Screen unlocked - rebuilding menu bars and reinitializing HUD windows")
        // Rebuild menu bar windows in case screen layout changed while locked
        displayMenuBarManager?.rebuildAllMenuBars()
        // Longer delay for unlock as system is still initializing after login
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.notchHUDManager?.handleScreenUnlock()
        }
    }

    @objc private func handleDisplayConfigChange(_ notification: Notification) {
        logInfo("Display configuration changed - recalculating notch dimensions")
        // Brief delay to let display settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.notchHUDManager?.handleDisplayConfigChange()
        }
    }

    // MARK: - Event Subscriptions
    private func startEventListening() {
        guard let router = eventRouter else { return }

        router.subscribe(to: .spaceChanged) { [weak self] _ in
            // Skip space updates if space indicators are disabled
            guard AegisConfig.shared.showSpaceIndicators else { return }
            self?.displayMenuBarManager?.updateSpaces()
        }

        // A native fullscreen transition can change only a display's native
        // space while the Rift workspace list stays identical. Refresh the
        // per-display menu-bar visibility even when indicators are disabled.
        router.subscribe(to: .displaysChanged) { [weak self] _ in
            self?.displayMenuBarManager?.updateSpaces()
        }

        router.subscribe(to: .windowsChanged) { [weak self] _ in
            // Skip window updates if space indicators are disabled
            guard AegisConfig.shared.showSpaceIndicators else { return }
            self?.displayMenuBarManager?.updateWindows()
        }

        router.subscribe(to: .volumeChanged) { [weak self] data in
            // Handle level - try Float first, then Double (since 0.0 might be stored as Double)
            let level: Float
            if let floatLevel = data["level"] as? Float {
                level = floatLevel
            } else if let doubleLevel = data["level"] as? Double {
                level = Float(doubleLevel)
            } else {
                return
            }

            let isMuted = data["isMuted"] as? Bool ?? false
            self?.notchHUDManager?.showVolume(level: level, isMuted: isMuted)
        }

        router.subscribe(to: .brightnessChanged) { [weak self] data in
            // Handle level - try Float first, then Double
            let level: Float
            if let floatLevel = data["level"] as? Float {
                level = floatLevel
            } else if let doubleLevel = data["level"] as? Double {
                level = Float(doubleLevel)
            } else {
                return
            }
            self?.notchHUDManager?.showBrightness(level: level)
        }

        router.subscribe(to: .mediaPlaybackChanged) { [weak self] data in
            guard let info = data["info"] as? MediaInfo else { return }
            self?.notchHUDManager?.showMedia(info: info)
        }

        router.subscribe(to: .bluetoothDeviceConnected) { [weak self] data in
            guard let device = data["device"] as? BluetoothDeviceInfo else { return }
            self?.notchHUDManager?.showDeviceConnected(device: device)
        }

        router.subscribe(to: .bluetoothDeviceDisconnected) { [weak self] data in
            guard let device = data["device"] as? BluetoothDeviceInfo else { return }
            self?.notchHUDManager?.showDeviceDisconnected(device: device)
        }

        router.subscribe(to: .focusChanged) { [weak self] data in
            let isEnabled = data["isEnabled"] as? Bool ?? false
            let focusName = data["focusName"] as? String
            let symbolName = data["symbolName"] as? String
            let status = FocusStatus(isEnabled: isEnabled, focusName: focusName, symbolName: symbolName)
            self?.notchHUDManager?.showFocusChanged(status: status)
        }

        router.subscribe(to: .notificationReceived) { [weak self] data in
            let appName = data["appName"] as? String ?? ""
            let title = data["title"] as? String ?? ""
            let body = data["body"] as? String ?? ""
            let bundleIdentifier = data["bundleIdentifier"] as? String ?? ""

            // Check if notification should be excluded based on config
            let excludedApps = AegisConfig.shared.notificationExcludedApps
            for excluded in excludedApps {
                // Check bundle identifier match
                if bundleIdentifier == excluded {
                    return
                }
                // Check app name match (case-insensitive, partial) for non-bundle-id entries
                if !excluded.contains(".") && appName.localizedCaseInsensitiveContains(excluded) {
                    return
                }
            }

            self?.notchHUDManager?.showNotification(
                appName: appName,
                title: title,
                body: body,
                bundleIdentifier: bundleIdentifier
            )
        }
    }
}
