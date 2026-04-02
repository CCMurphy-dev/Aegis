import SwiftUI

/// A small pill badge showing the active AeroSpace mode.
/// Only rendered when mode != "main" — visibility is controlled by the parent.
/// Styled to match the active space indicator (same background opacity, border, text color).
struct AeroSpaceModeBadge: View {
    let mode: String
    @ObservedObject private var config = AegisConfig.shared

    var body: some View {
        Text(mode.uppercased())
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundColor(ThemeColors.primaryText())
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(ThemeColors.background.opacity(config.activeSpaceBgOpacity))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(ThemeColors.border(opacity: 0.18), lineWidth: 1)
                    )
            )
            .shadow(color: ThemeColors.foreground.opacity(0.12), radius: 6)
            .padding(.trailing, 6)
    }
}
