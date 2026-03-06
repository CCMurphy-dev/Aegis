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

    /// Raw spaces data from YabaiService
    private var spaces: [Space] = []

    /// Window icons keyed by space index
    private var windowIconsBySpace: [Int: [WindowIcon]] = [:]

    /// All window icons (including overflow) keyed by space index
    private var allWindowIconsBySpace: [Int: [WindowIcon]] = [:]

    /// Pre-computed focused window index per space
    private var focusedIndexBySpace: [Int: Int] = [:]

    // MARK: - Services & Timers

    let yabaiService: YabaiService  // Made public for context menu
    private var updateTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let titleObserver = WindowTitleObserver()

    // Coalesce rapid updates to prevent double flash
    private var pendingUpdateWorkItem: DispatchWorkItem?
    private let updateCoalesceDelay: TimeInterval = 0.05  // 50ms coalesce window

    init(yabaiService: YabaiService, targetScreen: NSScreen? = nil) {
        self.yabaiService = yabaiService
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
        // Fetch data from YabaiService
        var allSpaces = yabaiService.getCurrentSpaces()

        // Apply display filtering if in perMonitor mode
        if spaceFilterMode == .perMonitor, let displayIdx = displayIndex {
            allSpaces = allSpaces.filter { $0.display == displayIdx }
        }

        spaces = allSpaces

        // Build window icons and focused indices
        var newIconsBySpace: [Int: [WindowIcon]] = [:]
        var newAllIconsBySpace: [Int: [WindowIcon]] = [:]
        var newFocusedIndexBySpace: [Int: Int] = [:]
        var activeSpaceIndices: Set<Int> = []
        var allWindowIds: Set<Int> = []

        let maxIcons = AegisConfig.shared.maxAppIconsPerSpace

        for space in spaces {
            let icons = yabaiService.getWindowIconsForSpace(space.index)
            // Apply the maxAppIconsPerSpace limit - visible icons are capped, allIcons keeps everything
            newIconsBySpace[space.index] = Array(icons.prefix(maxIcons))
            newAllIconsBySpace[space.index] = icons

            // Pre-compute focused index to avoid O(N) search in views
            if let focusedIdx = icons.firstIndex(where: { $0.hasFocus }) {
                newFocusedIndexBySpace[space.index] = focusedIdx
            }

            // Check if this space has any focused window (including excluded apps)
            let spaceHasFocus = yabaiService.spaceHasFocusedWindow(space.index)
            if spaceHasFocus || space.focused {
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
        let focusedWindow = yabaiService.getAllWindows().first { $0.hasFocus }
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
    func getSpaces() -> [Space] {
        return spaces
    }

    func getWindowIcons(for space: Space) -> [WindowIcon] {
        return windowIconsBySpace[space.index] ?? []
    }

    func getAllWindowIcons(for space: Space) -> [WindowIcon] {
        return allWindowIconsBySpace[space.index] ?? []
    }

    func getFocusedIndex(for spaceIndex: Int) -> Int? {
        return focusedIndexBySpace[spaceIndex]
    }

    func getAppIcons(for space: Space) -> [NSImage] {
        return yabaiService.getAppIconsForSpace(space.index)
    }

    /// Check if any window on this space has focus (including excluded apps)
    func spaceHasFocusedWindow(_ spaceIndex: Int) -> Bool {
        return yabaiService.spaceHasFocusedWindow(spaceIndex)
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
        .assign(to: &sharedState.$isHUDVisible)
    }
}
