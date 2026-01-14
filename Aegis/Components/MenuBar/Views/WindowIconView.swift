import SwiftUI
import AppKit
import Combine

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
                    onHover: onHover,
                    onLeftClick: onLeftClick,
                    onRightClick: onRightClick,
                    onDragStarted: onDragStarted,
                    onDragEnded: onDragEnded
                )

                // Stack indicator badge
                if windowIcon.stackIndex > 0 {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 10, height: 10)

                        Text("⧉")
                            .font(.system(size: 6, weight: .bold))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .offset(x: 2, y: 2)
                }
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

// MARK: - Window Expansion Controller
// Manages window icon expansion state and auto-collapse

class WindowExpansionController: ObservableObject {
    @Published var expandedIconId: Int?
    private var autoCollapseTask: Task<Void, Never>?

    private let config = AegisConfig.shared
    private let maxExpandedWidth: CGFloat = 100

    func toggleExpansion(for icon: WindowIcon) {
        autoCollapseTask?.cancel()

        // If clicking the same icon → just collapse
        if expandedIconId == icon.id {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                expandedIconId = nil
            }
            return
        }

        // Step 1: force collapse the previous expanded icon
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            expandedIconId = nil
        }

        // Step 2: expand the new icon on the next run loop
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                self.expandedIconId = icon.id
            }
        }

        // Auto-collapse timer
        let delayNanoseconds = UInt64(config.windowIconExpansionAutoCollapseDelay * 1_000_000_000)
        autoCollapseTask = Task {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            await MainActor.run {
                withAnimation {
                    self.expandedIconId = nil
                }
            }
        }
    }

    func collapse() {
        autoCollapseTask?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            expandedIconId = nil
        }
    }

    func calculatedWidth(for icon: WindowIcon) -> CGFloat {
        let titleFont = NSFont.systemFont(ofSize: 11, weight: .medium)
        let titleWidth = icon.title.width(using: titleFont)

        var maxWidth = titleWidth

        if config.showAppNameInExpansion {
            let appFont = NSFont.systemFont(ofSize: 9)
            let appWidth = icon.appName.width(using: appFont)
            maxWidth = max(titleWidth, appWidth)
        }

        return min(maxWidth + 8, maxExpandedWidth)
    }
}

// MARK: - Helper: String width measurement

private extension String {
    func width(using font: NSFont) -> CGFloat {
        let attributes = [NSAttributedString.Key.font: font]
        return (self as NSString).size(withAttributes: attributes).width
    }
}
