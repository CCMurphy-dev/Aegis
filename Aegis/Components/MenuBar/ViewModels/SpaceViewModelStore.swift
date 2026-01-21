//
//  SpaceViewModelStore.swift
//  Aegis
//
//  Manages collection of SpaceViewModels, handles space create/destroy.
//  Only publishes spaceIds when the list of spaces changes.
//

import SwiftUI
import Combine

/// Manages collection of SpaceViewModels, handles space create/destroy
final class SpaceViewModelStore: ObservableObject {
    /// Published array of space IDs - only changes when spaces are added/removed
    @Published private(set) var spaceIds: [Int] = []

    /// Internal storage of ViewModels keyed by space ID
    private var viewModels: [Int: SpaceViewModel] = [:]

    /// Get the ViewModel for a specific space ID
    func viewModel(for spaceId: Int) -> SpaceViewModel? {
        viewModels[spaceId]
    }

    /// Update all space ViewModels with new data
    /// Only creates/destroys ViewModels when spaces are added/removed
    /// Individual SpaceViewModels handle their own change detection
    func update(spaces: [Space],
                windowIconsBySpace: [Int: [WindowIcon]],
                allWindowIconsBySpace: [Int: [WindowIcon]],
                focusedIndexBySpace: [Int: Int],
                activeSpaceIndices: Set<Int>) {

        let newSpaceIds = spaces.map { $0.id }

        // Create new ViewModels for new spaces
        for space in spaces where viewModels[space.id] == nil {
            viewModels[space.id] = SpaceViewModel(space: space)
        }

        // Remove ViewModels for destroyed spaces
        let currentIds = Set(newSpaceIds)
        for existingId in viewModels.keys where !currentIds.contains(existingId) {
            viewModels.removeValue(forKey: existingId)
        }

        // Update each SpaceViewModel (equality checks inside prevent unnecessary publishes)
        for space in spaces {
            viewModels[space.id]?.update(
                space: space,
                windowIcons: windowIconsBySpace[space.index] ?? [],
                allWindowIcons: allWindowIconsBySpace[space.index] ?? [],
                focusedIndex: focusedIndexBySpace[space.index],
                isActive: activeSpaceIndices.contains(space.index)
            )
        }

        // Only publish spaceIds if the list actually changed
        if spaceIds != newSpaceIds {
            spaceIds = newSpaceIds
        }
    }
}
