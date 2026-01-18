import Foundation
import AppKit


// MARK: - YabaiService (SAFE, EVENT-DRIVEN)

final class YabaiService {

    private let eventRouter: EventRouter
    private let command = YabaiCommandActor.shared

    private var spaces: [Int: Space] = [:]
    private var windows: [Int: WindowInfo] = [:]

    // Cache window order per space to prevent shuffling on focus changes
    // Key: space index, Value: ordered array of window IDs
    private var windowOrderCache: [Int: [Int]] = [:]

    private let dataQueue = DispatchQueue(label: "com.aegis.yabai.data", attributes: .concurrent)

    // FIFO
    private var pipeSource: DispatchSourceRead?
    private var pipeFD: Int32 = -1

    private let pipeQueue = DispatchQueue(label: "com.aegis.yabai.pipe")

    // Debounce tracking to prevent multiple rapid refreshes
    private var lastRefreshTime: Date = .distantPast
    private let refreshDebounceInterval: TimeInterval = 0.1  // 100ms debounce for normal refreshes

    private lazy var pipePath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/aegis/yabai.pipe"
    }()

    // MARK: - Init

    init(eventRouter: EventRouter) {
        self.eventRouter = eventRouter
        logInfo("YabaiService initializing")

        Task {
            await refreshAll()
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

        pipeFD = open(pipePath, O_RDONLY | O_NONBLOCK)
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

        let event = String(decoding: buffer.prefix(count), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // print("📨 FIFO received yabai event: '\(event)'")
        Task { await handleYabaiEvent(event) }
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
        // Invalidate cache since we're switching spaces
        invalidateFocusedSpaceCache()
        // Delay refresh to allow yabai to update its internal state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            Task { await self?.refreshAll(source: "activeSpaceChanged", forceRefresh: true) }
        }
    }

    @objc private func appChanged(_ notification: Notification) {
        // App activation might indicate a space change (clicking window on another space)
        // Skip if Aegis itself is being activated (happens when clicking on Aegis UI)
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           app.bundleIdentifier == Bundle.main.bundleIdentifier {
            return
        }

        // Delay refresh to allow yabai to update its internal state
        // Without this delay, yabai returns stale focused space data
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            Task { await self?.refreshAll(source: "appChanged") }
        }
    }

    // MARK: - Events

    private func handleYabaiEvent(_ event: String) async {
        switch event {
        case "space_changed":
            // Space changes are critical for UI - always force refresh to update focus indicator
            invalidateFocusedSpaceCache()
            await refreshAll(source: "FIFO:space_changed", forceRefresh: true)
        case "space_created", "space_destroyed":
            invalidateFocusedSpaceCache()
            // Clean up stale window order cache entries for destroyed spaces
            cleanupWindowOrderCache()
            await refreshAll(source: "FIFO:\(event)")
        case "window_focused":
            // Window focus may change the active space (e.g., clicking a window on another space)
            invalidateFocusedSpaceCache()
            await refreshAll(source: "FIFO:window_focused", forceRefresh: true)
        case "window_created", "window_destroyed", "window_moved":
            await refreshWindows()
        default:
            invalidateFocusedSpaceCache()
            await refreshAll(source: "FIFO:default(\(event))")
        }
    }

    // MARK: - Refresh

    private func refreshAll(source: String = "unknown", forceRefresh: Bool = false) async {
        // Debounce: skip if we refreshed very recently (unless forced)
        let now = Date()
        let timeSinceLast = now.timeIntervalSince(lastRefreshTime)
        if !forceRefresh && timeSinceLast < refreshDebounceInterval {
            return
        }
        lastRefreshTime = now

        // Run both queries in parallel for better performance
        async let spacesTask: () = refreshSpaces()
        async let windowsTask: () = refreshWindows()
        _ = await (spacesTask, windowsTask)
    }

    private func refreshSpaces() async {
        do {
            let json = try await command.run(["-m", "query", "--spaces"])
            let decoded = try JSONDecoder().decode([Space].self, from: Data(json.utf8))

            // Write to cache synchronously (barrier) so data is available before we return
            dataQueue.sync(flags: .barrier) { [weak self] in
                self?.spaces = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
            }

            // Publish event on main queue AFTER cache write completes
            DispatchQueue.main.async { [weak self] in
                self?.eventRouter.publish(.spaceChanged, data: ["spaces": decoded])
            }
        } catch {
            logError("yabai spaces query failed: \(error)")
        }
    }

    private func refreshWindows() async {
        do {
            let json = try await command.run(["-m", "query", "--windows"])
            let decoded = try JSONDecoder().decode([WindowInfo].self, from: Data(json.utf8))

            // Write to cache synchronously (barrier) so data is available before we return
            dataQueue.sync(flags: .barrier) { [weak self] in
                guard let self = self else { return }
                self.windows = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
                // Update window order cache when windows change
                self.updateWindowOrderCache()
            }

            // Publish event on main queue AFTER cache write completes
            DispatchQueue.main.async { [weak self] in
                self?.eventRouter.publish(.windowsChanged, data: ["windows": decoded])
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

    private func getAppIcon(for appName: String) -> NSImage? {
        // Try to get app icon from workspace
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appName) ??
                        NSWorkspace.shared.urlsForApplications(withBundleIdentifier: appName).first {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }
        // Fallback: try to find by app name
        let runningApps = NSWorkspace.shared.runningApplications
        if let app = runningApps.first(where: { $0.localizedName == appName || $0.bundleIdentifier == appName }) {
            return app.icon
        }
        return nil
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

    /// Get all windows from cache
    func getAllWindows() -> [WindowInfo] {
        dataQueue.sync {
            Array(windows.values)
        }
    }

    func createSpace() {
        print("➕ Creating new space")
        Task {
            do {
                let output = try await command.run(["-m", "space", "--create"])
                print("✅ Create space succeeded: \(output)")
                await refreshSpaces()

                // Focus the newly created space (it's always the last one)
                let spaces = getCurrentSpaces()
                if let lastSpace = spaces.last {
                    try? await command.run(["-m", "space", "--focus", "\(lastSpace.index)"])
                    print("✅ Focused new space: \(lastSpace.index)")
                }
            } catch {
                print("❌ Create space failed: \(error)")
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

    func rotateLayout(_ degrees: Int) {
        print("🔄 Rotating layout: \(degrees)°")
        Task {
            do {
                let output = try await command.run(["-m", "space", "--rotate", "\(degrees)"])
                print("✅ Rotate layout succeeded: \(output)")
            } catch {
                print("❌ Rotate layout failed: \(error)")
            }
        }
    }

    func balanceLayout() {
        print("⚖️ Balancing layout")
        Task {
            do {
                let output = try await command.run(["-m", "space", "--balance"])
                print("✅ Balance layout succeeded: \(output)")
            } catch {
                print("❌ Balance layout failed: \(error)")
            }
        }
    }

    func toggleLayout() {
        guard let focused = getCurrentSpaces().first(where: { $0.focused }) else {
            print("❌ Toggle layout: No focused space found")
            return
        }
        let new = focused.type == "bsp" ? "float" : "bsp"
        print("🔄 Toggling layout from \(focused.type) to \(new)")

        Task {
            do {
                let output = try await command.run(["-m", "space", "--layout", new])
                print("✅ Toggle layout succeeded: \(output)")
                await refreshSpaces()
            } catch {
                print("❌ Toggle layout failed: \(error)")
            }
        }
    }

    func flipLayout(axis: String) {
        // Convert "x" to "x-axis" and "y" to "y-axis" for yabai
        let yabaiAxis = axis == "x" ? "x-axis" : "y-axis"
        print("🔄 Flipping layout on axis: \(yabaiAxis)")
        Task {
            do {
                let output = try await command.run(["-m", "space", "--mirror", yabaiAxis])
                print("✅ Flip layout succeeded: \(output)")
            } catch {
                print("❌ Flip layout failed: \(error)")
            }
        }
    }

    func toggleStackAllWindowsInCurrentSpace() {
        print("📚 Toggling stack for all windows in current space")
        Task {
            do {
                // Query yabai directly to get the actual focused space (cache may be stale)
                let focusedSpaceIndex = getFocusedSpaceIndexSync()
                print("🔍 Focused space index: \(focusedSpaceIndex)")

                let spaceWindows = windows.values.filter { $0.space == focusedSpaceIndex }
                print("🔍 Found \(spaceWindows.count) windows on space \(focusedSpaceIndex)")
                print("🔍 Window IDs: \(spaceWindows.map { $0.id })")
                print("🔍 Stack indices: \(spaceWindows.map { "\($0.id):\($0.stackIndex)" })")

                guard spaceWindows.count >= 2 else {
                    print("❌ Need at least 2 windows to stack (found \(spaceWindows.count))")
                    return
                }

                // Check if any windows are already stacked
                let hasStacks = spaceWindows.contains { $0.stackIndex > 0 }

                if hasStacks {
                    // Unstack: warp each stacked window to separate them
                    let stackWindows = spaceWindows.filter { $0.stackIndex > 0 }.sorted { $0.stackIndex < $1.stackIndex }

                    print("🔓 Unstacking \(stackWindows.count) windows")

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
                            print("⚠️ Warp \(direction) failed for window \(window.id): \(output)")
                        } else {
                            print("✅ Warped window \(window.id) \(direction)")
                            warpWorked = true
                        }
                    }

                    // If no warps worked, use float toggle as fallback
                    if !warpWorked {
                        print("⚠️ All warp attempts failed, using float toggle fallback")
                        for window in stackWindows {
                            try? await command.run(["-m", "window", "--focus", "\(window.id)"])
                            try? await command.run(["-m", "window", "\(window.id)", "--toggle", "float"])
                            // Small delay to let the float state register
                            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                            try? await command.run(["-m", "window", "\(window.id)", "--toggle", "float"])
                            print("✅ Float toggled window \(window.id)")
                        }
                    }

                    print("✅ Unstacked all windows in space \(focusedSpaceIndex)")
                } else {
                    // Stack all windows onto the first one
                    let sortedWindows = spaceWindows.sorted { $0.id < $1.id }
                    guard let firstWindow = sortedWindows.first else { return }

                    for window in sortedWindows.dropFirst() {
                        let output = try await command.run(["-m", "window", "\(window.id)", "--stack", "\(firstWindow.id)"])
                        print("✅ Stacked window \(window.id) onto \(firstWindow.id): \(output)")
                        // Small delay to let Yabai process the stack before the next one
                        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                    }
                }

                await refreshWindows()
            } catch {
                print("❌ Toggle stack failed: \(error)")
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
        print("📚 Stacking window \(sourceId) onto \(targetId)")
        Task {
            do {
                let output = try await command.run(["-m", "window", "\(sourceId)", "--stack", "\(targetId)"])
                print("✅ Stack succeeded: \(output)")
                await refreshWindows()
            } catch {
                print("❌ Stack window failed: \(error)")
            }
        }
    }

    /// Stack all windows in the current space onto a target window
    func stackAllWindowsOnto(_ targetId: Int) {
        print("📚 Stacking all windows onto \(targetId)")
        Task {
            do {
                let focusedSpaceIndex = getFocusedSpaceIndexSync()
                let spaceWindows = windows.values.filter { $0.space == focusedSpaceIndex && $0.id != targetId }

                for window in spaceWindows {
                    let output = try await command.run(["-m", "window", "\(window.id)", "--stack", "\(targetId)"])
                    print("✅ Stacked window \(window.id) onto \(targetId): \(output)")
                    // Small delay to let Yabai process each stack operation
                    try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                }

                await refreshWindows()
            } catch {
                print("❌ Stack all windows failed: \(error)")
            }
        }
    }

    // MARK: - Additional helper methods

    private static var lastFocusedSpaceQuery = Date.distantPast
    private static var cachedFocusedSpaceIndex = 1
    private static var cachedFocusedSpace: Space?
    private static let focusedSpaceQueryThrottle: TimeInterval = 0.1 // Max 10 queries/sec

    func getFocusedSpaceIndexSync() -> Int {
        return getFocusedSpaceSync()?.index ?? Self.cachedFocusedSpaceIndex
    }

    /// Query yabai synchronously for the currently focused space (fresh data, not cached)
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

        // Synchronously query yabai for the focused space
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
                return spaceData
            }
        } catch {
            print("❌ Failed to get focused space: \(error)")
        }

        // Fallback to cached data
        return Self.cachedFocusedSpace ?? dataQueue.sync { spaces.values.first { $0.index == Self.cachedFocusedSpaceIndex } }
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

    func executeYabai(args: [String], completion: @escaping (Result<String, Error>) -> Void) {
        Task {
            do {
                let output = try await command.run(args)
                DispatchQueue.main.async {
                    completion(.success(output))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
}
