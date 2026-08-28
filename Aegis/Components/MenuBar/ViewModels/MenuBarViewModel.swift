import SwiftUI
import AppKit
import Combine

// MARK: - Menu Bar ViewModel
// State-only view model for menu bar data
// Uses split state architecture for optimized re-renders

class MenuBarViewModel: ObservableObject {
    // MARK: - Split State Architecture

    /// Per-space ViewModels - each SpaceIndicatorView observes only its own SpaceViewModel
    let spaceStore: SpaceViewModelStore

    /// Shared state for cross-space coordination (drag, expansion, HUD)
    let sharedState: SharedMenuBarState

    // MARK: - Display Filtering

    /// Display index this view model is associated with (nil = show all spaces)
    var displayIndex: Int?

    /// Target screen for this menu bar (for notch detection)
    var targetScreen: NSScreen?

    /// Space filter mode (set by DisplayMenuBarManager based on config)
    var spaceFilterMode: SpaceFilterMode = .all

    enum SpaceFilterMode {
        case all          // Show all spaces on all monitors
        case perMonitor   // Show only spaces belonging to this monitor
    }

    // MARK: - Internal State (not directly observed by views)

    /// Whether the focused space is fullscreen (pre-computed during performUpdate)
    private(set) var isFocusedSpaceFullscreen: Bool = false

    /// Called by performUpdate when fullscreen state changes
    var onFullscreenStateChanged: ((Bool) -> Void)?

    /// Seed the initial fullscreen state so the change-detection diff works correctly
    /// after a rebuild. Called by the coordinator immediately after show().
    func seedFullscreenState(_ isFullscreen: Bool) {
        isFocusedSpaceFullscreen = isFullscreen
    }

    /// Raw spaces data from window manager
    private var spaces: [WMSpace] = []

    /// Window icons keyed by space index
    private var windowIconsBySpace: [Int: [WindowIcon]] = [:]

    /// All window icons (including overflow) keyed by space index
    private var allWindowIconsBySpace: [Int: [WindowIcon]] = [:]

    /// Pre-computed focused window index per space
    private var focusedIndexBySpace: [Int: Int] = [:]

    /// Last confirmed occupancy, retained across incomplete WM refreshes.
    private var knownWindowCounts: [Int: Int] = [:]

    // MARK: - Services & Timers

    let windowManager: WindowManagerProtocol  // Made public for context menu
    private var updateTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let titleObserver = WindowTitleObserver()

    // Coalesce rapid updates to prevent double flash
    private var pendingUpdateWorkItem: DispatchWorkItem?
    private let updateCoalesceDelay: TimeInterval = 0.05  // 50ms coalesce window

    init(windowManager: WindowManagerProtocol, targetScreen: NSScreen? = nil) {
        self.windowManager = windowManager
        self.targetScreen = targetScreen
        self.spaceStore = SpaceViewModelStore()
        self.sharedState = SharedMenuBarState()

        // Initial load
        performUpdate()

        // Initialize HUD layout coordinator with screen dimensions
        let screen = targetScreen ?? NSScreen.main
        if let screen = screen {
            let notchDimensions = NotchDimensions.calculate(for: screen)
            self.sharedState.hudLayoutCoordinator = HUDLayoutCoordinator(
                notchDimensions: notchDimensions,
                screenWidth: screen.frame.width
            )
        }

        // Backup polling as safety net (event-driven updates are primary)
        // Extended to 60 seconds since events from YabaiService should handle most updates
        updateTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.updateSpaces()
        }

        // Observe config changes to refresh when maxAppIconsPerSpace changes
        AegisConfig.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleCoalescedUpdate()
            }
            .store(in: &cancellables)
    }

    deinit {
        updateTimer?.invalidate()
        pendingUpdateWorkItem?.cancel()
    }

    // MARK: - Update methods

    func updateSpaces() {
        // Coalesce with any pending window updates to prevent double flash
        scheduleCoalescedUpdate()
    }

    /// Internal method that performs the actual update
    private func performUpdate() {
        // Fetch data from window manager
        let displays = windowManager.getCurrentDisplays()
        let allSpaces = windowManager.getCurrentSpaces()

        // Apply display filtering if in perMonitor mode
        var displayedSpaces = allSpaces
        if spaceFilterMode == .perMonitor, let displayIdx = displayIndex {
            displayedSpaces = allSpaces.filter { $0.display == displayIdx }
        }

        // Labels are resolved from the complete workspace list first. This
        // keeps name prefixes and explicit labels stable while empty spaces
        // appear and disappear from the bar.
        let labelsBySpaceId = WorkspaceLabelFormatter.labels(
            for: allSpaces,
            style: AegisConfig.shared.workspaceLabelStyle,
            overrides: AegisConfig.shared.workspaceLabelOverrides
        )
        let currentSpaceIds = Set(allSpaces.map(\.id))
        knownWindowCounts = knownWindowCounts.filter { currentSpaceIds.contains($0.key) }
        for space in allSpaces where space.windowCountIsKnown {
            knownWindowCounts[space.id] = space.windowCount
        }
        spaces = WorkspaceVisibilityPolicy.visibleSpaces(
            displayedSpaces,
            hideEmpty: AegisConfig.shared.hideEmptyWorkspaces,
            previousCounts: knownWindowCounts
        )

        // Pre-compute fullscreen state and notify coordinator on change
        if let focusedSpace = spaces.first(where: { $0.isFocused }) {
            let wasFullscreen = isFocusedSpaceFullscreen
            isFocusedSpaceFullscreen = focusedSpace.isFullscreen || focusedSpace.layoutType == .fullscreen
            if isFocusedSpaceFullscreen != wasFullscreen {
                onFullscreenStateChanged?(isFocusedSpaceFullscreen)
            }
        } else if isFocusedSpaceFullscreen {
            // No focused space found (e.g. during display transition) — assume we left fullscreen
            // so the window becomes interactive again (resets ignoresMouseEvents)
            isFocusedSpaceFullscreen = false
            onFullscreenStateChanged?(false)
        }

        // Fetch all windows once — reused for focused window check, launcher detection, and title observer
        let allWindows = windowManager.getAllWindows()
        let focusedWindow = allWindows.first { $0.hasFocus }

        // Pre-compute which space has the focused window (replaces per-space spaceHasFocusedWindow scan)
        // Excludes base apps (Finder, Aegis); adapter handles WM-specific filtering (e.g. AXWindow role)
        let baseExcludedApps = AegisConfig.shared.baseExcludedApps
        let focusedSpaceIndex: Int? = focusedWindow.flatMap { fw in
            guard !baseExcludedApps.contains(fw.app),
                  fw.isVisible,
                  !fw.isHidden else { return nil }
            return fw.space
        }

        // Build window icons and focused indices
        var newIconsBySpace: [Int: [WindowIcon]] = [:]
        var newAllIconsBySpace: [Int: [WindowIcon]] = [:]
        var newFocusedIndexBySpace: [Int: Int] = [:]
        var activeSpaceIndices: Set<Int> = []
        var allWindowIds: Set<Int> = []

        let maxIcons = AegisConfig.shared.maxAppIconsPerSpace

        for space in spaces {
            let icons = windowManager.getWindowIconsForSpace(space.index)
            // Apply the maxAppIconsPerSpace limit - visible icons are capped, allIcons keeps everything
            newIconsBySpace[space.index] = Array(icons.prefix(maxIcons))
            newAllIconsBySpace[space.index] = icons

            // Pre-compute focused index to avoid O(N) search in views
            if let focusedIdx = icons.firstIndex(where: { $0.hasFocus }) {
                newFocusedIndexBySpace[space.index] = focusedIdx
            }

            // O(1) check: is this space active? (replaces O(N) spaceHasFocusedWindow per space)
            if focusedSpaceIndex == space.index || space.isFocused {
                activeSpaceIndices.insert(space.index)
            }

            // Collect all window IDs for cleanup
            for icon in icons {
                allWindowIds.insert(icon.id)
            }
        }

        windowIconsBySpace = newIconsBySpace
        allWindowIconsBySpace = newAllIconsBySpace
        focusedIndexBySpace = newFocusedIndexBySpace

        // Check if focused window belongs to a launcher app
        let launcherAppNames = Set(FloatingApp.appsFromConfig().map { $0.name })
        let launcherFocused = focusedWindow.map { launcherAppNames.contains($0.app) } ?? false
        if sharedState.launcherAppFocused != launcherFocused {
            sharedState.launcherAppFocused = launcherFocused
        }

        // Observe title changes on the focused window (for tab switches, etc.)
        if let fw = focusedWindow, titleObserver.currentWindowId != fw.id {
            titleObserver.startObserving(windowId: fw.id, pid: fw.pid) { [weak self] windowId, newTitle in
                self?.spaceStore.updateWindowTitle(windowId: windowId, newTitle: newTitle)
            }
        }

        // Update the space store - this is the key to the split state architecture
        // Each SpaceViewModel only publishes if its data changed
        spaceStore.update(
            spaces: spaces,
            displayLabelsBySpaceId: labelsBySpaceId,
            windowIconsBySpace: windowIconsBySpace,
            allWindowIconsBySpace: allWindowIconsBySpace,
            focusedIndexBySpace: focusedIndexBySpace,
            activeSpaceIndices: activeSpaceIndices
        )

        // Clear expanded window if it no longer exists
        sharedState.cleanupExpandedWindowIfNeeded(allWindowIds: allWindowIds)

    }

    /// Schedule a coalesced update - multiple calls within the coalesce window
    /// will be batched into a single update to prevent UI flashing
    private func scheduleCoalescedUpdate() {
        // Cancel any pending update
        pendingUpdateWorkItem?.cancel()

        // Schedule a new update after the coalesce delay
        let workItem = DispatchWorkItem { [weak self] in
            self?.performUpdate()
        }
        pendingUpdateWorkItem = workItem

        DispatchQueue.main.asyncAfter(deadline: .now() + updateCoalesceDelay, execute: workItem)
    }

    func refreshWindowIcons() {
        // Coalesce with any pending space updates to prevent double flash
        scheduleCoalescedUpdate()
    }

    // MARK: - Public accessors for MenuBarView compatibility

    /// Get all spaces (for ForEach in legacy code path)
    func getSpaces() -> [WMSpace] {
        return spaces
    }

    func getWindowIcons(for space: WMSpace) -> [WindowIcon] {
        return windowIconsBySpace[space.index] ?? []
    }

    func getAllWindowIcons(for space: WMSpace) -> [WindowIcon] {
        return allWindowIconsBySpace[space.index] ?? []
    }

    func getFocusedIndex(for spaceIndex: Int) -> Int? {
        return focusedIndexBySpace[spaceIndex]
    }

    func getAppIcons(for space: WMSpace) -> [NSImage] {
        return windowManager.getAppIconsForSpace(space.index)
    }

    /// Check if any window on this space has focus (including excluded apps)
    func spaceHasFocusedWindow(_ spaceIndex: Int) -> Bool {
        return windowManager.spaceHasFocusedWindow(spaceIndex)
    }

    // MARK: - Notch HUD Integration

    /// Connect to NotchHUDController to observe HUD visibility
    func observeHUDVisibility(from hudController: NotchHUDController) {
        // Observe both media and overlay HUD visibility
        // HUD is visible if either media OR overlay is visible
        Publishers.CombineLatest(
            hudController.$isMediaHUDVisible,
            hudController.$isOverlayHUDVisible
        )
        .map { mediaVisible, overlayVisible in
            mediaVisible || overlayVisible
        }
        .receive(on: DispatchQueue.main)
        .sink { [weak self] visible in
            self?.sharedState.isHUDVisible = visible
        }
        .store(in: &cancellables)
    }
}
