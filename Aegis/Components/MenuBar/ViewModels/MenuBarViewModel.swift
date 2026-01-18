import SwiftUI
import AppKit
import Combine

// MARK: - Menu Bar ViewModel
// State-only view model for menu bar data

class MenuBarViewModel: ObservableObject {
    @Published var spaces: [Space] = []
    @Published var windowIconsBySpace: [Int: [WindowIcon]] = [:]  // Window icons keyed by space index
    @Published var windowIconsVersion: Int = 0  // Increment to force UI refresh
    @Published var isHUDVisible: Bool = false  // Tracks notch HUD visibility
    @Published var hudLayoutCoordinator: HUDLayoutCoordinator?  // Manages HUD module layout
    @Published var expandedWindowId: Int?  // Currently expanded window icon (persists across view updates)

    let yabaiService: YabaiService  // Made public for context menu
    private var updateTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // Coalesce rapid updates to prevent double flash
    // When both space and window events fire in quick succession,
    // this batches them into a single UI update
    private var pendingUpdateWorkItem: DispatchWorkItem?
    private let updateCoalesceDelay: TimeInterval = 0.05  // 50ms coalesce window

    init(yabaiService: YabaiService) {
        self.yabaiService = yabaiService

        // Initial load
        updateSpaces()

        // Initialize HUD layout coordinator with screen dimensions
        if let screen = NSScreen.main {
            let notchDimensions = NotchDimensions.calculate(for: screen)
            self.hudLayoutCoordinator = HUDLayoutCoordinator(
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
        spaces = yabaiService.getCurrentSpaces()

        // Also update window icons when spaces change
        var newIconsBySpace: [Int: [WindowIcon]] = [:]
        for space in spaces {
            newIconsBySpace[space.index] = yabaiService.getWindowIconsForSpace(space.index)
        }
        windowIconsBySpace = newIconsBySpace
        windowIconsVersion += 1

        // Clear expanded window if it no longer exists
        cleanupExpandedWindowIfNeeded(newIconsBySpace)
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

    /// Clear expandedWindowId if the window no longer exists in any space
    private func cleanupExpandedWindowIfNeeded(_ iconsBySpace: [Int: [WindowIcon]]) {
        guard let expandedId = expandedWindowId else { return }

        // Check if the expanded window still exists in any space
        let allWindowIds = iconsBySpace.values.flatMap { $0.map { $0.id } }
        if !allWindowIds.contains(expandedId) {
            expandedWindowId = nil
        }
    }

    func refreshWindowIcons() {
        // Coalesce with any pending space updates to prevent double flash
        scheduleCoalescedUpdate()
    }

    func getWindowIcons(for space: Space) -> [WindowIcon] {
        return windowIconsBySpace[space.index] ?? []
    }

    func getAllWindowIcons(for space: Space) -> [WindowIcon] {
        return yabaiService.getWindowIconsForSpace(space.index)
    }

    func getAppIcons(for space: Space) -> [NSImage] {
        return yabaiService.getAppIconsForSpace(space.index)
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
        .assign(to: &$isHUDVisible)
    }
}
