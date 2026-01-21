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
}
