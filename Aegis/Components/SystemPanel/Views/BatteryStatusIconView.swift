import SwiftUI

struct BatteryStatusIconView: View {
    let level: Float
    let isCharging: Bool

    private let pillWidth: CGFloat = 28
    private let pillHeight: CGFloat = 14

    // Fill color: green when charging, white otherwise
    private var fillColor: Color {
        isCharging ? Color.green : Color.white.opacity(0.9)
    }

    // Text color: contrast based on fill level and charging state
    private var textColor: Color {
        level > 0.5 ? .black : .white
    }

    var body: some View {
        // Return empty view if fully charged and not charging
        if !isCharging && level >= 1.0 {
            EmptyView()
        } else {
            ZStack(alignment: .leading) {
                // Background pill (dark)
                Capsule()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: pillWidth, height: pillHeight)

                // Fill level (animated color and width)
                Capsule()
                    .fill(fillColor)
                    .frame(width: max(pillHeight, pillWidth * CGFloat(level)), height: pillHeight)

                // Percentage text centered
                HStack(spacing: 1) {
                    if isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 6, weight: .semibold))
                            .transition(.scale.combined(with: .opacity))
                    }
                    Text("\(Int(level * 100))")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                }
                .foregroundColor(textColor)
                .frame(width: pillWidth, height: pillHeight)
            }
            .compositingGroup()
            .animation(.easeInOut(duration: 0.3), value: isCharging)
            .animation(.easeInOut(duration: 0.5), value: level)
        }
    }
}
