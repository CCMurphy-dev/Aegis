import SwiftUI
import AppKit

// MARK: - Window Icon View
// Displays a single window icon with expansion, hover, and drag support
// Note: Uses RightClickableIcon and ClickableIconView from SpaceIndicatorView.swift

struct WindowIconView: View {
    let windowIcon: WindowIcon
    let isExpanded: Bool
    let expandedWidth: CGFloat
    let hoveredIconId: Int?
    let draggedWindowId: Int?
    let onHover: (Bool) -> Void
    let onLeftClick: () -> Void
    let onRightClick: () -> Void
    let onDragStarted: () -> Void
    let onDragEnded: () -> Void

    private let config = AegisConfig.shared

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                RightClickableIcon(
                    windowId: windowIcon.id,
                    icon: windowIcon.icon ?? NSImage(),  // Unwrap optional with fallback
                    isHovered: hoveredIconId == windowIcon.id,
                    isMinimized: windowIcon.isMinimized,
                    isHidden: windowIcon.isHidden,
                    onHover: onHover,
                    onLeftClick: onLeftClick,
                    onRightClick: onRightClick,
                    onDragStarted: onDragStarted,
                    onDragEnded: onDragEnded
                )

                // Status indicator badge
                WindowStatusBadge(
                    isMinimized: windowIcon.isMinimized,
                    isHidden: windowIcon.isHidden,
                    stackIndex: windowIcon.stackIndex
                )
            }
            .frame(width: 22, height: 22)
            .opacity(draggedWindowId == windowIcon.id ? 0.0 : 1.0)

            // Expandable title area
            VStack(alignment: .leading, spacing: 2) {
                Text(windowIcon.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)

                if config.showAppNameInExpansion {
                    Text(windowIcon.appName)
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .frame(width: isExpanded ? expandedWidth : 0, alignment: .leading)
            .opacity(isExpanded ? 1 : 0)
            .clipped()
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isExpanded)
        }
    }
}

