import Cocoa
import Foundation

// MARK: - MenuBarInteractionMonitor
// Monitors for native menu bar activation (not mouse position)

class MenuBarInteractionMonitor {
    private var menuMonitor: Timer?
    private var nativeMenuHandler: ((Bool) -> Void)?

    // MARK: - Monitoring

    func startMonitoring(onNativeMenuChange: @escaping (Bool) -> Void) {
        self.nativeMenuHandler = onNativeMenuChange

        // Poll only for native menu bar activation, not mouse position
        menuMonitor = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.checkForNativeMenuBar()
        }
    }

    func stopMonitoring() {
        menuMonitor?.invalidate()
        menuMonitor = nil
        nativeMenuHandler = nil
    }

    // MARK: - Native Menu Bar Detection

    private func checkForNativeMenuBar() {
        // Check if any native menu is active by looking at the key window
        let isMenuActive = NSApp.keyWindow?.className.contains("NSStatusBarWindow") ?? false
        nativeMenuHandler?(isMenuActive)
    }

    deinit {
        stopMonitoring()
    }
}
