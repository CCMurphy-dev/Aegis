import AppKit
import XCTest
@testable import Aegis

@MainActor
final class AppSwitcherSurfaceAppearanceTests: XCTestCase {
    func testSwitcherUsesSolidThemesAndNativeLiquidGlass() {
        for theme in [AppTheme.dark, .light, .system, .custom] {
            XCTAssertEqual(
                AegisSurfaceAppearance.switcherRenderingMode(
                    theme: theme,
                    reduceTransparency: false,
                    nativeGlassAvailable: true
                ),
                .solid
            )
        }

        XCTAssertEqual(
            AegisSurfaceAppearance.switcherRenderingMode(
                theme: .liquidGlass,
                reduceTransparency: false,
                nativeGlassAvailable: true
            ),
            .nativeGlass
        )
        XCTAssertEqual(
            AegisSurfaceAppearance.switcherRenderingMode(
                theme: .liquidGlass,
                reduceTransparency: false,
                nativeGlassAvailable: false
            ),
            .legacyMaterial
        )
        XCTAssertEqual(
            AegisSurfaceAppearance.switcherRenderingMode(
                theme: .liquidGlass,
                reduceTransparency: true,
                nativeGlassAvailable: true
            ),
            .solid
        )
    }

    func testThemePalettesKeepTextReadable() {
        assertReadablePalette(theme: .dark, isDarkMode: true)
        assertReadablePalette(theme: .light, isDarkMode: false)
        assertReadablePalette(theme: .system, isDarkMode: false, appearance: .aqua)
        assertReadablePalette(theme: .system, isDarkMode: true, appearance: .darkAqua)
    }

    func testCustomPaletteUsesConfiguredColors() {
        let palette = AegisSurfaceAppearance.palette(
            theme: .custom,
            isDarkMode: true,
            customBackground: "#102030",
            customForeground: "#F5F7FA",
            customBorder: "#8090A0"
        )
        assertRGB(palette.background, red: 0x10, green: 0x20, blue: 0x30)
        assertRGB(palette.foreground, red: 0xF5, green: 0xF7, blue: 0xFA)
        assertReadablePalette(theme: .custom, isDarkMode: true)
    }

    private func assertReadablePalette(
        theme: AppTheme,
        isDarkMode: Bool,
        appearance: NSAppearance.Name? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let assertion = {
            let palette = AegisSurfaceAppearance.palette(theme: theme, isDarkMode: isDarkMode)
            XCTAssertGreaterThanOrEqual(self.contrastRatio(palette.foreground, palette.background), 4.5, file: file, line: line)
            XCTAssertGreaterThanOrEqual(self.contrastRatio(palette.secondaryForeground, palette.background), 3.0, file: file, line: line)
            XCTAssertGreaterThanOrEqual(self.contrastRatio(palette.tertiaryForeground, palette.background), 2.0, file: file, line: line)

            let selectedBackground = self.composite(palette.selectionFill, over: palette.background)
            XCTAssertGreaterThanOrEqual(self.contrastRatio(palette.foreground, selectedBackground), 4.5, file: file, line: line)
        }

        if let appearance, let resolvedAppearance = NSAppearance(named: appearance) {
            resolvedAppearance.performAsCurrentDrawingAppearance(assertion)
        } else {
            assertion()
        }
    }

    private func composite(_ foreground: NSColor, over background: NSColor) -> NSColor {
        let foreground = foreground.usingColorSpace(.sRGB)!
        let background = background.usingColorSpace(.sRGB)!
        let alpha = foreground.alphaComponent
        return NSColor(
            red: foreground.redComponent * alpha + background.redComponent * (1 - alpha),
            green: foreground.greenComponent * alpha + background.greenComponent * (1 - alpha),
            blue: foreground.blueComponent * alpha + background.blueComponent * (1 - alpha),
            alpha: 1
        )
    }

    private func contrastRatio(_ foreground: NSColor, _ background: NSColor) -> CGFloat {
        func luminance(_ color: NSColor) -> CGFloat {
            let rgb = color.usingColorSpace(.sRGB)!
            func linear(_ value: CGFloat) -> CGFloat {
                value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(rgb.redComponent)
                + 0.7152 * linear(rgb.greenComponent)
                + 0.0722 * linear(rgb.blueComponent)
        }
        let values = [luminance(foreground), luminance(background)].sorted()
        return (values[1] + 0.05) / (values[0] + 0.05)
    }

    private func assertRGB(
        _ color: NSColor,
        red: UInt8,
        green: UInt8,
        blue: UInt8,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let rgb = color.usingColorSpace(.sRGB)!
        XCTAssertEqual(UInt8((rgb.redComponent * 255).rounded()), red, file: file, line: line)
        XCTAssertEqual(UInt8((rgb.greenComponent * 255).rounded()), green, file: file, line: line)
        XCTAssertEqual(UInt8((rgb.blueComponent * 255).rounded()), blue, file: file, line: line)
    }
}
