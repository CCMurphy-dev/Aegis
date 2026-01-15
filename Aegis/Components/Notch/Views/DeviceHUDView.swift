import SwiftUI
import Combine

/// ViewModel for device connection HUD
class DeviceHUDViewModel: ObservableObject {
    @Published var isVisible: Bool = false
    @Published var deviceInfo: BluetoothDeviceInfo?
    @Published var isConnecting: Bool = true  // true = connecting, false = disconnecting

    func show(device: BluetoothDeviceInfo, isConnecting: Bool) {
        self.deviceInfo = device
        self.isConnecting = isConnecting
        self.isVisible = true
    }
}

/// HUD view for displaying Bluetooth device connection/disconnection
struct DeviceHUDView: View {
    @ObservedObject var viewModel: DeviceHUDViewModel
    let notchDimensions: NotchDimensions

    @ObservedObject private var config = AegisConfig.shared

    // Panel widths - match Volume/Brightness HUD for consistency
    // Left side (device icon): fixed square size
    private var leftPanelWidth: CGFloat {
        notchDimensions.height
    }

    // Right side (device info): match progress bar width
    private var rightPanelWidth: CGFloat {
        config.notchHUDProgressBarWidth + 16
    }

    // Use symmetric max width for centering (same pattern as MinimalHUDWrapper)
    private var panelWidth: CGFloat {
        max(leftPanelWidth, rightPanelWidth)
    }

    private let notchGapFill: CGFloat = 18

    var body: some View {
        let totalWidth = panelWidth + notchDimensions.width + panelWidth

        ZStack {
            // BACKGROUND LAYER
            HStack(spacing: 0) {
                // Left background - device icon
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    HUDLeftPanelShape(cornerRadius: 10, topCornerRadius: 6, innerCornerRadius: 8)
                        .fill(Color.black)
                        .frame(width: leftPanelWidth + notchGapFill, height: notchDimensions.height)
                }
                .frame(width: panelWidth + notchGapFill, alignment: .trailing)
                .opacity(viewModel.isVisible ? 1 : 0)
                .offset(x: viewModel.isVisible ? 0 : notchDimensions.width / 2 + notchGapFill)

                // Notch spacer
                Color.clear
                    .frame(width: notchDimensions.width - (notchGapFill * 2), height: notchDimensions.height)

                // Right background - device name
                HStack(spacing: 0) {
                    HUDRightPanelShape(cornerRadius: 10, topCornerRadius: 6, innerCornerRadius: 8)
                        .fill(Color.black)
                        .frame(width: rightPanelWidth + notchGapFill, height: notchDimensions.height)
                    Spacer(minLength: 0)
                }
                .frame(width: panelWidth + notchGapFill, alignment: .leading)
                .opacity(viewModel.isVisible ? 1 : 0)
                .offset(x: viewModel.isVisible ? 0 : -(notchDimensions.width / 2 + notchGapFill))
            }
            .frame(width: totalWidth, height: notchDimensions.height)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: viewModel.isVisible)

            // CONTENT LAYER
            HStack(spacing: 0) {
                // Left side - device icon
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    if let device = viewModel.deviceInfo {
                        Image(systemName: device.deviceType.iconName)
                            .font(.system(size: config.notchHUDIconSize, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: panelWidth, height: notchDimensions.height)
                .opacity(viewModel.isVisible ? 1 : 0)
                .offset(x: viewModel.isVisible ? 0 : notchDimensions.width / 2)

                // Notch spacer
                Color.clear
                    .frame(width: notchDimensions.width, height: notchDimensions.height)

                // Right side - device name and status
                HStack(spacing: 0) {
                    if let device = viewModel.deviceInfo {
                        HStack(spacing: 6) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(device.deviceType.displayName)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)

                                Text(viewModel.isConnecting ? "Connected" : "Disconnected")
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundColor(viewModel.isConnecting ? .green : .gray)
                            }

                            // Battery ring indicator
                            if let battery = device.batteryLevel, viewModel.isConnecting {
                                BatteryRingView(level: battery)
                                    .frame(width: 18, height: 18)
                            }
                        }
                        .frame(maxWidth: rightPanelWidth - 12, alignment: .leading)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: panelWidth, height: notchDimensions.height)
                .opacity(viewModel.isVisible ? 1 : 0)
                .offset(x: viewModel.isVisible ? 0 : -notchDimensions.width / 2)
            }
            .frame(width: totalWidth, height: notchDimensions.height)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: viewModel.isVisible)
        }
        .frame(width: totalWidth, height: notchDimensions.height)
    }

}

/// Circular battery ring indicator (like iPhone Dynamic Island)
struct BatteryRingView: View {
    let level: Int

    private var progress: Double {
        Double(level) / 100.0
    }

    private var ringColor: Color {
        if level <= 10 {
            return .red
        } else if level <= 20 {
            return .orange
        } else {
            return .green
        }
    }

    var body: some View {
        ZStack {
            // Background ring (unfilled)
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 2.5)

            // Foreground ring (filled based on battery level)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
