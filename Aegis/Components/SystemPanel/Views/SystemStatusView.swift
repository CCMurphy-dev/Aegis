import SwiftUI

struct SystemStatusView: View {
    @ObservedObject private var statusMonitor = SystemStatusMonitor.shared
    @ObservedObject private var config = AegisConfig.shared
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(config.systemStatusOrder.enumerated()), id: \.element) { index, component in
                if shouldShow(component) {
                    if index > 0, hasPreviousVisibleComponent(before: index) {
                        Color.clear.frame(width: 8)
                    }
                    componentView(for: component)
                }
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: statusMonitor.focusStatus.isEnabled)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: statusMonitor.focusStatus.symbolName)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: statusMonitor.focusStatus.focusName)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: statusMonitor.batteryLevel >= 1.0 && !statusMonitor.isCharging)
        .font(.system(size: 13, weight: .medium))
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

    private func shouldShow(_ component: String) -> Bool {
        switch component {
        case "focus":
            return statusMonitor.focusStatus.isEnabled
        case "cpu":
            return config.showCPUMonitor
        case "ram":
            return config.showRAMMonitor
        case "wifi":
            return true
        case "clock":
            return true
        case "date":
            return true
        case "battery":
            return statusMonitor.batteryLevel < 1.0 || statusMonitor.isCharging
        default:
            return false
        }
    }

    private func hasPreviousVisibleComponent(before index: Int) -> Bool {
        for i in 0..<index {
            if shouldShow(config.systemStatusOrder[i]) {
                return true
            }
        }
        return false
    }

    @ViewBuilder
    private func componentView(for component: String) -> some View {
        switch component {
        case "focus":
            if config.showFocusName {
                FocusStatusIconView(focusStatus: statusMonitor.focusStatus)
                    .fixedSize()
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            } else {
                FocusStatusIconView(focusStatus: statusMonitor.focusStatus)
                    .frame(width: 16, alignment: .leading)
            }
        case "cpu":
            CPUSparklineView()
        case "ram":
            RAMSparklineView()
        case "wifi":
            NetworkStatusIconView(status: statusMonitor.networkStatus)
        case "clock":
            ClockView()
        case "date":
            DateView()
        case "battery":
            BatteryStatusIconView(level: statusMonitor.batteryLevel,
                                  isCharging: statusMonitor.isCharging)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
        default:
            EmptyView()
        }
    }
}
