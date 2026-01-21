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

    /// Clear expandedWindowId if the window no longer exists
    func cleanupExpandedWindowIfNeeded(allWindowIds: Set<Int>) {
        guard let expandedId = expandedWindowId else { return }
        if !allWindowIds.contains(expandedId) {
            expandedWindowId = nil
        }
    }
}
