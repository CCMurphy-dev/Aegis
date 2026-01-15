import SwiftUI

struct BatteryStatusIconView: View {
    let level: Float
    let isCharging: Bool

    @ObservedObject private var config = AegisConfig.shared

    private let pillWidth: CGFloat = 28
    private let pillHeight: CGFloat = 14

    // Check if battery is critically low
    private var isCritical: Bool {
        !isCharging && Double(level) <= config.batteryCriticalThreshold
    }

    // Fill color: green when charging, red when critical, white otherwise
    private var fillColor: Color {
        if isCharging {
            return Color.green
        } else if isCritical {
            return Color.red
        } else {
            return Color.white.opacity(0.9)
        }
    }

    // Text color: contrast based on fill level and charging state
    private var textColor: Color {
        if isCritical {
            return .white
        }
        return level > 0.5 ? .black : .white
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

                // Percentage text centered with shadow for readability
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
                .shadow(color: .black.opacity(0.6), radius: 0.5, x: 0, y: 0.5)
                .frame(width: pillWidth, height: pillHeight)
            }
            .compositingGroup()
            .animation(.easeInOut(duration: 0.3), value: isCharging)
            .animation(.easeInOut(duration: 0.5), value: level)
        }
    }
}
