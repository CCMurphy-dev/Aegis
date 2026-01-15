import Cocoa
import SwiftUI

@objc
class AppDelegate: NSObject, NSApplicationDelegate {

    var menuBarController: MenuBarController?
    var notchHUDController: NotchHUDController?

    var yabaiService: YabaiService?
    var systemInfoService: SystemInfoService?
    var musicService: MediaService?
    var eventRouter: EventRouter?

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

        logInfo("Startup complete")
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

        router.subscribe(to: .musicPlaybackChanged) { [weak self] data in
            guard let info = data["info"] as? MusicInfo else { return }
            self?.notchHUDController?.showMusic(info: info)
        }
    }
}