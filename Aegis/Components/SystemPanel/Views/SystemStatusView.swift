import SwiftUI

struct SystemStatusView: View {
    @StateObject private var statusMonitor = SystemStatusMonitor()
    @ObservedObject private var config = AegisConfig.shared

    var body: some View {
        HStack(spacing: 0) {
            // Focus icon container - animates in/out with clipping
            // Uses fixedSize when showing name to allow dynamic width
            if config.showFocusName {
                // When showing name, use standard transition (can't clip text nicely)
                if statusMonitor.focusStatus.isEnabled {
                    FocusStatusIconView(focusStatus: statusMonitor.focusStatus)
                        .fixedSize()
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            } else {
                // Icon only - use frame width animation with clipping
                FocusStatusIconView(focusStatus: statusMonitor.focusStatus)
                    .frame(width: statusMonitor.focusStatus.isEnabled ? 12 : 0, alignment: .leading)
                    .clipped()
            }

            // Spacing between focus and wifi (only when focus visible)
            Color.clear
                .frame(width: statusMonitor.focusStatus.isEnabled ? 8 : 0)

            // WiFi icon - always visible
            NetworkStatusIconView(status: statusMonitor.networkStatus)

            // Spacing after WiFi
            Color.clear.frame(width: 8)

            // Time (24hr) and Date (DD/MM/YY)
            ClockView()

            Color.clear.frame(width: 8)

            DateView(format: .short)

            // Show battery when not full, or when charging
            // Animated slide in/out from trailing edge
            if statusMonitor.batteryLevel < 1.0 || statusMonitor.isCharging {
                Color.clear.frame(width: 8)

                BatteryStatusIconView(level: statusMonitor.batteryLevel,
                                      isCharging: statusMonitor.isCharging)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: statusMonitor.focusStatus.isEnabled)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: statusMonitor.focusStatus.symbolName)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: statusMonitor.focusStatus.focusName)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: statusMonitor.batteryLevel >= 1.0 && !statusMonitor.isCharging)
        .font(.system(size: 13, weight: .medium)) // macOS menu bar font
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .frame(height: 20) 
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.2), lineWidth: 1) // light border
        )
        .shadow(color: Color.black.opacity(0.3), radius: 1, x: 0, y: 1)
    }
}
