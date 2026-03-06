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

    /// Optimistically reorder a space (called before yabai confirms the move)
    /// Prevents visual snap-back by updating the ForEach order immediately
    func reorderSpace(fromDisplayIndex: Int, toDisplayIndex: Int) {
        // Find array positions by matching global display index (works across all displays)
        guard let fromArrayIndex = spaceIds.firstIndex(where: { viewModels[$0]?.space.index == fromDisplayIndex }),
              let toArrayIndex = spaceIds.firstIndex(where: { viewModels[$0]?.space.index == toDisplayIndex }) else { return }

        // Compute base index before modifying (e.g., 5 for display 2 with spaces 5,6,7)
        let baseIndex = spaceIds.compactMap { viewModels[$0]?.space.index }.min() ?? 1

        var reordered = spaceIds
        let movedId = reordered.remove(at: fromArrayIndex)
        reordered.insert(movedId, at: toArrayIndex)
        spaceIds = reordered

        // Update display indices to match new positions
        for (offset, spaceId) in reordered.enumerated() {
            viewModels[spaceId]?.updateDisplayIndex(baseIndex + offset)
        }
    }

    /// Update the title of a specific window (called when AX title change is observed)
    func updateWindowTitle(windowId: Int, newTitle: String) {
        // Find which space has this window and update it
        for (_, viewModel) in viewModels {
            if viewModel.updateWindowTitle(windowId: windowId, newTitle: newTitle) {
                return  // Found and updated
            }
        }
    }
}
