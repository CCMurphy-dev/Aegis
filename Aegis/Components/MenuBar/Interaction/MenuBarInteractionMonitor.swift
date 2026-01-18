import Cocoa
import Foundation

// MARK: - MenuBarInteractionMonitor
// Monitors for native menu bar activation using event-based detection (no polling)

class MenuBarInteractionMonitor {
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var nativeMenuHandler: ((Bool) -> Void)?
    private var lastMenuState: Bool = false

    // MARK: - Monitoring

    func startMonitoring(onNativeMenuChange: @escaping (Bool) -> Void) {
        self.nativeMenuHandler = onNativeMenuChange

        // Use NSEvent monitors for menu tracking instead of polling
        // Local monitor catches events when app is active
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            self?.checkMenuState()
            return event
        }

        // Global monitor catches events when other apps are active
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.checkMenuState()
        }

        // Also observe when app becomes/resigns active
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )

        // Check menu state when menus open/close
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuDidBeginTracking),
            name: NSMenu.didBeginTrackingNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuDidEndTracking),
            name: NSMenu.didEndTrackingNotification,
            object: nil
        )
    }

    func stopMonitoring() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        NotificationCenter.default.removeObserver(self)
        nativeMenuHandler = nil
    }

    // MARK: - Event Handlers

    @objc private func appDidBecomeActive() {
        checkMenuState()
    }

    @objc private func appDidResignActive() {
        checkMenuState()
    }

    @objc private func menuDidBeginTracking(_ notification: Notification) {
        // A menu started tracking - check if it's a native menu bar menu
        DispatchQueue.main.async { [weak self] in
            self?.checkMenuState()
        }
    }

    @objc private func menuDidEndTracking(_ notification: Notification) {
        // A menu stopped tracking
        DispatchQueue.main.async { [weak self] in
            self?.checkMenuState()
        }
    }

    // MARK: - Native Menu Bar Detection

    private func checkMenuState() {
        // Check if any native menu is active by looking at the key window
        let isMenuActive = NSApp.keyWindow?.className.contains("NSStatusBarWindow") ?? false

        // Only notify if state changed
        if isMenuActive != lastMenuState {
            lastMenuState = isMenuActive
            nativeMenuHandler?(isMenuActive)
        }
    }

    deinit {
        stopMonitoring()
    }
}
