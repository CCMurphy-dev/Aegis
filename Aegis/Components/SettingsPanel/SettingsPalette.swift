import AppKit
import SwiftUI

/// Dynamic system colors used by the settings window.
///
/// These deliberately do not use the bar theme: settings follow the macOS
/// appearance selected by the user, while the menu bar can remain customized.
enum SettingsPalette {
    static var background: Color { Color(nsColor: .windowBackgroundColor) }
    static var controlBackground: Color { Color(nsColor: .controlBackgroundColor) }
    static var primaryText: Color { Color(nsColor: .labelColor) }
    static var secondaryText: Color { Color(nsColor: .secondaryLabelColor) }
    static var tertiaryText: Color { Color(nsColor: .tertiaryLabelColor) }
    static var separator: Color { Color(nsColor: .separatorColor) }

    static var windowBackground: NSColor { .windowBackgroundColor }

    /// Resolves a dynamic color under a specific system appearance for tests
    /// and other AppKit callers that need an opaque color value.
    static func resolved(_ color: NSColor, for appearanceName: NSAppearance.Name) -> NSColor {
        var resolvedColor = color
        NSAppearance(named: appearanceName)?.performAsCurrentDrawingAppearance {
            resolvedColor = color.usingColorSpace(.deviceRGB) ?? color
        }
        return resolvedColor
    }
}
