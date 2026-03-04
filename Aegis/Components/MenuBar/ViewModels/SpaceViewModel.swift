//
//  SpaceViewModel.swift
//  Aegis
//
//  Per-space observable state - each space indicator owns one.
//  This isolates re-renders so only affected spaces update.
//

import SwiftUI
import Combine

/// Per-space observable state - each space indicator owns one
final class SpaceViewModel: ObservableObject, Identifiable {
    let spaceId: Int

    @Published private(set) var space: Space
    @Published private(set) var windowIcons: [WindowIcon] = []
    @Published private(set) var allWindowIcons: [WindowIcon] = []
    @Published private(set) var focusedIndex: Int?
    @Published private(set) var isActive: Bool = false

    var id: Int { spaceId }

    init(space: Space) {
        self.spaceId = space.id
        self.space = space
    }

    /// Update from parent - only publishes if data actually changed
    func update(space: Space, windowIcons: [WindowIcon], allWindowIcons: [WindowIcon],
                focusedIndex: Int?, isActive: Bool) {
        // Only trigger @Published updates when values actually change
        // This is the key optimization - unchanged properties don't trigger view rebuilds
        if self.space != space { self.space = space }
        if self.windowIcons != windowIcons { self.windowIcons = windowIcons }
        if self.allWindowIcons != allWindowIcons { self.allWindowIcons = allWindowIcons }
        if self.focusedIndex != focusedIndex { self.focusedIndex = focusedIndex }
        if self.isActive != isActive { self.isActive = isActive }
    }

    /// Update the display index (called during optimistic reorder)
    func updateDisplayIndex(_ newIndex: Int) {
        if space.index != newIndex {
            space.index = newIndex
        }
    }

    /// Update the title of a specific window (from AX title change notification)
    /// Returns true if the window was found and updated
    func updateWindowTitle(windowId: Int, newTitle: String) -> Bool {
        // Check if this space has the window
        guard let index = windowIcons.firstIndex(where: { $0.id == windowId }) else {
            return false
        }

        // Update the windowIcons array with the new title
        var updatedIcons = windowIcons
        updatedIcons[index] = updatedIcons[index].withUpdatedTitle(newTitle)
        windowIcons = updatedIcons

        // Also update allWindowIcons if the window is there
        if let allIndex = allWindowIcons.firstIndex(where: { $0.id == windowId }) {
            var updatedAllIcons = allWindowIcons
            updatedAllIcons[allIndex] = updatedAllIcons[allIndex].withUpdatedTitle(newTitle)
            allWindowIcons = updatedAllIcons
        }

        return true
    }
}
