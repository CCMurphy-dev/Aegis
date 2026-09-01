//
//  RiftService.swift
//  Aegis
//
//  Core service for Rift window manager integration.
//  Mirrors YabaiService architecture: CLI execution, event subscription,
//  cached state with smart coalescing, and EventRouter publishing.
//

import Foundation
import AppKit

enum RiftFallbackRefreshPolicy {
    enum Trigger {
        case activeSpaceChange
        case applicationActivation
    }

    static func shouldRefresh(
        trigger: Trigger,
        hasRecentSubscriptionEvent: Bool
    ) -> Bool {
        switch trigger {
        case .activeSpaceChange:
            // The recent Rift event may only describe focus. The macOS Space
            // notification is authoritative for native fullscreen changes.
            return true
        case .applicationActivation:
            return !hasRecentSubscriptionEvent
        }
    }
}

enum RiftRefreshScope: Int, Comparable {
    case none = 0
    case windowsOnly = 1
    case workspacesAndWindows = 2
    case all = 3

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    func merging(_ other: Self) -> Self {
        max(self, other)
    }
}


// Private API: maps AXUIElement → CGWindowID (available since macOS 10.x)
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

// MARK: - Rift Command Actor

actor RiftCommandActor {

    static let shared = RiftCommandActor()

    let riftCliPath: String?
    private var lastRun = Date.distantPast
    private let minInterval: TimeInterval = 0.05   // 50ms between commands (max 20/sec)
    private var activeProcessCount = 0
    private let maxConcurrentProcesses = 3

    init() {
        self.riftCliPath = Self.findRiftCli()
        if let path = riftCliPath {
            logInfo("Found rift-cli at \(path)")
        } else {
            logError("rift-cli not found")
        }
    }

    nonisolated var isAvailable: Bool { riftCliPath != nil }

    /// Check if the Rift daemon is actually running (not just rift-cli installed)
    nonisolated static func isRiftDaemonRunning() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-x", "rift"]
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

    private static func findRiftCli() -> String? {
        let candidates = [
            "/opt/homebrew/bin/rift-cli",
            "/usr/local/bin/rift-cli",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Fallback: `which rift-cli`
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["rift-cli"]
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
        guard let path = riftCliPath else {
            throw NSError(domain: "RiftService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "rift-cli not found"])
        }

        guard Self.isRiftDaemonRunning() else {
            throw NSError(domain: "RiftService", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Rift daemon not running"])
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


// MARK: - Rift Service

final class RiftService {

    private let eventRouter: EventRouter
    private let command = RiftCommandActor.shared

    // Cached state
    // Workspaces keyed by 1-based index (Rift uses 0-based, we add 1 on ingest)
    private var workspaces: [Int: RiftWorkspace] = [:]
    private var windows: [Int: RiftWindow] = [:]       // Keyed by windowServerId
    private var displays: [Int: RiftDisplay] = [:]     // Keyed by screenId

    // Derived: windowServerId → 1-based workspace index
    private var windowToWorkspace: [Int: Int] = [:]

    // Rift internal ID → windowServerId lookup (built from workspace queries)
    // Key format: "pid:idx"
    private var riftIdToSysId: [String: Int] = [:]

    // Active virtual workspace (1-based)
    private var activeWorkspaceIndex: Int = 1

    // Cache window order per workspace (same pattern as YabaiService)
    private var windowOrderCache: [Int: [Int]] = [:]

    private let dataQueue = DispatchQueue(label: "com.aegis.rift.data", attributes: .concurrent)

    // Event subscription process
    private var subscriptionProcess: Process?
    private var lineBuffer = ""

    private var lastSubscriptionEventTime: Date = .distantPast

    // Every refresh enters this coordinator, including startup and fallback
    // notifications. It guarantees one sequence at a time and keeps weaker
    // requests pending while a stronger request is running.
    private lazy var refreshCoordinator = RiftRefreshCoordinator { [weak self] scope, source, generation, finish in
        guard let self else {
            finish()
            return
        }
        Task {
            await self.executeRefresh(scope: scope, source: source, generation: generation)
            finish()
        }
    }

    // Each native Space notification owns a transition generation. A newer
    // notification makes older delayed retries harmless.
    private let transitionTracker = RiftTransitionGenerationTracker()

    // Focused workspace cache
    private static var cachedFocusedWorkspaceIndex = 1
    private static var cachedFocusedWorkspace: RiftWorkspace?
    private static var lastFocusedWorkspaceQuery = Date.distantPast
    private static let focusedWorkspaceQueryThrottle: TimeInterval = 0.1

    // App icon cache
    private var appIconCache: [String: NSImage] = [:]
    private let appIconCacheLimit = 100

    // MARK: - Init

    init(eventRouter: EventRouter) {
        self.eventRouter = eventRouter
        logInfo("RiftService initializing")

        requestRefresh(scope: .all, source: "init")

        startSubscription()
        setupWorkspaceFallback()
        logInfo("RiftService ready")
    }

    deinit {
        stop()
    }

    func stop() {
        refreshCoordinator.stop()
        transitionTracker.stop()
        subscriptionProcess?.terminate()
        subscriptionProcess = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Event Subscription

    private func startSubscription() {
        guard let path = command.riftCliPath else {
            logError("Cannot start Rift event subscription: rift-cli not found")
            return
        }

        guard RiftCommandActor.isRiftDaemonRunning() else {
            logWarning("Rift daemon not running, skipping subscription (will retry via fallback)")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["subscribe", "mach", "*"]

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
            logInfo("Rift event subscription started")
        } catch {
            logError("Failed to start rift-cli subscribe: \(error)")
        }
    }

    private func processIncomingData(_ raw: String) {
        lineBuffer += raw
        while let newlineIndex = lineBuffer.firstIndex(of: "\n") {
            let line = String(lineBuffer[lineBuffer.startIndex..<newlineIndex])
                .trimmingCharacters(in: .whitespaces)
            lineBuffer = String(lineBuffer[lineBuffer.index(after: newlineIndex)...])
            if !line.isEmpty {
                handleRiftEventLine(line)
            }
        }
    }

    private func handleSubscriptionTerminated() {
        logWarning("Rift subscription process terminated, will retry if daemon is running")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard RiftCommandActor.isRiftDaemonRunning() else {
                logInfo("Rift daemon not running, deferring subscription reconnect")
                return
            }
            self?.startSubscription()
        }
    }

    private func handleRiftEventLine(_ line: String) {
        lastSubscriptionEventTime = Date()

        logInfo("[RIFT-DEBUG] event raw: \(line.prefix(200))")

        guard let data = line.data(using: .utf8),
              let event = try? JSONDecoder().decode(RiftEvent.self, from: data) else {
            logDebug("Failed to decode rift event: \(line.prefix(100))")
            return
        }

        switch event.type {
        case "workspace_changed":
            // Track which virtual workspace is now active
            if let wsId = event.workspaceId {
                dataQueue.sync(flags: .barrier) { [weak self] in
                    guard let self = self else { return }
                    self.activeWorkspaceIndex = wsId.idx + 1  // Convert 0-based to 1-based
                    logInfo("[RIFT-DEBUG] workspace_changed: wsIdx=\(wsId.idx) → activeWorkspaceIndex=\(self.activeWorkspaceIndex)")
                }
            }
            invalidateFocusedWorkspaceCache()
            // A workspace switch can also move the display between a managed
            // native space, an unmanaged space, and a native fullscreen space.
            // Refresh the display snapshot before publishing the workspace
            // change so menu bars make their decision from the same transition.
            requestRefresh(scope: .all, source: "sub:workspace_changed")

        case "space_changed", "active_space_changed", "display_changed", "native_fullscreen_changed":
            // These names are accepted for newer Rift event payloads. Rift
            // versions that do not emit them still reach this path through
            // NSWorkspace.activeSpaceDidChangeNotification below.
            invalidateFocusedWorkspaceCache()
            requestRefresh(scope: .all, source: "sub:\(event.type)")

        case "windows_changed":
            // Use workspace index from event to map windows to correct virtual workspace
            if let windowIds = event.windows {
                dataQueue.sync(flags: .barrier) { [weak self] in
                    guard let self = self else { return }

                    // Resolve workspace index from event
                    var wsIndex: Int?
                    if let wsId = event.workspaceId {
                        wsIndex = wsId.idx + 1  // 0-based to 1-based
                    } else if let wsIdx = event.workspaceIndex {
                        wsIndex = Int(wsIdx) + 1
                    }

                    guard let targetWs = wsIndex else {
                        logInfo("[RIFT-DEBUG] windows_changed: can't resolve workspace from event")
                        return
                    }

                    // Parse Rift internal IDs: "WindowId { pid: 60750, idx: 65381 }"
                    var eventSysIds: Set<Int> = []
                    for idStr in windowIds {
                        if let sysId = self.parseRiftWindowIdToSysId(idStr) {
                            eventSysIds.insert(sysId)
                        }
                    }
                    logInfo("[RIFT-DEBUG] windows_changed: ws=\(targetWs) resolved \(eventSysIds.count)/\(windowIds.count) sysIds")

                    // Update mapping for resolved windows
                    for sysId in eventSysIds {
                        self.windowToWorkspace[sysId] = targetWs
                    }
                    // Remove windows no longer on this workspace
                    for (sysId, mappedWs) in self.windowToWorkspace {
                        if mappedWs == targetWs && !eventSysIds.contains(sysId) {
                            self.windowToWorkspace.removeValue(forKey: sysId)
                        }
                    }
                }
            }
            requestRefresh(scope: .windowsOnly, source: "sub:windows_changed")

        case "window_title_changed":
            requestRefresh(scope: .windowsOnly, source: "sub:window_title_changed")

        case "stacks_changed":
            requestRefresh(scope: .windowsOnly, source: "sub:stacks_changed")

        default:
            invalidateFocusedWorkspaceCache()
            requestRefresh(scope: .workspacesAndWindows, source: "sub:\(event.type)")
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
        invalidateFocusedWorkspaceCache()
        let transition = beginActiveSpaceTransition()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }
            guard self.isCurrentActiveSpaceTransition(transition.generation) else { return }
            self.requestRefresh(scope: .all, source: "activeSpaceChanged")
            self.scheduleActiveSpaceRetry(
                after: 0.25,
                transition: transition,
                source: "activeSpaceChanged.retry250"
            )
            self.scheduleActiveSpaceRetry(
                after: 0.5,
                transition: transition,
                source: "activeSpaceChanged.retry500"
            )
        }
    }

    @objc private func appChanged(_ notification: Notification) {
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           app.bundleIdentifier == Bundle.main.bundleIdentifier {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self else { return }
            let hasRecentSubscriptionEvent = Date().timeIntervalSince(self.lastSubscriptionEventTime) < 0.5
            guard RiftFallbackRefreshPolicy.shouldRefresh(
                trigger: .applicationActivation,
                hasRecentSubscriptionEvent: hasRecentSubscriptionEvent
            ) else { return }
            self.requestRefresh(scope: .windowsOnly, source: "appChanged")
        }
    }

    // MARK: - Serialized Refresh Gate

    private func requestRefresh(scope: RiftRefreshScope, source: String = "unknown") {
        if Thread.isMainThread {
            refreshCoordinator.request(scope: scope, source: source)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.refreshCoordinator.request(scope: scope, source: source)
            }
        }
    }

    private func executeRefresh(
        scope: RiftRefreshScope,
        source: String = "unknown",
        generation: UInt64
    ) async {
        guard refreshCoordinator.isCurrent(generation) else { return }
        // Keep this sequential. refreshWorkspaces can publish `.spaceChanged`,
        // and its subscribers immediately query displays. The display cache
        // must therefore describe the same native-space transition first.
        for operation in RiftRefreshOperationPlan.operations(for: scope) {
            switch operation {
            case .displays:
                await refreshDisplays(generation: generation)
            case .workspaces:
                await refreshWorkspaces(generation: generation)
            }
        }
    }

    private typealias ActiveSpaceTransition = (
        generation: UInt64,
        baseline: [Int: RiftDisplayChangeSnapshot]
    )

    private func beginActiveSpaceTransition() -> ActiveSpaceTransition {
        (transitionTracker.begin(), displaySnapshot())
    }

    private func isCurrentActiveSpaceTransition(_ generation: UInt64) -> Bool {
        transitionTracker.isCurrent(generation)
    }

    private func scheduleActiveSpaceRetry(
        after delay: TimeInterval,
        transition: ActiveSpaceTransition,
        source: String
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self,
                  self.isCurrentActiveSpaceTransition(transition.generation),
                  RiftActiveSpaceRetryPolicy.shouldRetry(
                      baseline: transition.baseline,
                      current: self.displaySnapshot()
                  ) else { return }
            self.requestRefresh(scope: .all, source: source)
        }
    }

    private func displaySnapshot() -> [Int: RiftDisplayChangeSnapshot] {
        dataQueue.sync {
            displays.mapValues { RiftDisplayChangeSnapshot(display: $0) }
        }
    }

    // MARK: - Refresh Methods

    private func refreshWorkspaces(generation: UInt64) async {
        do {
            let json = try await command.run(["query", "workspaces"])
            let decoded = try JSONDecoder().decode([RiftWorkspace].self, from: Data(json.utf8))

            // DEBUG: Log what Rift returned
            for ws in decoded {
                logInfo("[RIFT-DEBUG] ws\(ws.index) '\(ws.name)' active=\(ws.isActive) windowCount=\(ws.windowCount) windows.count=\(ws.windows.count)")
            }

            // Find which workspace indices have fresh window data (only active ws has windows populated)
            let activeWsIndices = Set(decoded.filter { !$0.windows.isEmpty }.map { $0.index + 1 })

            // Extract windows from workspaces that reported them
            var newWindows: [Int: RiftWindow] = [:]
            var newWsMap: [Int: Int] = [:]

            for ws in decoded {
                let wsIndex = ws.index + 1  // 1-based
                if !ws.windows.isEmpty {
                    for window in ws.windows {
                        if let sysId = window.windowServerId {
                            newWindows[Int(sysId)] = window
                            newWsMap[Int(sysId)] = wsIndex
                        }
                    }
                }
                // Track active workspace
                if ws.isActive {
                    dataQueue.sync(flags: .barrier) { [weak self] in
                        guard let self = self,
                              self.refreshCoordinator.isCurrent(generation) else { return }
                        self.activeWorkspaceIndex = wsIndex
                    }
                }
            }

            // Check if workspaces changed
            let workspacesChanged = dataQueue.sync { [weak self] () -> Bool in
                guard let self = self else { return false }
                let oldIds = Set(self.workspaces.keys)
                let newIds = Set(decoded.map { $0.index + 1 })
                if oldIds != newIds { return true }
                for ws in decoded {
                    let key = ws.index + 1
                    if let old = self.workspaces[key],
                       old.isActive != ws.isActive || old.layoutMode != ws.layoutMode {
                        return true
                    }
                }
                return false
            }

            // Check if windows changed
            let windowsChanged = dataQueue.sync { [weak self] () -> Bool in
                guard let self = self else { return false }

                // Merge: keep cached windows from inactive workspaces
                var mergedWindows = self.windows
                var mergedWsMap = self.windowToWorkspace

                // Remove windows from workspaces that just reported fresh data
                for (sysId, wsIndex) in self.windowToWorkspace {
                    if activeWsIndices.contains(wsIndex) {
                        mergedWindows.removeValue(forKey: sysId)
                        mergedWsMap.removeValue(forKey: sysId)
                    }
                }

                // Add fresh windows
                for (sysId, window) in newWindows {
                    mergedWindows[sysId] = window
                }
                for (sysId, wsIndex) in newWsMap {
                    mergedWsMap[sysId] = wsIndex
                }

                let oldIds = Set(self.windows.keys)
                let newIds = Set(mergedWindows.keys)
                if oldIds != newIds { return true }
                for (id, window) in mergedWindows {
                    if let old = self.windows[id],
                       old.isFocused != window.isFocused || old.isFloating != window.isFloating {
                        return true
                    }
                }
                return false
            }

            // Write to cache (merge strategy)
            dataQueue.sync(flags: .barrier) { [weak self] in
                guard let self = self,
                      self.refreshCoordinator.isCurrent(generation) else { return }
                self.workspaces = Dictionary(uniqueKeysWithValues: decoded.map { ($0.index + 1, $0) })

                // Remove windows from workspaces that reported fresh data
                for (sysId, wsIndex) in self.windowToWorkspace {
                    if activeWsIndices.contains(wsIndex) {
                        self.windows.removeValue(forKey: sysId)
                        self.windowToWorkspace.removeValue(forKey: sysId)
                    }
                }

                // Add fresh windows
                for (sysId, window) in newWindows {
                    self.windows[sysId] = window
                }
                for (sysId, wsIndex) in newWsMap {
                    self.windowToWorkspace[sysId] = wsIndex
                }

                // Update riftIdToSysId lookup from all decoded workspaces
                for ws in decoded {
                    for window in ws.windows {
                        if let sysId = window.windowServerId {
                            let key = "\(window.id.pid):\(window.id.idx)"
                            self.riftIdToSysId[key] = Int(sysId)
                        }
                    }
                }

                self.updateWindowOrderCache()

                // DEBUG: Log cache state after merge
                var wsWindowCounts: [Int: Int] = [:]
                for (_, wsIndex) in self.windowToWorkspace {
                    wsWindowCounts[wsIndex, default: 0] += 1
                }
                logInfo("[RIFT-DEBUG] After merge: windows.count=\(self.windows.count) wsMap=\(wsWindowCounts) activeWs=\(self.activeWorkspaceIndex)")
            }

            guard refreshCoordinator.isCurrent(generation) else { return }
            if workspacesChanged {
                eventRouter.publish(.spaceChanged, data: [:])
            }
            if windowsChanged {
                eventRouter.publish(.windowsChanged, data: [:])
            }
        } catch {
            logError("rift workspaces query failed: \(error)")
        }
    }

    private func refreshDisplays(generation: UInt64) async {
        do {
            let json = try await command.run(["query", "displays"])
            let decoded = try JSONDecoder().decode([RiftDisplay].self, from: Data(json.utf8))

            let currentSnapshots = Dictionary(uniqueKeysWithValues: decoded.map {
                (Int($0.screenId), RiftDisplayChangeSnapshot(display: $0))
            })

            let displaysChanged = dataQueue.sync { [weak self] () -> Bool in
                guard let self = self else { return false }
                let previousSnapshots = self.displays.mapValues {
                    RiftDisplayChangeSnapshot(display: $0)
                }
                return RiftDisplayChangeDetector.hasChanges(
                    previous: previousSnapshots,
                    current: currentSnapshots
                )
            }

            dataQueue.sync(flags: .barrier) { [weak self] in
                guard let self = self,
                      self.refreshCoordinator.isCurrent(generation) else { return }
                self.displays = Dictionary(uniqueKeysWithValues: decoded.map { (Int($0.screenId), $0) })
            }

            guard refreshCoordinator.isCurrent(generation) else { return }
            if displaysChanged {
                eventRouter.publish(.displaysChanged, data: [:])
            }
        } catch {
            logError("rift displays query failed: \(error)")
        }
    }

    // MARK: - Queries

    func getCurrentWorkspaces() -> [RiftWorkspace] {
        dataQueue.sync {
            // Return actual Rift virtual workspaces, enriched with cached windows
            Array(workspaces.values).sorted { $0.index < $1.index }.map { ws in
                let wsIndex = ws.index + 1
                // Populate windows from global cache (ws.windows is only filled for active workspace)
                let cachedWindows = windows.values.filter { window in
                    guard let sysId = window.windowServerId else { return false }
                    return windowToWorkspace[Int(sysId)] == wsIndex
                }
                return RiftWorkspace(
                    id: ws.id,
                    index: ws.index,
                    name: ws.name,
                    layoutMode: ws.layoutMode,
                    isActive: ws.isActive,
                    windowCount: cachedWindows.count,
                    windows: Array(cachedWindows)
                )
            }
        }
    }

    func getWorkspacesForDisplay(_ displayIndex: Int) -> [RiftWorkspace] {
        return getCurrentWorkspaces()
    }

    func getCurrentDisplays() -> [RiftDisplay] {
        dataQueue.sync {
            Array(displays.values).sorted { $0.screenId < $1.screenId }
        }
    }

    func getAllWindows() -> [RiftWindow] {
        dataQueue.sync { Array(windows.values) }
    }

    func getWindow(_ sysId: Int) -> RiftWindow? {
        dataQueue.sync { windows[sysId] }
    }

    func getWindowsForWorkspace(_ wsIndex: Int) -> [RiftWindow] {
        dataQueue.sync {
            return windows.values.filter { window in
                guard let sysId = window.windowServerId else { return false }
                return windowToWorkspace[Int(sysId)] == wsIndex
            }
        }
    }

    func getWindowSpace(_ sysId: Int) -> Int? {
        dataQueue.sync { windowToWorkspace[sysId] }
    }

    func spaceHasFocusedWindow(_ spaceIndex: Int) -> Bool {
        let excludedApps = AegisConfig.shared.baseExcludedApps
        return dataQueue.sync {
            // Only the active workspace can truly have focus
            guard spaceIndex == activeWorkspaceIndex else { return false }

            for (sysId, window) in windows {
                if windowToWorkspace[sysId] == spaceIndex &&
                   window.isFocused &&
                   !(excludedApps.contains(window.bundleId ?? "") || excludedApps.contains(window.appName ?? "")) {
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

    func getFocusedWorkspace() -> RiftWorkspace? {
        let now = Date()
        if now.timeIntervalSince(Self.lastFocusedWorkspaceQuery) < Self.focusedWorkspaceQueryThrottle {
            if let cached = Self.cachedFocusedWorkspace { return cached }
        }
        Self.lastFocusedWorkspaceQuery = now

        let ws = getCurrentWorkspaces().first { $0.isActive }
        if let ws = ws {
            Self.cachedFocusedWorkspace = ws
            Self.cachedFocusedWorkspaceIndex = ws.index + 1
        }
        return ws
    }

    func invalidateFocusedWorkspaceCache() {
        Self.lastFocusedWorkspaceQuery = .distantPast
        Self.cachedFocusedWorkspace = nil
    }

    // MARK: - Window Icons

    func getWindowIconsForSpace(_ spaceIndex: Int) -> [WindowIcon] {
        let excludedApps = AegisConfig.shared.excludedApps
        return dataQueue.sync {
            // Only the active workspace can have a focused window — cached windows from
            // inactive workspaces retain stale isFocused=true from when they were last active
            let isActiveWs = spaceIndex == activeWorkspaceIndex

            let spaceWindows = windows.values.filter { window in
                guard let sysId = window.windowServerId else { return false }
                let wsIndex = windowToWorkspace[Int(sysId)]
                return wsIndex == spaceIndex &&
                    !(excludedApps.contains(window.bundleId ?? "") || excludedApps.contains(window.appName ?? ""))
            }
            logInfo("[RIFT-DEBUG] getWindowIconsForSpace(\(spaceIndex)): found \(spaceWindows.count) windows (total cache: \(windows.count))")

            let currentWindowIds = Set(spaceWindows.compactMap { $0.windowServerId.map { Int($0) } })
            let cachedOrder = windowOrderCache[spaceIndex] ?? []
            let cachedIds = Set(cachedOrder)
            let needsRecalculation = currentWindowIds != cachedIds

            let orderedIds: [Int]
            if needsRecalculation {
                let sorted = sortWindowsByPosition(Array(spaceWindows))
                orderedIds = sorted.compactMap { $0.windowServerId.map { Int($0) } }
            } else {
                orderedIds = cachedOrder
            }

            let windowLookup = Dictionary(uniqueKeysWithValues:
                spaceWindows.compactMap { w -> (Int, RiftWindow)? in
                    guard let sysId = w.windowServerId else { return nil }
                    return (Int(sysId), w)
                }
            )

            let icons = orderedIds.compactMap { id -> WindowIcon? in
                guard let window = windowLookup[id] else { return nil }
                let appId = window.bundleId ?? window.appName ?? "Unknown"
                return WindowIcon(
                    id: id,
                    pid: pid_t(window.id.pid),
                    title: window.title,
                    app: appId,
                    appName: window.appName ?? "Unknown",
                    icon: getAppIcon(for: appId),
                    frame: window.frame.cgRect,
                    hasFocus: isActiveWs && window.isFocused,
                    stackIndex: 0,
                    isMinimized: false,
                    isHidden: false
                )
            }

            let activeIcons = icons.filter { !$0.isMinimized && !$0.isHidden }
            let inactiveIcons = icons.filter { $0.isMinimized || $0.isHidden }
            return activeIcons + inactiveIcons
        }
    }

    private func sortWindowsByPosition(_ windows: [RiftWindow]) -> [RiftWindow] {
        windows.sorted { lhs, rhs in
            let lhsX = lhs.frame.origin.x
            let rhsX = rhs.frame.origin.x
            if abs(lhsX - rhsX) < 10 {
                return (lhs.windowServerId ?? 0) < (rhs.windowServerId ?? 0)
            }
            if lhsX != rhsX {
                return lhsX < rhsX
            }
            return (lhs.windowServerId ?? 0) < (rhs.windowServerId ?? 0)
        }
    }

    private func updateWindowOrderCache() {
        let excludedApps = AegisConfig.shared.excludedApps
        var newCache: [Int: [Int]] = [:]

        // Build cache from windowToWorkspace mapping
        var wsWindowsMap: [Int: [RiftWindow]] = [:]
        for (sysId, wsIndex) in windowToWorkspace {
            if let window = windows[sysId],
               !(excludedApps.contains(window.bundleId ?? "") || excludedApps.contains(window.appName ?? "")) {
                wsWindowsMap[wsIndex, default: []].append(window)
            }
        }

        for (wsIndex, wsWindows) in wsWindowsMap {
            let sorted = sortWindowsByPosition(wsWindows)
            newCache[wsIndex] = sorted.compactMap { $0.windowServerId.map { Int($0) } }
        }

        windowOrderCache = newCache
    }

    func getAppIconsForSpace(_ spaceIndex: Int) -> [NSImage] {
        let excludedApps = AegisConfig.shared.excludedApps
        return dataQueue.sync {
            let apps = Set(windows.values.compactMap { window -> String? in
                guard let sysId = window.windowServerId else { return nil }
                let wsIndex = windowToWorkspace[Int(sysId)]
                guard wsIndex == spaceIndex else { return nil }
                let appId = window.bundleId ?? window.appName ?? ""
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

    // MARK: - Commands

    func focusWorkspace(_ index: Int) {
        let riftIndex = index - 1  // Rift uses 0-based workspace indices
        Task {
            try? await command.run(["execute", "workspace", "switch", "\(riftIndex)"])
        }
    }

    func focusWindow(_ sysId: Int) {
        // rift-cli's "window focus" is directional only — use macOS Accessibility to focus by ID
        let pid = dataQueue.sync { windows[sysId]?.id.pid }
        guard let pid = pid else { return }

        let app = NSRunningApplication(processIdentifier: pid_t(pid))
        app?.activate()

        // Raise the specific window via AXUIElement
        let axApp = AXUIElementCreateApplication(pid_t(pid))
        var windowList: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowList) == .success,
              let axWindows = windowList as? [AXUIElement] else { return }

        for axWindow in axWindows {
            var windowIdRef: CGWindowID = 0
            if _AXUIElementGetWindow(axWindow, &windowIdRef) == .success,
               windowIdRef == CGWindowID(sysId) {
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                break
            }
        }
    }

    func focusWindowByAppName(_ appName: String) -> Bool {
        let windowId = dataQueue.sync {
            windows.values.first { $0.appName == appName || $0.bundleId == appName }?.windowServerId
        }
        guard let sysId = windowId else { return false }
        focusWindow(Int(sysId))
        return true
    }

    func moveWindow(_ sysId: Int, toWorkspace index: Int) {
        let riftIndex = index - 1
        // Rift's move-window with explicit window_server_id doesn't work —
        // focus the window first, then move the focused window
        Task {
            self.focusWindow(sysId)
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms for focus to take effect
            try? await command.run(["execute", "workspace", "move-window", "\(riftIndex)"])
        }
    }

    func createWorkspace() {
        Task {
            try? await command.run(["execute", "workspace", "create"])
            requestRefresh(scope: .workspacesAndWindows, source: "createWorkspace")
        }
    }

    func toggleLayout() {
        guard let focused = getCurrentWorkspaces().first(where: { $0.isActive }) else { return }
        let newLayout = focused.layoutMode == "bsp" ? "stack" : "bsp"
        Task {
            try? await command.run(["execute", "workspace", "set-layout", newLayout])
            requestRefresh(scope: .workspacesAndWindows, source: "toggleLayout")
        }
    }

    func toggleStackAllWindows() {
        Task {
            try? await command.run(["execute", "layout", "toggle-stack"])
        }
    }

    func unstackWindows(_ windowIds: [Int]) {
        Task {
            try? await command.run(["execute", "layout", "unjoin"])
        }
    }

    func toggleFloat() {
        Task {
            try? await command.run(["execute", "window", "toggle-float"])
        }
    }

    func setWorkspaceLayout(_ mode: String) {
        Task {
            try? await command.run(["execute", "workspace", "set-layout", mode])
            requestRefresh(scope: .workspacesAndWindows, source: "setWorkspaceLayout")
        }
    }

    func toggleFullscreen() {
        Task {
            try? await command.run(["execute", "window", "toggle-fullscreen"])
        }
    }

    func toggleSpaceActivated() {
        Task {
            try? await command.run(["execute", "toggle-space-activated"])
            requestRefresh(scope: .workspacesAndWindows, source: "toggleSpaceActivated")
        }
    }

    func focusDirection(_ direction: String) {
        Task {
            try? await command.run(["execute", "window", "focus", direction])
        }
    }

    func moveNodeDirection(_ direction: String) {
        Task {
            try? await command.run(["execute", "window", "move-node", direction])
        }
    }

    func closeWindow(_ sysId: Int? = nil) {
        Task {
            if let sysId = sysId {
                try? await command.run(["execute", "window", "close", "\(sysId)"])
            } else {
                try? await command.run(["execute", "window", "close"])
            }
        }
    }

    func focusDisplay(_ selector: String) {
        Task {
            try? await command.run(["execute", "display", "focus", selector])
        }
    }

    func moveWindowToDisplay(_ selector: String, windowId: Int? = nil) {
        Task {
            if let windowId = windowId {
                try? await command.run(["execute", "display", "move-window", selector, "\(windowId)"])
            } else {
                try? await command.run(["execute", "display", "move-window", selector])
            }
        }
    }

    func executeRiftCli(args: [String], completion: @escaping (Result<String, Error>) -> Void) {
        Task {
            do {
                let output = try await command.run(args)
                completion(.success(output))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func getRiftVersion() -> String {
        guard command.isAvailable else { return "Not found" }
        return "Installed"
    }

    // MARK: - Helpers

    /// Parse Rift's debug-format window ID string to sysId via lookup table
    /// Input format: "WindowId { pid: 60750, idx: 65381 }"
    /// Must be called inside dataQueue
    private func parseRiftWindowIdToSysId(_ idStr: String) -> Int? {
        guard let pidRange = idStr.range(of: "pid: "),
              let idxRange = idStr.range(of: "idx: ") else { return nil }

        let pidStart = pidRange.upperBound
        let pidEnd = idStr[pidStart...].firstIndex(of: ",") ?? idStr.endIndex
        let idxStart = idxRange.upperBound
        let idxEnd = idStr[idxStart...].firstIndex(where: { $0 == " " || $0 == "}" }) ?? idStr.endIndex

        guard let pid = Int(idStr[pidStart..<pidEnd].trimmingCharacters(in: .whitespaces)),
              let idx = Int(idStr[idxStart..<idxEnd].trimmingCharacters(in: .whitespaces)) else { return nil }

        let key = "\(pid):\(idx)"
        return riftIdToSysId[key]
    }
}
