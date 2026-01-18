import Cocoa
import SwiftUI

@objc
class AppDelegate: NSObject, NSApplicationDelegate {

    var menuBarController: MenuBarController?
    var notchHUDController: NotchHUDController?

    var yabaiService: YabaiService?
    var systemInfoService: SystemInfoService?
    var musicService: MediaService?
    var bluetoothService: BluetoothDeviceService?
    var focusMonitor: FocusStatusMonitor?
    var appSwitcherService: AppSwitcherService?
    var eventRouter: EventRouter?

    private var setupWindowController: YabaiSetupWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let aegisVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        logInfo("Aegis v\(aegisVersion) starting")

        NSApp.setActivationPolicy(.accessory)
        setupServices()
        setupMenuBar()
        setupNotchHUD()

        // IMPORTANT: Subscribe to events BEFORE services start publishing
        startEventListening()

        // 🎬 DIAGNOSTICS: Uncomment to enable frame-by-frame animation logging
        notchHUDController?.enableAnimationDiagnostics(true)

        // Show startup notification with status
        StartupNotificationService.showStartupNotification()

        // Sync launch at login setting with actual system state
        LaunchAtLoginService.shared.syncWithConfig()

        // Check if yabai setup is needed and show setup window
        checkAndShowSetupIfNeeded()

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

    func applicationWillTerminate(_ notification: Notification) {
        logInfo("Aegis shutting down")
        menuBarController?.hide()
        notchHUDController?.hide()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - Setup Services
    private func setupServices() {
        eventRouter = EventRouter()
        yabaiService = YabaiService(eventRouter: eventRouter!)
        systemInfoService = SystemInfoService(eventRouter: eventRouter!)
        musicService = MediaService(eventRouter: eventRouter!)
        bluetoothService = BluetoothDeviceService(eventRouter: eventRouter!)
        focusMonitor = FocusStatusMonitor(eventRouter: eventRouter!)

        // App Switcher (Cmd+Tab replacement)
        appSwitcherService = AppSwitcherService.shared
        appSwitcherService?.start()

        // Wire up SystemStatusMonitor.shared to receive focus events
        // This avoids duplicate file system watchers
        SystemStatusMonitor.shared.subscribeToFocusEvents(eventRouter: eventRouter!)
        SystemStatusMonitor.shared.setInitialFocusStatus(focusMonitor!.focusStatus)
    }

    // MARK: - Setup Menu Bar
    private func setupMenuBar() {
        guard let yabaiService, let eventRouter else { return }
        menuBarController = MenuBarController(
            yabaiService: yabaiService,
            eventRouter: eventRouter
        )
        menuBarController?.show()
    }

    // MARK: - Setup Notch HUD
    private func setupNotchHUD() {
        guard let systemInfoService, let musicService, let eventRouter else { return }
        notchHUDController = NotchHUDController(
            systemInfoService: systemInfoService,
            musicService: musicService,
            eventRouter: eventRouter
        )

        // CRITICAL: Prepare windows at app startup (before any interactions)
        notchHUDController?.prepareWindows()

        // Connect HUD visibility to menu bar
        if let menuBarController, let notchHUDController {
            menuBarController.connectHUDVisibility(from: notchHUDController)
        }

    }

    // MARK: - Event Subscriptions
    private func startEventListening() {
        guard let router = eventRouter else { return }

        router.subscribe(to: .spaceChanged) { [weak self] _ in
            self?.menuBarController?.updateSpaces()
        }

        router.subscribe(to: .windowsChanged) { [weak self] _ in
            self?.menuBarController?.updateWindows()
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
            self?.notchHUDController?.showVolume(level: level, isMuted: isMuted)
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
            self?.notchHUDController?.showBrightness(level: level)
        }

        router.subscribe(to: .mediaPlaybackChanged) { [weak self] data in
            guard let info = data["info"] as? MediaInfo else { return }
            self?.notchHUDController?.showMedia(info: info)
        }

        router.subscribe(to: .bluetoothDeviceConnected) { [weak self] data in
            guard let device = data["device"] as? BluetoothDeviceInfo else { return }
            self?.notchHUDController?.showDeviceConnected(device: device)
        }

        router.subscribe(to: .bluetoothDeviceDisconnected) { [weak self] data in
            guard let device = data["device"] as? BluetoothDeviceInfo else { return }
            self?.notchHUDController?.showDeviceDisconnected(device: device)
        }

        router.subscribe(to: .focusChanged) { [weak self] data in
            let isEnabled = data["isEnabled"] as? Bool ?? false
            let focusName = data["focusName"] as? String
            let symbolName = data["symbolName"] as? String
            let status = FocusStatus(isEnabled: isEnabled, focusName: focusName, symbolName: symbolName)
            self?.notchHUDController?.showFocusChanged(status: status)
        }
    }
}