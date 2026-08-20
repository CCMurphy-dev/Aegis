//
//  NotchHUDManager.swift
//  Aegis
//
//  Coordinates NotchHUDController instances across multiple displays.
//  Hardware-notch screens get a standard controller; external screens
//  get a virtual-notch controller when showVirtualNotch is enabled.
//

import Cocoa
import Combine

class NotchHUDManager {
    private var controllers: [CGDirectDisplayID: NotchHUDController] = [:]

    private let systemInfoService: SystemInfoService
    private let musicService: MediaService
    private let eventRouter: EventRouter
    private let windowManager: WindowManagerProtocol

    private var configCancellables = Set<AnyCancellable>()

    init(systemInfoService: SystemInfoService,
         musicService: MediaService,
         eventRouter: EventRouter,
         windowManager: WindowManagerProtocol) {
        self.systemInfoService = systemInfoService
        self.musicService = musicService
        self.eventRouter = eventRouter
        self.windowManager = windowManager
    }

    /// Called once at startup
    func setup() {
        syncControllersWithDisplays()
        observeConfigChanges()
    }

    private func observeConfigChanges() {
        let config = AegisConfig.shared

        // Toggle adds/removes virtual notch controllers
        // NOTE: @Published emits on willSet (before value changes),
        // so we must receive on next run loop to read the new value
        config.$showVirtualNotch
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncControllersWithDisplays()
            }
            .store(in: &configCancellables)

        // Dimension changes require rebuilding virtual notch controllers
        // (windows are sized at creation time)
        Publishers.CombineLatest(config.$virtualNotchWidth, config.$virtualNotchHeight)
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildVirtualNotchControllers()
            }
            .store(in: &configCancellables)
    }

    /// Tear down and recreate only virtual notch controllers (dimension change)
    private func rebuildVirtualNotchControllers() {
        let virtualIDs = controllers.filter { $0.value.isVirtualNotch }.map { $0.key }
        for id in virtualIDs {
            controllers[id]?.hide()
            controllers.removeValue(forKey: id)
        }
        // Re-sync will recreate them with new dimensions
        syncControllersWithDisplays()
    }

    /// Diff current screens vs. active controllers; create/destroy as needed
    private func syncControllersWithDisplays() {
        let targetScreens = DisplayScreenMatcher.screensWithNotch()
        logInfo("NotchHUDManager syncControllersWithDisplays: \(targetScreens.count) target screens, \(controllers.count) existing controllers, showVirtualNotch=\(AegisConfig.shared.showVirtualNotch)")

        // Build map of displayID -> screen for targets
        var targetMap: [CGDirectDisplayID: NSScreen] = [:]
        for screen in targetScreens {
            if let id = DisplayScreenMatcher.displayID(for: screen) {
                targetMap[id] = screen
                logInfo("  target screen: displayID=\(id), safeArea.top=\(screen.safeAreaInsets.top), frame=\(screen.frame)")
            }
        }

        // Remove controllers for screens no longer present/eligible
        for id in controllers.keys where targetMap[id] == nil {
            logInfo("  removing controller for displayID=\(id) (isVirtual=\(controllers[id]?.isVirtualNotch ?? false))")
            controllers[id]?.hide()
            controllers.removeValue(forKey: id)
        }

        // Add controllers for new screens
        for (id, screen) in targetMap where controllers[id] == nil {
            let isVirtual = screen.safeAreaInsets.top == 0
            logInfo("  creating controller for displayID=\(id) (isVirtual=\(isVirtual))")
            let controller = NotchHUDController(
                systemInfoService: systemInfoService,
                musicService: musicService,
                eventRouter: eventRouter,
                windowManager: windowManager,
                targetScreen: screen,
                isVirtualNotch: isVirtual
            )
            controller.prepareWindows()
            controllers[id] = controller
        }

        logInfo("  final controller count: \(controllers.count)")
    }

    // MARK: - Fan-Out Public API

    func showVolume(level: Float, isMuted: Bool) {
        for ctrl in controllers.values { ctrl.showVolume(level: level, isMuted: isMuted) }
    }

    func showBrightness(level: Float) {
        for ctrl in controllers.values { ctrl.showBrightness(level: level) }
    }

    func showMedia(info: MediaInfo) {
        for ctrl in controllers.values { ctrl.showMedia(info: info) }
    }

    func showDeviceConnected(device: BluetoothDeviceInfo) {
        for ctrl in controllers.values { ctrl.showDeviceConnected(device: device) }
    }

    func showDeviceDisconnected(device: BluetoothDeviceInfo) {
        for ctrl in controllers.values { ctrl.showDeviceDisconnected(device: device) }
    }

    func showFocusChanged(status: FocusStatus) {
        for ctrl in controllers.values { ctrl.showFocusChanged(status: status) }
    }

    func showNotification(appName: String, title: String, body: String, bundleIdentifier: String) {
        for ctrl in controllers.values {
            ctrl.showNotification(appName: appName, title: title, body: body, bundleIdentifier: bundleIdentifier)
        }
    }

    func hide() {
        for ctrl in controllers.values { ctrl.hide() }
    }

    func handleScreenWake() {
        syncControllersWithDisplays()
        for ctrl in controllers.values { ctrl.handleScreenWake() }
    }

    func handleScreenUnlock() {
        syncControllersWithDisplays()
        for ctrl in controllers.values { ctrl.handleScreenUnlock() }
    }

    func handleDisplayConfigChange() {
        syncControllersWithDisplays()
        for ctrl in controllers.values { ctrl.handleDisplayConfigChange() }
    }

    func enableAnimationDiagnostics(_ enabled: Bool) {
        for ctrl in controllers.values { ctrl.enableAnimationDiagnostics(enabled) }
    }

    // MARK: - Menu Bar Integration

    /// Returns the hardware-notch controller (for menu bar HUD coordination)
    var primaryController: NotchHUDController? {
        controllers.values.first(where: { !$0.isVirtualNotch })
            ?? controllers.values.first
    }

    func connectHUDVisibility(to displayMenuBarManager: DisplayMenuBarManager) {
        if let primary = primaryController {
            displayMenuBarManager.connectHUDVisibility(from: primary)
        }
    }
}
