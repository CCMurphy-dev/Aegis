import SwiftUI

// MARK: - Space Windows Row
// Displays window icons and overflow menu
// Note: Uses OverflowWindowMenu from SpaceIndicatorView.swift

struct SpaceWindowsRow: View {
    let windowIcons: [WindowIcon]
    let allWindowIcons: [WindowIcon]
    let expandedIconId: Int?
    let hoveredIconId: Int?
    let draggedWindowId: Int?
    let onWindowClick: (Int) -> Void
    let onHoverChange: (Int?) -> Void
    let onToggleExpansion: (WindowIcon) -> Void
    let calculatedWidth: (WindowIcon) -> CGFloat

    @State private var showOverflowMenu = false
    private let config = AegisConfig.shared

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            ForEach(windowIcons) { windowIcon in
                WindowIconView(
                    windowIcon: windowIcon,
                    isExpanded: expandedIconId == windowIcon.id,
                    expandedWidth: calculatedWidth(windowIcon),
                    hoveredIconId: hoveredIconId,
                    draggedWindowId: draggedWindowId,
                    onHover: { hovering in
                        onHoverChange(hovering ? windowIcon.id : nil)
                    },
                    onLeftClick: {
                        // Collapse if this icon is expanded
                        if expandedIconId == windowIcon.id {
                            onToggleExpansion(windowIcon)
                        }
                        onWindowClick(windowIcon.id)
                    },
                    onRightClick: {
                        onToggleExpansion(windowIcon)
                    },
                    onDragStarted: {
                        // Handled by parent
                    },
                    onDragEnded: {
                        // Handled by parent
                    }
                )
            }

            // Overflow button
            if allWindowIcons.count > windowIcons.count {
                Button {
                    showOverflowMenu.toggle()
                } label: {
                    Text("+\(allWindowIcons.count - windowIcons.count)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 20, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(showOverflowMenu ? 0.25 : 0.12))
                        )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showOverflowMenu, arrowEdge: .bottom) {
                    OverflowWindowMenu(
                        hiddenIcons: Array(allWindowIcons.dropFirst(windowIcons.count)),
                        onWindowClick: { id in
                            showOverflowMenu = false
                            onWindowClick(id)
                        }
                    )
                }
            }
        }
    }
}
