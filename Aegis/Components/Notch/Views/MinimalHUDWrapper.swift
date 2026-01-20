//
//  MinimalHUDWrapper.swift
//  Aegis
//
//  Created by Claude on 13/01/2026.
//

import SwiftUI

/// Wrapper that positions HUD content around the notch, matching mew-notch's approach
struct MinimalHUDWrapper: View {
    @ObservedObject var viewModel: OverlayHUDViewModel
    @ObservedObject var mediaViewModel: MediaHUDViewModel
    let notchDimensions: NotchDimensions
    @Binding var isVisible: Bool

    @ObservedObject private var config = AegisConfig.shared

    // Calculate the width of each HUD side panel
    // Left side (icon): fixed square size
    private var leftPanelWidth: CGFloat {
        notchDimensions.height
    }

    // Base right panel width (overlay's own content)
    private var baseRightPanelWidth: CGFloat {
        if config.notchHUDUseProgressBar {
            // Progress bar width + padding on each side
            return config.notchHUDProgressBarWidth + 16
        } else {
            // Text value - use square size
            return notchDimensions.height
        }
    }

    // Right side (progress bar or value): must be at least as wide as media content
    private var rightPanelWidth: CGFloat {
        max(baseRightPanelWidth, mediaViewModel.currentRightPanelWidth)
    }

    // How far the black background extends into the notch area to fill the gap
    // This only affects the background shape, not the content position
    private let notchGapFill: CGFloat = 18

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
                // Left container - icon centered within the visible left panel area
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    // Icon explicitly centered within leftPanelWidth frame
                    Image(systemName: viewModel.iconName)
                        .font(.system(size: config.notchHUDIconSize, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: leftPanelWidth, height: notchDimensions.height, alignment: .center)
                }
                .frame(width: maxSideWidth)
                .opacity(isVisible ? 1 : 0)
                .offset(x: isVisible ? 0 : notchDimensions.width / 2)

                // Notch spacer
                Color.clear
                    .frame(width: notchDimensions.width, height: notchDimensions.height)

                // Right container - progress bar centered within visible right panel area
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
