//
//  SpaceIndicatorViewContainer.swift
//  Aegis
//
//  Container that isolates per-space re-renders.
//  Each container observes only its own SpaceViewModel,
//  so changes to one space don't affect other spaces.
//

import SwiftUI
import Combine

/// Container that isolates per-space re-renders
struct SpaceIndicatorViewContainer: View {
    @ObservedObject var spaceViewModel: SpaceViewModel
    let sharedState: SharedMenuBarState

    let onWindowClick: (Int) -> Void
    let onSpaceClick: () -> Void
    let onSpaceDestroy: (Int) -> Void
    let onWindowDrop: (Int, Int, Int?, Bool) -> Void
    let onSpaceMove: (Int, Int) -> Void
    let spaceIds: [Int]
    let spaceDisplayIndices: [Int]  // Ordered global indices of spaces on this display

    // Per-space local state: only updates via .onReceive, preventing all-space re-renders
    @State private var localExpandedWindowId: Int?
    @State private var hasReceivedInitialValue = false
    @State private var localDraggedWindowId: Int?
    @State private var localDraggedSpaceIndex: Int?
    @State private var localDropTargetSpaceIndex: Int?
    @State private var localDraggedSpaceWidth: CGFloat = 0
    @State private var lastExpandedChangeTime: Date = .distantPast

    /// Custom bindings: read local state, write to global shared state
    private var expandedBinding: Binding<Int?> {
        Binding(get: { localExpandedWindowId }, set: { sharedState.expandedWindowId = $0 })
    }
    private var draggedWindowIdBinding: Binding<Int?> {
        Binding(get: { localDraggedWindowId }, set: { sharedState.draggedWindowId = $0 })
    }
    private var draggedSpaceIndexBinding: Binding<Int?> {
        Binding(get: { localDraggedSpaceIndex }, set: { sharedState.draggedSpaceIndex = $0 })
    }
    private var dropTargetSpaceIndexBinding: Binding<Int?> {
        Binding(get: { localDropTargetSpaceIndex }, set: { sharedState.dropTargetSpaceIndex = $0 })
    }
    private var draggedSpaceWidthBinding: Binding<CGFloat> {
        Binding(get: { localDraggedSpaceWidth }, set: { sharedState.draggedSpaceWidth = $0 })
    }

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
            draggedWindowId: draggedWindowIdBinding,
            expandedWindowId: expandedBinding,
            draggedSpaceIndex: draggedSpaceIndexBinding,
            dropTargetSpaceIndex: dropTargetSpaceIndexBinding,
            draggedSpaceWidth: draggedSpaceWidthBinding,
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
        .onChange(of: spaceViewModel.focusedIndex) { newFocusedIndex in
            guard AegisConfig.shared.autoExpandFocusedWindow else { return }
            if let idx = newFocusedIndex, idx < spaceViewModel.windowIcons.count {
                let focusedWindowId = spaceViewModel.windowIcons[idx].id
                if sharedState.expandedWindowId != focusedWindowId {
                    sharedState.expandedWindowId = focusedWindowId
                }
            } else if newFocusedIndex == nil {
                if let expandedId = sharedState.expandedWindowId,
                   spaceViewModel.windowIcons.contains(where: { $0.id == expandedId }) {
                    sharedState.expandedWindowId = nil
                }
            }
        }
        .onReceive(sharedState.expandedWindowIdSubject.removeDuplicates()) { newId in
            let myWindowIds = Set(spaceViewModel.windowIcons.map { $0.id })
            let newLocal = newId.flatMap { myWindowIds.contains($0) ? $0 : nil }

            guard hasReceivedInitialValue else {
                localExpandedWindowId = newLocal
                hasReceivedInitialValue = true
                return
            }
            guard newLocal != localExpandedWindowId else { return }

            // Detect rapid switching: skip animation if changes come faster than 300ms
            let now = Date()
            let isRapid = now.timeIntervalSince(lastExpandedChangeTime) < 0.3
            lastExpandedChangeTime = now

            if isRapid {
                // Snap instantly — avoids overlapping animations
                localExpandedWindowId = newLocal
            } else {
                // easeOut completes in a fixed duration and STOPS — unlike springs
                // which asymptotically settle over 700ms+ causing continuous rendering.
                // At 120fps ProMotion: 0.2s = 24 frames vs spring's 80+ frames.
                let animation: Animation = newLocal != nil
                    ? .easeOut(duration: 0.2)   // Expand
                    : .easeOut(duration: 0.15)  // Collapse (shorter)
                withAnimation(animation) {
                    localExpandedWindowId = newLocal
                }
            }
        }
        .onReceive(sharedState.draggedWindowIdSubject.removeDuplicates()) { localDraggedWindowId = $0 }
        .onReceive(sharedState.draggedSpaceIndexSubject.removeDuplicates()) { localDraggedSpaceIndex = $0 }
        .onReceive(sharedState.dropTargetSpaceIndexSubject.removeDuplicates()) { localDropTargetSpaceIndex = $0 }
        .onReceive(sharedState.draggedSpaceWidthSubject.removeDuplicates()) { localDraggedSpaceWidth = $0 }
    }
}
