import AppKit
import XCTest
@testable import Aegis

@MainActor
final class AegisSurfaceAppearanceTests: XCTestCase {
    func testNativeGlassOnlyAppliesToSmallLiquidGlassSurfaces() {
        XCTAssertTrue(AegisSurfaceAppearance.shouldUseNativeGlass(
            theme: .liquidGlass, reduceTransparency: false, nativeGlassAvailable: true
        ))
        XCTAssertFalse(AegisSurfaceAppearance.shouldUseNativeGlass(
            theme: .dark, reduceTransparency: false, nativeGlassAvailable: true
        ))
        XCTAssertFalse(AegisSurfaceAppearance.shouldUseNativeGlass(
            theme: .liquidGlass, reduceTransparency: true, nativeGlassAvailable: true
        ))
        XCTAssertFalse(AegisSurfaceAppearance.shouldUseNativeGlass(
            theme: .liquidGlass, reduceTransparency: false, nativeGlassAvailable: false
        ))

        XCTAssertEqual(
            AegisSurfaceAppearance.menuBarRenderingMode(
                theme: .liquidGlass,
                reduceTransparency: false,
                nativeGlassAvailable: true
            ),
            .legacyMaterial
        )
        XCTAssertEqual(
            AegisSurfaceAppearance.pillRenderingMode(
                theme: .liquidGlass,
                reduceTransparency: false,
                nativeGlassAvailable: true
            ),
            .nativeGlass
        )
        XCTAssertEqual(
            AegisSurfaceAppearance.pillRenderingMode(
                theme: .liquidGlass,
                reduceTransparency: true,
                nativeGlassAvailable: true
            ),
            .solid
        )
    }

    func testPaletteHasReadableThemePairs() {
        for theme in AppTheme.allCases {
            let palette = AegisSurfaceAppearance.palette(theme: theme, isDarkMode: true)
            XCTAssertGreaterThanOrEqual(contrastRatio(palette.foreground, palette.background), 4.5)
        }

        let custom = AegisSurfaceAppearance.palette(
            theme: .custom,
            isDarkMode: true,
            customBackground: "#101010",
            customForeground: "#FFFFFF"
        )
        XCTAssertGreaterThanOrEqual(contrastRatio(custom.foreground, custom.background), 4.5)
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
}
