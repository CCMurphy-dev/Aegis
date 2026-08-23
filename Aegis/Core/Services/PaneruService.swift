//
//  PaneruService.swift
//  Aegis
//
//  Core service for Paneru window manager integration.
//  Mirrors RiftService architecture: CLI execution, event subscription,
//  cached state with smart coalescing, and EventRouter publishing.
//
//  Differences from RiftService:
//  - Paneru snapshots are complete (inactive rows include full window lists),
//    so no merge cache is needed — each refresh replaces the cache wholesale.
//  - Window IDs are plain CGWindowIDs in JSON, no debug-string parsing.
//  - Windows have no frames; each row's `windows` array is already in strip
//    order, so array order is used directly (no x-position sort).
//

import Foundation
import AppKit


// MARK: - Paneru Command Actor

actor PaneruCommandActor {

    static let shared = PaneruCommandActor()

    let paneruPath: String?
    private var lastRun = Date.distantPast
    private let minInterval: TimeInterval = 0.05   // 50ms between commands (max 20/sec)
    private var activeProcessCount = 0
    private let maxConcurrentProcesses = 3

    init() {
        self.paneruPath = Self.findPaneru()
        if let path = paneruPath {
            logInfo("Found paneru at \(path)")
        } else {
            logError("paneru not found")
        }
    }

    nonisolated var isAvailable: Bool { paneruPath != nil }

    /// Check if the Paneru daemon is actually running (not just the binary installed)
    nonisolated static func isPaneruDaemonRunning() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-x", "paneru"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func findPaneru() -> String? {
        let candidates = [
            "/opt/homebrew/bin/paneru",
            "/usr/local/bin/paneru",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Fallback: `which paneru`
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["paneru"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                if !path.isEmpty && FileManager.default.isExecutableFile(atPath: path) {
                    return path
                }
            }
        } catch {}

        return nil
    }

    func run(_ args: [String]) async throws -> String {
        guard let path = paneruPath else {
            throw NSError(domain: "PaneruService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "paneru not found"])
        }

        guard Self.isPaneruDaemonRunning() else {
            throw NSError(domain: "PaneruService", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Paneru daemon not running"])
        }

        // Wait if too many processes are active
        while activeProcessCount >= maxConcurrentProcesses {
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }

        // Throttle: ensure minimum interval between starts
        let now = Date()
        let delta = now.timeIntervalSince(lastRun)
        if delta < minInterval {
            try await Task.sleep(nanoseconds: UInt64((minInterval - delta) * 1_000_000_000))
        }
        lastRun = Date()

        activeProcessCount += 1

        let result: String
        do {
            result = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let process = Process()
                        process.executableURL = URL(fileURLWithPath: path)
                        process.arguments = args

                        let pipe = Pipe()
                        process.standardOutput = pipe
                        process.standardError = pipe

                        try process.run()
                        process.waitUntilExit()

                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        let output = String(decoding: data, as: UTF8.self)
                        continuation.resume(returning: output)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } catch {
            activeProcessCount -= 1
            throw error
        }

        activeProcessCount -= 1
        return result
    }
}


// MARK: - Paneru Service

final class PaneruService {

    private let eventRouter: EventRouter
    private let command = PaneruCommandActor.shared

    // Cached state — only rows of the CURRENT native macOS Space are kept,
    // keyed by 1-based row number (paneru `number`)
    private var workspaces: [Int: PaneruVirtualWorkspace] = [:]
    private var windows: [Int: PaneruWindow] = [:]       // Keyed by windowId (CGWindowID)

    // Derived: windowId → row number
    private var windowToWorkspace: [Int: Int] = [:]

    // Active virtual row (1-based) and its native macOS Space
    private var activeWorkspaceIndex: Int = 1
    private var activeNativeWorkspaceId: Int = 0

    private let dataQueue = DispatchQueue(label: "com.aegis.paneru.data", attributes: .concurrent)

    // Event subscription process
    private var subscriptionProcess: Process?
    private var lineBuffer = ""

    // Coalescing gate (identical pattern to RiftService)
    private enum RefreshScope: Int, Comparable {
        case none = 0
        case windowsOnly = 1
        case workspacesAndWindows = 2
        case all = 3
        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }
    private var coalesceTimer: DispatchWorkItem?
    private var pendingScope: RefreshScope = .none
    private var lastRefreshTime: Date = .distantPast
    private let coalesceDelay: TimeInterval = 0.03     // 30ms coalesce window
    private let debounceInterval: TimeInterval = 0.1   // 100ms post-refresh debounce
    private var lastSubscriptionEventTime: Date = .distantPast

    // App icon cache
    private var appIconCache: [String: NSImage] = [:]
    private let appIconCacheLimit = 100

    // Bundle ID → PID cache (paneru JSON has no PID; resolved via NSWorkspace)
    private var pidCache: [String: pid_t] = [:]

    // MARK: - Init

    init(eventRouter: EventRouter) {
        self.eventRouter = eventRouter
        logInfo("PaneruService initializing")

        Task {
            await executeRefresh(scope: .all, source: "init")
        }

        startSubscription()
        setupWorkspaceFallback()
        logInfo("PaneruService ready")
    }

    deinit {
        stop()
    }

    func stop() {
        subscriptionProcess?.terminate()
        subscriptionProcess = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Event Subscription

    private func startSubscription() {
        guard let path = command.paneruPath else {
            logError("Cannot start Paneru event subscription: paneru not found")
            return
        }

        guard PaneruCommandActor.isPaneruDaemonRunning() else {
            logWarning("Paneru daemon not running, skipping subscription (will retry via fallback)")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["subscribe", "--json"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                self?.handleSubscriptionTerminated()
                return
            }
            let raw = String(decoding: data, as: UTF8.self)
            self?.processIncomingData(raw)
        }

        do {
            try process.run()
            self.subscriptionProcess = process
            logInfo("Paneru event subscription started")
        } catch {
            logError("Failed to start paneru subscribe: \(error)")
        }
    }

    private func processIncomingData(_ raw: String) {
        lineBuffer += raw
        while let newlineIndex = lineBuffer.firstIndex(of: "\n") {
            let line = String(lineBuffer[lineBuffer.startIndex..<newlineIndex])
                .trimmingCharacters(in: .whitespaces)
            lineBuffer = String(lineBuffer[lineBuffer.index(after: newlineIndex)...])
            if !line.isEmpty {
                handlePaneruEventLine(line)
            }
        }
    }

    private func handleSubscriptionTerminated() {
        logWarning("Paneru subscription process terminated, will retry if daemon is running")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard PaneruCommandActor.isPaneruDaemonRunning() else {
                logInfo("Paneru daemon not running, deferring subscription reconnect")
                return
            }
            self?.startSubscription()
        }
    }

    private func handlePaneruEventLine(_ line: String) {
        lastSubscriptionEventTime = Date()

        guard let data = line.data(using: .utf8),
              let event = try? JSONDecoder().decode(PaneruEvent.self, from: data) else {
            logDebug("Failed to decode paneru event: \(line.prefix(100))")
            return
        }

        switch event.event {
        case "virtual_workspace_changed":
            // Track which virtual row (and native Space) is now active
            if let active = event.active {
                dataQueue.sync(flags: .barrier) { [weak self] in
                    guard let self = self else { return }
                    self.activeWorkspaceIndex = active.virtualWorkspaceNumber
                    self.activeNativeWorkspaceId = active.nativeWorkspaceId
                }
            }
            scheduleRefresh(scope: .workspacesAndWindows, source: "sub:virtual_workspace_changed")

        case "windows_changed", "window_focused", "window_title_changed":
            scheduleRefresh(scope: .windowsOnly, source: "sub:\(event.event)")

        case "display_changed":
            scheduleRefresh(scope: .workspacesAndWindows, source: "sub:display_changed")

        default:
            scheduleRefresh(scope: .workspacesAndWindows, source: "sub:\(event.event)")
        }
    }

    // MARK: - Workspace Fallback

    private func setupWorkspaceFallback() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func activeSpaceChanged(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }
            guard Date().timeIntervalSince(self.lastSubscriptionEventTime) >= 0.5 else { return }
            self.scheduleRefresh(scope: .workspacesAndWindows, source: "activeSpaceChanged")
        }
    }

    @objc private func appChanged(_ notification: Notification) {
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           app.bundleIdentifier == Bundle.main.bundleIdentifier {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self else { return }
            guard Date().timeIntervalSince(self.lastSubscriptionEventTime) >= 0.5 else { return }
            self.scheduleRefresh(scope: .windowsOnly, source: "appChanged")
        }
    }

    // MARK: - Coalescing Refresh Gate

    private func scheduleRefresh(scope: RefreshScope, source: String = "unknown") {
        pendingScope = max(pendingScope, scope)
        coalesceTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let finalScope = self.pendingScope
            self.pendingScope = .none
            Task { await self.executeRefresh(scope: finalScope, source: source) }
        }
        coalesceTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + coalesceDelay, execute: work)
    }

    private func executeRefresh(scope: RefreshScope, source: String = "unknown") async {
        let now = Date()
        let timeSinceLast = now.timeIntervalSince(lastRefreshTime)
        if timeSinceLast < debounceInterval { return }
        lastRefreshTime = now

        switch scope {
        case .none:
            return
        case .windowsOnly, .workspacesAndWindows, .all:
            // Paneru windows are embedded in workspace snapshots — one query covers all scopes
            await refreshWorkspaces()
        }
    }

    // MARK: - Refresh Methods

    private func refreshWorkspaces() async {
        do {
            let json = try await command.run(["query", "state", "--json"])
            let state = try JSONDecoder().decode(PaneruState.self, from: Data(json.utf8))

            // Only show rows of the current native macOS Space (trailing empty rows are kept)
            let rows = state.virtualWorkspaces.filter {
                $0.nativeWorkspaceId == state.active.nativeWorkspaceId
            }

            // Check if workspaces changed
            let workspacesChanged = dataQueue.sync { [weak self] () -> Bool in
                guard let self = self else { return false }
                let oldIds = Set(self.workspaces.keys)
                let newIds = Set(rows.map { $0.number })
                if oldIds != newIds { return true }
                for row in rows {
                    if let old = self.workspaces[row.number], old.active != row.active {
                        return true
                    }
                }
                return false
            }

            // Check if windows changed
            let windowsChanged = dataQueue.sync { [weak self] () -> Bool in
                guard let self = self else { return false }
                var newWindows: [Int: PaneruWindow] = [:]
                for row in rows {
                    for window in row.windows {
                        newWindows[window.windowId] = window
                    }
                }
                let oldIds = Set(self.windows.keys)
                let newIds = Set(newWindows.keys)
                if oldIds != newIds { return true }
                for (id, window) in newWindows {
                    if let old = self.windows[id],
                       old.focused != window.focused || old.floating != window.floating {
                        return true
                    }
                }
                return false
            }

            // Write to cache (full replace — snapshots are complete)
            dataQueue.sync(flags: .barrier) { [weak self] in
                guard let self = self else { return }
                self.workspaces = Dictionary(uniqueKeysWithValues: rows.map { ($0.number, $0) })
                self.windows = [:]
                self.windowToWorkspace = [:]
                for row in rows {
                    for window in row.windows {
                        self.windows[window.windowId] = window
                        self.windowToWorkspace[window.windowId] = row.number
                    }
                }
                self.activeWorkspaceIndex = state.active.virtualWorkspaceNumber
                self.activeNativeWorkspaceId = state.active.nativeWorkspaceId
            }

            if workspacesChanged {
                DispatchQueue.main.async { [weak self] in
                    self?.eventRouter.publish(.spaceChanged, data: [:])
                }
            }
            if windowsChanged {
                DispatchQueue.main.async { [weak self] in
                    self?.eventRouter.publish(.windowsChanged, data: [:])
                }
            }
        } catch {
            logError("paneru state query failed: \(error)")
        }
    }

    // MARK: - Queries

    func getCurrentWorkspaces() -> [PaneruVirtualWorkspace] {
        dataQueue.sync {
            Array(workspaces.values).sorted { $0.number < $1.number }
        }
    }

    func getWorkspacesForDisplay(_ displayIndex: Int) -> [PaneruVirtualWorkspace] {
        return getCurrentWorkspaces()
    }

    func getAllWindows() -> [PaneruWindow] {
        dataQueue.sync { Array(windows.values) }
    }

    func getWindow(_ windowId: Int) -> PaneruWindow? {
        dataQueue.sync { windows[windowId] }
    }

    func getWindowsForWorkspace(_ wsIndex: Int) -> [PaneruWindow] {
        dataQueue.sync { workspaces[wsIndex]?.windows ?? [] }
    }

    func getWindowSpace(_ windowId: Int) -> Int? {
        dataQueue.sync { windowToWorkspace[windowId] }
    }

    func spaceHasFocusedWindow(_ spaceIndex: Int) -> Bool {
        let excludedApps = AegisConfig.shared.baseExcludedApps
        return dataQueue.sync {
            // Only the active row can truly have focus
            guard spaceIndex == activeWorkspaceIndex else { return false }

            for (windowId, window) in windows {
                if windowToWorkspace[windowId] == spaceIndex &&
                   window.focused &&
                   !(excludedApps.contains(window.bundleId) || excludedApps.contains(window.appName)) {
                    return true
                }
            }
            return false
        }
    }

    // MARK: - Focused Workspace

    func getFocusedWorkspaceIndex() -> Int {
        return dataQueue.sync { activeWorkspaceIndex }
    }

    func getFocusedWorkspace() -> PaneruVirtualWorkspace? {
        dataQueue.sync { workspaces[activeWorkspaceIndex] }
    }

    // MARK: - Window Icons

    func getWindowIconsForSpace(_ spaceIndex: Int) -> [WindowIcon] {
        let excludedApps = AegisConfig.shared.excludedApps
        return dataQueue.sync {
            guard let row = workspaces[spaceIndex] else { return [] }

            // The row's windows array is already in strip order
            let spaceWindows = row.windows.filter { window in
                !(excludedApps.contains(window.bundleId) || excludedApps.contains(window.appName))
            }

            return spaceWindows.map { window in
                WindowIcon(
                    id: window.windowId,
                    pid: resolvePid(for: window.bundleId),
                    title: window.title,
                    app: window.bundleId,
                    appName: window.appName,
                    icon: getAppIcon(for: window.bundleId),
                    frame: nil,
                    hasFocus: window.focused,
                    stackIndex: 0,
                    isMinimized: false,
                    isHidden: false
                )
            }
        }
    }

    func getAppIconsForSpace(_ spaceIndex: Int) -> [NSImage] {
        let excludedApps = AegisConfig.shared.excludedApps
        return dataQueue.sync {
            guard let row = workspaces[spaceIndex] else { return [] }
            let apps = Set(row.windows.compactMap { window -> String? in
                guard !excludedApps.contains(window.bundleId) else { return nil }
                return window.bundleId
            })
            return apps.compactMap { getAppIcon(for: $0) }
        }
    }

    func getAppIcon(for appName: String) -> NSImage? {
        if let cached = appIconCache[appName] {
            return cached
        }

        var icon: NSImage?

        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appName) ??
                        NSWorkspace.shared.urlsForApplications(withBundleIdentifier: appName).first {
            icon = NSWorkspace.shared.icon(forFile: appURL.path)
        }

        if icon == nil {
            let runningApps = NSWorkspace.shared.runningApplications
            if let app = runningApps.first(where: { $0.localizedName == appName || $0.bundleIdentifier == appName }) {
                icon = app.icon
            }
        }

        if let icon = icon {
            if appIconCache.count >= appIconCacheLimit {
                let keysToRemove = Array(appIconCache.keys.prefix(appIconCacheLimit / 5))
                keysToRemove.forEach { appIconCache.removeValue(forKey: $0) }
            }
            appIconCache[appName] = icon
        }

        return icon
    }

    /// Resolve PID from bundle ID — needed for AXObserver (window title tracking).
    /// Must be called inside dataQueue.
    private func resolvePid(for bundleId: String) -> pid_t {
        if let cached = pidCache[bundleId] {
            return cached
        }
        let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            .first?.processIdentifier ?? 0
        if pid != 0 {
            pidCache[bundleId] = pid
        }
        return pid
    }

    // MARK: - Commands

    func focusWorkspace(_ index: Int) {
        Task {
            try? await command.run(["send-cmd", "window", "virtualnum", "\(index)"])
        }
    }

    func focusWindow(_ windowId: Int) {
        // paneru has no focus-window-by-id command — use macOS Accessibility to focus by ID
        let pid = dataQueue.sync { () -> pid_t? in
            guard let window = windows[windowId] else { return nil }
            return resolvePid(for: window.bundleId)
        }
        guard let pid = pid, pid != 0 else { return }

        let app = NSRunningApplication(processIdentifier: pid)
        app?.activate()

        // Raise the specific window via AXUIElement
        let axApp = AXUIElementCreateApplication(pid)
        var windowList: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowList) == .success,
              let axWindows = windowList as? [AXUIElement] else { return }

        for axWindow in axWindows {
            var windowIdRef: CGWindowID = 0
            if _AXUIElementGetWindow(axWindow, &windowIdRef) == .success,
               windowIdRef == CGWindowID(windowId) {
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                break
            }
        }
    }

    func focusWindowByAppName(_ appName: String) -> Bool {
        let windowId = dataQueue.sync {
            windows.values.first { $0.appName == appName || $0.bundleId == appName }?.windowId
        }
        guard let windowId = windowId else { return false }
        focusWindow(windowId)
        return true
    }

    func moveWindow(_ windowId: Int, toWorkspace index: Int) {
        // paneru has no move-window-by-id command — focus the window first,
        // then virtualsendnum moves the focused window without following
        Task {
            self.focusWindow(windowId)
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms for focus to take effect
            try? await command.run(["send-cmd", "window", "virtualsendnum", "\(index)"])
        }
    }

    func moveWindowAndFocus(_ windowId: Int, toWorkspace index: Int) {
        // virtualmovenum moves the focused window and follows it
        Task {
            self.focusWindow(windowId)
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms for focus to take effect
            try? await command.run(["send-cmd", "window", "virtualmovenum", "\(index)"])
        }
    }

    func executePaneruCommand(args: [String], completion: @escaping (Result<String, Error>) -> Void) {
        Task {
            do {
                let output = try await command.run(args)
                completion(.success(output))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func getPaneruVersion() -> String {
        guard command.isAvailable else { return "Not found" }
        return "Installed"
    }
}
