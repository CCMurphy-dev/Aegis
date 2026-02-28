import SwiftUI
import AppKit

extension Notification.Name {
    static let themeDidChange = Notification.Name("com.aegis.themeDidChange")
}

struct ThemeColors {
    private static var themeManager: ThemeManager { ThemeManager.shared }

    // MARK: - SwiftUI Colors

    static var foreground: Color {
        themeManager.isDarkMode ? .white : .black
    }

    static var background: Color {
        themeManager.isDarkMode ? .black : .white
    }

    static func spaceBackground(opacity: Double) -> Color {
        background.opacity(opacity)
    }

    static func buttonBackground(opacity: Double) -> Color {
        background.opacity(opacity)
    }

    static func primaryText(opacity: Double = 1.0) -> Color {
        foreground.opacity(opacity)
    }

    static func secondaryText(opacity: Double = 0.9) -> Color {
        foreground.opacity(opacity)
    }

    static func tertiaryText(opacity: Double = 0.6) -> Color {
        foreground.opacity(opacity)
    }

    static func border(opacity: Double = 0.25) -> Color {
        foreground.opacity(opacity)
    }

    static func shadow(opacity: Double = 0.3) -> Color {
        Color.black.opacity(opacity)
    }

    // MARK: - CGColor Accessors

    static func foregroundCGColor(alpha: CGFloat) -> CGColor {
        if themeManager.isDarkMode {
            return CGColor(gray: 1.0, alpha: alpha)
        } else {
            return CGColor(gray: 0.0, alpha: alpha)
        }
    }

    static func backgroundCGColor(alpha: CGFloat) -> CGColor {
        if themeManager.isDarkMode {
            return CGColor(gray: 0.0, alpha: alpha)
        } else {
            return CGColor(gray: 1.0, alpha: alpha)
        }
    }

    // MARK: - NSColor Accessors

    static func foregroundNSColor(alpha: CGFloat) -> NSColor {
        if themeManager.isDarkMode {
            return NSColor.white.withAlphaComponent(alpha)
        } else {
            return NSColor.black.withAlphaComponent(alpha)
        }
    }

    static func backgroundNSColor(alpha: CGFloat) -> NSColor {
        if themeManager.isDarkMode {
            return NSColor.black.withAlphaComponent(alpha)
        } else {
            return NSColor.white.withAlphaComponent(alpha)
        }
    }
}
