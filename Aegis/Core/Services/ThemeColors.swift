import SwiftUI
import AppKit

extension Notification.Name {
    static let themeDidChange = Notification.Name("com.aegis.themeDidChange")
}

struct ThemeColors {
    private static var themeManager: ThemeManager { ThemeManager.shared }
    private static var config: AegisConfig { AegisConfig.shared }
    private static var isCustom: Bool { config.appTheme == .custom }

    // MARK: - SwiftUI Colors

    static var foreground: Color {
        if isCustom, let hex = config.customTextColor, let color = Color(hex: hex) {
            return color
        }
        return themeManager.isDarkMode ? .white : .black
    }

    static var background: Color {
        if isCustom, let hex = config.customBackgroundColor, let color = Color(hex: hex) {
            return color
        }
        return themeManager.isDarkMode ? .black : .white
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
        if isCustom, let hex = config.customBorderColor, let color = Color(hex: hex) {
            return color.opacity(opacity)
        }
        return foreground.opacity(opacity)
    }

    static func shadow(opacity: Double = 0.3) -> Color {
        Color.black.opacity(opacity)
    }

    // MARK: - CGColor Accessors

    static func foregroundCGColor(alpha: CGFloat) -> CGColor {
        if isCustom, let hex = config.customTextColor, let nsColor = NSColor(hex: hex) {
            return nsColor.withAlphaComponent(alpha).cgColor
        }
        if themeManager.isDarkMode {
            return CGColor(gray: 1.0, alpha: alpha)
        } else {
            return CGColor(gray: 0.0, alpha: alpha)
        }
    }

    static func backgroundCGColor(alpha: CGFloat) -> CGColor {
        if isCustom, let hex = config.customBackgroundColor, let nsColor = NSColor(hex: hex) {
            return nsColor.withAlphaComponent(alpha).cgColor
        }
        if themeManager.isDarkMode {
            return CGColor(gray: 0.0, alpha: alpha)
        } else {
            return CGColor(gray: 1.0, alpha: alpha)
        }
    }

    static func borderCGColor(alpha: CGFloat) -> CGColor {
        if isCustom, let hex = config.customBorderColor, let nsColor = NSColor(hex: hex) {
            return nsColor.withAlphaComponent(alpha).cgColor
        }
        return foregroundCGColor(alpha: alpha)
    }

    // MARK: - NSColor Accessors

    static func foregroundNSColor(alpha: CGFloat) -> NSColor {
        if isCustom, let hex = config.customTextColor, let nsColor = NSColor(hex: hex) {
            return nsColor.withAlphaComponent(alpha)
        }
        if themeManager.isDarkMode {
            return NSColor.white.withAlphaComponent(alpha)
        } else {
            return NSColor.black.withAlphaComponent(alpha)
        }
    }

    static func backgroundNSColor(alpha: CGFloat) -> NSColor {
        if isCustom, let hex = config.customBackgroundColor, let nsColor = NSColor(hex: hex) {
            return nsColor.withAlphaComponent(alpha)
        }
        if themeManager.isDarkMode {
            return NSColor.black.withAlphaComponent(alpha)
        } else {
            return NSColor.white.withAlphaComponent(alpha)
        }
    }

    static func borderNSColor(alpha: CGFloat) -> NSColor {
        if isCustom, let hex = config.customBorderColor, let nsColor = NSColor(hex: hex) {
            return nsColor.withAlphaComponent(alpha)
        }
        return foregroundNSColor(alpha: alpha)
    }
}
