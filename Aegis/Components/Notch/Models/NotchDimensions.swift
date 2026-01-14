//
//  NotchDimensions.swift
//  Aegis
//
//  Created by Claude on 13/01/2026.
//

import Foundation
import AppKit

/// Calculates the actual notch dimensions from screen properties
struct NotchDimensions {
    let width: CGFloat
    let height: CGFloat
    let padding: CGFloat = 16  // Extra padding on sides to push content away from notch edges

    /// Calculate notch dimensions for a given screen
    static func calculate(for screen: NSScreen) -> NotchDimensions {
        // Get notch height from safe area insets
        let height = screen.safeAreaInsets.top

        // Calculate notch width from auxiliary areas
        // The notch sits in the center, with auxiliary areas on left and right
        let totalWidth = screen.frame.width
        let leftArea = screen.auxiliaryTopLeftArea?.width ?? 0
        let rightArea = screen.auxiliaryTopRightArea?.width ?? 0
        let width = totalWidth - leftArea - rightArea

        return NotchDimensions(width: width, height: height)
    }

    /// Check if this screen has a notch
    var hasNotch: Bool {
        return height > 0
    }
}
