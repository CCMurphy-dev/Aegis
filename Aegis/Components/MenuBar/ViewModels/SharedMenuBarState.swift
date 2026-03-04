//
//  SharedMenuBarState.swift
//  Aegis
//
//  Shared state for cross-space coordination.
//  Used for state that needs to be shared between spaces
//  (e.g., which window is expanded, which window is being dragged).
//

import SwiftUI
import Combine

/// Shared state for cross-space coordination
final class SharedMenuBarState: ObservableObject {
    /// Currently expanded window icon (persists across view updates)
    @Published var expandedWindowId: Int?

    /// ID of window currently being dragged
    @Published var draggedWindowId: Int?

    /// Tracks notch HUD visibility
    @Published var isHUDVisible: Bool = false

    /// Manages HUD module layout
    @Published var hudLayoutCoordinator: HUDLayoutCoordinator?

    /// Whether a launcher-configured app currently has focus
    @Published var launcherAppFocused: Bool = false

    /// Space index currently being dragged (nil when not dragging)
    @Published var draggedSpaceIndex: Int?

    /// Proposed insertion index during drag (where the space would land)
    @Published var dropTargetSpaceIndex: Int?

    /// Width of the space indicator being dragged (used by other spaces to compute shift amount)
    @Published var draggedSpaceWidth: CGFloat = 0

    /// Index of the space that previously had focus (for directional dot animation)
    var previousFocusedSpaceIndex: Int?

    /// Index of the space that currently has focus
    var currentFocusedSpaceIndex: Int?

    /// Clear expandedWindowId if the window no longer exists
    func cleanupExpandedWindowIfNeeded(allWindowIds: Set<Int>) {
        guard let expandedId = expandedWindowId else { return }
        if !allWindowIds.contains(expandedId) {
            expandedWindowId = nil
        }
    }
}
