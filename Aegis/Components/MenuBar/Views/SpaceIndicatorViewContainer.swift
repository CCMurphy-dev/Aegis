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

    var body: some View {
        SpaceIndicatorView(
            space: spaceViewModel.space,
            isActive: spaceViewModel.isActive,
            windowIcons: spaceViewModel.windowIcons,
            allWindowIcons: spaceViewModel.allWindowIcons,
            focusedIndex: spaceViewModel.focusedIndex,
            onWindowClick: onWindowClick,
            onSpaceClick: onSpaceClick,
            onSpaceDestroy: onSpaceDestroy,
            onWindowDrop: onWindowDrop,
            draggedWindowId: $sharedState.draggedWindowId,
            expandedWindowId: $sharedState.expandedWindowId
        )
        .id(spaceViewModel.spaceId)
    }
}
