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

    // Coalesce rapid updates to prevent double flash
    private var pendingUpdateWorkItem: DispatchWorkItem?
    private let updateCoalesceDelay: TimeInterval = 0.05  // 50ms coalesce window

    init(yabaiService: YabaiService) {
        self.yabaiService = yabaiService
        self.spaceStore = SpaceViewModelStore()
        self.sharedState = SharedMenuBarState()

        // Initial load
        performUpdate()

        // Initialize HUD layout coordinator with screen dimensions
        if let screen = NSScreen.main {
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
        spaces = yabaiService.getCurrentSpaces()

        // Build window icons and focused indices
        var newIconsBySpace: [Int: [WindowIcon]] = [:]
        var newAllIconsBySpace: [Int: [WindowIcon]] = [:]
        var newFocusedIndexBySpace: [Int: Int] = [:]
        var activeSpaceIndices: Set<Int> = []
        var allWindowIds: Set<Int> = []

        for space in spaces {
            let icons = yabaiService.getWindowIconsForSpace(space.index)
            newIconsBySpace[space.index] = icons
            newAllIconsBySpace[space.index] = icons  // Same for now, overflow handled in view

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
