import Foundation
import AppKit


// MARK: - YabaiService (SAFE, EVENT-DRIVEN)

final class YabaiService {

    private let eventRouter: EventRouter
    private let command = YabaiCommandActor.shared

    private var spaces: [Int: Space] = [:]
    private var windows: [Int: WindowInfo] = [:]
    private var displays: [Int: Display] = [:]

    // Cache window order per space to prevent shuffling on focus changes
    // Key: space index, Value: ordered array of window IDs
    private var windowOrderCache: [Int: [Int]] = [:]

    private let dataQueue = DispatchQueue(label: "com.aegis.yabai.data", attributes: .concurrent)

    // FIFO
    private var pipeSource: DispatchSourceRead?
    private var pipeFD: Int32 = -1

    private let pipeQueue = DispatchQueue(label: "com.aegis.yabai.pipe")

    // Coalescing gate: collects events for a short window, then executes one optimally-scoped refresh
    private enum RefreshScope: Int, Comparable {
        case none = 0
        case windowsOnly = 1       // 1 subprocess: --windows
        case spacesAndWindows = 2  // 2 subprocesses: --spaces + --windows
        case all = 3               // 3 subprocesses: --displays + --spaces + --windows
        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }
    private var coalesceTimer: DispatchWorkItem?
    private var pendingScope: RefreshScope = .none
    private var lastRefreshTime: Date = .distantPast
    private let coalesceDelay: TimeInterval = 0.03   // 30ms coalesce window
    private let debounceInterval: TimeInterval = 0.1 // 100ms post-refresh debounce
    private var lastFIFOEventTime: Date = .distantPast // Skip NSWorkspace fallbacks when FIFO is active

    private lazy var pipePath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/aegis/yabai.pipe"
    }()

    // MARK: - Init

    init(eventRouter: EventRouter) {
        self.eventRouter = eventRouter
        logInfo("YabaiService initializing")

        Task {
            await executeRefresh(scope: .all, source: "init")
        }

        setupFIFO()
        setupWorkspaceFallback()
        logInfo("YabaiService ready")
    }

    deinit {
        pipeSource?.cancel()
        if pipeFD >= 0 { close(pipeFD) }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - FIFO

    private func setupFIFO() {
        try? FileManager.default.removeItem(atPath: pipePath)
        mkfifo(pipePath, 0o666)

        pipeFD = open(pipePath, O_RDWR | O_NONBLOCK)
        guard pipeFD >= 0 else {
            logError("Failed to open FIFO pipe at \(pipePath)")
            return
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: pipeFD, queue: pipeQueue)
        pipeSource = source

        source.setEventHandler { [weak self] in
            self?.handlePipeRead()
        }

        source.setCancelHandler {
            close(self.pipeFD)
        }

        source.resume()
        logDebug("FIFO pipe ready at \(pipePath)")
    }

    private func handlePipeRead() {
        var buffer = [UInt8](repeating: 0, count: 256)
        let count = read(pipeFD, &buffer, buffer.count)
        guard count > 0 else { return }

        let raw = String(decoding: buffer.prefix(count), as: UTF8.self)

        // Split on newlines — multiple events can arrive in a single read
        let lines = raw.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return }

        Task {
            for line in lines {
                await handleYabaiEvent(line)
            }
        }
    }

    // MARK: - Workspace fallback

    private func setupWorkspaceFallback() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        // Also observe space changes (critical for fullscreen detection)
        // macOS switches to a new Space when entering native fullscreen
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    @objc private func activeSpaceChanged(_ notification: Notification) {
        invalidateFocusedSpaceCache()
        // Fallback only — skip if FIFO pipe handled this already
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }
            guard Date().timeIntervalSince(self.lastFIFOEventTime) >= 0.5 else { return }
            self.scheduleRefresh(scope: .spacesAndWindows, source: "activeSpaceChanged")
        }
    }

    @objc private func appChanged(_ notification: Notification) {
        // Skip if Aegis itself is being activated (happens when clicking on Aegis UI)
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           app.bundleIdentifier == Bundle.main.bundleIdentifier {
            return
        }

        // Fallback only — skip if FIFO pipe handled this already
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self else { return }
            guard Date().timeIntervalSince(self.lastFIFOEventTime) >= 0.5 else { return }
            self.scheduleRefresh(scope: .windowsOnly, source: "appChanged")
        }
    }

    // MARK: - Events

    private func handleYabaiEvent(_ event: String) async {
        lastFIFOEventTime = Date()
        switch event {
        case "space_changed":
            invalidateFocusedSpaceCache()
            scheduleRefresh(scope: .spacesAndWindows, source: "FIFO:space_changed")
        case "space_created", "space_destroyed":
            invalidateFocusedSpaceCache()
            cleanupWindowOrderCache()
            scheduleRefresh(scope: .spacesAndWindows, source: "FIFO:\(event)")
        case "window_focused", "application_front_switched":
            invalidateFocusedSpaceCache()
            scheduleRefresh(scope: .windowsOnly, source: "FIFO:\(event)")
        case "window_created", "window_destroyed", "window_moved":
            scheduleRefresh(scope: .windowsOnly, source: "FIFO:\(event)")
        case "window_minimized", "window_deminimized":
            // Brief delay for yabai state update, then coalesce
            try? await Task.sleep(nanoseconds: 50_000_000)
            scheduleRefresh(scope: .windowsOnly, source: "FIFO:\(event)")
        case "application_launched", "application_terminated":
            scheduleRefresh(scope: .spacesAndWindows, source: "FIFO:\(event)")
        case "application_hidden", "application_visible":
            scheduleRefresh(scope: .windowsOnly, source: "FIFO:\(event)")
        default:
            invalidateFocusedSpaceCache()
            scheduleRefresh(scope: .spacesAndWindows, source: "FIFO:\(event)")
        }
    }

    // MARK: - Coalescing Refresh Gate

    /// Schedule a refresh with the given scope. Multiple calls within the coalesce window
    /// are merged into a single refresh at the highest requested scope.
    private func scheduleRefresh(scope: RefreshScope, source: String = "unknown") {
        // Upgrade pending scope (windowsOnly → spacesAndWindows → all)
        pendingScope = max(pendingScope, scope)

        // Cancel any pending timer, start a new one
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

    /// Execute a refresh at the given scope, respecting post-refresh debounce.
    private func executeRefresh(scope: RefreshScope, source: String = "unknown") async {
        // Post-refresh debounce: skip if we just refreshed
        let now = Date()
        let timeSinceLast = now.timeIntervalSince(lastRefreshTime)
        if timeSinceLast < debounceInterval { return }
        lastRefreshTime = now

        switch scope {
        case .none:
            return
        case .windowsOnly:
            await refreshWindows()
        case .spacesAndWindows:
            async let s: () = refreshSpaces()
            async let w: () = refreshWindows()
            _ = await (s, w)
        case .all:
            async let d: () = refreshDisplays()
            async let s: () = refreshSpaces()
            async let w: () = refreshWindows()
            _ = await (d, s, w)
        }

    }

    private func refreshDisplays() async {
        do {
            let json = try await command.run(["-m", "query", "--displays"])
            let decoded = try JSONDecoder().decode([Display].self, from: Data(json.utf8))

            // Check if displays changed
            let displaysChanged = dataQueue.sync { [weak self] () -> Bool in
                guard let self = self else { return false }
                let oldDisplayIds = Set(self.displays.keys)
                let newDisplayIds = Set(decoded.map { $0.id })
                return oldDisplayIds != newDisplayIds
            }

            // Write to cache
            dataQueue.sync(flags: .barrier) { [weak self] in
                self?.displays = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
            }

            // Publish event if displays changed
            if displaysChanged {
                DispatchQueue.main.async { [weak self] in
                    self?.eventRouter.publish(.displaysChanged, data: ["displays": decoded])
                }
            }
        } catch {
            logError("yabai displays query failed: \(error)")
        }
    }

    private func refreshSpaces() async {
        do {
            let json = try await command.run(["-m", "query", "--spaces"])
            let decoded = try JSONDecoder().decode([Space].self, from: Data(json.utf8))

            // Check if spaces actually changed before updating and publishing
            let spacesChanged = dataQueue.sync { [weak self] () -> Bool in
                guard let self = self else { return false }
                let oldSpaceIds = Set(self.spaces.keys)
                let newSpaceIds = Set(decoded.map { $0.id })

                // Quick check: different count or different IDs
                if oldSpaceIds != newSpaceIds {
                    return true
                }

                // Deeper check: compare focused state, type, and fullscreen
                for space in decoded {
                    if let oldSpace = self.spaces[space.id],
                       oldSpace.focused != space.focused ||
                       oldSpace.type != space.type ||
                       oldSpace.isNativeFullscreen != space.isNativeFullscreen {
                        return true
                    }
                }
                return false
            }

            // Write to cache synchronously (barrier) so data is available before we return
            dataQueue.sync(flags: .barrier) { [weak self] in
                self?.spaces = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
            }

            // Only publish event if spaces actually changed
            if spacesChanged {
                DispatchQueue.main.async { [weak self] in
                    self?.eventRouter.publish(.spaceChanged, data: ["spaces": decoded])
                }
            }
        } catch {
            logError("yabai spaces query failed: \(error)")
        }
    }

    private func refreshWindows() async {
        do {
            let json = try await command.run(["-m", "query", "--windows"])
            let decoded = try JSONDecoder().decode([WindowInfo].self, from: Data(json.utf8))

            // Check if windows actually changed before updating and publishing
            let windowsChanged = dataQueue.sync { [weak self] () -> Bool in
                guard let self = self else { return false }
                let oldWindowIds = Set(self.windows.keys)
                let newWindowIds = Set(decoded.map { $0.id })

                // Quick check: different count or different IDs
                if oldWindowIds != newWindowIds {
                    return true
                }

                // Deeper check: compare focus state and space assignment
                for window in decoded {
                    if let oldWindow = self.windows[window.id] {
                        if oldWindow.hasFocus != window.hasFocus ||
                           oldWindow.space != window.space ||
                           oldWindow.isMinimized != window.isMinimized ||
                           oldWindow.stackIndex != window.stackIndex {
                            return true
                        }
                    }
                }
                return false
            }

            // Write to cache synchronously (barrier) so data is available before we return
            dataQueue.sync(flags: .barrier) { [weak self] in
                guard let self = self else { return }
                self.windows = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
                // Update window order cache when windows change
                self.updateWindowOrderCache()
            }

            // Only publish event if windows actually changed
            if windowsChanged {
                DispatchQueue.main.async { [weak self] in
                    self?.eventRouter.publish(.windowsChanged, data: ["windows": decoded])
                }
            }
        } catch {
            logError("yabai windows query failed: \(error)")
        }
    }

    // MARK: - Queries

    func getCurrentSpaces() -> [Space] {
        dataQueue.sync {
            Array(spaces.values).sorted { $0.index < $1.index }
        }
    }

    func getCurrentDisplays() -> [Display] {
        dataQueue.sync {
            Array(displays.values).sorted { $0.index < $1.index }
        }
    }

    func getSpacesForDisplay(_ displayIndex: Int) -> [Space] {
        dataQueue.sync {
            Array(spaces.values)
                .filter { $0.display == displayIndex }
                .sorted { $0.index < $1.index }
        }
    }

    func getWindow(_ id: Int) -> WindowInfo? {
        dataQueue.sync { windows[id] }
    }

    /// Check if any window on this space has focus (including excluded apps like launcher apps)
    /// Used to determine if the space indicator should show the active/highlighted state
    /// Note: We still check excluded apps here because an excluded app (like iTerm2) being focused
    /// should still highlight its space - we just don't show its icon in the indicator
    func spaceHasFocusedWindow(_ spaceIndex: Int) -> Bool {
        let excludedApps = AegisConfig.shared.baseExcludedApps  // Only base exclusions (Finder, Aegis)
        return dataQueue.sync {
            windows.values.contains { window in
                window.space == spaceIndex &&
                window.hasFocus &&
                !excludedApps.contains(window.app) &&  // Exclude base apps (Finder, Aegis) from focus check
                window.role == "AXWindow" &&
                (window.subrole == "AXStandardWindow" || window.isMinimized)
            }
        }
    }

    func getWindowIconsForSpace(_ spaceIndex: Int) -> [WindowIcon] {
        let excludedApps = AegisConfig.shared.excludedApps
        return dataQueue.sync {
            // Get filtered windows for this space
            let spaceWindows = windows.values
                .filter { $0.space == spaceIndex && !excludedApps.contains($0.app) && $0.role == "AXWindow" && ($0.subrole == "AXStandardWindow" || $0.isMinimized) }

            let currentWindowIds = Set(spaceWindows.map { $0.id })
            let cachedOrder = windowOrderCache[spaceIndex] ?? []

            // Check if we need to recalculate order (windows added or removed)
            let cachedIds = Set(cachedOrder)
            let needsRecalculation = currentWindowIds != cachedIds

            // Build the final order
            let orderedIds: [Int]
            if needsRecalculation {
                // Calculate fresh order using shared sorting logic
                let sorted = sortWindowsByPosition(Array(spaceWindows))
                orderedIds = sorted.map { $0.id }
            } else {
                // Use cached order (stable across focus changes)
                orderedIds = cachedOrder
            }

            // Create a lookup for window data
            let windowLookup = Dictionary(uniqueKeysWithValues: spaceWindows.map { ($0.id, $0) })

            // Build icons in the stable order, then apply active/inactive sorting
            let icons = orderedIds.compactMap { id -> WindowIcon? in
                guard let window = windowLookup[id] else { return nil }
                return WindowIcon(
                    id: window.id,
                    pid: window.pid,
                    title: window.title,
                    app: window.app,
                    appName: window.app,
                    icon: getAppIcon(for: window.app),
                    frame: window.frame,
                    hasFocus: window.hasFocus,
                    stackIndex: window.stackIndex,
                    isMinimized: window.isMinimized,
                    isHidden: window.isHidden
                )
            }

            // Final sort: active windows first, then inactive, preserving relative order within each group
            let activeIcons = icons.filter { !$0.isMinimized && !$0.isHidden }
            let inactiveIcons = icons.filter { $0.isMinimized || $0.isHidden }

            return activeIcons + inactiveIcons
        }
    }

    /// Sort windows by x-position, with stacked windows sorted by stack-index
    /// Shared sorting logic used by both getWindowIconsForSpace and updateWindowOrderCache
    private func sortWindowsByPosition(_ windows: [WindowInfo]) -> [WindowInfo] {
        windows.sorted { lhs, rhs in
            let lhsX = lhs.frame?.origin.x ?? CGFloat.greatestFiniteMagnitude
            let rhsX = rhs.frame?.origin.x ?? CGFloat.greatestFiniteMagnitude

            // Check if stacked (same x-position within tolerance)
            if abs(lhsX - rhsX) < 10 {
                // Stacked: sort by stack-index
                if lhs.stackIndex != rhs.stackIndex {
                    return lhs.stackIndex < rhs.stackIndex
                }
                return lhs.id < rhs.id
            }

            // Non-stacked: sort by x-position
            if lhsX != rhsX {
                return lhsX < rhsX
            }
            return lhs.id < rhs.id
        }
    }

    /// Update the cached window order for a space (call when windows are added/removed/moved)
    private func updateWindowOrderCache() {
        let excludedApps = AegisConfig.shared.excludedApps

        // Group windows by space and calculate order
        var newCache: [Int: [Int]] = [:]

        for (spaceIndex, _) in spaces {
            let spaceWindows = windows.values
                .filter { $0.space == spaceIndex && !excludedApps.contains($0.app) && $0.role == "AXWindow" && ($0.subrole == "AXStandardWindow" || $0.isMinimized) }

            let sorted = sortWindowsByPosition(Array(spaceWindows))
            newCache[spaceIndex] = sorted.map { $0.id }
        }

        windowOrderCache = newCache
    }

    /// Remove stale entries from windowOrderCache for spaces that no longer exist
    private func cleanupWindowOrderCache() {
        dataQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            let currentSpaceIndices = Set(self.spaces.values.map { $0.index })
            self.windowOrderCache = self.windowOrderCache.filter { currentSpaceIndices.contains($0.key) }
        }
    }

    func getAppIconsForSpace(_ spaceIndex: Int) -> [NSImage] {
        let excludedApps = AegisConfig.shared.excludedApps
        return dataQueue.sync {
            let apps = Set(windows.values
                .filter { $0.space == spaceIndex && !excludedApps.contains($0.app) && $0.role == "AXWindow" && $0.subrole == "AXStandardWindow" }
                .map { $0.app })
            return apps.compactMap { getAppIcon(for: $0) }
        }
    }

    // Cache app icons to avoid repeated disk I/O on every refresh
    // Limited to 100 entries to prevent unbounded growth
    private var appIconCache: [String: NSImage] = [:]
    private let appIconCacheLimit = 100

    func getAppIcon(for appName: String) -> NSImage? {
        // Check cache first
        if let cached = appIconCache[appName] {
            return cached
        }

        var icon: NSImage?

        // Try to get app icon from workspace
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appName) ??
                        NSWorkspace.shared.urlsForApplications(withBundleIdentifier: appName).first {
            icon = NSWorkspace.shared.icon(forFile: appURL.path)
        }

        // Fallback: try to find by app name
        if icon == nil {
            let runningApps = NSWorkspace.shared.runningApplications
            if let app = runningApps.first(where: { $0.localizedName == appName || $0.bundleIdentifier == appName }) {
                icon = app.icon
            }
        }

        // Cache the result with size limit
        if let icon = icon {
            // Clear oldest entries if cache is full (simple FIFO-ish behavior)
            if appIconCache.count >= appIconCacheLimit {
                // Remove ~20% of entries to avoid thrashing
                let keysToRemove = Array(appIconCache.keys.prefix(appIconCacheLimit / 5))
                keysToRemove.forEach { appIconCache.removeValue(forKey: $0) }
            }
            appIconCache[appName] = icon
        }

        return icon
    }

    // MARK: - Commands (ALL serialized)

    func focusSpace(_ index: Int) {
        Task {
            // Check if target space is native fullscreen
            // yabai's "space --focus" doesn't work for native fullscreen spaces
            // Instead, we focus a window on that space which switches to it
            let targetSpace = dataQueue.sync { spaces.values.first { $0.index == index } }

            if let space = targetSpace, space.isNativeFullscreen {
                // Find a window on this fullscreen space and focus it instead
                let windowOnSpace = dataQueue.sync { windows.values.first { $0.space == index } }
                if let window = windowOnSpace {
                    try? await command.run(["-m", "window", "--focus", "\(window.id)"])
                    return
                }
            }

            // Normal space focus for non-fullscreen spaces
            try? await command.run(["-m", "space", "--focus", "\(index)"])
        }
    }

    func focusWindow(_ id: Int) {
        Task {
            // Check if window is minimized - need to deminimize first
            let isMinimized = dataQueue.sync { windows[id]?.isMinimized ?? false }
            if isMinimized {
                try? await command.run(["-m", "window", "--deminimize", "\(id)"])
            }

            // yabai's "window --focus" works for fullscreen windows - it switches to the space
            try? await command.run(["-m", "window", "--focus", "\(id)"])
        }
    }

    /// Find and focus a window by app name (returns true if found and focused)
    func focusWindowByAppName(_ appName: String) -> Bool {
        // Find any window belonging to this app
        let windowId = dataQueue.sync {
            windows.values.first { $0.app == appName }?.id
        }

        guard let id = windowId else {
            return false
        }

        focusWindow(id)
        return true
    }

    func moveWindow(_ id: Int, toSpace index: Int) {
        Task {
            try? await command.run(["-m", "window", "\(id)", "--space", "\(index)"])
        }
    }

    /// Move window to space and focus it (for Finder toggle)
    func moveWindowToSpaceAndFocus(_ id: Int, spaceIndex: Int) {
        Task {
            // Move to current space first
            try? await command.run(["-m", "window", "\(id)", "--space", "\(spaceIndex)"])
            // Then focus the window
            try? await command.run(["-m", "window", "--focus", "\(id)"])
        }
    }

    /// Move window to space, ensure it's floating, then focus (for launcher apps)
    func moveWindowToSpaceFloatAndFocus(_ id: Int, spaceIndex: Int) {
        Task {
            // Move to space
            try? await command.run(["-m", "window", "\(id)", "--space", "\(spaceIndex)"])
            // Ensure floating (query first to avoid unnecessary toggle)
            if let output = try? await command.run(["-m", "query", "--windows", "--window", "\(id)"]),
               let data = output.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let isFloating = json["is-floating"] as? Bool,
               !isFloating {
                try? await command.run(["-m", "window", "\(id)", "--toggle", "float"])
            }
            // Focus
            try? await command.run(["-m", "window", "--focus", "\(id)"])
        }
    }

    /// Float window and center it using grid positioning (4:4:1:1:2:2 = center 50% of screen)
    func floatAndCenterWindow(_ id: Int) {
        Task {
            // First ensure it's floating
            if let output = try? await command.run(["-m", "query", "--windows", "--window", "\(id)"]),
               let data = output.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let isFloating = json["is-floating"] as? Bool,
               !isFloating {
                try? await command.run(["-m", "window", "\(id)", "--toggle", "float"])
            }
            // Center using grid: 4 rows, 4 cols, start at row 1 col 1, span 2x2
            try? await command.run(["-m", "window", "\(id)", "--grid", "4:4:1:1:2:2"])
            // Focus
            try? await command.run(["-m", "window", "--focus", "\(id)"])
        }
    }

    /// Get all windows from cache
    func getAllWindows() -> [WindowInfo] {
        dataQueue.sync {
            Array(windows.values)
        }
    }

    func createSpace() {
        logDebug("➕ Creating new space")
        Task {
            do {
                let output = try await command.run(["-m", "space", "--create"])
                logDebug("✅ Create space succeeded: \(output)")
                await refreshSpaces()

                // Focus the newly created space (it's always the last one)
                let spaces = getCurrentSpaces()
                if let lastSpace = spaces.last {
                    try? await command.run(["-m", "space", "--focus", "\(lastSpace.index)"])
                    logDebug("✅ Focused new space: \(lastSpace.index)")
                }
            } catch {
                logDebug("❌ Create space failed: \(error)")
            }
        }
    }

    func destroySpace(_ index: Int) {
        Task {
            // If destroying the focused space, focus the previous space first
            // (like closing a browser tab - focus moves left)
            let focusedSpace = getCurrentSpaces().first { $0.focused }
            if focusedSpace?.index == index && index > 1 {
                try? await command.run(["-m", "space", "--focus", "\(index - 1)"])
            }

            try? await command.run(["-m", "space", "\(index)", "--destroy"])
            await refreshSpaces()
        }
    }

    func moveSpace(_ fromIndex: Int, toIndex: Int) {
        Task {
            do {
                let output = try await command.run(["-m", "space", "\(fromIndex)", "--move", "\(toIndex)"])
                logDebug("✅ Move space succeeded: \(output)")
                await refreshSpaces()
            } catch {
                logDebug("❌ Move space failed: \(error)")
            }
        }
    }

    func rotateLayout(_ degrees: Int) {
        logDebug("🔄 Rotating layout: \(degrees)°")
        Task {
            do {
                let output = try await command.run(["-m", "space", "--rotate", "\(degrees)"])
                logDebug("✅ Rotate layout succeeded: \(output)")
            } catch {
                logDebug("❌ Rotate layout failed: \(error)")
            }
        }
    }

    func balanceLayout() {
        logDebug("⚖️ Balancing layout")
        Task {
            do {
                let output = try await command.run(["-m", "space", "--balance"])
                logDebug("✅ Balance layout succeeded: \(output)")
            } catch {
                logDebug("❌ Balance layout failed: \(error)")
            }
        }
    }

    func toggleLayout() {
        guard let focused = getCurrentSpaces().first(where: { $0.focused }) else {
            logDebug("❌ Toggle layout: No focused space found")
            return
        }
        let new = focused.type == "bsp" ? "float" : "bsp"
        logDebug("🔄 Toggling layout from \(focused.type) to \(new)")

        Task {
            do {
                let output = try await command.run(["-m", "space", "--layout", new])
                logDebug("✅ Toggle layout succeeded: \(output)")
                await refreshSpaces()
            } catch {
                logDebug("❌ Toggle layout failed: \(error)")
            }
        }
    }

    func flipLayout(axis: String) {
        // Convert "x" to "x-axis" and "y" to "y-axis" for yabai
        let yabaiAxis = axis == "x" ? "x-axis" : "y-axis"
        logDebug("🔄 Flipping layout on axis: \(yabaiAxis)")
        Task {
            do {
                let output = try await command.run(["-m", "space", "--mirror", yabaiAxis])
                logDebug("✅ Flip layout succeeded: \(output)")
            } catch {
                logDebug("❌ Flip layout failed: \(error)")
            }
        }
    }

    func toggleStackAllWindowsInCurrentSpace() {
        Task {
            do {
                // Query yabai directly to get the actual focused space (cache may be stale)
                let focusedSpaceIndex = getFocusedSpaceIndexSync()

                let spaceWindows = windows.values.filter { $0.space == focusedSpaceIndex }

                guard spaceWindows.count >= 2 else { return }

                // Check if any windows are already stacked
                let hasStacks = spaceWindows.contains { $0.stackIndex > 0 }

                if hasStacks {
                    // Unstack: warp each stacked window to separate them
                    let stackWindows = spaceWindows.filter { $0.stackIndex > 0 }.sorted { $0.stackIndex < $1.stackIndex }

                    // Try warping each stacked window in different directions to separate them
                    let directions = ["east", "south", "west", "north"]
                    var warpWorked = false

                    for (index, window) in stackWindows.enumerated() {
                        let direction = directions[index % directions.count]

                        // Focus the window first
                        try? await command.run(["-m", "window", "--focus", "\(window.id)"])

                        // Try to warp it out of the stack
                        let output = try await command.run(["-m", "window", "--warp", direction])

                        // Check if warp actually worked (output contains error message if it failed)
                        if output.contains("could not locate") {
                            logDebug("⚠️ Warp \(direction) failed for window \(window.id): \(output)")
                        } else {
                            logDebug("✅ Warped window \(window.id) \(direction)")
                            warpWorked = true
                        }
                    }

                    // If no warps worked, use float toggle as fallback
                    if !warpWorked {
                        logDebug("⚠️ All warp attempts failed, using float toggle fallback")
                        for window in stackWindows {
                            try? await command.run(["-m", "window", "--focus", "\(window.id)"])
                            try? await command.run(["-m", "window", "\(window.id)", "--toggle", "float"])
                            // Small delay to let the float state register
                            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                            try? await command.run(["-m", "window", "\(window.id)", "--toggle", "float"])
                            logDebug("✅ Float toggled window \(window.id)")
                        }
                    }

                    logDebug("✅ Unstacked all windows in space \(focusedSpaceIndex)")
                } else {
                    // Stack all windows onto the first one
                    let sortedWindows = spaceWindows.sorted { $0.id < $1.id }
                    guard let firstWindow = sortedWindows.first else { return }

                    for window in sortedWindows.dropFirst() {
                        let output = try await command.run(["-m", "window", "\(window.id)", "--stack", "\(firstWindow.id)"])
                        logDebug("✅ Stacked window \(window.id) onto \(firstWindow.id): \(output)")
                        // Small delay to let Yabai process the stack before the next one
                        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                    }
                }

                await refreshWindows()
            } catch {
                logDebug("❌ Toggle stack failed: \(error)")
            }
        }
    }

    func getWindowSpace(_ windowId: Int) -> Int? {
        dataQueue.sync {
            windows[windowId]?.space
        }
    }

    func moveWindowToSpace(_ windowId: Int, spaceIndex: Int, insertBeforeWindowId: Int?, shouldStack: Bool) {
        Task {
            // Move window to space
            try? await command.run(["-m", "window", "\(windowId)", "--space", "\(spaceIndex)"])

            if shouldStack, let beforeId = insertBeforeWindowId {
                // Stack with another window
                try? await command.run(["-m", "window", "\(windowId)", "--stack", "\(beforeId)"])
            } else if let beforeId = insertBeforeWindowId {
                // Insert before specific window
                try? await command.run(["-m", "window", "\(windowId)", "--insert", "\(beforeId)"])
            }

            await refreshWindows()
        }
    }

    /// Stack a specific window onto another window
    func stackWindow(_ sourceId: Int, onto targetId: Int) {
        Task {
            do {
                // Deminimize source if needed (no-op if not minimized)
                try? await command.run(["-m", "window", "--deminimize", "\(sourceId)"])
                try? await Task.sleep(nanoseconds: 100_000_000)
                // Use --insert stack + --warp pattern for reliable stack insertion
                // This tells yabai the next insertion at target's node should be a stack
                try? await command.run(["-m", "window", "\(targetId)", "--insert", "stack"])
                _ = try await command.run(["-m", "window", "\(sourceId)", "--warp", "\(targetId)"])
                await refreshWindows()
            } catch {
                logDebug("❌ Stack window failed: \(error)")
            }
        }
    }

    /// Stack all windows in the current space onto a target window
    func stackAllWindowsOnto(_ targetId: Int) {
        Task {
            do {
                let focusedSpaceIndex = getFocusedSpaceIndexSync()
                let spaceWindows = dataQueue.sync {
                    windows.values.filter { $0.space == focusedSpaceIndex && $0.id != targetId }
                }

                for window in spaceWindows {
                    // Deminimize if needed
                    if window.isMinimized {
                        try? await command.run(["-m", "window", "--deminimize", "\(window.id)"])
                        try? await Task.sleep(nanoseconds: 100_000_000)
                    }
                    // Use --insert stack + --warp for reliable stack insertion
                    try? await command.run(["-m", "window", "\(targetId)", "--insert", "stack"])
                    _ = try await command.run(["-m", "window", "\(window.id)", "--warp", "\(targetId)"])
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }

                await refreshWindows()
            } catch {
                logDebug("❌ Stack all windows failed: \(error)")
            }
        }
    }

    // MARK: - Additional helper methods

    private static var lastFocusedSpaceQuery = Date.distantPast
    private static var cachedFocusedSpaceIndex = 1
    private static var cachedFocusedSpace: Space?
    private static let focusedSpaceQueryThrottle: TimeInterval = 0.1 // Max 10 queries/sec

    /// Query yabai directly (blocking) for the currently focused space index.
    /// Unlike getFocusedSpaceIndexSync(), this always runs a fresh yabai query.
    func queryFocusedSpaceIndexSync() -> Int {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/yabai")
        task.arguments = ["-m", "query", "--spaces", "--space"]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        task.standardOutput = stdoutPipe
        task.standardError = stderrPipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let spaceData = try JSONDecoder().decode(Space.self, from: data)
            Self.cachedFocusedSpaceIndex = spaceData.index
            Self.cachedFocusedSpace = spaceData
            return spaceData.index
        } catch {
            logDebug("❌ queryFocusedSpaceIndexSync failed: \(error)")
        }
        return Self.cachedFocusedSpaceIndex
    }

    func getFocusedSpaceIndexSync() -> Int {
        return queryFocusedSpaceIndexSync()
    }

    /// Query yabai for the currently focused space (uses cache, refreshes in background)
    /// Use this when you need accurate space type information (e.g., for fullscreen detection)
    /// Set forceRefresh to true to bypass the throttle (use sparingly)
    func getFocusedSpaceSync(forceRefresh: Bool = false) -> Space? {
        // Rate limit: return cached value if queried too recently (unless forced)
        let now = Date()
        if !forceRefresh && now.timeIntervalSince(Self.lastFocusedSpaceQuery) < Self.focusedSpaceQueryThrottle {
            // Return from static cache if available
            if let cached = Self.cachedFocusedSpace {
                return cached
            }
            // Fallback to spaces dictionary
            return dataQueue.sync { spaces.values.first { $0.index == Self.cachedFocusedSpaceIndex } }
        }
        Self.lastFocusedSpaceQuery = now

        // Return cached value immediately, refresh in background to avoid blocking main thread
        let cachedResult = Self.cachedFocusedSpace ?? dataQueue.sync { spaces.values.first { $0.index == Self.cachedFocusedSpaceIndex } }

        // Refresh cache in background (non-blocking)
        DispatchQueue.global(qos: .userInitiated).async {
            self.refreshFocusedSpaceCache()
        }

        return cachedResult
    }

    /// Background refresh of focused space cache - called asynchronously to avoid blocking main thread
    private func refreshFocusedSpaceCache() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/yabai")
        task.arguments = ["-m", "query", "--spaces", "--space"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let json = String(decoding: data, as: UTF8.self)

            if let spaceData = try? JSONDecoder().decode(Space.self, from: Data(json.utf8)) {
                Self.cachedFocusedSpaceIndex = spaceData.index
                Self.cachedFocusedSpace = spaceData
            }
        } catch {
            logDebug("❌ Failed to get focused space: \(error)")
        }
    }

    /// Invalidate the focused space cache (call when space changes to ensure fresh data on next query)
    func invalidateFocusedSpaceCache() {
        Self.lastFocusedSpaceQuery = .distantPast
        Self.cachedFocusedSpace = nil
    }

    func getYabaiVersion() -> String {
        // Synchronously get yabai version
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/yabai")
        task.arguments = ["--version"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return output.isEmpty ? "Unknown" : output
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    /// Query yabai synchronously for fresh window data in a specific space.
    /// Used by the context menu to get accurate stack-index values.
    func queryWindowsForSpaceSync(_ spaceIndex: Int) -> [WindowInfo] {
        let excludedApps = AegisConfig.shared.excludedApps
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/yabai")
        task.arguments = ["-m", "query", "--windows", "--space", "\(spaceIndex)"]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        task.standardOutput = stdoutPipe
        task.standardError = stderrPipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let decoded = try JSONDecoder().decode([WindowInfo].self, from: data)
            let filtered = decoded.filter {
                $0.role == "AXWindow"
                && ($0.subrole == "AXStandardWindow" || $0.isMinimized)
                && !excludedApps.contains($0.app)
            }
            logDebug("📋 queryWindowsForSpaceSync(space:\(spaceIndex)): \(filtered.count) windows, stackIndexes: \(filtered.map { "\($0.app):\($0.stackIndex)" })")
            return filtered
        } catch {
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(decoding: errData, as: UTF8.self)
            logDebug("❌ queryWindowsForSpaceSync(space:\(spaceIndex)) failed: \(error), stderr: \(errStr)")
            return []
        }
    }

    /// Unstack specific windows by warping them out of their stack
    func unstackWindows(_ windowIds: [Int]) {
        Task {
            let directions = ["east", "south", "west", "north"]
            var warpWorked = false

            for (index, windowId) in windowIds.enumerated() {
                let direction = directions[index % directions.count]

                // Focus the window first
                try? await command.run(["-m", "window", "--focus", "\(windowId)"])

                // Try to warp it out of the stack
                let output = try await command.run(["-m", "window", "--warp", direction])

                if output.contains("could not locate") {
                    logDebug("⚠️ Warp \(direction) failed for window \(windowId)")
                } else {
                    logDebug("✅ Warped window \(windowId) \(direction)")
                    warpWorked = true
                }
            }

            // Float toggle fallback if warps failed
            if !warpWorked {
                for windowId in windowIds {
                    try? await command.run(["-m", "window", "--focus", "\(windowId)"])
                    try? await command.run(["-m", "window", "\(windowId)", "--toggle", "float"])
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    try? await command.run(["-m", "window", "\(windowId)", "--toggle", "float"])
                }
            }

            await refreshWindows()
        }
    }

    func executeYabai(args: [String], completion: @escaping (Result<String, Error>) -> Void) {
        Task {
            do {
                let result = YabaiCLIExecutionPolicy.result(try await command.runWithStatus(args))
                DispatchQueue.main.async {
                    completion(result)
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
}
