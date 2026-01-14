import SwiftUI

struct SystemStatusView: View {
    @StateObject private var statusMonitor = SystemStatusMonitor()

    var body: some View {
        HStack(spacing: 8) {
            // WiFi / Network icon
            NetworkStatusIconView(status: statusMonitor.networkStatus)

            // Time (24hr) and Date (DD/MM/YY)
            ClockView()
            DateView(format: .short)

            // Show battery when not full, or when charging
            // Animated slide in/out from trailing edge
            if statusMonitor.batteryLevel < 1.0 || statusMonitor.isCharging {
                BatteryStatusIconView(level: statusMonitor.batteryLevel,
                                      isCharging: statusMonitor.isCharging)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: statusMonitor.batteryLevel >= 1.0 && !statusMonitor.isCharging)
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
