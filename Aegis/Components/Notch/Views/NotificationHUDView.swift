//
//  NotificationHUDView.swift
//  Aegis
//
//  HUD view for displaying system notifications in the notch
//  Layout matches existing HUD patterns: icon left of notch, content right of notch
//

import SwiftUI
import AppKit

struct NotificationHUDView: View {
    @ObservedObject var viewModel: NotificationHUDViewModel
    let notchDimensions: NotchDimensions

    @ObservedObject private var config = AegisConfig.shared

    // Panel widths - symmetric for centering
    private var leftPanelWidth: CGFloat {
        notchDimensions.height  // Square for icon
    }

    private var calculatedRightPanelWidth: CGFloat {
        // Calculate based on title/body text width
        let titleFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
        let bodyFont = NSFont.systemFont(ofSize: 8, weight: .medium)
        let titleWidth = viewModel.title.width(using: titleFont)
        let bodyWidth = viewModel.body.width(using: bodyFont)
        let maxTextWidth = max(titleWidth, bodyWidth)

        // Minimum width based on progress bar width, max reasonable width
        let minWidth = config.notchHUDProgressBarWidth + 16
        let maxWidth: CGFloat = 200

        return min(max(minWidth, maxTextWidth + 16), maxWidth)
    }

    private var panelWidth: CGFloat {
        max(leftPanelWidth, calculatedRightPanelWidth)
    }

    private let notchGapFill: CGFloat = 18

    var body: some View {
        let totalWidth = panelWidth + notchDimensions.width + panelWidth

        ZStack {
            // BACKGROUND LAYER - same pattern as DeviceHUDView
            // Note: Clicks are handled by NotificationHUDHostingView.mouseDown, not SwiftUI gestures
            HStack(spacing: 0) {
                // Left background - app icon
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

                // Right background - notification content
                HStack(spacing: 0) {
                    HUDRightPanelShape(cornerRadius: 10, topCornerRadius: 6, innerCornerRadius: 8)
                        .fill(Color.black)
                        .frame(width: calculatedRightPanelWidth + notchGapFill, height: notchDimensions.height)
                    Spacer(minLength: 0)
                }
                .frame(width: panelWidth + notchGapFill, alignment: .leading)
                .opacity(viewModel.isVisible ? 1 : 0)
                .offset(x: viewModel.isVisible ? 0 : -(notchDimensions.width / 2 + notchGapFill))
            }
            .frame(width: totalWidth, height: notchDimensions.height)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: viewModel.isVisible)

            // CONTENT LAYER - visual only, clicks handled at NSView level
            HStack(spacing: 0) {
                // Left side - app icon
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    if let icon = viewModel.appIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: config.notchHUDIconSize, height: config.notchHUDIconSize)
                            .clipShape(RoundedRectangle(cornerRadius: config.notchHUDIconSize * 0.2))
                    } else {
                        Image(systemName: "app.fill")
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

                // Right side - title and body
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(viewModel.title)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        if !viewModel.body.isEmpty {
                            Text(viewModel.body)
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: panelWidth, height: notchDimensions.height)
                .padding(.leading, 8)
                .opacity(viewModel.isVisible ? 1 : 0)
                .offset(x: viewModel.isVisible ? 0 : -notchDimensions.width / 2)
            }
            .frame(width: totalWidth, height: notchDimensions.height)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: viewModel.isVisible)
        }
        .frame(width: totalWidth, height: notchDimensions.height)
    }
}
