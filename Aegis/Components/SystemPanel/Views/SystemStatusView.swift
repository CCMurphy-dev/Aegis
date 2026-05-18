import SwiftUI

struct SystemStatusView: View {
    @ObservedObject private var statusMonitor = SystemStatusMonitor.shared
    @ObservedObject private var config = AegisConfig.shared
    @ObservedObject private var themeManager = ThemeManager.shared

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
                // Width 16 accommodates wider icons like book.fill (Study mode)
                FocusStatusIconView(focusStatus: statusMonitor.focusStatus)
                    .frame(width: statusMonitor.focusStatus.isEnabled ? 16 : 0, alignment: .leading)
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

            DateView()

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
        .foregroundColor(ThemeColors.foreground)
        .padding(.horizontal, 6)
        .frame(height: 20)
        .background(
            Group {
                if config.isLiquidGlass {
                    SpacePillGlassBackground(isActive: true, cornerRadius: 8)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(ThemeColors.background.opacity(config.inactiveSpaceBgOpacity))
                }
            }
        )
        .overlay(
            Group {
                if !config.isLiquidGlass {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(ThemeColors.border(opacity: config.activeBorderOpacity), lineWidth: 1)
                }
            }
        )
        .shadow(color: config.isLiquidGlass ? .black.opacity(0.20) : ThemeColors.shadow(), radius: config.isLiquidGlass ? 9 : 1, x: 0, y: config.isLiquidGlass ? 2 : 1)
    }
}
