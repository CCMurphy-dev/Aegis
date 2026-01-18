import Foundation
import AppKit
import Carbon.HIToolbox

/// Service that intercepts Cmd+Tab to provide a custom app switcher
/// Displays windows organized by space in a centered overlay
final class AppSwitcherService {

    static let shared = AppSwitcherService()

    // MARK: - State

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var isActive: Bool = false

    /// Currently selected index in the flat list of all windows
    private(set) var selectedIndex: Int = 0

    /// Windows organized by space
    private(set) var spaceGroups: [SpaceGroup] = []

    /// Flat list of all windows for navigation
    private(set) var allWindows: [SwitcherWindow] = []

    /// Filtered list based on search query
    private(set) var filteredWindows: [SwitcherWindow] = []

    /// Current search/filter query
    private(set) var searchQuery: String = ""

    /// The overlay window controller
    private var windowController: AppSwitcherWindowController?

    private let yabaiCommand = YabaiCommandActor.shared
    private let config = AegisConfig.shared

    /// Scroll accumulator for Cmd+scroll activation
    private var cmdScrollAccumulator: CGFloat = 0

    /// Cached app icons by name - persists across activations
    private var appIconCache: [String: NSImage] = [:]

    /// Whether the icon cache needs refreshing (set true when apps change)
    private var iconCacheNeedsRefresh: Bool = true

    // MARK: - Init

    private init() {
        logInfo("AppSwitcherService initialized")
        // Pre-warm icon cache with running apps
        refreshIconCache(force: true)

        // Listen for app launch/quit to update cache
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidLaunchOrTerminate),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidLaunchOrTerminate),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
    }

    @objc private func appDidLaunchOrTerminate(_ notification: Notification) {
        // Mark cache as needing refresh when apps change
        iconCacheNeedsRefresh = true
    }

    /// Track if a refresh is already in progress
    private var isRefreshingIconCache = false

    /// Refresh icon cache from running apps (only when needed - event-driven)
    private func refreshIconCache(force: Bool = false) {
        // Skip if cache is fresh and not forced
        guard force || iconCacheNeedsRefresh else { return }

        // Skip if refresh already in progress
        guard !isRefreshingIconCache else { return }

        iconCacheNeedsRefresh = false
        isRefreshingIconCache = true

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let runningApps = NSWorkspace.shared.runningApplications
            var newCache: [String: NSImage] = [:]
            for app in runningApps {
                if let name = app.localizedName, let icon = app.icon {
                    newCache[name] = icon
                }
            }
            DispatchQueue.main.async {
                self?.appIconCache.merge(newCache) { _, new in new }
                self?.isRefreshingIconCache = false
            }
        }
    }

    deinit {
        stop()
        // Remove workspace notification observers
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Public API

    /// Start intercepting Cmd+Tab
    func start() {
        guard config.appSwitcherEnabled else {
            logInfo("AppSwitcherService disabled in settings")
            return
        }

        guard eventTap == nil else {
            logDebug("AppSwitcherService already running")
            return
        }

        // Check accessibility permissions
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)

        if !trusted {
            logWarning("Accessibility permission not granted - app switcher will not work")
            return
        }

        setupEventTap()
    }

    /// Stop intercepting Cmd+Tab
    func stop() {
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }

        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
        }

        dismissSwitcher()
        logInfo("AppSwitcherService stopped")
    }

    /// Dismiss the switcher and switch to selected window
    func confirmSelection() {
        let windows = searchQuery.isEmpty ? allWindows : filteredWindows
        guard isActive, selectedIndex < windows.count else { return }

        let selectedWindow = windows[selectedIndex]
        dismissSwitcher()

        // Focus the selected window via yabai
        focusWindow(selectedWindow)
    }

    /// Dismiss the switcher without switching
    func cancel() {
        dismissSwitcher()
    }

    // MARK: - Event Tap Setup

    private func setupEventTap() {
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) |
                                      (1 << CGEventType.keyUp.rawValue) |
                                      (1 << CGEventType.flagsChanged.rawValue) |
                                      (1 << CGEventType.leftMouseDown.rawValue) |
                                      (1 << CGEventType.scrollWheel.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let service = Unmanaged<AppSwitcherService>.fromOpaque(refcon).takeUnretainedValue()
                return service.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logError("Failed to create event tap - accessibility permission may be required")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        logInfo("AppSwitcherService event tap enabled")
    }

    // MARK: - Event Handling

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let cmdPressed = flags.contains(.maskCommand)
        let tabKeyCode: Int64 = 48

        switch type {
        case .flagsChanged:
            if !cmdPressed {
                // Cmd released - reset scroll accumulator
                cmdScrollAccumulator = 0

                if isActive {
                    DispatchQueue.main.async { [weak self] in
                        self?.confirmSelection()
                    }
                    return nil
                }
            }

        case .keyDown:
            if cmdPressed && keyCode == tabKeyCode {
                let shiftPressed = flags.contains(.maskShift)
                DispatchQueue.main.async { [weak self] in
                    if self?.isActive == true {
                        self?.cycleSelection(reverse: shiftPressed)
                    } else {
                        self?.activateSwitcher(reverse: shiftPressed)
                    }
                }
                return nil
            }

            if isActive && keyCode == 53 {  // Escape
                DispatchQueue.main.async { [weak self] in
                    self?.cancel()
                }
                return nil
            }

            if isActive {
                if keyCode == 123 {  // Left arrow
                    DispatchQueue.main.async { [weak self] in
                        self?.cycleSelection(reverse: true)
                    }
                    return nil
                } else if keyCode == 124 {  // Right arrow
                    DispatchQueue.main.async { [weak self] in
                        self?.cycleSelection(reverse: false)
                    }
                    return nil
                }
            }

            if isActive && cmdPressed {
                if let num = keyCodeToNumber(keyCode), num >= 1 && num <= 9 {
                    let index = num - 1
                    let windows = searchQuery.isEmpty ? allWindows : filteredWindows
                    if index < windows.count {
                        DispatchQueue.main.async { [weak self] in
                            self?.selectedIndex = index
                            self?.updateWindow()
                        }
                    }
                    return nil
                }
            }

            // Handle backspace for search
            if isActive && keyCode == 51 {  // Backspace
                DispatchQueue.main.async { [weak self] in
                    self?.handleBackspace()
                }
                return nil
            }

            // Handle character input for search (when switcher is active and Cmd is held)
            if isActive && cmdPressed {
                if let char = keyCodeToChar(keyCode) {
                    DispatchQueue.main.async { [weak self] in
                        self?.appendSearchChar(char)
                    }
                    return nil
                }
            }

        case .keyUp:
            if isActive && keyCode == tabKeyCode {
                return nil
            }

        case .leftMouseDown:
            if isActive {
                // Check if click is outside the switcher window
                let mouseLocation = event.location
                if let windowFrame = windowController?.windowFrame {
                    if !windowFrame.contains(mouseLocation) {
                        // Click outside - dismiss switcher
                        DispatchQueue.main.async { [weak self] in
                            self?.cancel()
                        }
                        return nil  // Consume the click
                    }
                }
                // Click inside - let it through for SwiftUI to handle
            }

        case .scrollWheel:
            // Cmd+scroll to activate/cycle the switcher (opt-in feature)
            if cmdPressed && config.appSwitcherCmdScrollEnabled {
                // Get scroll delta (use scrollingDeltaY for trackpad precision)
                let deltaY = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)

                // Accumulate scroll
                cmdScrollAccumulator += CGFloat(deltaY)

                let threshold: CGFloat = config.scrollActionThreshold
                let steps = Int(cmdScrollAccumulator / threshold)

                if steps != 0 {
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        if self.isActive {
                            // Already active - cycle selection
                            self.cycleSelection(reverse: steps < 0)
                        } else {
                            // Not active - activate and optionally cycle
                            self.activateSwitcher(reverse: steps < 0)
                        }
                    }

                    // Reset accumulator (notched behavior)
                    cmdScrollAccumulator = 0
                    return nil  // Consume the scroll event
                }

                return nil  // Consume scroll while Cmd is held to prevent zoom
            } else if !cmdPressed {
                // Cmd released - reset accumulator
                cmdScrollAccumulator = 0
            }

        default:
            break
        }

        return Unmanaged.passRetained(event)
    }

    private func keyCodeToNumber(_ keyCode: Int64) -> Int? {
        switch keyCode {
        case 18: return 1
        case 19: return 2
        case 20: return 3
        case 21: return 4
        case 23: return 5
        case 22: return 6
        case 26: return 7
        case 28: return 8
        case 25: return 9
        default: return nil
        }
    }

    private func keyCodeToChar(_ keyCode: Int64) -> Character? {
        // Map key codes to characters for search
        let keyMap: [Int64: Character] = [
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
            8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
            16: "y", 17: "t", 31: "o", 32: "u", 34: "i", 35: "p", 37: "l",
            38: "j", 40: "k", 45: "n", 46: "m"
        ]
        return keyMap[keyCode]
    }

    // MARK: - Search Methods

    private func appendSearchChar(_ char: Character) {
        searchQuery.append(char)
        applySearchFilter()
    }

    private func handleBackspace() {
        guard !searchQuery.isEmpty else { return }
        searchQuery.removeLast()
        applySearchFilter()
    }

    private func applySearchFilter() {
        if searchQuery.isEmpty {
            filteredWindows = allWindows
        } else {
            let query = searchQuery.lowercased()
            filteredWindows = allWindows.filter { window in
                window.appName.lowercased().contains(query) ||
                window.title.lowercased().contains(query)
            }
        }

        // Reset selection to first item if current selection is out of bounds
        if selectedIndex >= filteredWindows.count {
            selectedIndex = 0
        }

        updateWindowWithFilter()
    }

    private func updateWindowWithFilter() {
        // Rebuild space groups based on filtered windows
        var filteredGroups: [SpaceGroup] = []

        for group in spaceGroups {
            let groupWindows = group.windows.filter { window in
                filteredWindows.contains(where: { $0.id == window.id })
            }
            if !groupWindows.isEmpty {
                filteredGroups.append(SpaceGroup(
                    spaceIndex: group.spaceIndex,
                    spaceLabel: group.spaceLabel,
                    isFocused: group.isFocused,
                    windows: groupWindows
                ))
            }
        }

        windowController?.show(
            spaceGroups: filteredGroups,
            allWindows: filteredWindows,
            selectedIndex: selectedIndex,
            searchQuery: searchQuery
        )
    }

    // MARK: - Switcher Logic

    private func activateSwitcher(reverse: Bool) {
        logDebug("Activating app switcher")

        // Fetch windows from yabai asynchronously
        Task {
            await refreshWindowsFromYabai()

            await MainActor.run {
                guard !self.allWindows.isEmpty else {
                    logDebug("No windows to switch between")
                    return
                }

                self.isActive = true
                self.searchQuery = ""
                self.filteredWindows = self.allWindows

                // Start with index 1 (next window) or wrap to last if reverse
                if reverse {
                    self.selectedIndex = self.allWindows.count - 1
                } else {
                    self.selectedIndex = min(1, self.allWindows.count - 1)
                }

                self.showWindow()
            }
        }
    }

    private func cycleSelection(reverse: Bool) {
        let windows = searchQuery.isEmpty ? allWindows : filteredWindows
        guard !windows.isEmpty else { return }

        if reverse {
            selectedIndex = (selectedIndex - 1 + windows.count) % windows.count
        } else {
            selectedIndex = (selectedIndex + 1) % windows.count
        }

        updateWindow()
    }

    private func dismissSwitcher() {
        isActive = false
        selectedIndex = 0
        searchQuery = ""
        filteredWindows = []
        hideWindow()
    }

    // MARK: - Window Management

    private func showWindow() {
        if windowController == nil {
            windowController = AppSwitcherWindowController()
            // Hover updates both visual and service index so scroll/keyboard continues from there
            windowController?.onSelectionChanged = { [weak self] index in
                self?.selectedIndex = index
                self?.windowController?.update(selectedIndex: index)
            }
            // Click confirms and switches to the window
            windowController?.onSelectionConfirmed = { [weak self] index in
                self?.selectedIndex = index
                self?.confirmSelection()
            }
            // Two-finger scroll cycles through windows
            windowController?.onScrollCycle = { [weak self] direction in
                // direction: -1 for previous (scroll up), +1 for next (scroll down)
                self?.cycleSelection(reverse: direction < 0)
            }
        }
        windowController?.show(spaceGroups: spaceGroups, allWindows: allWindows, selectedIndex: selectedIndex, searchQuery: searchQuery)
    }

    private func updateWindow() {
        windowController?.update(selectedIndex: selectedIndex)
    }

    private func hideWindow() {
        windowController?.hide()
    }

    // MARK: - Yabai Data

    private func refreshWindowsFromYabai() async {
        do {
            // Query spaces and windows from yabai
            async let spacesJson = yabaiCommand.run(["-m", "query", "--spaces"])
            async let windowsJson = yabaiCommand.run(["-m", "query", "--windows"])

            let (spacesData, windowsData) = try await (spacesJson, windowsJson)

            let spaces = try JSONDecoder().decode([Space].self, from: Data(spacesData.utf8))
            let windows = try JSONDecoder().decode([WindowInfo].self, from: Data(windowsData.utf8))

            // Filter to only real windows, excluding:
            // - Non-AXWindow roles (popups/panels)
            // - System dialogs (AXSystemDialog subrole) - often stale/invisible windows
            // - Configured excluded apps
            // - Minimized/hidden windows based on settings
            let excludedApps = config.excludedApps
            let showMinimized = config.appSwitcherShowMinimized
            let showHidden = config.appSwitcherShowHidden

            let realWindows = windows.filter { window in
                // Basic filtering
                // Note: minimized windows report AXDialog subrole instead of AXStandardWindow
                guard window.role == "AXWindow" &&
                      (window.subrole == "AXStandardWindow" || window.isMinimized) &&
                      !excludedApps.contains(window.app) else {
                    return false
                }

                // Filter minimized windows based on setting
                if window.isMinimized && !showMinimized {
                    return false
                }

                // Filter hidden windows based on setting
                if window.isHidden && !showHidden {
                    return false
                }

                return true
            }

            // Use cached icons - much faster than fetching on every activation
            // Refresh cache in background for any new apps
            refreshIconCache()

            // Group windows by space, starting with focused space
            var groups: [SpaceGroup] = []
            var flatWindows: [SwitcherWindow] = []

            // Sort spaces: focused first, then by index
            let sortedSpaces = spaces.sorted { space1, space2 in
                if space1.focused { return true }
                if space2.focused { return false }
                return space1.index < space2.index
            }

            for space in sortedSpaces {
                let spaceWindows = realWindows
                    .filter { $0.space == space.index }
                    .sorted { w1, w2 in
                        // Focused window first, then by title
                        if w1.hasFocus { return true }
                        if w2.hasFocus { return false }
                        return w1.title < w2.title
                    }

                guard !spaceWindows.isEmpty else { continue }

                let switcherWindows: [SwitcherWindow] = spaceWindows.map { [weak self] window in
                    // Use cached icon for faster lookup
                    let icon = self?.appIconCache[window.app]

                    return SwitcherWindow(
                        id: window.id,
                        title: window.title,
                        appName: window.app,
                        spaceIndex: window.space,
                        icon: icon,
                        hasFocus: window.hasFocus,
                        isMinimized: window.isMinimized,
                        isHidden: window.isHidden
                    )
                }

                groups.append(SpaceGroup(
                    spaceIndex: space.index,
                    spaceLabel: space.label,
                    isFocused: space.focused,
                    windows: switcherWindows
                ))

                flatWindows.append(contentsOf: switcherWindows)
            }

            self.spaceGroups = groups
            self.allWindows = flatWindows

        } catch {
            logError("Failed to query yabai: \(error)")

            // Fallback to running apps if yabai fails
            await fallbackToRunningApps()
        }
    }

    private func fallbackToRunningApps() async {
        let runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .sorted { app1, app2 in
                if app1.isActive { return true }
                if app2.isActive { return false }
                return app1.processIdentifier < app2.processIdentifier
            }

        let windows: [SwitcherWindow] = runningApps.compactMap { app -> SwitcherWindow? in
            guard let name = app.localizedName else { return nil }
            return SwitcherWindow(
                id: Int(app.processIdentifier),
                title: name,
                appName: name,
                spaceIndex: 1,
                icon: app.icon,
                hasFocus: app.isActive,
                isMinimized: false,
                isHidden: app.isHidden
            )
        }

        self.spaceGroups = [SpaceGroup(spaceIndex: 1, spaceLabel: nil, isFocused: true, windows: windows)]
        self.allWindows = windows
    }

    private func focusWindow(_ window: SwitcherWindow) {
        // Use yabai to focus the specific window
        Task {
            do {
                // First switch to the window's space if needed
                _ = try await yabaiCommand.run(["-m", "space", "--focus", "\(window.spaceIndex)"])

                // If window is minimized, deminimize it first
                if window.isMinimized {
                    _ = try await yabaiCommand.run(["-m", "window", "--deminimize", "\(window.id)"])
                }

                // Then focus the specific window
                _ = try await yabaiCommand.run(["-m", "window", "--focus", "\(window.id)"])
            } catch {
                logError("Failed to focus window \(window.id): \(error)")
            }
        }
    }
}

// MARK: - Models

struct SpaceGroup: Identifiable {
    var id: Int { spaceIndex }
    let spaceIndex: Int
    let spaceLabel: String?
    let isFocused: Bool
    let windows: [SwitcherWindow]
}

struct SwitcherWindow: Identifiable {
    let id: Int
    let title: String
    let appName: String
    let spaceIndex: Int
    let icon: NSImage?
    let hasFocus: Bool
    let isMinimized: Bool
    let isHidden: Bool
}
