import AppKit
import XCTest
@testable import Aegis

final class SettingsPaletteTests: XCTestCase {
    func testAquaPaletteHasReadableSemanticText() {
        assertReadablePalette(for: .aqua)
    }

    func testDarkAquaPaletteHasReadableSemanticText() {
        assertReadablePalette(for: .darkAqua)
    }

    private func assertReadablePalette(
        for appearanceName: NSAppearance.Name,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let background = SettingsPalette.resolved(.windowBackgroundColor, for: appearanceName)
        let primary = SettingsPalette.resolved(.labelColor, for: appearanceName)
        let secondary = SettingsPalette.resolved(.secondaryLabelColor, for: appearanceName)

        XCTAssertGreaterThan(contrastRatio(primary, background), 4.0, file: file, line: line)
        XCTAssertGreaterThan(contrastRatio(secondary, background), 2.0, file: file, line: line)
    }

    private func contrastRatio(_ foreground: NSColor, _ background: NSColor) -> CGFloat {
        let foregroundRGB = foreground.usingColorSpace(.deviceRGB)!
        let backgroundRGB = background.usingColorSpace(.deviceRGB)!
        let luminances = [relativeLuminance(foregroundRGB), relativeLuminance(backgroundRGB)].sorted()
        return (luminances[1] + 0.05) / (luminances[0] + 0.05)
    }

    private func relativeLuminance(_ color: NSColor) -> CGFloat {
        func linear(_ channel: CGFloat) -> CGFloat {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * linear(color.redComponent)
            + 0.7152 * linear(color.greenComponent)
            + 0.0722 * linear(color.blueComponent)
    }
}

final class SettingsWindowConfigurationTests: XCTestCase {
    func testSettingsWindowUsesOpaqueNativeAppearance() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )

        SettingsPanelController.configureSettingsWindow(window)

        XCTAssertTrue(window.isOpaque)
        XCTAssertEqual(window.alphaValue, 1)
        XCTAssertNil(window.appearance)
        XCTAssertTrue(window.backgroundColor.isEqual(to: NSColor.windowBackgroundColor))
    }
}
