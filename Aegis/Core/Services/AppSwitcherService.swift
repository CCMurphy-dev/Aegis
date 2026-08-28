import Foundation
import AppKit
import Carbon.HIToolbox
import Combine
import ScreenCaptureKit

/// The lifecycle state of the event tap used by the Cmd+Tab switcher.
enum AppSwitcherHealth: String, CaseIterable, Equatable {
    case disabled
    case permissionRequired
    case starting
    case running
    case recovering
    case failed

    var displayName: String {
        switch self {
        case .disabled: return "Disabled"
        case .permissionRequired: return "Accessibility required"
        case .starting: return "Starting"
        case .running: return "Active"
        case .recovering: return "Recovering"
        case .failed: return "Failed"
        }
    }
}

/// Permission state for the optional ScreenCaptureKit window previews.
/// This is deliberately separate from the Accessibility event-tap health: the
/// switcher remains useful with app icons when Screen Recording is unavailable.
enum AppSwitcherPreviewHealth: String, CaseIterable, Equatable {
    case disabled
    case permissionRequired
    case active
    case failed

    var displayName: String {
        switch self {
        case .disabled: return "Disabled"
        case .permissionRequired: return "Screen Recording required"
        case .active: return "Active"
        case .failed: return "Failed"
        }
    }
}

/// Isolates the macOS privacy API so permission behaviour is testable without
/// exercising ScreenCaptureKit or changing the test host's TCC state.
@MainActor
protocol AppSwitcherPreviewPermissionRuntime: AnyObject {
    func screenCaptureAccessIsGranted() -> Bool
    func requestScreenCaptureAccess()
}

/// Gates thumbnail capture. macOS may show a permission panel when a process
/// first requests Screen Recording; never repeat that request for every Cmd+Tab.
@MainActor
final class AppSwitcherPreviewPermissionCoordinator {
    private weak var runtime: AppSwitcherPreviewPermissionRuntime?
    private var requestedThisLaunch = false
    private var captureBlocked = false

    private(set) var health: AppSwitcherPreviewHealth = .disabled

    init(runtime: AppSwitcherPreviewPermissionRuntime) {
        self.runtime = runtime
    }

    /// Returns whether this activation may call ScreenCaptureKit.
    func prepareForCapture(enabled: Bool) -> Bool {
        guard enabled else {
            health = .disabled
            return false
        }
        guard !captureBlocked else { return false }
        guard let runtime else {
            health = .failed
            captureBlocked = true
            return false
        }
        guard runtime.screenCaptureAccessIsGranted() else {
            health = .permissionRequired
            if !requestedThisLaunch {
                requestedThisLaunch = true
                runtime.requestScreenCaptureAccess()
            }
            return false
        }
        health = .active
        return true
    }

    /// Rechecks a grant after the user returns from System Settings. This never
    /// asks macOS again: explicit permission is a user-controlled action.
    func recheck(enabled: Bool) {
        guard enabled else {
            health = .disabled
            return
        }
        guard !captureBlocked else { return }
        health = runtime?.screenCaptureAccessIsGranted() == true ? .active : .permissionRequired
    }

    /// Retry clears a previous capture error but does not create another prompt.
    func retry(enabled: Bool) {
        captureBlocked = false
        recheck(enabled: enabled)
    }

    func captureFailed() {
        captureBlocked = true
        health = .failed
    }
}

/// Small, side-effect-free part of the event-tap recovery policy.
/// Keeping the timings and transitions here makes the failure modes easy to
/// exercise without creating a global event tap in a test process.
struct AppSwitcherRecoveryPolicy {
    static let permissionPollInterval: TimeInterval = 2
    static let permissionPollDuration: TimeInterval = 60
    static let tapRecoveryDelays: [TimeInterval] = [1, 2, 4]
}

/// The small runtime surface needed by the recovery coordinator. The real
/// service supplies the CoreGraphics implementation; tests can supply a fake
/// runtime without creating an event tap or requesting Accessibility access.
@MainActor
protocol AppSwitcherRecoveryRuntime: AnyObject {
    var eventTapIsInstalled: Bool { get }
    var eventTapIsUsable: Bool { get }
    func accessibilityTrusted(prompt: Bool) -> Bool
    func createEventTap() -> Bool
    func reenableEventTap() -> Bool
    func teardownEventTap()
}

/// Owns the event-tap lifecycle policy and its bounded retry scheduling.
/// Keeping this separate from the switcher UI makes permission and recovery
/// transitions deterministic to test.
@MainActor
final class AppSwitcherRecoveryCoordinator {
    typealias Schedule = (_ delay: TimeInterval, _ action: @escaping () -> Void) -> DispatchWorkItem
    typealias Clock = () -> Date

    private weak var runtime: AppSwitcherRecoveryRuntime?
    private let schedule: Schedule
    private let clock: Clock
    private let onHealthChange: (AppSwitcherHealth) -> Void
    private var permissionPollTask: DispatchWorkItem?
    private var permissionPollDeadline: Date?
    private var recoveryTasks: [DispatchWorkItem] = []
    private var watchdogTask: DispatchWorkItem?
    private var hasPromptedForAccessibility = false

    static let watchdogInterval: TimeInterval = 5

    private(set) var health: AppSwitcherHealth = .disabled {
        didSet {
            guard oldValue != health else { return }
            onHealthChange(health)
        }
    }

    init(
        runtime: AppSwitcherRecoveryRuntime,
        schedule: Schedule? = nil,
        clock: @escaping Clock = Date.init,
        onHealthChange: @escaping (AppSwitcherHealth) -> Void = { _ in }
    ) {
        self.runtime = runtime
        self.schedule = schedule ?? Self.defaultSchedule
        self.clock = clock
        self.onHealthChange = onHealthChange
    }

    func start(enabled: Bool) {
        guard enabled else {
            stop()
            return
        }

        cancelPermissionPolling()
        guard let runtime else {
            health = .failed
            return
        }
        if runtime.eventTapIsUsable {
            health = .running
            beginWatchdog()
            return
        }
        if runtime.eventTapIsInstalled {
            // A stale Mach port must not block a fresh tap from being made.
            runtime.teardownEventTap()
        }

        health = .starting

        // Check silently first. A prompt on every launch causes macOS to
        // reopen its Accessibility UI for rebuilt local binaries, even when
        // the user has already granted access. Only make the one explicit
        // request allowed for this process after the silent check fails.
        var trusted = runtime.accessibilityTrusted(prompt: false)
        if !trusted, !hasPromptedForAccessibility {
            hasPromptedForAccessibility = true
            trusted = runtime.accessibilityTrusted(prompt: true)
        }
        guard trusted else {
            health = .permissionRequired
            beginPermissionPolling()
            return
        }

        cancelRecovery()
        if runtime.createEventTap() {
            health = .running
            beginWatchdog()
        } else {
            beginRecovery()
        }
    }

    func retry(enabled: Bool) {
        cancelPermissionPolling()
        cancelRecovery()
        start(enabled: enabled)
    }

    func stop() {
        cancelPermissionPolling()
        cancelRecovery()
        cancelWatchdog()
        runtime?.teardownEventTap()
        health = .disabled
    }

    func tapDisabled(enabled: Bool) {
        guard enabled else {
            stop()
            return
        }
        guard let runtime, runtime.eventTapIsInstalled, runtime.reenableEventTap() else {
            runtime?.teardownEventTap()
            beginRecovery()
            return
        }
        health = .running
        beginWatchdog()
    }

    private static let defaultSchedule: Schedule = { delay, action in
        let task = DispatchWorkItem(block: action)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
        return task
    }

    private func beginPermissionPolling() {
        guard permissionPollTask == nil else { return }
        permissionPollDeadline = clock().addingTimeInterval(AppSwitcherRecoveryPolicy.permissionPollDuration)
        schedulePermissionPoll()
    }

    private func schedulePermissionPoll() {
        permissionPollTask = schedule(AppSwitcherRecoveryPolicy.permissionPollInterval) { [weak self] in
            guard let self else { return }
            self.permissionPollTask = nil
            guard let deadline = self.permissionPollDeadline, self.clock() < deadline else {
                self.permissionPollDeadline = nil
                return
            }
            guard let runtime = self.runtime else { return }
            if runtime.accessibilityTrusted(prompt: false) {
                self.start(enabled: true)
            } else {
                self.schedulePermissionPoll()
            }
        }
    }

    private func cancelPermissionPolling() {
        permissionPollTask?.cancel()
        permissionPollTask = nil
        permissionPollDeadline = nil
    }

    private func beginRecovery() {
        guard recoveryTasks.isEmpty else { return }
        cancelWatchdog()
        health = .recovering
        for delay in AppSwitcherRecoveryPolicy.tapRecoveryDelays {
            let task = schedule(delay) { [weak self] in
                self?.attemptRecovery()
            }
            recoveryTasks.append(task)
        }
        let finalTask = schedule((AppSwitcherRecoveryPolicy.tapRecoveryDelays.last ?? 4) + 0.05) { [weak self] in
            if let self, self.runtime?.eventTapIsUsable == true {
                self.cancelRecovery()
                self.beginWatchdog()
                return
            }
            guard let self else { return }
            self.cancelRecovery()
            if self.health != .permissionRequired {
                self.health = .failed
            }
        }
        recoveryTasks.append(finalTask)
    }

    private func attemptRecovery() {
        guard let runtime else { return }
        guard !runtime.eventTapIsUsable else {
            health = .running
            beginWatchdog()
            return
        }
        if runtime.eventTapIsInstalled {
            runtime.teardownEventTap()
        }
        guard runtime.accessibilityTrusted(prompt: false) else {
            health = .permissionRequired
            beginPermissionPolling()
            return
        }
        guard runtime.createEventTap() else { return }
        cancelRecovery()
        health = .running
        beginWatchdog()
    }

    private func cancelRecovery() {
        recoveryTasks.forEach { $0.cancel() }
        recoveryTasks.removeAll()
    }

    private func beginWatchdog() {
        guard watchdogTask == nil else { return }
        scheduleWatchdog()
    }

    private func scheduleWatchdog() {
        watchdogTask = schedule(Self.watchdogInterval) { [weak self] in
            guard let self else { return }
            self.watchdogTask = nil
            guard self.health == .running else { return }
            guard let runtime = self.runtime, runtime.eventTapIsUsable else {
                self.runtime?.teardownEventTap()
                self.beginRecovery()
                return
            }
            self.scheduleWatchdog()
        }
    }

    private func cancelWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = nil
    }
}

/// Service that intercepts Cmd+Tab to provide a custom app switcher
/// Displays windows organized by space in a centered overlay
final class AppSwitcherService: ObservableObject {

    static let shared = AppSwitcherService()

    /// Cancellable for config observation
    private var configCancellable: AnyCancellable?
    private var previewConfigCancellable: AnyCancellable?

    // MARK: - State

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var isActive: Bool = false
    private var suppressedKeyUps: Set<Int64> = []

    /// Current event-tap health, exposed to the General settings tab.
    @Published private(set) var health: AppSwitcherHealth = .disabled

    /// Current Screen Recording health for optional window previews.
    @Published private(set) var previewHealth: AppSwitcherPreviewHealth = .disabled

    /// The switcher must use icons until both the preference and Screen
    /// Recording permission are active.
    var showingWindowPreviews: Bool {
        config.appSwitcherShowPreviews && previewHealth == .active
    }

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

    /// Whether command mode is active (query starts with ":")
    var isCommandMode: Bool { searchQuery.hasPrefix(":") }

    /// Command query without the ":" prefix
    private var commandQuery: String {
        isCommandMode ? String(searchQuery.dropFirst()) : ""
    }

    /// Filtered commands for command palette mode
    private(set) var filteredCommands: [PaletteCommand] = []

    /// All available commands (rebuilt each activation)
    private var allCommands: [PaletteCommand] = []

    /// Command registry
    private var commandRegistry: CommandRegistry?

    /// The overlay window controller
    private var windowController: AppSwitcherWindowController?

    private let yabaiCommand = YabaiCommandActor.shared
    private let config = AegisConfig.shared

    /// Window manager reference for WM-agnostic window queries
    private var windowManager: WindowManagerProtocol?

    /// Set the window manager (called from AppDelegate after both are initialized)
    func setWindowManager(_ wm: WindowManagerProtocol) {
        self.windowManager = wm
        self.commandRegistry = CommandRegistry(windowManager: wm)
    }

    /// Scroll accumulator for Cmd+scroll activation
    private var cmdScrollAccumulator: CGFloat = 0

    /// Cached app icons by name - persists across activations
    private var appIconCache: [String: NSImage] = [:]

    /// Whether the icon cache needs refreshing (set true when apps change)
    private var iconCacheNeedsRefresh: Bool = true

    // Event-tap recovery is isolated behind an injectable coordinator.
    private lazy var recoveryCoordinator = AppSwitcherRecoveryCoordinator(
        runtime: self,
        onHealthChange: { [weak self] health in self?.health = health }
    )

    private lazy var previewPermissionCoordinator = AppSwitcherPreviewPermissionCoordinator(runtime: self)

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

        // Observe config changes to start/stop service dynamically
        configCancellable = config.$appSwitcherEnabled
            .dropFirst() // Skip initial value
            .receive(on: DispatchQueue.main) // Event tap must be created on main thread
            .sink { [weak self] enabled in
                logInfo("AppSwitcherService config changed: enabled = \(enabled)")
                if enabled {
                    self?.start()
                } else {
                    self?.stop()
                }
            }

        previewConfigCancellable = config.$appSwitcherShowPreviews
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                self.previewPermissionCoordinator.recheck(enabled: enabled)
                self.previewHealth = self.previewPermissionCoordinator.health
            }

        previewPermissionCoordinator.recheck(enabled: config.appSwitcherShowPreviews)
        previewHealth = previewPermissionCoordinator.health

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
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
                // Replace entire cache instead of merging to prevent unbounded growth
                self?.appIconCache = newCache
                self?.isRefreshingIconCache = false
            }
        }
    }

    deinit {
        stop()
        // Remove workspace notification observers
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public API

    /// Start intercepting Cmd+Tab
    func start() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.start() }
            return
        }

        recoveryCoordinator.start(enabled: config.appSwitcherEnabled)
    }

    /// Retry after the user grants Accessibility or presses Retry in Settings.
    func retry() {
        recoveryCoordinator.retry(enabled: config.appSwitcherEnabled)
    }

    /// Retry Screen Recording after the user returns from System Settings.
    /// This only rechecks the grant, so it cannot create a repeat prompt.
    func retryPreviewPermission() {
        previewPermissionCoordinator.retry(enabled: config.appSwitcherShowPreviews)
        previewHealth = previewPermissionCoordinator.health
    }

    /// Opens the narrow Accessibility preference pane used by the status row.
    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Opens the narrow Screen Recording preference pane used by preview status.
    func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func applicationDidBecomeActive() {
        guard config.appSwitcherEnabled else { return }
        // Activation is a useful, low-cost point to recover after the user
        // returns from System Settings or macOS re-enables the event tap.
        retry()
        previewPermissionCoordinator.recheck(enabled: config.appSwitcherShowPreviews)
        previewHealth = previewPermissionCoordinator.health
    }

    /// Stop intercepting Cmd+Tab
    func stop() {
        recoveryCoordinator.stop()

        dismissSwitcher()
        health = .disabled
        logInfo("AppSwitcherService stopped")
    }

    /// Dismiss the switcher and switch to selected window (or execute command)
    func confirmSelection() {
        guard isActive else { return }

        if isCommandMode {
            guard selectedIndex < filteredCommands.count else { return }
            let command = filteredCommands[selectedIndex]
            dismissSwitcher()
            command.action()
            return
        }

        let windows = searchQuery.isEmpty ? allWindows : filteredWindows
        guard selectedIndex < windows.count else { return }

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

    @discardableResult
    private func setupEventTap() -> Bool {
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
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CGEvent.tapEnable(tap: tap, enable: false)
            logError("Failed to create event tap run-loop source")
            return false
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        logInfo("AppSwitcherService event tap enabled")
        return true
    }

    // MARK: - Event Handling

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            recoveryCoordinator.tapDisabled(enabled: config.appSwitcherEnabled)
            return Unmanaged.passRetained(event)
        }

        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let cmdPressed = flags.contains(.maskCommand)

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
            if let reverse = AppSwitcherShortcutMatcher.reverseDirection(for: keyCode, flags: flags) {
                suppressedKeyUps.insert(keyCode)
                DispatchQueue.main.async { [weak self] in
                    if self?.isActive == true {
                        self?.cycleSelection(reverse: reverse)
                    } else {
                        self?.activateSwitcher(reverse: reverse)
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
                    let count = isCommandMode ? filteredCommands.count : (searchQuery.isEmpty ? allWindows : filteredWindows).count
                    if index < count {
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
                let shiftPressed = flags.contains(.maskShift)
                if let char = keyCodeToChar(keyCode, shift: shiftPressed) {
                    DispatchQueue.main.async { [weak self] in
                        self?.appendSearchChar(char)
                    }
                    return nil
                }
            }

        case .keyUp:
            if suppressedKeyUps.remove(keyCode) != nil {
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

    private func keyCodeToChar(_ keyCode: Int64, shift: Bool = false) -> Character? {
        // Shifted characters first
        if shift {
            switch keyCode {
            case 41: return ":"   // Shift+; = :
            case 27: return "-"   // Shift+- (just pass through)
            default: break
            }
        }
        // Map key codes to characters for search
        let keyMap: [Int64: Character] = [
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
            8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
            16: "y", 17: "t", 31: "o", 32: "u", 34: "i", 35: "p", 37: "l",
            38: "j", 40: "k", 45: "n", 46: "m",
            41: ";", 43: ",", 44: "/", 47: ".", 49: " ", 27: "-"
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
        if isCommandMode {
            // Command mode — filter commands instead of windows
            let registry = commandRegistry ?? CommandRegistry(windowManager: windowManager)
            if allCommands.isEmpty {
                // Set focused window context for move-to-space commands
                let focusedWindow = allWindows.first(where: { $0.hasFocus })
                registry.focusedWindowId = focusedWindow?.id
                allCommands = registry.allCommands()
            }
            filteredCommands = registry.filter(allCommands, query: commandQuery)

            if selectedIndex >= filteredCommands.count {
                selectedIndex = 0
            }

            updateWindowWithFilter()
            return
        }

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
        if isCommandMode {
            windowController?.showCommands(
                commands: filteredCommands,
                selectedIndex: selectedIndex,
                searchQuery: searchQuery
            )
            return
        }

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

        // Fetch windows from window manager
        Task {
            if let wm = windowManager, wm.name != "Yabai" {
                await refreshWindowsFromWM(wm)
            } else {
                await refreshWindowsFromYabai()
            }

            // Capture window thumbnails if preview mode is enabled
            await captureWindowThumbnails()

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
        let count = isCommandMode ? filteredCommands.count : (searchQuery.isEmpty ? allWindows : filteredWindows).count
        guard count > 0 else { return }

        if reverse {
            selectedIndex = (selectedIndex - 1 + count) % count
        } else {
            selectedIndex = (selectedIndex + 1) % count
        }

        updateWindow()
    }

    private func dismissSwitcher() {
        isActive = false
        selectedIndex = 0
        searchQuery = ""
        filteredWindows = []
        filteredCommands = []
        allCommands = []
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

    // MARK: - WM-agnostic Data

    private func refreshWindowsFromWM(_ wm: WindowManagerProtocol) async {
        let excludedApps = config.excludedApps
        let showMinimized = config.appSwitcherShowMinimized
        let showHidden = config.appSwitcherShowHidden

        let spaces = wm.getCurrentSpaces()
        let allWMWindows = wm.getAllWindows()

        let realWindows = allWMWindows.filter { window in
            guard !excludedApps.contains(window.app) else { return false }
            if window.isMinimized && !showMinimized { return false }
            if window.isHidden && !showHidden { return false }
            guard window.isVisible else { return false }
            return true
        }

        refreshIconCache()

        var groups: [SpaceGroup] = []
        var flatWindows: [SwitcherWindow] = []

        let sortedSpaces = spaces.sorted { s1, s2 in
            if s1.isFocused { return true }
            if s2.isFocused { return false }
            return s1.index < s2.index
        }

        for space in sortedSpaces {
            let spaceWindows = realWindows
                .filter { $0.space == space.index }
                .sorted { w1, w2 in
                    if w1.hasFocus { return true }
                    if w2.hasFocus { return false }
                    return w1.title < w2.title
                }

            guard !spaceWindows.isEmpty else { continue }

            let switcherWindows: [SwitcherWindow] = spaceWindows.map { [weak self] window in
                let icon = self?.appIconCache[window.app] ?? self?.appIconCache[window.appName]
                    ?? wm.getAppIcon(for: window.app)

                return SwitcherWindow(
                    id: window.id,
                    title: window.title,
                    appName: window.appName,
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
                isFocused: space.isFocused,
                windows: switcherWindows
            ))

            flatWindows.append(contentsOf: switcherWindows)
        }

        self.spaceGroups = groups
        self.allWindows = flatWindows
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
        if let wm = windowManager, wm.name != "Yabai" {
            // Use WM protocol for non-yabai window managers
            wm.focusSpace(window.spaceIndex)
            wm.focusWindow(window.id)
        } else {
            // Use yabai directly for yabai (supports deminimize)
            Task {
                do {
                    _ = try await yabaiCommand.run(["-m", "space", "--focus", "\(window.spaceIndex)"])
                    if window.isMinimized {
                        _ = try await yabaiCommand.run(["-m", "window", "--deminimize", "\(window.id)"])
                    }
                    _ = try await yabaiCommand.run(["-m", "window", "--focus", "\(window.id)"])
                } catch {
                    logError("Failed to focus window \(window.id): \(error)")
                }
            }
        }
    }

    // MARK: - Window Thumbnail Capture

    /// Capture thumbnails for all windows via ScreenCaptureKit
    private func captureWindowThumbnails() async {
        let mayCapture = previewPermissionCoordinator.prepareForCapture(enabled: config.appSwitcherShowPreviews)
        previewHealth = previewPermissionCoordinator.health
        guard mayCapture else { return }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)

            // Build a lookup of SCWindow by windowID
            var scWindowMap: [CGWindowID: SCWindow] = [:]
            for scWindow in content.windows {
                scWindowMap[scWindow.windowID] = scWindow
            }

            // Capture thumbnails concurrently
            let captureCandidates = self.allWindows.filter { window in
                !window.isMinimized && !window.isHidden && scWindowMap[CGWindowID(window.id)] != nil
            }

            await withTaskGroup(of: (Int, NSImage?).self) { group in
                for window in captureCandidates {
                    // Skip minimized/hidden — no valid capture available
                    guard let scWindow = scWindowMap[CGWindowID(window.id)] else { continue }

                    group.addTask {
                        do {
                            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
                            let config = SCStreamConfiguration()
                            // Thumbnail size — fit within 160x100
                            let aspectRatio = CGFloat(scWindow.frame.width) / max(CGFloat(scWindow.frame.height), 1)
                            if aspectRatio > 1.6 {
                                config.width = 160
                                config.height = Int(160.0 / aspectRatio)
                            } else {
                                config.height = 100
                                config.width = Int(100.0 * aspectRatio)
                            }
                            config.showsCursor = false
                            config.captureResolution = .best

                            let cgImage = try await SCScreenshotManager.captureImage(
                                contentFilter: filter,
                                configuration: config
                            )
                            let nsImage = NSImage(
                                cgImage: cgImage,
                                size: NSSize(width: config.width, height: config.height)
                            )
                            return (window.id, nsImage)
                        } catch {
                            return (window.id, nil)
                        }
                    }
                }

                // Apply thumbnails to windows
                var thumbnails: [Int: NSImage] = [:]
                for await (windowId, image) in group {
                    if let image { thumbnails[windowId] = image }
                }

                // A successful permission preflight followed by no thumbnails
                // means ScreenCaptureKit itself failed. Use icons on future
                // activations until the user explicitly retries.
                if !captureCandidates.isEmpty && thumbnails.isEmpty {
                    self.previewHealth = self.previewPermissionCoordinator.health
                }

                // Update allWindows and spaceGroups with thumbnails
                for i in self.allWindows.indices {
                    self.allWindows[i].thumbnail = thumbnails[self.allWindows[i].id]
                }
                for gi in self.spaceGroups.indices {
                    for wi in self.spaceGroups[gi].windows.indices {
                        let wid = self.spaceGroups[gi].windows[wi].id
                        self.spaceGroups[gi].windows[wi].thumbnail = thumbnails[wid]
                    }
                }
            }
        } catch {
            logDebug("Failed to capture window thumbnails: \(error)")
            previewHealth = previewPermissionCoordinator.health
        }
    }
}

extension AppSwitcherService: AppSwitcherPreviewPermissionRuntime {
    func screenCaptureAccessIsGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    func requestScreenCaptureAccess() {
        CGRequestScreenCaptureAccess()
    }
}

extension AppSwitcherService: AppSwitcherRecoveryRuntime {
    var eventTapIsInstalled: Bool {
        eventTap != nil
    }

    var eventTapIsUsable: Bool {
        guard let eventTap, runLoopSource != nil else { return false }
        return CGEvent.tapIsEnabled(tap: eventTap)
    }

    func accessibilityTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func createEventTap() -> Bool {
        setupEventTap()
    }

    func reenableEventTap() -> Bool {
        guard let eventTap, runLoopSource != nil else { return false }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        return eventTapIsUsable
    }

    func teardownEventTap() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
        }
    }
}

// MARK: - Models

struct SpaceGroup: Identifiable {
    var id: Int { spaceIndex }
    let spaceIndex: Int
    let spaceLabel: String?
    let isFocused: Bool
    var windows: [SwitcherWindow]
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
    var thumbnail: NSImage?
}
