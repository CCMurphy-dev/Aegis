//
//  AeroSpaceService.swift
//  Aegis
//
//  Manages AeroSpace window manager integration.
//  AeroSpace uses string-named virtual workspaces (e.g. "1", "A", "B").
//  Workspaces 1 through highest-in-use are always shown (stable identity).
//  Event-driven: FIFO pipe + NSWorkspace notifications + post-command refresh.
//

import Foundation
import AppKit

// MARK: - CLI Command Actor

actor AeroSpaceCommandActor {
    static let shared = AeroSpaceCommandActor()

    let aerospacePath: String?

    init() {
        let candidates = ["/opt/homebrew/bin/aerospace", "/usr/local/bin/aerospace"]
        aerospacePath = candidates.first { FileManager.default.fileExists(atPath: $0) }
        if aerospacePath == nil {
            logError("aerospace CLI not found")
        }
    }

    nonisolated var isAvailable: Bool { aerospacePath != nil }

    /// Check if AeroSpace.app is running
    nonisolated static func isAeroSpaceRunning() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-x", "AeroSpace"]
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

    func run(_ args: [String]) async throws -> String {
        guard let path = aerospacePath else {
            throw NSError(domain: "AeroSpace", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "aerospace CLI not found"])
        }

        guard Self.isAeroSpaceRunning() else {
            throw NSError(domain: "AeroSpace", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "AeroSpace.app not running"])
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args

        let stdout = Pipe()
        let stderr = Pipe()
        task.standardOutput = stdout
        task.standardError = stderr

        try task.run()
        task.waitUntilExit()

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

        if task.terminationStatus != 0 {
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(decoding: errData, as: UTF8.self)
            throw NSError(domain: "AeroSpace", code: Int(task.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: errStr.isEmpty ? output : errStr])
        }

        return output
    }
}


// MARK: - AeroSpace Service

final class AeroSpaceService {

    private let eventRouter: EventRouter
    private let command = AeroSpaceCommandActor.shared

    // Cached state
    // Visible workspaces: only those with windows + focused
    // Key: workspace name (e.g. "1", "A"), Value: list of window IDs
    private var workspaceWindows: [String: [ASWindow]] = [:]
    private var visibleWorkspaces: [String] = []           // Ordered workspace names to display
    private var focusedWorkspace: String = "1"
    private var focusedWindowId: Int? = nil
    private var allWindows: [Int: ASWindow] = [:]          // windowId → ASWindow
    private var windowSnapshotReady = false
    private var windowToWorkspace: [Int: String] = [:]     // windowId → workspace name
    private var monitors: [ASMonitor] = []

    // Workspace name → 1-based display index mapping
    private var workspaceIndexMap: [String: Int] = [:]

    // Window order cache
    private var windowOrderCache: [String: [Int]] = [:]

    // App icon cache
    private var appIconCache: [String: NSImage] = [:]
    private let appIconCacheLimit = 100

    private let dataQueue = DispatchQueue(label: "com.aegis.aerospace.data", attributes: .concurrent)

    // FIFO pipe
    private var pipeSource: DispatchSourceRead?
    private var pipeFD: Int32 = -1
    private let pipeQueue = DispatchQueue(label: "com.aegis.aerospace.pipe")
    private var lastFIFOEventTime: Date = .distantPast

    private lazy var pipePath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/aegis/aerospace.pipe"
    }()

    // No polling — FIFO pipe + NSWorkspace notifications are sufficient

    // Coalescing
    private var coalesceTimer: DispatchWorkItem?
    private let coalesceDelay: TimeInterval = 0.03         // 30ms coalesce window
    private var lastRefreshTime: Date = .distantPast
    private var isRefreshing = false

    // MARK: - Init

    init(eventRouter: EventRouter) {
        self.eventRouter = eventRouter
        logInfo("AeroSpaceService initializing")

        Task {
            await refresh(source: "init")
        }

        setupFIFO()
        setupWorkspaceFallback()
        logInfo("AeroSpaceService ready")
    }

    deinit {
        stop()
    }

    func stop() {
        pipeSource?.cancel()
        if pipeFD >= 0 { close(pipeFD) }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - FIFO Pipe

    private func setupFIFO() {
        // Remove stale pipe, create fresh
        try? FileManager.default.removeItem(atPath: pipePath)
        mkfifo(pipePath, 0o666)

        pipeFD = open(pipePath, O_RDWR | O_NONBLOCK)
        guard pipeFD >= 0 else {
            logError("AeroSpace: Failed to open FIFO pipe at \(pipePath)")
            return
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: pipeFD, queue: pipeQueue)
        pipeSource = source

        source.setEventHandler { [weak self] in
            self?.handlePipeRead()
        }

        source.setCancelHandler { [weak self] in
            guard let self = self else { return }
            close(self.pipeFD)
        }

        source.resume()
        logInfo("AeroSpace: FIFO pipe monitoring active at \(pipePath)")
    }

    private func handlePipeRead() {
        var buffer = [UInt8](repeating: 0, count: 256)
        let count = read(pipeFD, &buffer, buffer.count)
        guard count > 0 else { return }

        let raw = String(decoding: buffer.prefix(count), as: UTF8.self)
        let lines = raw.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return }

        lastFIFOEventTime = Date()
        logDebug("AeroSpace FIFO: \(lines.joined(separator: ", "))")

        for line in lines {
            if line.hasPrefix("mode:") {
                let mode = String(line.dropFirst("mode:".count))
                DispatchQueue.main.async {
                    AegisConfig.shared.aeroSpaceCurrentMode = mode
                }
                logInfo("AeroSpace mode changed: \(mode)")
            } else {
                // Workspace change event (or any other event)
                scheduleRefresh(source: "FIFO:workspace_changed")
            }
        }
    }

    private func scheduleRefresh(source: String) {
        let isCommand = source.hasPrefix("cmd:")
        let delay = isCommand ? 0.08 : coalesceDelay  // Commands get 80ms delay to let AeroSpace settle

        coalesceTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { await self?.refresh(source: source, force: isCommand) }
        }
        coalesceTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// NSWorkspace fallback: catches window changes (app launch/quit/focus) that FIFO can't detect
    private func setupWorkspaceFallback() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            // Brief delay to let AeroSpace settle, then coalesce
            self.scheduleRefresh(source: "appActivated")
        }
    }

    // MARK: - Refresh

    private func refresh(source: String, force: Bool = false) async {
        guard !isRefreshing else { return }
        let now = Date()
        if !force {
            guard now.timeIntervalSince(lastRefreshTime) > 0.1 else { return }
        }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            // Query all data in parallel
            async let focusedWsResult = command.run(["list-workspaces", "--focused", "--json"])
            async let allWindowsResult = command.run(["list-windows", "--all", "--json",
                                                       "--format", "%{window-id} %{app-name} %{workspace} %{monitor-id} %{window-title} %{app-bundle-id}"])
            async let monitorsResult = command.run(["list-monitors", "--json"])

            let focusedJson = try await focusedWsResult
            let windowsJson = try await allWindowsResult
            let monitorsJson = try await monitorsResult

            // Also get focused window
            var focusedWinId: Int? = nil
            if let focusedWinJson = try? await command.run(["list-windows", "--focused", "--json"]) {
                if let focusedWins = try? JSONDecoder().decode([ASWindow].self, from: Data(focusedWinJson.utf8)),
                   let first = focusedWins.first {
                    focusedWinId = first.windowId
                }
            }

            // Parse
            let decoder = JSONDecoder()
            let focusedWsList = try decoder.decode([ASWorkspace].self, from: Data(focusedJson.utf8))
            let windowsList = try decoder.decode([ASWindow].self, from: Data(windowsJson.utf8))
            let monitorsList = try decoder.decode([ASMonitor].self, from: Data(monitorsJson.utf8))

            let newFocused = focusedWsList.first?.workspace ?? "1"

            // Build window maps
            var newAllWindows: [Int: ASWindow] = [:]
            var newWindowToWorkspace: [Int: String] = [:]
            var newWorkspaceWindows: [String: [ASWindow]] = [:]

            for window in windowsList {
                newAllWindows[window.windowId] = window
                if let ws = window.workspace {
                    newWindowToWorkspace[window.windowId] = ws
                    newWorkspaceWindows[ws, default: []].append(window)
                }
            }

            // Fallback: if no focused window reported (e.g. Aegis has macOS focus),
            // use the first window on the focused workspace
            if focusedWinId == nil, let wsWindows = newWorkspaceWindows[newFocused], !wsWindows.isEmpty {
                focusedWinId = wsWindows.first?.windowId
            }

            // Visible workspaces: always show 1 through max(highest in use, focused)
            // This prevents workspaces from "dying" when emptied
            var allRelevant = Set(newWorkspaceWindows.keys)
            allRelevant.insert(newFocused)

            // Find highest numbered workspace in use
            let highestInUse = allRelevant.compactMap { Int($0) }.max() ?? 1
            let maxWs = max(highestInUse, Int(newFocused) ?? 1)
            for i in 1...maxWs {
                allRelevant.insert("\(i)")
            }

            let sorted = sortWorkspaceNames(Array(allRelevant))

            // Build index map: stable identity (workspace "3" = index 3)
            var newIndexMap: [String: Int] = [:]
            for name in sorted {
                if let num = Int(name) {
                    newIndexMap[name] = num
                } else {
                    // Non-numeric workspace: append after numeric ones
                    let maxIdx = newIndexMap.values.max() ?? 0
                    newIndexMap[name] = maxIdx + 1
                }
            }

            // Detect changes
            let workspacesChanged = sorted != visibleWorkspaces || newFocused != focusedWorkspace
            let windowsChanged = newWindowToWorkspace != windowToWorkspace || focusedWinId != focusedWindowId

            // Apply
            dataQueue.sync(flags: .barrier) { [self] in
                self.workspaceWindows = newWorkspaceWindows
                self.visibleWorkspaces = sorted
                self.focusedWorkspace = newFocused
                self.focusedWindowId = focusedWinId
                self.allWindows = newAllWindows
                self.windowSnapshotReady = true
                self.windowToWorkspace = newWindowToWorkspace
                self.workspaceIndexMap = newIndexMap
                self.monitors = monitorsList
                self.lastRefreshTime = Date()
            }

            // Emit events
            if workspacesChanged {
                eventRouter.publish(.spaceChanged)
            }
            if windowsChanged {
                eventRouter.publish(.windowsChanged)
            }

        } catch {
            // Silent fail for poll — AeroSpace may not be running
            if source == "init" {
                logError("AeroSpace refresh failed: \(error.localizedDescription)")
            }
        }
    }

    /// Sort workspace names: numeric first (by value), then alpha
    private func sortWorkspaceNames(_ names: [String]) -> [String] {
        names.sorted { a, b in
            let aNum = Int(a)
            let bNum = Int(b)
            switch (aNum, bNum) {
            case let (.some(an), .some(bn)): return an < bn
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return a < b
            }
        }
    }

    // MARK: - Queries — Workspaces

    func getCurrentWorkspaces() -> [(name: String, index: Int, isFocused: Bool, windows: [ASWindow])] {
        dataQueue.sync {
            visibleWorkspaces.map { name in
                let idx = workspaceIndexMap[name] ?? 1
                let isFocused = name == focusedWorkspace
                let wins = workspaceWindows[name] ?? []
                return (name: name, index: idx, isFocused: isFocused, windows: wins)
            }
        }
    }

    func getFocusedWorkspaceName() -> String {
        dataQueue.sync { focusedWorkspace }
    }

    func getFocusedWorkspaceIndex() -> Int {
        dataQueue.sync { workspaceIndexMap[focusedWorkspace] ?? 1 }
    }

    func getWorkspaceName(forIndex index: Int) -> String? {
        dataQueue.sync {
            workspaceIndexMap.first(where: { $0.value == index })?.key
        }
    }

    func spaceHasFocusedWindow(_ spaceIndex: Int) -> Bool {
        dataQueue.sync {
            guard let wsName = workspaceIndexMap.first(where: { $0.value == spaceIndex })?.key else { return false }
            guard wsName == focusedWorkspace else { return false }
            return focusedWindowId != nil
        }
    }

    func getFocusedWindowId() -> Int? {
        dataQueue.sync { focusedWindowId }
    }

    // MARK: - Queries — Windows

    func getAllASWindows() -> [ASWindow] {
        dataQueue.sync { Array(allWindows.values) }
    }

    var hasWindowSnapshot: Bool {
        dataQueue.sync { windowSnapshotReady }
    }

    func getWindowsForWorkspace(_ wsIndex: Int) -> [ASWindow] {
        dataQueue.sync {
            guard let wsName = workspaceIndexMap.first(where: { $0.value == wsIndex })?.key else { return [] }
            return workspaceWindows[wsName] ?? []
        }
    }

    func getWindow(_ windowId: Int) -> ASWindow? {
        dataQueue.sync { allWindows[windowId] }
    }

    func getWindowSpace(_ windowId: Int) -> Int? {
        dataQueue.sync {
            guard let wsName = windowToWorkspace[windowId] else { return nil }
            return workspaceIndexMap[wsName]
        }
    }

    // MARK: - Queries — Monitors

    func getCurrentMonitors() -> [ASMonitor] {
        dataQueue.sync { monitors }
    }

    // MARK: - Window Icons

    func getWindowIconsForSpace(_ spaceIndex: Int) -> [WindowIcon] {
        let excludedApps = AegisConfig.shared.excludedApps
        return dataQueue.sync {
            guard let wsName = workspaceIndexMap.first(where: { $0.value == spaceIndex })?.key else { return [] }
            let isFocusedWs = wsName == focusedWorkspace
            let windows = workspaceWindows[wsName] ?? []

            let filtered = windows.filter { window in
                let appId = window.appBundleId ?? window.appName
                return !excludedApps.contains(appId)
            }

            return filtered.map { window in
                let appId = window.appBundleId ?? window.appName
                let pid: pid_t = {
                    if let bundleId = window.appBundleId,
                       let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
                        return app.processIdentifier
                    }
                    return 0
                }()
                return WindowIcon(
                    id: window.windowId,
                    pid: pid,
                    title: window.windowTitle,
                    app: appId,
                    appName: window.appName,
                    icon: getAppIcon(for: appId),
                    frame: nil,
                    hasFocus: isFocusedWs && window.windowId == focusedWindowId,
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
            guard let wsName = workspaceIndexMap.first(where: { $0.value == spaceIndex })?.key else { return [] }
            let windows = workspaceWindows[wsName] ?? []
            let apps = Set(windows.compactMap { window -> String? in
                let appId = window.appBundleId ?? window.appName
                guard !excludedApps.contains(appId) else { return nil }
                return appId
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
            let running = NSWorkspace.shared.runningApplications
            if let app = running.first(where: { $0.bundleIdentifier == appName || $0.localizedName == appName }) {
                icon = app.icon
            }
        }

        if let icon = icon {
            if appIconCache.count >= appIconCacheLimit {
                appIconCache.removeAll()
            }
            appIconCache[appName] = icon
        }

        return icon
    }

    // MARK: - Commands

    func focusWorkspace(_ index: Int) {
        guard let wsName = getWorkspaceName(forIndex: index) else { return }
        Task {
            try? await command.run(["workspace", wsName])
            scheduleRefresh(source: "cmd:focusWorkspace")
        }
    }

    func focusWindow(_ windowId: Int) {
        Task {
            try? await command.run(["focus", "--window-id", "\(windowId)"])
            scheduleRefresh(source: "cmd:focusWindow")
        }
    }

    func focusWindowByAppName(_ appName: String) -> Bool {
        let windows = dataQueue.sync { Array(allWindows.values) }
        guard let window = windows.first(where: {
            $0.appName == appName || $0.appBundleId == appName
        }) else { return false }
        focusWindow(window.windowId)
        return true
    }

    func moveWindow(_ windowId: Int, toWorkspace index: Int) {
        guard let wsName = getWorkspaceName(forIndex: index) else { return }
        Task {
            try? await command.run(["focus", "--window-id", "\(windowId)"])
            try? await command.run(["move-node-to-workspace", wsName])
            scheduleRefresh(source: "cmd:moveWindow")
        }
    }

    func moveWindowAndFocus(_ windowId: Int, toWorkspace index: Int) {
        guard let wsName = getWorkspaceName(forIndex: index) else { return }
        Task {
            try? await command.run(["focus", "--window-id", "\(windowId)"])
            try? await command.run(["move-node-to-workspace", "--focus-follows-window", wsName])
            scheduleRefresh(source: "cmd:moveWindowAndFocus")
        }
    }

    func toggleLayout() {
        Task {
            try? await command.run(["layout", "tiling", "floating"])
            scheduleRefresh(source: "cmd:toggleLayout")
        }
    }

    func setLayout(_ layout: String) {
        Task {
            try? await command.run(["layout", layout])
            scheduleRefresh(source: "cmd:setLayout")
        }
    }

    func toggleFloat() {
        Task {
            try? await command.run(["layout", "floating", "tiling"])
            scheduleRefresh(source: "cmd:toggleFloat")
        }
    }

    func toggleFullscreen() {
        Task {
            try? await command.run(["fullscreen"])
            scheduleRefresh(source: "cmd:toggleFullscreen")
        }
    }

    func balanceSizes() {
        Task {
            try? await command.run(["balance-sizes"])
            scheduleRefresh(source: "cmd:balanceSizes")
        }
    }

    func flattenWorkspaceTree() {
        Task {
            try? await command.run(["flatten-workspace-tree"])
            scheduleRefresh(source: "cmd:flattenWorkspaceTree")
        }
    }

    func reloadConfig() {
        Task {
            try? await command.run(["reload-config"])
            scheduleRefresh(source: "cmd:reloadConfig")
        }
    }

    /// "Create" a workspace by focusing the first empty one (AeroSpace workspaces are virtual)
    func createWorkspace() {
        let candidates = (1...9).map { "\($0)" }
        let occupiedWorkspaces = dataQueue.sync { Set(visibleWorkspaces) }

        guard let emptyWs = candidates.first(where: { !occupiedWorkspaces.contains($0) }) else {
            logInfo("AeroSpace: No empty workspaces available (1-9 all in use)")
            return
        }

        logInfo("AeroSpace: Creating workspace by focusing empty workspace '\(emptyWs)'")
        Task {
            try? await command.run(["workspace", emptyWs])
            scheduleRefresh(source: "cmd:createWorkspace")
        }
    }

    // MARK: - Raw Command

    func executeRawCommand(args: [String], completion: @escaping (Result<String, Error>) -> Void) {
        Task {
            do {
                let output = try await command.run(args)
                completion(.success(output))
                scheduleRefresh(source: "cmd:raw(\(args.first ?? "?"))")
            } catch {
                completion(.failure(error))
            }
        }
    }

    func getVersion() -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/aerospace")
        task.arguments = ["--version"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            // Extract version from "aerospace CLI client version: 0.20.3-Beta ..."
            if let range = output.range(of: #"\d+\.\d+\.\d+(-\w+)?"#, options: .regularExpression) {
                return String(output[range])
            }
            return output
        } catch {
            return "?"
        }
    }
}
