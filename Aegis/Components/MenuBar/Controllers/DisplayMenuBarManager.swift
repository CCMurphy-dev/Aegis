//
//  DisplayMenuBarManager.swift
//  Aegis
//
//  Manages multiple menu bar instances, one per display.
//  Handles auto-detection of displays and configurable multi-monitor modes.
//

import Cocoa
import SwiftUI
import Combine
import CoreGraphics

/// Manages menu bars across multiple displays based on configuration
final class DisplayMenuBarManager {
    private let windowManager: WindowManagerProtocol
    private let eventRouter: EventRouter
    private let config = AegisConfig.shared

    /// Menu bar coordinators keyed by display index
    private var coordinatorsByDisplay: [Int: MenuBarCoordinator] = [:]

    /// Track which displays we've created menu bars for
    private var activeDisplayIndices: Set<Int> = []

    /// Track the current config mode to detect mode changes (use raw config value, not resolved)
    private var currentConfigMode: AegisConfig.MultiMonitorMode?

    /// Track whether we've received valid yabai display data yet
    private var hasValidYabaiDisplayData = false

    /// Cancellables for config observation
    private var cancellables = Set<AnyCancellable>()

    /// Reference to HUD controller for integration
    private weak var hudController: NotchHUDController?

    /// CoreGraphics display reconfiguration callback (stored to allow removal)
    private var displayCallback: CGDisplayReconfigurationCallBack?

    /// Debounce timer for display changes (avoid duplicate handling from multiple callbacks)
    private var displayChangeDebounceWorkItem: DispatchWorkItem?

    init(windowManager: WindowManagerProtocol, eventRouter: EventRouter) {
        self.windowManager = windowManager
        self.eventRouter = eventRouter

        // Observe display changes via NSNotification (high-level)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDisplayChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // Register CoreGraphics callback for faster/more granular detection
        registerDisplayReconfigurationCallback()

        // Observe config changes for multi-monitor mode
        config.objectWillChange
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncMenuBarsWithDisplays()
            }
            .store(in: &cancellables)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        unregisterDisplayReconfigurationCallback()
    }

    // MARK: - Show/Hide

    func show() {
        syncMenuBarsWithDisplays()

        // Re-sync after delays to catch yabai data and external monitors that weren't ready at startup
        // 0.5s - catch yabai's initial async refresh
        // 2.0s - catch external monitors that initialize later than the MacBook display
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.syncMenuBarsWithDisplays()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.syncMenuBarsWithDisplays()
        }
    }

    func hide() {
        for (_, coordinator) in coordinatorsByDisplay {
            coordinator.hide()
        }
        coordinatorsByDisplay.removeAll()
        activeDisplayIndices.removeAll()
    }

    // MARK: - Display Sync

    /// Synchronize menu bars with current displays based on config mode
    private func syncMenuBarsWithDisplays() {
        let displays = windowManager.getCurrentDisplays()
        let screens = NSScreen.screens
        let displayCount = max(displays.count, screens.count)

        // Determine effective mode based on auto-detection
        let effectiveMode = resolveEffectiveMode(displayCount: displayCount)

        // Check if the RAW config mode changed - this catches perMonitor <-> allShowAll switches
        // which have the same display targets but different spaceFilterMode
        let configMode = config.multiMonitorMode
        let modeChanged = currentConfigMode != nil && currentConfigMode != configMode

        // Check if yabai display data just became available
        // This forces a rebuild when we transition from fallback mode to proper display matching
        let yabaiDataJustLoaded = !hasValidYabaiDisplayData && !displays.isEmpty
        if !displays.isEmpty {
            hasValidYabaiDisplayData = true
        }

        // Force rebuild if mode changed OR if yabai data just loaded (screen assignments may have been wrong)
        if modeChanged || yabaiDataJustLoaded {
            if modeChanged {
                logInfo("Multi-monitor mode changed from \(currentConfigMode?.rawValue ?? "nil") to \(configMode.rawValue) - rebuilding all menu bars")
            }
            if yabaiDataJustLoaded {
                logInfo("Yabai display data now available - rebuilding menu bars with correct screen assignments")
            }
            // Tear down all existing coordinators
            for (_, coordinator) in coordinatorsByDisplay {
                coordinator.hide()
            }
            coordinatorsByDisplay.removeAll()
            activeDisplayIndices.removeAll()
        }
        currentConfigMode = configMode

        // Determine which display indices should have menu bars
        let targetDisplayIndices: Set<Int>

        switch effectiveMode {
        case .primaryOnly:
            // Only display index 1 (primary)
            targetDisplayIndices = [1]

        case .perMonitor, .allShowAll:
            // All displays get menu bars
            if displays.isEmpty {
                // Fallback: use NSScreen count
                targetDisplayIndices = Set(1...max(1, screens.count))
            } else {
                targetDisplayIndices = Set(displays.map { $0.index })
            }

        case .auto:
            // This shouldn't happen after resolveEffectiveMode, but default to primaryOnly
            targetDisplayIndices = [1]
        }

        // Remove menu bars for displays that should no longer have them
        for displayIndex in activeDisplayIndices where !targetDisplayIndices.contains(displayIndex) {
            coordinatorsByDisplay[displayIndex]?.hide()
            coordinatorsByDisplay.removeValue(forKey: displayIndex)
            logInfo("Removed menu bar for display \(displayIndex)")
        }

        // Add/update menu bars for target displays
        for displayIndex in targetDisplayIndices {
            if coordinatorsByDisplay[displayIndex] == nil {
                // Create new coordinator for this display
                let coordinator = createCoordinator(for: displayIndex, mode: effectiveMode)
                coordinatorsByDisplay[displayIndex] = coordinator
                coordinator.show()

                // Connect HUD if available
                if let hud = hudController {
                    coordinator.connectHUDVisibility(from: hud)
                }

                logInfo("Created menu bar for display \(displayIndex)")
            }
        }

        activeDisplayIndices = targetDisplayIndices

        // Verify window health after sync settles
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.verifyWindowHealth()
        }
    }

    /// Resolve the effective mode (handles .auto based on display count)
    private func resolveEffectiveMode(displayCount: Int) -> AegisConfig.MultiMonitorMode {
        switch config.multiMonitorMode {
        case .auto:
            // Auto-detect: single display = primaryOnly, multiple = perMonitor
            return displayCount > 1 ? .perMonitor : .primaryOnly
        case .primaryOnly, .perMonitor, .allShowAll:
            return config.multiMonitorMode
        }
    }

    /// Create a MenuBarCoordinator for a specific display
    private func createCoordinator(for displayIndex: Int, mode: AegisConfig.MultiMonitorMode) -> MenuBarCoordinator {
        // Find the NSScreen for this display using DisplayScreenMatcher
        let displays = windowManager.getCurrentDisplays()
        let targetScreen: NSScreen?

        if let display = displays.first(where: { $0.index == displayIndex }) {
            targetScreen = DisplayScreenMatcher.matchScreen(for: display)
            logInfo("Display \(displayIndex): matched via yabai to screen \(targetScreen?.frame.width ?? 0)x\(targetScreen?.frame.height ?? 0)")
        } else if displays.isEmpty && NSScreen.screens.count > 1 {
            // Yabai data not loaded yet but we have multiple screens
            // Use NSScreen.main for display 1, and the other screen(s) for display 2+
            // NOTE: NSScreen.screens order is not guaranteed, so we must use .main explicitly
            let screens = NSScreen.screens
            if displayIndex == 1 {
                // Display 1 = main screen (the one with keyboard focus / menu bar)
                targetScreen = NSScreen.main
                logInfo("Display \(displayIndex): yabai data empty, using NSScreen.main")
            } else {
                // For display 2+, find a screen that isn't main
                // This handles the case where we have 2 screens and yabai isn't ready yet
                let nonMainScreens = screens.filter { $0 != NSScreen.main }
                let index = displayIndex - 2  // displayIndex 2 -> index 0, displayIndex 3 -> index 1, etc.
                if index < nonMainScreens.count {
                    targetScreen = nonMainScreens[index]
                    logInfo("Display \(displayIndex): yabai data empty, using non-main screen \(index)")
                } else {
                    targetScreen = nil
                    logInfo("Display \(displayIndex): yabai data empty, no matching screen found")
                }
            }
        } else {
            // Single monitor or yabai has data but this display index not found
            targetScreen = displayIndex == 1 ? NSScreen.main : nil
            logInfo("Display \(displayIndex): fallback to \(displayIndex == 1 ? "main" : "nil")")
        }

        // Determine space filter mode
        let spaceFilterMode: MenuBarViewModel.SpaceFilterMode = mode == .perMonitor ? .perMonitor : .all

        let coordinator = MenuBarCoordinator(
            windowManager: windowManager,
            eventRouter: eventRouter,
            displayIndex: displayIndex,
            targetScreen: targetScreen,
            spaceFilterMode: spaceFilterMode
        )
        return coordinator
    }

    // MARK: - CoreGraphics Display Reconfiguration

    /// Register for CoreGraphics display reconfiguration callbacks
    /// This provides faster and more granular detection than NSNotification
    private func registerDisplayReconfigurationCallback() {
        // Create the callback - must be a C function pointer
        displayCallback = { (displayID: CGDirectDisplayID, flags: CGDisplayChangeSummaryFlags, userInfo: UnsafeMutableRawPointer?) in
            guard let userInfo = userInfo else { return }
            let manager = Unmanaged<DisplayMenuBarManager>.fromOpaque(userInfo).takeUnretainedValue()
            manager.handleDisplayReconfiguration(displayID: displayID, flags: flags)
        }

        // Register with self as userInfo
        if let callback = displayCallback {
            let selfPointer = Unmanaged.passUnretained(self).toOpaque()
            CGDisplayRegisterReconfigurationCallback(callback, selfPointer)
        }
    }

    /// Unregister the CoreGraphics callback
    private func unregisterDisplayReconfigurationCallback() {
        if let callback = displayCallback {
            let selfPointer = Unmanaged.passUnretained(self).toOpaque()
            CGDisplayRemoveReconfigurationCallback(callback, selfPointer)
            displayCallback = nil
        }
    }

    /// Handle CoreGraphics display reconfiguration events
    private func handleDisplayReconfiguration(displayID: CGDirectDisplayID, flags: CGDisplayChangeSummaryFlags) {
        // Only act on completion, not begin
        guard !flags.contains(.beginConfigurationFlag) else { return }

        // Log what changed for debugging
        if flags.contains(.addFlag) {
            logInfo("Display \(displayID) added (CoreGraphics)")
        } else if flags.contains(.removeFlag) {
            logInfo("Display \(displayID) removed (CoreGraphics)")
        } else if flags.contains(.movedFlag) {
            logInfo("Display \(displayID) moved (CoreGraphics)")
        } else if flags.contains(.setMainFlag) {
            logInfo("Display \(displayID) became main (CoreGraphics)")
        }

        // Debounce to avoid duplicate handling with NSNotification
        scheduleDisplaySync()
    }

    // MARK: - Display Change Handling

    @objc private func handleDisplayChange() {
        logInfo("Display configuration changed (NSNotification)")
        // Debounce to avoid duplicate handling with CoreGraphics callback
        scheduleDisplaySync()
    }

    /// Debounced display sync — performs a full rebuild (same as wake/unlock)
    /// to handle stale NSScreen references after monitor connect/disconnect
    private func scheduleDisplaySync() {
        displayChangeDebounceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            logInfo("Display change detected — performing full rebuild")
            self?.rebuildAllMenuBars()
        }
        displayChangeDebounceWorkItem = workItem

        // 0.5s delay to let macOS settle its display list
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    // MARK: - Wake / Reconnect Rebuild

    /// Force full teardown and rebuild of all menu bar windows.
    /// Called on screen wake or unlock, where NSScreen frames may have shifted
    /// but existing coordinators still hold stale window positions.
    func rebuildAllMenuBars() {
        for (_, coordinator) in coordinatorsByDisplay {
            coordinator.hide()
        }
        coordinatorsByDisplay.removeAll()
        activeDisplayIndices.removeAll()
        // Reset so the yabai-data-loaded path fires again on first sync
        hasValidYabaiDisplayData = false

        // Sync immediately, then again after the display has fully settled
        // Note: we intentionally do NOT seed fullscreen state from the old coordinators.
        // Display indices can shift during monitor connect/disconnect, so seeding by index
        // could apply the wrong display's fullscreen state (e.g. external monitor's fullscreen
        // state applied to laptop), leaving ignoresMouseEvents=true and blocking all clicks.
        // performUpdate() will detect the correct fullscreen state within ~50ms.
        syncMenuBarsWithDisplays()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.syncMenuBarsWithDisplays()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.syncMenuBarsWithDisplays()
        }
    }

    // MARK: - Window Health Check

    /// Timestamp of last health-check-triggered rebuild (prevents loops)
    private var lastHealthCheckRebuild: Date = .distantPast

    /// Verify all menu bar windows are healthy; rebuild if not
    private func verifyWindowHealth() {
        // Don't rebuild more than once per 5 seconds from health checks
        guard Date().timeIntervalSince(lastHealthCheckRebuild) > 5.0 else { return }

        for (displayIndex, coordinator) in coordinatorsByDisplay {
            // Skip fullscreen displays — windows are intentionally hidden
            if coordinator.isCurrentlyFullscreen { continue }

            if !coordinator.isWindowHealthy {
                logInfo("Menu bar window unhealthy on display \(displayIndex) — triggering rebuild")
                lastHealthCheckRebuild = Date()
                rebuildAllMenuBars()
                return
            }
        }
    }

    // MARK: - Updates

    func updateSpaces() {
        for (_, coordinator) in coordinatorsByDisplay {
            coordinator.updateSpaces()
        }
    }

    func updateWindows() {
        for (_, coordinator) in coordinatorsByDisplay {
            coordinator.updateWindows()
        }
    }

    // MARK: - HUD Integration

    func connectHUDVisibility(from hudController: NotchHUDController) {
        self.hudController = hudController
        for (_, coordinator) in coordinatorsByDisplay {
            coordinator.connectHUDVisibility(from: hudController)
        }
    }
}
