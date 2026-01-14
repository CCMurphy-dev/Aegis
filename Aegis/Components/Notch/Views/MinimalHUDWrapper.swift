//
//  MinimalHUDWrapper.swift
//  Aegis
//
//  Created by Claude on 13/01/2026.
//

import SwiftUI
import Combine

/// Wrapper that positions HUD content around the notch, matching mew-notch's approach
struct MinimalHUDWrapper: View {
    @ObservedObject var viewModel: OverlayHUDViewModel
    let notchDimensions: NotchDimensions
    @Binding var isVisible: Bool

    @ObservedObject private var config = AegisConfig.shared

    // Calculate the width of each HUD side panel
    // Left side (icon): fixed square size
    private var leftPanelWidth: CGFloat {
        notchDimensions.height
    }

    // Right side (progress bar or value): needs to accommodate content
    private var rightPanelWidth: CGFloat {
        if config.notchHUDUseProgressBar {
            // Progress bar width + padding on each side
            return config.notchHUDProgressBarWidth + 16
        } else {
            // Text value - use square size
            return notchDimensions.height
        }
    }

    // How far the black background extends into the notch area to fill the gap
    // This only affects the background shape, not the content position
    private let notchGapFill: CGFloat = 8

    var body: some View {
        // Use symmetric max width for both sides to ensure proper centering
        // This way the notch spacer is always at the center of the frame
        let maxSideWidth = max(leftPanelWidth, rightPanelWidth)
        let totalWidth = maxSideWidth + notchDimensions.width + maxSideWidth

        ZStack {
            // BACKGROUND LAYER: Black shapes that extend into notch area to fill gaps
            HStack(spacing: 0) {
                // Left background - extends right into notch area
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    HUDLeftPanelShape(cornerRadius: 10, topCornerRadius: 6, innerCornerRadius: 8)
                        .fill(Color.black)
                        .frame(width: leftPanelWidth + notchGapFill, height: notchDimensions.height)
                }
                .frame(width: maxSideWidth + notchGapFill, alignment: .trailing)
                .opacity(isVisible ? 1 : 0)
                .offset(x: isVisible ? 0 : notchDimensions.width / 2 + notchGapFill)

                // Notch spacer (reduced by gap fill on both sides)
                Color.clear
                    .frame(width: notchDimensions.width - (notchGapFill * 2), height: notchDimensions.height)

                // Right background - extends left into notch area
                HStack(spacing: 0) {
                    HUDRightPanelShape(cornerRadius: 10, topCornerRadius: 6, innerCornerRadius: 8)
                        .fill(Color.black)
                        .frame(width: rightPanelWidth + notchGapFill, height: notchDimensions.height)
                    Spacer(minLength: 0)
                }
                .frame(width: maxSideWidth + notchGapFill, alignment: .leading)
                .opacity(isVisible ? 1 : 0)
                .offset(x: isVisible ? 0 : -(notchDimensions.width / 2 + notchGapFill))
            }
            .frame(width: totalWidth, height: notchDimensions.height)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isVisible)

            // CONTENT LAYER: Positioned normally without overlap
            HStack(spacing: 0) {
                // Left container - icon aligned trailing (toward notch)
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Image(systemName: viewModel.iconName)
                        .font(.system(size: config.notchHUDIconSize, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: leftPanelWidth, height: notchDimensions.height)
                }
                .frame(width: maxSideWidth)
                .opacity(isVisible ? 1 : 0)
                .offset(x: isVisible ? 0 : notchDimensions.width / 2)

                // Notch spacer
                Color.clear
                    .frame(width: notchDimensions.width, height: notchDimensions.height)

                // Right container - progress bar aligned leading (toward notch)
                HStack(spacing: 0) {
                    Group {
                        if config.notchHUDUseProgressBar {
                            HUDProgressBar(animator: viewModel.progressAnimator)
                        } else {
                            Text("\(Int(viewModel.isMuted ? 0 : viewModel.level * 100))")
                                .font(.system(size: config.notchHUDValueFontSize, weight: .bold))
                                .foregroundColor(.white)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .frame(width: rightPanelWidth, height: notchDimensions.height)
                    Spacer(minLength: 0)
                }
                .frame(width: maxSideWidth)
                .opacity(isVisible ? 1 : 0)
                .offset(x: isVisible ? 0 : -notchDimensions.width / 2)
            }
            .frame(width: totalWidth, height: notchDimensions.height)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isVisible)
        }
        .frame(width: totalWidth, height: notchDimensions.height)
    }

    // MARK: - Helpers

    /// Volume icon helper - selects appropriate speaker icon based on level
    static func volumeIcon(for level: Float) -> String {
        if level == 0 { return "speaker.slash.fill" }
        if level < 0.33 { return "speaker.fill" }
        if level < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

/// Shape for LEFT panel - curved outer edges, inner edge curves outward to connect with notch
struct HUDLeftPanelShape: Shape {
    let cornerRadius: CGFloat
    let topCornerRadius: CGFloat
    let innerCornerRadius: CGFloat  // Curves outward to match notch's bottom corner

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Top-left: outward curve
        path.move(to: CGPoint(x: topCornerRadius, y: 0))
        path.addQuadCurve(
            to: CGPoint(x: 0, y: topCornerRadius),
            control: CGPoint(x: 0, y: 0)
        )

        // Left edge down
        path.addLine(to: CGPoint(x: 0, y: rect.height - cornerRadius))

        // Bottom-left rounded corner (inward)
        path.addQuadCurve(
            to: CGPoint(x: cornerRadius, y: rect.height),
            control: CGPoint(x: 0, y: rect.height)
        )

        // Bottom edge to inner corner
        path.addLine(to: CGPoint(x: rect.width - innerCornerRadius, y: rect.height))

        // Bottom-right: outward curve (concave - matches notch's corner)
        path.addQuadCurve(
            to: CGPoint(x: rect.width, y: rect.height - innerCornerRadius),
            control: CGPoint(x: rect.width, y: rect.height)
        )

        // Right edge straight up to top
        path.addLine(to: CGPoint(x: rect.width, y: 0))

        // Top edge back to start
        path.addLine(to: CGPoint(x: topCornerRadius, y: 0))

        return path
    }
}

/// Shape for RIGHT panel - curved outer edges, inner edge curves outward to connect with notch
struct HUDRightPanelShape: Shape {
    let cornerRadius: CGFloat
    let topCornerRadius: CGFloat
    let innerCornerRadius: CGFloat  // Curves outward to match notch's bottom corner

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Start at top-left (connects to notch)
        path.move(to: CGPoint(x: 0, y: 0))

        // Left edge straight down to inner corner
        path.addLine(to: CGPoint(x: 0, y: rect.height - innerCornerRadius))

        // Bottom-left: outward curve (concave - matches notch's corner)
        path.addQuadCurve(
            to: CGPoint(x: innerCornerRadius, y: rect.height),
            control: CGPoint(x: 0, y: rect.height)
        )

        // Bottom edge to outer corner
        path.addLine(to: CGPoint(x: rect.width - cornerRadius, y: rect.height))

        // Bottom-right rounded corner (inward)
        path.addQuadCurve(
            to: CGPoint(x: rect.width, y: rect.height - cornerRadius),
            control: CGPoint(x: rect.width, y: rect.height)
        )

        // Right edge up
        path.addLine(to: CGPoint(x: rect.width, y: topCornerRadius))

        // Top-right: outward curve
        path.addQuadCurve(
            to: CGPoint(x: rect.width - topCornerRadius, y: 0),
            control: CGPoint(x: rect.width, y: 0)
        )

        // Top edge back to start
        path.addLine(to: CGPoint(x: 0, y: 0))

        return path
    }
}

/// Progress bar for volume/brightness HUD with frame-locked interpolation
struct HUDProgressBar: View {
    @ObservedObject var animator: ProgressBarAnimator
    @ObservedObject private var config = AegisConfig.shared

    var body: some View {
        let width = config.notchHUDProgressBarWidth * CGFloat(animator.displayed)

        return ZStack(alignment: .leading) {
            // Background track
            RoundedRectangle(cornerRadius: config.notchHUDProgressBarHeight / 2)
                .fill(Color.white.opacity(0.3))
                .frame(width: config.notchHUDProgressBarWidth, height: config.notchHUDProgressBarHeight)

            // Filled portion - uses frame-locked animator's displayed value
            RoundedRectangle(cornerRadius: config.notchHUDProgressBarHeight / 2)
                .fill(Color.white)
                .frame(width: width, height: config.notchHUDProgressBarHeight)
        }
        .frame(width: config.notchHUDProgressBarWidth, height: config.notchHUDProgressBarHeight)
        .animation(nil, value: animator.displayed)  // Disable SwiftUI animation - we handle smoothing
        .transaction { transaction in
            // Freeze layout during value updates
            transaction.animation = nil
        }
    }
}
