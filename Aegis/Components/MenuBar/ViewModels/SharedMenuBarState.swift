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
    /// Currently expanded window icon (persists across view updates).
    /// Non-published: changes propagate via expandedWindowIdSubject to avoid
    /// triggering objectWillChange (which would re-render ALL space containers).
    /// Only the containers whose windows are affected will re-render.
    var expandedWindowId: Int? {
        didSet {
            if expandedWindowId != oldValue {
                expandedWindowIdSubject.send(expandedWindowId)
            }
        }
    }
    let expandedWindowIdSubject = CurrentValueSubject<Int?, Never>(nil)

    /// ID of window currently being dragged
    /// Non-published: changes propagate via subject to avoid triggering objectWillChange.
    var draggedWindowId: Int? {
        didSet {
            if draggedWindowId != oldValue {
                draggedWindowIdSubject.send(draggedWindowId)
            }
        }
    }
    let draggedWindowIdSubject = CurrentValueSubject<Int?, Never>(nil)

    /// Tracks notch HUD visibility; broadcasts via subject so MenuBarView can observe
    /// without triggering objectWillChange (which would re-render all space containers).
    var isHUDVisible: Bool = false {
        didSet {
            if isHUDVisible != oldValue {
                isHUDVisibleSubject.send(isHUDVisible)
            }
        }
    }
    let isHUDVisibleSubject = CurrentValueSubject<Bool, Never>(false)

    /// Manages HUD module layout (non-published: not read by any SwiftUI view body)
    var hudLayoutCoordinator: HUDLayoutCoordinator?

    /// Whether a launcher-configured app currently has focus
    /// Non-published: changes propagate via launcherAppFocusedSubject to avoid
    /// triggering objectWillChange (which would re-render ALL space containers).
    var launcherAppFocused: Bool = false {
        didSet {
            if launcherAppFocused != oldValue {
                launcherAppFocusedSubject.send(launcherAppFocused)
            }
        }
    }
    let launcherAppFocusedSubject = CurrentValueSubject<Bool, Never>(false)

    /// Space index currently being dragged (nil when not dragging)
    /// Non-published: changes propagate via subject to avoid triggering objectWillChange.
    var draggedSpaceIndex: Int? {
        didSet {
            if draggedSpaceIndex != oldValue {
                draggedSpaceIndexSubject.send(draggedSpaceIndex)
            }
        }
    }
    let draggedSpaceIndexSubject = CurrentValueSubject<Int?, Never>(nil)

    /// Proposed insertion index during drag (where the space would land)
    /// Non-published: changes propagate via subject to avoid triggering objectWillChange.
    var dropTargetSpaceIndex: Int? {
        didSet {
            if dropTargetSpaceIndex != oldValue {
                dropTargetSpaceIndexSubject.send(dropTargetSpaceIndex)
            }
        }
    }
    let dropTargetSpaceIndexSubject = CurrentValueSubject<Int?, Never>(nil)

    /// Width of the space indicator being dragged (used by other spaces to compute shift amount)
    /// Non-published: changes propagate via subject to avoid triggering objectWillChange.
    var draggedSpaceWidth: CGFloat = 0 {
        didSet {
            if draggedSpaceWidth != oldValue {
                draggedSpaceWidthSubject.send(draggedSpaceWidth)
            }
        }
    }
    let draggedSpaceWidthSubject = CurrentValueSubject<CGFloat, Never>(0)

    /// Measured widths of space indicators (non-published, used only for drag computation)
    var measuredSpaceWidths: [Int: CGFloat] = [:]

    /// Index of the space that previously had focus (for directional dot animation)
    var previousFocusedSpaceIndex: Int?

    /// Index of the space that currently has focus.
    var currentFocusedSpaceIndex: Int?

    /// Clear expandedWindowId if the window no longer exists
    func cleanupExpandedWindowIfNeeded(allWindowIds: Set<Int>) {
        guard let expandedId = expandedWindowId else { return }
        if !allWindowIds.contains(expandedId) {
            expandedWindowId = nil
        }
    }
}
