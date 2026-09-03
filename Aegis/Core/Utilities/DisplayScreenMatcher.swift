//
//  DisplayScreenMatcher.swift
//  Aegis
//
//  Matches yabai Display objects to NSScreen instances
//

import AppKit
import CoreGraphics

struct DisplayScreenMatcher {
    /// Match a WM Display to the corresponding NSScreen
    /// Primary method: UUID matching (most reliable, works with any monitor arrangement)
    /// Fallback: frame size matching (reliable since different monitors have different resolutions)
    static func matchScreen(for display: WMDisplay) -> NSScreen? {
        // Primary: Match by UUID (most reliable)
        if let screen = matchByUUID(display.uuid) {
            return screen
        }

        // Fallback: Match by size only (width and height within tolerance)
        // This is reliable since different physical monitors have different resolutions
        // NOTE: We don't use x-position because yabai and NSScreen use different coordinate systems
        let yabaiFrame = display.frame
        for screen in NSScreen.screens {
            let screenFrame = screen.frame
            if abs(screenFrame.width - yabaiFrame.width) < 2 &&
               abs(screenFrame.height - yabaiFrame.height) < 2 {
                return screen
            }
        }

        // Return nil rather than guessing with unreliable index mapping
        // Index-based matching fails because yabai and NSScreen sort displays differently
        return nil
    }

    /// Match NSScreen by display UUID
    /// Uses CoreGraphics to get the UUID for each screen and compare with yabai's UUID
    private static func matchByUUID(_ yabaiUUID: String) -> NSScreen? {
        for screen in NSScreen.screens {
            if let screenUUID = getScreenUUID(screen) {
                // Case-insensitive comparison in case of format differences
                if screenUUID.uppercased() == yabaiUUID.uppercased() {
                    return screen
                }
            }
        }
        return nil
    }

    /// Get the UUID string for an NSScreen using CoreGraphics
    private static func getScreenUUID(_ screen: NSScreen) -> String? {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return nil
        }

        guard let uuid = CGDisplayCreateUUIDFromDisplayID(screenNumber)?.takeRetainedValue() else {
            return nil
        }

        return CFUUIDCreateString(nil, uuid) as String?
    }

    /// Get the yabai display index for a given NSScreen
    static func displayIndex(for screen: NSScreen, displays: [WMDisplay]) -> Int? {
        for display in displays {
            if let matched = matchScreen(for: display), matched == screen {
                return display.index
            }
        }
        return nil
    }

    /// Check if the screen is the main/primary display
    static func isMainScreen(_ screen: NSScreen) -> Bool {
        return screen == NSScreen.main
    }

    /// Check if a screen has a notch
    static func hasNotch(_ screen: NSScreen) -> Bool {
        return screen.safeAreaInsets.top > 0
    }

    static func shouldIncludeScreen(
        hasHardwareNotch: Bool,
        showVirtualNotch: Bool
    ) -> Bool {
        hasHardwareNotch || showVirtualNotch
    }

    /// Returns all screens that should display a notch HUD.
    /// Includes screens with a hardware notch, plus external screens when showVirtualNotch is enabled.
    static func screensWithNotch() -> [NSScreen] {
        let config = AegisConfig.shared
        return NSScreen.screens.filter { screen in
            shouldIncludeScreen(
                hasHardwareNotch: hasNotch(screen),
                showVirtualNotch: config.showVirtualNotch
            )
        }
    }

    /// Get the CGDirectDisplayID for an NSScreen
    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        return screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
