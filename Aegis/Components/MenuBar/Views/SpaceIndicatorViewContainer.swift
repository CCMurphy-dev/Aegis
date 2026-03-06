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
    let onSpaceMove: (Int, Int) -> Void
    let spaceIds: [Int]
    let spaceDisplayIndices: [Int]  // Ordered global indices of spaces on this display

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
            onSpaceMove: onSpaceMove,
            spaceIds: spaceIds,
            draggedWindowId: $sharedState.draggedWindowId,
            expandedWindowId: $sharedState.expandedWindowId,
            draggedSpaceIndex: $sharedState.draggedSpaceIndex,
            dropTargetSpaceIndex: $sharedState.dropTargetSpaceIndex,
            draggedSpaceWidth: $sharedState.draggedSpaceWidth,
            spaceWidths: sharedState.measuredSpaceWidths,
            spaceDisplayIndices: spaceDisplayIndices
        )
        .id(spaceViewModel.spaceId)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        sharedState.measuredSpaceWidths[spaceViewModel.space.index] = geo.size.width
                    }
                    .onChange(of: geo.size.width) {
                        sharedState.measuredSpaceWidths[spaceViewModel.space.index] = $0
                    }
            }
        )
        .onChange(of: spaceViewModel.isActive) { isActive in
            if isActive {
                sharedState.previousFocusedSpaceIndex = sharedState.currentFocusedSpaceIndex
                sharedState.currentFocusedSpaceIndex = spaceViewModel.space.index
            }
        }
    }
}
