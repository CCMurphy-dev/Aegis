import SwiftUI
import Combine

/// ViewModel for Focus mode HUD
class FocusHUDViewModel: ObservableObject {
    @Published var isVisible: Bool = false
    @Published var focusStatus: FocusStatus = .disabled

    func show(status: FocusStatus) {
        self.focusStatus = status
        self.isVisible = true
    }
}

/// HUD view for displaying Focus mode changes
struct FocusHUDView: View {
    @ObservedObject var viewModel: FocusHUDViewModel
    let notchDimensions: NotchDimensions

    @ObservedObject private var config = AegisConfig.shared

    // Panel widths - match Volume/Brightness HUD for consistency
    // Left side (focus icon): fixed square size
    private var leftPanelWidth: CGFloat {
        notchDimensions.height
    }

    // Right side (focus name): match progress bar width
    private var rightPanelWidth: CGFloat {
        config.notchHUDProgressBarWidth + 16
    }

    // Use symmetric max width for centering (same pattern as MinimalHUDWrapper)
    private var panelWidth: CGFloat {
        max(leftPanelWidth, rightPanelWidth)
    }

    private let notchGapFill: CGFloat = 18

    // Icon name from Focus status
    private var iconName: String {
        if let symbol = viewModel.focusStatus.symbolName, !symbol.isEmpty {
            return symbol
        }
        return "moon.fill"
    }

    // Display name for Focus mode (e.g., "Study" or "Do Not Disturb")
    private var focusName: String {
        // Use the focus name if available, otherwise fallback to "Focus"
        viewModel.focusStatus.focusName ?? "Focus"
    }

    // Status text
    private var statusText: String {
        viewModel.focusStatus.isEnabled ? "On" : "Off"
    }

    // Status color
    private var statusColor: Color {
        viewModel.focusStatus.isEnabled ? .purple : .gray
    }

    var body: some View {
        let totalWidth = panelWidth + notchDimensions.width + panelWidth

        ZStack {
            // BACKGROUND LAYER
            HStack(spacing: 0) {
                // Left background - focus icon
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

                // Right background - focus name
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
                // Left side - focus icon (centered within leftPanelWidth, aligned trailing in container)
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Image(systemName: iconName)
                        .font(.system(size: config.notchHUDIconSize, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: leftPanelWidth, height: notchDimensions.height)
                }
                .frame(width: panelWidth, height: notchDimensions.height)
                .opacity(viewModel.isVisible ? 1 : 0)
                .offset(x: viewModel.isVisible ? 0 : notchDimensions.width / 2)

                // Notch spacer
                Color.clear
                    .frame(width: notchDimensions.width, height: notchDimensions.height)

                // Right side - focus name and status
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(focusName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Text(statusText)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(statusColor)
                    }
                    .frame(maxWidth: rightPanelWidth - 12, alignment: .leading)
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
