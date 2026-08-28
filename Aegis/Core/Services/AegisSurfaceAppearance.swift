import AppKit
import Combine
import SwiftUI

/// The colors and rendering mode used by surfaces that can adopt the system's
/// Liquid Glass treatment.  This is deliberately separate from ThemeColors:
/// the bar theme remains user-controlled, while the native glass surface is
/// provided by macOS.
struct AegisSurfacePalette {
    let background: NSColor
    let foreground: NSColor
    let secondaryForeground: NSColor
    let border: NSColor
}

enum AegisSurfaceRenderingMode: Equatable {
    case solid
    case legacyMaterial
    case nativeGlass
}

final class AegisSurfaceAppearance: ObservableObject {
    static let shared = AegisSurfaceAppearance()

    @Published private(set) var reduceTransparency: Bool
    private var observer: NSObjectProtocol?

    init(workspace: NSWorkspace = .shared) {
        reduceTransparency = workspace.accessibilityDisplayShouldReduceTransparency
        observer = NotificationCenter.default.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: workspace,
            queue: .main
        ) { [weak self, weak workspace] _ in
            guard let self, let workspace else { return }
            self.reduceTransparency = workspace.accessibilityDisplayShouldReduceTransparency
            NotificationCenter.default.post(name: .themeDidChange, object: nil)
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Kept pure so availability and accessibility behavior can be tested
    /// without constructing AppKit glass views.
    static func shouldUseNativeGlass(
        theme: AppTheme,
        reduceTransparency: Bool,
        nativeGlassAvailable: Bool
    ) -> Bool {
        pillRenderingMode(
            theme: theme,
            reduceTransparency: reduceTransparency,
            nativeGlassAvailable: nativeGlassAvailable
        ) == .nativeGlass
    }

    static func menuBarRenderingMode(
        theme: AppTheme,
        reduceTransparency: Bool,
        nativeGlassAvailable: Bool
    ) -> AegisSurfaceRenderingMode {
        if reduceTransparency { return .solid }
        // The menu bar is deliberately kept as the existing full-width
        // background. Liquid Glass applies only to individual pills.
        return .legacyMaterial
    }

    static func pillRenderingMode(
        theme: AppTheme,
        reduceTransparency: Bool,
        nativeGlassAvailable: Bool
    ) -> AegisSurfaceRenderingMode {
        if reduceTransparency { return .solid }
        guard theme == .liquidGlass else { return .solid }
        return nativeGlassAvailable ? .nativeGlass : .legacyMaterial
    }

    static func switcherRenderingMode(
        theme: AppTheme,
        reduceTransparency: Bool,
        nativeGlassAvailable: Bool
    ) -> AegisSurfaceRenderingMode {
        if reduceTransparency { return .solid }
        if theme == .liquidGlass {
            return nativeGlassAvailable ? .nativeGlass : .legacyMaterial
        }
        return .solid
    }

    @MainActor
    static func palette(
        theme: AppTheme,
        isDarkMode: Bool,
        customBackground: String? = nil,
        customForeground: String? = nil,
        customBorder: String? = nil
    ) -> AegisSurfacePalette {
        if theme == .custom {
            let background = customBackground.flatMap(NSColor.init(hex:))
                ?? NSColor.black
            let foreground = customForeground.flatMap(NSColor.init(hex:))
                ?? NSColor.white
            let border = customBorder.flatMap(NSColor.init(hex:))
                ?? foreground
            return AegisSurfacePalette(
                background: background,
                foreground: foreground,
                secondaryForeground: foreground.withAlphaComponent(0.78),
                border: border
            )
        }

        if theme == .liquidGlass || theme == .system {
            return AegisSurfacePalette(
                background: NSColor.windowBackgroundColor,
                foreground: NSColor.labelColor,
                secondaryForeground: NSColor.secondaryLabelColor,
                border: NSColor.separatorColor
            )
        }

        let background = isDarkMode ? NSColor.black : NSColor.white
        let foreground = isDarkMode ? NSColor.white : NSColor.black
        return AegisSurfacePalette(
            background: background,
            foreground: foreground,
            secondaryForeground: foreground.withAlphaComponent(0.78),
            border: foreground.withAlphaComponent(0.28)
        )
    }

    var usesNativeGlass: Bool {
        if #available(macOS 26.0, *) {
            return Self.pillRenderingMode(
                theme: AegisConfig.shared.appTheme,
                reduceTransparency: reduceTransparency,
                nativeGlassAvailable: true
            ) == .nativeGlass
        }
        return false
    }
}

/// The full-width menu bar keeps its existing background treatment. Liquid
/// Glass is intentionally scoped to workspace and system-status pills.
struct AegisMenuBarSurface<Content: View>: View {
    @ObservedObject private var config = AegisConfig.shared
    @ObservedObject private var appearance = AegisSurfaceAppearance.shared
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private var nativeGlassAvailable: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    var body: some View {
        let renderingMode = AegisSurfaceAppearance.menuBarRenderingMode(
            theme: config.appTheme,
            reduceTransparency: appearance.reduceTransparency,
            nativeGlassAvailable: nativeGlassAvailable
        )

        Group {
            switch renderingMode {
            case .solid:
                ZStack(alignment: .top) {
                    ThemeColors.background
                    content
                }
            case .nativeGlass:
                // This case is not returned by menuBarRenderingMode, but
                // keep a safe fallback if another caller extends the enum.
                ZStack(alignment: .top) {
                    GradientBlurView(material: .hudWindow, blendingMode: .behindWindow)
                    content
                }
            case .legacyMaterial:
                ZStack(alignment: .top) {
                    GradientBlurView(material: .hudWindow, blendingMode: .behindWindow)
                    content
                }
            }
        }
    }
}

@available(macOS 26.0, *)
struct AegisNativeGlassBackground: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSGlassEffectView {
        let glass = NSGlassEffectView()
        glass.style = .regular
        glass.cornerRadius = cornerRadius
        return glass
    }

    func updateNSView(_ nsView: NSGlassEffectView, context: Context) {
        nsView.style = .regular
        nsView.cornerRadius = cornerRadius
    }
}
