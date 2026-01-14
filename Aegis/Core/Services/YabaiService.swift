import Foundation
import AppKit   // Only needed if you're using NSImage, NSWorkspace, etc.


// MARK: - YabaiService (SAFE, EVENT-DRIVEN)

final class YabaiService {

    private let eventRouter: EventRouter
    private let command = YabaiCommandActor.shared

    private var spaces: [Int: Space] = [:]
    private var windows: [Int: WindowInfo] = [:]

    private let dataQueue = DispatchQueue(label: "com.aegis.yabai.data", attributes: .concurrent)

    // FIFO
    private var pipeSource: DispatchSourceRead?
    private var pipeFD: Int32 = -1

    private let pipeQueue = DispatchQueue(label: "com.aegis.yabai.pipe")

    // Debounce tracking to prevent multiple rapid refreshes causing UI flash
    private var lastRefreshTime: Date = .distantPast
    private let refreshDebounceInterval: TimeInterval = 0.3  // 300ms debounce

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
    }

    @objc private func appChanged(_ notification: Notification) {
        // App activation might indicate a space change (clicking window on another space)
        // Skip if Aegis itself is being activated (happens when clicking on Aegis UI)
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           app.bundleIdentifier == Bundle.main.bundleIdentifier {
            print("🔄 [DEBUG] appChanged triggered (NSWorkspace) - SKIPPED (Aegis self-activation)")
            return
        }

        print("🔄 [DEBUG] appChanged triggered (NSWorkspace)")
        // Delay refresh to allow yabai to update its internal state
        // Without this delay, yabai returns stale focused space data
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            Task { await self?.refreshAll(source: "appChanged") }
        }
    }

    // MARK: - Events

    private func handleYabaiEvent(_ event: String) async {
        print("🔄 [DEBUG] FIFO event: '\(event)'")
        switch event {
        case "space_changed", "space_created", "space_destroyed":
            await refreshAll(source: "FIFO:\(event)")
        case "window_focused":
            // Window focus may change the active space (e.g., clicking a window on another space)
            // Refresh both spaces and windows to ensure focus state is accurate
            await refreshAll(source: "FIFO:window_focused")
        case "window_created", "window_destroyed", "window_moved":
            print("🔄 [DEBUG] refreshWindows from FIFO:\(event)")
            await refreshWindows()
        default:
            await refreshAll(source: "FIFO:default(\(event))")
        }
    }

    // MARK: - Refresh

    private func refreshAll(source: String = "unknown") async {
        // Debounce: skip if we refreshed very recently
        let now = Date()
        let timeSinceLast = now.timeIntervalSince(lastRefreshTime)
        if timeSinceLast < refreshDebounceInterval {
            print("🔄 [DEBUG] refreshAll SKIPPED (debounce) - source: \(source), timeSinceLast: \(String(format: "%.3f", timeSinceLast))s")
            return
        }
        lastRefreshTime = now
        print("🔄 [DEBUG] refreshAll EXECUTING - source: \(source)")

        await refreshSpaces()
        await refreshWindows()
    }

    private func refreshSpaces() async {
        do {
            let json = try await command.run(["-m", "query", "--spaces"])
            let decoded = try JSONDecoder().decode([Space].self, from: Data(json.utf8))

            // Debug: log which space yabai reports as focused
            if let focusedSpace = decoded.first(where: { $0.focused }) {
                print("🔄 [DEBUG] refreshSpaces: yabai reports space \(focusedSpace.index) as focused")
            } else {
                print("🔄 [DEBUG] refreshSpaces: NO focused space reported by yabai!")
            }

            // Write to cache first, then publish event AFTER write completes
            // This prevents race condition where event fires before data is ready
            dataQueue.async(flags: .barrier) { [weak self] in
                self?.spaces = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })

                // Publish event on main queue AFTER cache write completes
                DispatchQueue.main.async {
                    self?.eventRouter.publish(.spaceChanged, data: ["spaces": decoded])
                }
            }
        } catch {
            print("❌ yabai spaces failed:", error)
        }
    }

    private func refreshWindows() async {
        do {
            let json = try await command.run(["-m", "query", "--windows"])
            let decoded = try JSONDecoder().decode([WindowInfo].self, from: Data(json.utf8))

            // Write to cache first, then publish event AFTER write completes
            dataQueue.async(flags: .barrier) { [weak self] in
                self?.windows = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })

                // Publish event on main queue AFTER cache write completes
                DispatchQueue.main.async {
                    self?.eventRouter.publish(.windowsChanged, data: ["windows": decoded])
                }
            }
        } catch {
            print("❌ yabai windows failed:", error)
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

    func getWindowIconsForSpace(_ spaceIndex: Int) -> [WindowIcon] {
        let excludedApps = AegisConfig.shared.excludedApps
        return dataQueue.sync {
            windows.values
                // Filter to only real windows (AXWindow role), exclude popups/panels (AXGroup)
                .filter { $0.space == spaceIndex && !excludedApps.contains($0.app) && $0.role == "AXWindow" }
                .map { window in
                    WindowIcon(
                        id: window.id,
                        title: window.title,
                        app: window.app,
                        appName: window.app,  // Use app name as display name
                        icon: getAppIcon(for: window.app),
                        frame: window.frame,
                        hasFocus: window.hasFocus,
                        stackIndex: window.stackIndex
                    )
                }
                .sorted { lhs, rhs in
                    // Sort by x-position (left to right) to match desktop layout
                    // If frames are missing, fall back to ID sorting
                    guard let lhsFrame = lhs.frame, let rhsFrame = rhs.frame else {
                        return lhs.id < rhs.id
                    }
                    return lhsFrame.origin.x < rhsFrame.origin.x
                }
        }
    }

    func getAppIconsForSpace(_ spaceIndex: Int) -> [NSImage] {
        let excludedApps = AegisConfig.shared.excludedApps
        return dataQueue.sync {
            let apps = Set(windows.values
                .filter { $0.space == spaceIndex && !excludedApps.contains($0.app) && $0.role == "AXWindow" }
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
            try? await command.run(["-m", "space", "--focus", "\(index)"])
        }
    }

    func focusWindow(_ id: Int) {
        Task {
            try? await command.run(["-m", "window", "--focus", "\(id)"])
        }
    }

    func moveWindow(_ id: Int, toSpace index: Int) {
        Task {
            try? await command.run(["-m", "window", "\(id)", "--space", "\(index)"])
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
    private static let focusedSpaceQueryThrottle: TimeInterval = 0.1 // Max 10 queries/sec

    func getFocusedSpaceIndexSync() -> Int {
        // Rate limit: return cached value if queried too recently
        let now = Date()
        if now.timeIntervalSince(Self.lastFocusedSpaceQuery) < Self.focusedSpaceQueryThrottle {
            return Self.cachedFocusedSpaceIndex
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
                return spaceData.index
            }
        } catch {
            print("❌ Failed to get focused space: \(error)")
        }

        return Self.cachedFocusedSpaceIndex // Fallback to cached value
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
