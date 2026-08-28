import SwiftUI

/// Shared badge view for window status indicators (minimized, hidden, stacked)
/// Used by SpaceIndicatorView, WindowIconView, and AppSwitcherWindowController
struct WindowStatusBadge: View {
    let isMinimized: Bool
    let isHidden: Bool
    let stackIndex: Int
    var stackBackground: Color = Color.white.opacity(0.2)
    var stackForeground: Color = Color.white.opacity(0.9)

    var body: some View {
        Group {
            if isMinimized {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.yellow)
            } else if isHidden {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.gray)
            } else if stackIndex > 0 {
                ZStack {
                    Circle()
                        .fill(stackBackground)
                        .frame(width: 10, height: 10)
                    Text("⧉")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundColor(stackForeground)
                }
            }
        }
        .offset(x: 2, y: 0)
    }

    /// Returns true if any badge should be displayed
    var hasBadge: Bool {
        isMinimized || isHidden || stackIndex > 0
    }
}
