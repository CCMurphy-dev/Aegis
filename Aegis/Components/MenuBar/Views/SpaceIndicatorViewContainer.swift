//
//  SpaceIndicatorViewContainer.swift
//  Aegis
//
//  Container that isolates per-space re-renders.
//  Each container observes only its own SpaceViewModel,
//  so changes to one space don't affect other spaces.
//

import SwiftUI

/// Container that isolates per-space re-renders
struct SpaceIndicatorViewContainer: View {
    @ObservedObject var spaceViewModel: SpaceViewModel
    @ObservedObject var sharedState: SharedMenuBarState

    let onWindowClick: (Int) -> Void
    let onSpaceClick: () -> Void
    let onSpaceDestroy: (Int) -> Void
    let onWindowDrop: (Int, Int, Int?, Bool) -> Void

    /// Compute entry edge based on previous focused space
    private var dotEntryEdge: Edge {
        guard let previous = sharedState.previousFocusedSpaceIndex else { return .leading }
        return previous > spaceViewModel.space.index ? .trailing : .leading
    }

    var body: some View {
        SpaceIndicatorView(
            space: spaceViewModel.space,
            isActive: spaceViewModel.isActive,
            windowIcons: spaceViewModel.windowIcons,
            allWindowIcons: spaceViewModel.allWindowIcons,
            focusedIndex: spaceViewModel.focusedIndex,
            dotEntryEdge: dotEntryEdge,
            onWindowClick: onWindowClick,
            onSpaceClick: onSpaceClick,
            onSpaceDestroy: onSpaceDestroy,
            onWindowDrop: onWindowDrop,
            draggedWindowId: $sharedState.draggedWindowId,
            expandedWindowId: $sharedState.expandedWindowId
        )
        .id(spaceViewModel.spaceId)
        .onChange(of: spaceViewModel.isActive) { isActive in
            if isActive {
                sharedState.previousFocusedSpaceIndex = sharedState.currentFocusedSpaceIndex
                sharedState.currentFocusedSpaceIndex = spaceViewModel.space.index
            }
        }
    }
}
