import SwiftUI

/// Displays the Focus mode icon using the actual SF Symbol from the user's Focus configuration
/// Optionally shows the Focus name alongside the symbol based on config
struct FocusStatusIconView: View {
    let focusStatus: FocusStatus

    @ObservedObject private var config = AegisConfig.shared

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: 11, weight: .medium))

            // Show focus name if enabled and available
            if config.showFocusName, let name = focusStatus.focusName, !name.isEmpty {
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
        }
        .foregroundColor(.white)
    }

    /// Uses the actual symbol from the Focus configuration, falls back to moon.fill
    private var iconName: String {
        // Use the symbol directly from the Focus status if available
        if let symbol = focusStatus.symbolName, !symbol.isEmpty {
            return symbol
        }

        // Fallback to moon.fill for Do Not Disturb
        return "moon.fill"
    }
}
