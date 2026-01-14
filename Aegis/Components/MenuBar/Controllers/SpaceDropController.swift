import SwiftUI
import UniformTypeIdentifiers

// MARK: - Space Drop Controller
// Handles drag target math and drop positioning logic
// Note: WindowDropDelegate is defined in SpaceIndicatorView.swift

class SpaceDropController {
    func determineInsertPosition(
        at location: CGPoint,
        windowIcons: [WindowIcon],
        expandedIconId: Int?,
        calculatedWidth: (WindowIcon) -> CGFloat
    ) -> Int? {
        // Calculate the x position accounting for padding and space number
        let baseOffset: CGFloat = 8 + 16 + 6  // left padding + space number + spacing
        var currentX = baseOffset

        for (_, windowIcon) in windowIcons.enumerated() {
            let iconWidth: CGFloat = 22
            let expandedWidth = expandedIconId == windowIcon.id ? calculatedWidth(windowIcon) : 0
            let totalIconWidth = iconWidth + 6 + expandedWidth  // icon + spacing + expanded title

            // Check if drop is in the left half of this icon
            if location.x < currentX + (totalIconWidth / 2) {
                // Insert before this icon
                return windowIcon.id
            }

            currentX += totalIconWidth + 6  // add icon width and spacing after icon
        }

        // If we got here, drop is after all icons (insert at end)
        return nil
    }

    func calculateIconOffset(
        for iconId: Int,
        dropTargetId: Int?,
        windowIcons: [WindowIcon]
    ) -> CGFloat {
        guard let dropTargetId = dropTargetId else { return 0 }

        // Find indices
        guard let targetIndex = windowIcons.firstIndex(where: { $0.id == dropTargetId }),
              let currentIndex = windowIcons.firstIndex(where: { $0.id == iconId }) else {
            return 0
        }

        // Icons at or after the drop target shift right to make space
        if currentIndex >= targetIndex {
            return 28  // Space for the dropped icon + gap
        }

        return 0
    }

    func calculateTrailingPadding(
        isDraggingOver: Bool,
        draggedWindowId: Int?,
        windowIcons: [WindowIcon]
    ) -> CGFloat {
        // If dragging over this space, add extra padding for the incoming icon
        guard isDraggingOver else { return 0 }

        // Check if the dragged icon is from this space
        let isDraggingFromThisSpace = draggedWindowId != nil && windowIcons.contains(where: { $0.id == draggedWindowId })

        // If dragging from this space (reordering), don't add padding since we're not adding a new icon
        // If dragging from another space, add padding for the incoming icon
        return isDraggingFromThisSpace ? 0 : 28
    }
}
