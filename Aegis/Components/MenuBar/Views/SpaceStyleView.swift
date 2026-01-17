import SwiftUI

// MARK: - Space Style View
// Handles background, hover state, and focus dot positioning

struct SpaceStyleView: View {
    let isActive: Bool
    let isHovered: Bool
    let windowIcons: [WindowIcon]
    let expandedWindowId: Int?
    let calculatedWidth: (WindowIcon) -> CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(backgroundColor)
            .animation(.easeInOut(duration: 0.25), value: isActive)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isActive ? Color.white.opacity(0.18) : .clear, lineWidth: 1)
                    .animation(.easeInOut(duration: 0.25), value: isActive)
            )
            .shadow(color: isActive ? .white.opacity(0.12) : .clear, radius: 6)
            .animation(.easeInOut(duration: 0.25), value: isActive)
    }

    private var backgroundColor: Color {
        if isActive {
            return Color.white.opacity(0.18)
        } else if isHovered {
            return Color.white.opacity(0.15)
        } else {
            return Color.white.opacity(0.12)
        }
    }
}

// MARK: - Focus Dot View
// Displays the focus indicator dot for the active window

struct FocusDotView: View {
    let windowIcons: [WindowIcon]
    let expandedWindowId: Int?
    let calculatedWidth: (WindowIcon) -> CGFloat

    var body: some View {
        GeometryReader { geometry in
            if let focusedIndex = windowIcons.firstIndex(where: { $0.hasFocus }) {
                let xPosition = calculateDotPosition(for: focusedIndex, in: geometry)

                Circle()
                    .fill(Color.white)
                    .frame(width: 3, height: 3)
                    .offset(x: xPosition - 1.5, y: geometry.size.height - 2.5)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: xPosition)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
    }

    private func calculateDotPosition(for focusedIndex: Int, in geometry: GeometryProxy) -> CGFloat {
        // Starting position: left padding + space number + spacing after space number
        var xPosition: CGFloat = 8 + 16 + 6

        // Add width of all icons before the focused one
        for i in 0..<focusedIndex {
            xPosition += 22  // Icon width
            xPosition += 6   // Spacing in icon's HStack (always present between icon and title area)

            // If this icon is expanded, add the title width
            if expandedWindowId == windowIcons[i].id {
                xPosition += calculatedWidth(windowIcons[i])
            }

            xPosition += 6  // Spacing after this icon (from parent HStack)
        }

        // Center on the focused icon: half icon width
        xPosition += 11

        return xPosition
    }
}
