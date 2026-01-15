import Foundation
import SwiftUI
import Combine

/// Centralized configuration for all Aegis UI elements, behaviors, and visual parameters
/// This singleton provides @Published properties that can be observed by SwiftUI views
/// and persisted via UserDefaults for user customization
class AegisConfig: ObservableObject {
    static let shared = AegisConfig()

    // MARK: - Menu Bar Layout

    /// Height of the menu bar (controls MenuBarView frame)
    /// Default matches the hardware notch height for visual alignment
    @Published var menuBarHeight: CGFloat = NSScreen.main?.safeAreaInsets.top ?? 37

    /// Padding from screen edges (affects button and system status placement)
    @Published var menuBarEdgePadding: CGFloat = 100

    /// Spacing between space indicators in the menu bar
    @Published var spaceIndicatorSpacing: CGFloat = 8

    /// Spacing between system status icons (battery, wifi, etc.)
    @Published var systemIconSpacing: CGFloat = 12

    /// Size of system status icons
    @Published var systemIconSize: CGFloat = 14

    /// Width of the layout actions button
    @Published var layoutButtonWidth: CGFloat = 32

    /// Width of button label when expanded
    @Published var buttonLabelExpandedWidth: CGFloat = 95

    /// Estimated width of system status area for layout calculations
    @Published var systemStatusWidth: CGFloat = 150

    // MARK: - Space Indicator Dimensions

    /// Size of the space circle/number indicator
    @Published var spaceCircleSize: CGFloat = 32

    /// Size of window app icons
    @Published var appIconSize: CGFloat = 28

    /// Spacing between app icons in a space
    @Published var appIconSpacing: CGFloat = 4

    /// Maximum window icons visible per space before overflow
    @Published var maxAppIconsPerSpace: Int = 3

    /// Width of window icon frames
    @Published var windowIconFrameWidth: CGFloat = 22

    /// Height of window icon frames
    @Published var windowIconFrameHeight: CGFloat = 22

    /// Maximum width when window title expands
    @Published var maxExpandedWidth: CGFloat = 100

    /// Size of the stack indicator badge
    @Published var stackBadgeSize: CGFloat = 10

    /// Size of the focus dot indicator
    @Published var focusDotSize: CGFloat = 3

    /// Size of overflow button frame
    @Published var overflowButtonSize: CGFloat = 20

    // MARK: - Space Indicator Spacing & Padding

    /// Horizontal spacing between space number and icons
    @Published var spaceContentSpacing: CGFloat = 6

    /// Horizontal padding inside space indicator
    @Published var spaceIndicatorHorizontalPadding: CGFloat = 8

    /// Vertical padding inside space indicator
    @Published var spaceIndicatorVerticalPadding: CGFloat = 5

    /// Horizontal padding for drop zone
    @Published var dropZoneHorizontalPadding: CGFloat = 4

    /// Vertical padding for drop zone
    @Published var dropZoneVerticalPadding: CGFloat = 8

    // MARK: - Typography

    /// Font size for space numbers
    @Published var spaceNumberFontSize: CGFloat = 12

    /// Font size for window titles
    @Published var windowTitleFontSize: CGFloat = 11

    /// Font size for app names in expansion
    @Published var appNameFontSize: CGFloat = 9

    /// Font size for overflow button text
    @Published var overflowButtonFontSize: CGFloat = 9

    /// Font size for stack badge symbol
    @Published var stackBadgeFontSize: CGFloat = 6

    /// Font size for system status text (date, time)
    @Published var systemStatusFontSize: CGFloat = 13

    // MARK: - Corner Radii

    /// Corner radius for space indicator background
    @Published var spaceIndicatorCornerRadius: CGFloat = 8

    /// Corner radius for overflow button
    @Published var overflowButtonCornerRadius: CGFloat = 4

    /// Corner radius for system status container
    @Published var systemStatusCornerRadius: CGFloat = 8

    /// Corner radius for layout action button
    @Published var layoutButtonCornerRadius: CGFloat = 8

    // MARK: - Colors - Background Opacity (Dynamic States)

    /// Background opacity for active space
    @Published var activeSpaceBgOpacity: Double = 0.18

    /// Background opacity for hovered space
    @Published var hoveredSpaceBgOpacity: Double = 0.15

    /// Background opacity for inactive space
    @Published var inactiveSpaceBgOpacity: Double = 0.12

    /// Background opacity for active button
    @Published var activeButtonBgOpacity: Double = 0.2

    /// Background opacity for hovered button
    @Published var hoveredButtonBgOpacity: Double = 0.15

    /// Background opacity for inactive button
    @Published var inactiveButtonBgOpacity: Double = 0.12

    /// Background opacity for overflow button when showing menu
    @Published var overflowMenuShowingBgOpacity: Double = 0.25

    /// Background opacity for overflow button default
    @Published var overflowButtonBgOpacity: Double = 0.12

    /// Background opacity for system status container
    @Published var systemStatusBgOpacity: Double = 0.12

    // MARK: - Colors - Border & Stroke Opacity

    /// Border opacity for active state
    @Published var activeBorderOpacity: Double = 0.18

    /// Border opacity for system status
    @Published var systemStatusBorderOpacity: Double = 0.2

    // MARK: - Colors - Text & Icon Opacity

    /// Text opacity for primary text (active state)
    @Published var primaryTextOpacity: Double = 1.0

    /// Text opacity for secondary text (window titles)
    @Published var secondaryTextOpacity: Double = 0.9

    /// Text opacity for tertiary text (app names, inactive state)
    @Published var tertiaryTextOpacity: Double = 0.6

    // MARK: - Colors - Hover & Glow Effects

    /// Icon hover glow opacity
    @Published var iconHoverGlowOpacity: Double = 0.15

    /// Icon hover background opacity
    @Published var iconHoverBgOpacity: Double = 0.2

    /// Backdrop blur opacity when button label expands
    @Published var buttonBackdropBlurOpacity: Double = 0.4

    // MARK: - Colors - Shadows

    /// Shadow opacity for space indicators
    @Published var spaceShadowOpacity: Double = 0.12

    /// Shadow radius for space indicators
    @Published var spaceShadowRadius: CGFloat = 4

    /// Shadow radius for system status
    @Published var systemStatusShadowRadius: CGFloat = 1

    // MARK: - Window Filtering

    /// Apps to exclude from showing in space indicators (by app name)
    /// Aegis and Finder are excluded by default as they're not managed by Yabai
    @Published var excludedApps: Set<String> = ["Finder", "Aegis"]

    // MARK: - Behavior Flags - Menu Bar

    /// Show app names under window titles when expanded
    @Published var showAppNameInExpansion: Bool = false

    /// Enable swipe-up gesture to destroy spaces
    @Published var useSwipeToDestroySpace: Bool = true

    /// Enable haptic feedback on layout actions
    @Published var enableLayoutActionHaptics: Bool = true

    /// Launch Aegis automatically when macOS starts
    @Published var launchAtLogin: Bool = true {
        didSet {
            LaunchAtLoginService.shared.setLaunchAtLogin(launchAtLogin)
        }
    }

    // MARK: - Behavior Settings - Auto-Hide & Delays

    /// Delay before window icon expansion auto-collapses
    @Published var windowIconExpansionAutoCollapseDelay: TimeInterval = 2.0

    /// Delay before layout action label auto-hides
    @Published var actionLabelAutoHideDelay: TimeInterval = 1.5

    // MARK: - Interaction Thresholds

    /// Minimum drag distance before starting window drag
    @Published var dragDistanceThreshold: CGFloat = 3

    /// Swipe distance threshold for space destruction
    @Published var swipeDestroyThreshold: CGFloat = -120

    /// Scroll amount threshold for action selector
    @Published var scrollActionThreshold: CGFloat = 3

    // MARK: - Animation Settings - Spring Animations

    /// Spring response for hover effects
    @Published var hoverAnimationResponse: Double = 0.3

    /// Spring damping for hover effects
    @Published var hoverAnimationDamping: Double = 0.7

    /// Spring response for expansion animations
    @Published var expansionAnimationResponse: Double = 0.35

    /// Spring damping for expansion animations
    @Published var expansionAnimationDamping: Double = 0.75

    /// Spring response for collapse animations
    @Published var collapseAnimationResponse: Double = 0.25

    /// Spring damping for collapse animations
    @Published var collapseAnimationDamping: Double = 0.8

    /// Spring response for position updates
    @Published var positionUpdateResponse: Double = 0.3

    /// Spring damping for position updates
    @Published var positionUpdateDamping: Double = 0.7

    // MARK: - Animation Settings - Durations

    /// Duration for state transition animations (active/inactive)
    @Published var stateTransitionDuration: Double = 0.25

    /// Duration for window update animations
    @Published var windowUpdateDuration: Double = 0.2

    /// Duration for auto-scroll animations
    @Published var autoScrollDuration: Double = 0.3

    /// Duration for fade mask animations
    @Published var fadeMaskDuration: Double = 0.2

    /// Duration for notch HUD fade in
    @Published var notchHUDFadeInDuration: Double = 0.2

    /// Duration for notch HUD fade out
    @Published var notchHUDFadeOutDuration: Double = 0.3

    /// Duration for hover effect animations
    @Published var hoverEffectDuration: Double = 0.2

    // MARK: - Dynamic Visuals - Scale Effects

    /// Scale factor for hovered buttons
    @Published var hoveredButtonScale: CGFloat = 1.02

    /// Scale factor for hovered icons
    @Published var hoveredIconScale: CGFloat = 1.0

    // MARK: - Notch Settings - Screen & Layout

    /// Width of the notch area
    @Published var notchWidth: CGFloat = 200

    /// Padding around the notch area
    @Published var notchPadding: CGFloat = 20

    // MARK: - Notch Settings - HUD Dimensions

    /// Width of the notch HUD
    @Published var notchHUDWidth: CGFloat = 50

    /// Height of the notch HUD
    @Published var notchHUDHeight: CGFloat = 50

    /// Top padding for the notch HUD
    @Published var notchHUDTopPadding: CGFloat = 8

    /// Delay before notch HUD auto-hides
    @Published var notchHUDAutoHideDelay: TimeInterval = 1.5

    /// Vertical padding for minimal HUD
    @Published var minimalHUDVerticalPadding: CGFloat = 12

    /// Vertical padding for music HUD
    @Published var musicHUDVerticalPadding: CGFloat = 8

    // MARK: - Notch Settings - Music HUD

    /// Size of album art in music HUD
    @Published var albumArtSize: CGFloat = 40

    /// Padding around album art
    @Published var albumArtPadding: CGFloat = 10

    /// Height of visualizer in music HUD
    @Published var visualizerHeight: CGFloat = 40

    /// Padding around visualizer
    @Published var visualizerPadding: CGFloat = 10

    /// Number of bars in visualizer
    @Published var visualizerBarCount: Int = 5

    /// Spacing between visualizer bars
    @Published var visualizerBarSpacing: CGFloat = 4

    /// Width of visualizer bars
    @Published var visualizerBarWidth: CGFloat = 3

    /// Minimum height of visualizer bars
    @Published var visualizerBarMinHeight: CGFloat = 5

    /// Maximum height of visualizer bars
    @Published var visualizerBarMaxHeight: CGFloat = 20

    /// Animation duration for visualizer bars
    @Published var visualizerAnimationDuration: Double = 0.3

    /// Use transparent/blur effect for visualizer bars (shows wallpaper through bars)
    /// Note: May impact performance on some systems
    @Published var visualizerUseBlurEffect: Bool = false

    /// Show the Now Playing music HUD when music is playing
    @Published var showMusicHUD: Bool = true

    /// What to show in the right panel of the music HUD
    enum MusicHUDRightPanelMode: String, CaseIterable {
        case visualizer = "visualizer"
        case trackInfo = "trackInfo"
    }

    @Published var musicHUDRightPanelMode: MusicHUDRightPanelMode = .visualizer

    /// Auto-hide music HUD after showing track info (only reappears on track change)
    @Published var musicHUDAutoHide: Bool = false

    /// Delay before auto-hiding music HUD (seconds)
    @Published var musicHUDAutoHideDelay: TimeInterval = 5.0

    // MARK: - Notch HUD Icon & Text Settings

    /// Font size for notch HUD icons (volume, brightness)
    @Published var notchHUDIconSize: CGFloat = 13

    /// Font size for notch HUD value text
    @Published var notchHUDValueFontSize: CGFloat = 13

    /// Inner padding for HUD sides
    @Published var notchHUDInnerPadding: CGFloat = 8

    /// Show background for HUD sides
    @Published var notchHUDShowBackground: Bool = false

    /// Use progress bar instead of numeric value for volume/brightness
    @Published var notchHUDUseProgressBar: Bool = false

    /// Width of the progress bar
    @Published var notchHUDProgressBarWidth: CGFloat = 60

    /// Height of the progress bar
    @Published var notchHUDProgressBarHeight: CGFloat = 4

    // MARK: - SystemStatus Settings

    /// Height of system status frame
    @Published var systemStatusFrameHeight: CGFloat = 20

    /// Horizontal padding for system status items
    @Published var systemStatusHorizontalPadding: CGFloat = 6

    /// WiFi signal strength threshold for strong (above this = strong)
    @Published var wifiStrongThreshold: Double = 0.66

    /// WiFi signal strength threshold for medium (above this = medium, below = weak)
    @Published var wifiMediumThreshold: Double = 0.33

    /// Battery level threshold for high (above this = green/high)
    @Published var batteryHighThreshold: Double = 0.75

    /// Battery level threshold for medium (above this = yellow/medium)
    @Published var batteryMediumThreshold: Double = 0.5

    /// Battery level threshold for low (above this = orange/low)
    @Published var batteryLowThreshold: Double = 0.25

    /// Battery level threshold for critical (below this = red/critical)
    @Published var batteryCriticalThreshold: Double = 0.1

    /// Show Focus mode name alongside the symbol
    @Published var showFocusName: Bool = false

    // MARK: - SystemStatus / Date Settings

    enum DateFormat: String, CaseIterable {
        case long  // "Mon Jan 13"
        case short // "13/01/26"
    }

    @Published var dateFormat: DateFormat = .long

    // MARK: - Computed Color Properties

    /// Active space background color (uses activeSpaceBgOpacity)
    var activeSpaceColor: Color { Color.white.opacity(activeSpaceBgOpacity) }

    /// Hovered space background color (uses hoveredSpaceBgOpacity)
    var hoveredSpaceColor: Color { Color.white.opacity(hoveredSpaceBgOpacity) }

    /// Inactive space background color (uses inactiveSpaceBgOpacity)
    var inactiveSpaceColor: Color { Color.white.opacity(inactiveSpaceBgOpacity) }

    /// Active border color (uses activeBorderOpacity)
    var activeBorderColor: Color { Color.white.opacity(activeBorderOpacity) }

    private init() {
        loadPreferences()
    }

    // MARK: - Persistence

    func savePreferences() {
        // Menu Bar Layout
        UserDefaults.standard.set(menuBarHeight, forKey: "menuBarHeight")
        UserDefaults.standard.set(menuBarEdgePadding, forKey: "menuBarEdgePadding")
        UserDefaults.standard.set(spaceIndicatorSpacing, forKey: "spaceIndicatorSpacing")
        UserDefaults.standard.set(systemIconSpacing, forKey: "systemIconSpacing")
        UserDefaults.standard.set(systemIconSize, forKey: "systemIconSize")
        UserDefaults.standard.set(layoutButtonWidth, forKey: "layoutButtonWidth")
        UserDefaults.standard.set(buttonLabelExpandedWidth, forKey: "buttonLabelExpandedWidth")
        UserDefaults.standard.set(systemStatusWidth, forKey: "systemStatusWidth")

        // Space Indicator Dimensions
        UserDefaults.standard.set(spaceCircleSize, forKey: "spaceCircleSize")
        UserDefaults.standard.set(appIconSize, forKey: "appIconSize")
        UserDefaults.standard.set(appIconSpacing, forKey: "appIconSpacing")
        UserDefaults.standard.set(maxAppIconsPerSpace, forKey: "maxAppIconsPerSpace")
        UserDefaults.standard.set(windowIconFrameWidth, forKey: "windowIconFrameWidth")
        UserDefaults.standard.set(windowIconFrameHeight, forKey: "windowIconFrameHeight")
        UserDefaults.standard.set(maxExpandedWidth, forKey: "maxExpandedWidth")
        UserDefaults.standard.set(stackBadgeSize, forKey: "stackBadgeSize")
        UserDefaults.standard.set(focusDotSize, forKey: "focusDotSize")
        UserDefaults.standard.set(overflowButtonSize, forKey: "overflowButtonSize")

        // Spacing & Padding
        UserDefaults.standard.set(spaceContentSpacing, forKey: "spaceContentSpacing")
        UserDefaults.standard.set(spaceIndicatorHorizontalPadding, forKey: "spaceIndicatorHorizontalPadding")
        UserDefaults.standard.set(spaceIndicatorVerticalPadding, forKey: "spaceIndicatorVerticalPadding")
        UserDefaults.standard.set(dropZoneHorizontalPadding, forKey: "dropZoneHorizontalPadding")
        UserDefaults.standard.set(dropZoneVerticalPadding, forKey: "dropZoneVerticalPadding")

        // Typography
        UserDefaults.standard.set(spaceNumberFontSize, forKey: "spaceNumberFontSize")
        UserDefaults.standard.set(windowTitleFontSize, forKey: "windowTitleFontSize")
        UserDefaults.standard.set(appNameFontSize, forKey: "appNameFontSize")
        UserDefaults.standard.set(overflowButtonFontSize, forKey: "overflowButtonFontSize")
        UserDefaults.standard.set(stackBadgeFontSize, forKey: "stackBadgeFontSize")
        UserDefaults.standard.set(systemStatusFontSize, forKey: "systemStatusFontSize")

        // Corner Radii
        UserDefaults.standard.set(spaceIndicatorCornerRadius, forKey: "spaceIndicatorCornerRadius")
        UserDefaults.standard.set(overflowButtonCornerRadius, forKey: "overflowButtonCornerRadius")
        UserDefaults.standard.set(systemStatusCornerRadius, forKey: "systemStatusCornerRadius")
        UserDefaults.standard.set(layoutButtonCornerRadius, forKey: "layoutButtonCornerRadius")

        // Colors - Opacity Values
        UserDefaults.standard.set(activeSpaceBgOpacity, forKey: "activeSpaceBgOpacity")
        UserDefaults.standard.set(hoveredSpaceBgOpacity, forKey: "hoveredSpaceBgOpacity")
        UserDefaults.standard.set(inactiveSpaceBgOpacity, forKey: "inactiveSpaceBgOpacity")
        UserDefaults.standard.set(activeButtonBgOpacity, forKey: "activeButtonBgOpacity")
        UserDefaults.standard.set(hoveredButtonBgOpacity, forKey: "hoveredButtonBgOpacity")
        UserDefaults.standard.set(inactiveButtonBgOpacity, forKey: "inactiveButtonBgOpacity")
        UserDefaults.standard.set(overflowMenuShowingBgOpacity, forKey: "overflowMenuShowingBgOpacity")
        UserDefaults.standard.set(overflowButtonBgOpacity, forKey: "overflowButtonBgOpacity")
        UserDefaults.standard.set(systemStatusBgOpacity, forKey: "systemStatusBgOpacity")
        UserDefaults.standard.set(activeBorderOpacity, forKey: "activeBorderOpacity")
        UserDefaults.standard.set(systemStatusBorderOpacity, forKey: "systemStatusBorderOpacity")
        UserDefaults.standard.set(primaryTextOpacity, forKey: "primaryTextOpacity")
        UserDefaults.standard.set(secondaryTextOpacity, forKey: "secondaryTextOpacity")
        UserDefaults.standard.set(tertiaryTextOpacity, forKey: "tertiaryTextOpacity")
        UserDefaults.standard.set(iconHoverGlowOpacity, forKey: "iconHoverGlowOpacity")
        UserDefaults.standard.set(iconHoverBgOpacity, forKey: "iconHoverBgOpacity")
        UserDefaults.standard.set(buttonBackdropBlurOpacity, forKey: "buttonBackdropBlurOpacity")
        UserDefaults.standard.set(spaceShadowOpacity, forKey: "spaceShadowOpacity")
        UserDefaults.standard.set(spaceShadowRadius, forKey: "spaceShadowRadius")
        UserDefaults.standard.set(systemStatusShadowRadius, forKey: "systemStatusShadowRadius")

        // Behavior Flags
        UserDefaults.standard.set(showAppNameInExpansion, forKey: "showAppNameInExpansion")
        UserDefaults.standard.set(useSwipeToDestroySpace, forKey: "useSwipeToDestroySpace")
        UserDefaults.standard.set(enableLayoutActionHaptics, forKey: "enableLayoutActionHaptics")
        UserDefaults.standard.set(windowIconExpansionAutoCollapseDelay, forKey: "windowIconExpansionAutoCollapseDelay")
        UserDefaults.standard.set(actionLabelAutoHideDelay, forKey: "actionLabelAutoHideDelay")

        // Interaction Thresholds
        UserDefaults.standard.set(dragDistanceThreshold, forKey: "dragDistanceThreshold")
        UserDefaults.standard.set(swipeDestroyThreshold, forKey: "swipeDestroyThreshold")
        UserDefaults.standard.set(scrollActionThreshold, forKey: "scrollActionThreshold")

        // Animation Settings
        UserDefaults.standard.set(hoverAnimationResponse, forKey: "hoverAnimationResponse")
        UserDefaults.standard.set(hoverAnimationDamping, forKey: "hoverAnimationDamping")
        UserDefaults.standard.set(expansionAnimationResponse, forKey: "expansionAnimationResponse")
        UserDefaults.standard.set(expansionAnimationDamping, forKey: "expansionAnimationDamping")
        UserDefaults.standard.set(collapseAnimationResponse, forKey: "collapseAnimationResponse")
        UserDefaults.standard.set(collapseAnimationDamping, forKey: "collapseAnimationDamping")
        UserDefaults.standard.set(positionUpdateResponse, forKey: "positionUpdateResponse")
        UserDefaults.standard.set(positionUpdateDamping, forKey: "positionUpdateDamping")
        UserDefaults.standard.set(stateTransitionDuration, forKey: "stateTransitionDuration")
        UserDefaults.standard.set(windowUpdateDuration, forKey: "windowUpdateDuration")
        UserDefaults.standard.set(autoScrollDuration, forKey: "autoScrollDuration")
        UserDefaults.standard.set(fadeMaskDuration, forKey: "fadeMaskDuration")
        UserDefaults.standard.set(notchHUDFadeInDuration, forKey: "notchHUDFadeInDuration")
        UserDefaults.standard.set(notchHUDFadeOutDuration, forKey: "notchHUDFadeOutDuration")
        UserDefaults.standard.set(hoverEffectDuration, forKey: "hoverEffectDuration")

        // Dynamic Visuals
        UserDefaults.standard.set(hoveredButtonScale, forKey: "hoveredButtonScale")
        UserDefaults.standard.set(hoveredIconScale, forKey: "hoveredIconScale")

        // Notch Settings
        UserDefaults.standard.set(notchWidth, forKey: "notchWidth")
        UserDefaults.standard.set(notchPadding, forKey: "notchPadding")
        UserDefaults.standard.set(notchHUDWidth, forKey: "notchHUDWidth")
        UserDefaults.standard.set(notchHUDHeight, forKey: "notchHUDHeight")
        UserDefaults.standard.set(notchHUDTopPadding, forKey: "notchHUDTopPadding")
        UserDefaults.standard.set(notchHUDAutoHideDelay, forKey: "notchHUDAutoHideDelay")
        UserDefaults.standard.set(minimalHUDVerticalPadding, forKey: "minimalHUDVerticalPadding")
        UserDefaults.standard.set(musicHUDVerticalPadding, forKey: "musicHUDVerticalPadding")
        UserDefaults.standard.set(albumArtSize, forKey: "albumArtSize")
        UserDefaults.standard.set(albumArtPadding, forKey: "albumArtPadding")
        UserDefaults.standard.set(visualizerHeight, forKey: "visualizerHeight")
        UserDefaults.standard.set(visualizerPadding, forKey: "visualizerPadding")
        UserDefaults.standard.set(visualizerBarCount, forKey: "visualizerBarCount")
        UserDefaults.standard.set(visualizerBarSpacing, forKey: "visualizerBarSpacing")
        UserDefaults.standard.set(visualizerBarWidth, forKey: "visualizerBarWidth")
        UserDefaults.standard.set(visualizerBarMinHeight, forKey: "visualizerBarMinHeight")
        UserDefaults.standard.set(visualizerBarMaxHeight, forKey: "visualizerBarMaxHeight")
        UserDefaults.standard.set(visualizerAnimationDuration, forKey: "visualizerAnimationDuration")
        UserDefaults.standard.set(visualizerUseBlurEffect, forKey: "visualizerUseBlurEffect")
        UserDefaults.standard.set(showMusicHUD, forKey: "showMusicHUD")
        UserDefaults.standard.set(musicHUDRightPanelMode.rawValue, forKey: "musicHUDRightPanelMode")
        UserDefaults.standard.set(musicHUDAutoHide, forKey: "musicHUDAutoHide")
        UserDefaults.standard.set(musicHUDAutoHideDelay, forKey: "musicHUDAutoHideDelay")
        UserDefaults.standard.set(notchHUDIconSize, forKey: "notchHUDIconSize")
        UserDefaults.standard.set(notchHUDValueFontSize, forKey: "notchHUDValueFontSize")
        UserDefaults.standard.set(notchHUDInnerPadding, forKey: "notchHUDInnerPadding")
        UserDefaults.standard.set(notchHUDShowBackground, forKey: "notchHUDShowBackground")
        UserDefaults.standard.set(notchHUDUseProgressBar, forKey: "notchHUDUseProgressBar")
        UserDefaults.standard.set(notchHUDProgressBarWidth, forKey: "notchHUDProgressBarWidth")
        UserDefaults.standard.set(notchHUDProgressBarHeight, forKey: "notchHUDProgressBarHeight")

        // SystemStatus Settings
        UserDefaults.standard.set(systemStatusFrameHeight, forKey: "systemStatusFrameHeight")
        UserDefaults.standard.set(systemStatusHorizontalPadding, forKey: "systemStatusHorizontalPadding")
        UserDefaults.standard.set(wifiStrongThreshold, forKey: "wifiStrongThreshold")
        UserDefaults.standard.set(wifiMediumThreshold, forKey: "wifiMediumThreshold")
        UserDefaults.standard.set(batteryHighThreshold, forKey: "batteryHighThreshold")
        UserDefaults.standard.set(batteryMediumThreshold, forKey: "batteryMediumThreshold")
        UserDefaults.standard.set(batteryLowThreshold, forKey: "batteryLowThreshold")
        UserDefaults.standard.set(batteryCriticalThreshold, forKey: "batteryCriticalThreshold")
        UserDefaults.standard.set(showFocusName, forKey: "showFocusName")
        UserDefaults.standard.set(dateFormat.rawValue, forKey: "dateFormat")
    }

    private func loadPreferences() {
        // Menu Bar Layout
        if let val = UserDefaults.standard.object(forKey: "menuBarHeight") as? Double {
            menuBarHeight = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "menuBarEdgePadding") as? Double {
            menuBarEdgePadding = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "spaceIndicatorSpacing") as? Double {
            spaceIndicatorSpacing = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "systemIconSpacing") as? Double {
            systemIconSpacing = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "systemIconSize") as? Double {
            systemIconSize = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "layoutButtonWidth") as? Double {
            layoutButtonWidth = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "buttonLabelExpandedWidth") as? Double {
            buttonLabelExpandedWidth = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "systemStatusWidth") as? Double {
            systemStatusWidth = CGFloat(val)
        }

        // Space Indicator Dimensions
        if let val = UserDefaults.standard.object(forKey: "spaceCircleSize") as? Double {
            spaceCircleSize = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "appIconSize") as? Double {
            appIconSize = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "appIconSpacing") as? Double {
            appIconSpacing = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "maxAppIconsPerSpace") as? Int {
            maxAppIconsPerSpace = val
        }
        if let val = UserDefaults.standard.object(forKey: "windowIconFrameWidth") as? Double {
            windowIconFrameWidth = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "windowIconFrameHeight") as? Double {
            windowIconFrameHeight = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "maxExpandedWidth") as? Double {
            maxExpandedWidth = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "stackBadgeSize") as? Double {
            stackBadgeSize = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "focusDotSize") as? Double {
            focusDotSize = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "overflowButtonSize") as? Double {
            overflowButtonSize = CGFloat(val)
        }

        // Spacing & Padding
        if let val = UserDefaults.standard.object(forKey: "spaceContentSpacing") as? Double {
            spaceContentSpacing = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "spaceIndicatorHorizontalPadding") as? Double {
            spaceIndicatorHorizontalPadding = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "spaceIndicatorVerticalPadding") as? Double {
            spaceIndicatorVerticalPadding = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "dropZoneHorizontalPadding") as? Double {
            dropZoneHorizontalPadding = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "dropZoneVerticalPadding") as? Double {
            dropZoneVerticalPadding = CGFloat(val)
        }

        // Typography
        if let val = UserDefaults.standard.object(forKey: "spaceNumberFontSize") as? Double {
            spaceNumberFontSize = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "windowTitleFontSize") as? Double {
            windowTitleFontSize = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "appNameFontSize") as? Double {
            appNameFontSize = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "overflowButtonFontSize") as? Double {
            overflowButtonFontSize = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "stackBadgeFontSize") as? Double {
            stackBadgeFontSize = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "systemStatusFontSize") as? Double {
            systemStatusFontSize = CGFloat(val)
        }

        // Corner Radii
        if let val = UserDefaults.standard.object(forKey: "spaceIndicatorCornerRadius") as? Double {
            spaceIndicatorCornerRadius = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "overflowButtonCornerRadius") as? Double {
            overflowButtonCornerRadius = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "systemStatusCornerRadius") as? Double {
            systemStatusCornerRadius = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "layoutButtonCornerRadius") as? Double {
            layoutButtonCornerRadius = CGFloat(val)
        }

        // Colors - Opacity Values
        if let val = UserDefaults.standard.object(forKey: "activeSpaceBgOpacity") as? Double {
            activeSpaceBgOpacity = val
        }
        if let val = UserDefaults.standard.object(forKey: "hoveredSpaceBgOpacity") as? Double {
            hoveredSpaceBgOpacity = val
        }
        if let val = UserDefaults.standard.object(forKey: "inactiveSpaceBgOpacity") as? Double {
            inactiveSpaceBgOpacity = val
        }
        if let val = UserDefaults.standard.object(forKey: "activeButtonBgOpacity") as? Double {
            activeButtonBgOpacity = val
        }
        if let val = UserDefaults.standard.object(forKey: "hoveredButtonBgOpacity") as? Double {
            hoveredButtonBgOpacity = val
        }
        if let val = UserDefaults.standard.object(forKey: "inactiveButtonBgOpacity") as? Double {
            inactiveButtonBgOpacity = val
        }
        if let val = UserDefaults.standard.object(forKey: "overflowMenuShowingBgOpacity") as? Double {
            overflowMenuShowingBgOpacity = val
        }
        if let val = UserDefaults.standard.object(forKey: "overflowButtonBgOpacity") as? Double {
            overflowButtonBgOpacity = val
        }
        if let val = UserDefaults.standard.object(forKey: "systemStatusBgOpacity") as? Double {
            systemStatusBgOpacity = val
        }
        if let val = UserDefaults.standard.object(forKey: "activeBorderOpacity") as? Double {
            activeBorderOpacity = val
        }
        if let val = UserDefaults.standard.object(forKey: "systemStatusBorderOpacity") as? Double {
            systemStatusBorderOpacity = val
        }
        if let val = UserDefaults.standard.object(forKey: "primaryTextOpacity") as? Double {
            primaryTextOpacity = val
        }
        if let val = UserDefaults.standard.object(forKey: "secondaryTextOpacity") as? Double {
            secondaryTextOpacity = val
        }
        if let val = UserDefaults.standard.object(forKey: "tertiaryTextOpacity") as? Double {
            tertiaryTextOpacity = val
        }
        if let val = UserDefaults.standard.object(forKey: "iconHoverGlowOpacity") as? Double {
            iconHoverGlowOpacity = val
        }
        if let val = UserDefaults.standard.object(forKey: "iconHoverBgOpacity") as? Double {
            iconHoverBgOpacity = val
        }
        if let val = UserDefaults.standard.object(forKey: "buttonBackdropBlurOpacity") as? Double {
            buttonBackdropBlurOpacity = val
        }
        if let val = UserDefaults.standard.object(forKey: "spaceShadowOpacity") as? Double {
            spaceShadowOpacity = val
        }
        if let val = UserDefaults.standard.object(forKey: "spaceShadowRadius") as? Double {
            spaceShadowRadius = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "systemStatusShadowRadius") as? Double {
            systemStatusShadowRadius = CGFloat(val)
        }

        // Behavior Flags
        if let val = UserDefaults.standard.object(forKey: "showAppNameInExpansion") as? Bool {
            showAppNameInExpansion = val
        }
        if let val = UserDefaults.standard.object(forKey: "useSwipeToDestroySpace") as? Bool {
            useSwipeToDestroySpace = val
        }
        if let val = UserDefaults.standard.object(forKey: "enableLayoutActionHaptics") as? Bool {
            enableLayoutActionHaptics = val
        }
        if let val = UserDefaults.standard.object(forKey: "windowIconExpansionAutoCollapseDelay") as? Double {
            windowIconExpansionAutoCollapseDelay = val
        }
        if let val = UserDefaults.standard.object(forKey: "actionLabelAutoHideDelay") as? Double {
            actionLabelAutoHideDelay = val
        }

        // Interaction Thresholds
        if let val = UserDefaults.standard.object(forKey: "dragDistanceThreshold") as? Double {
            dragDistanceThreshold = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "swipeDestroyThreshold") as? Double {
            swipeDestroyThreshold = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "scrollActionThreshold") as? Double {
            scrollActionThreshold = CGFloat(val)
        }

        // Animation Settings
        if let val = UserDefaults.standard.object(forKey: "hoverAnimationResponse") as? Double {
            hoverAnimationResponse = val
        }
        if let val = UserDefaults.standard.object(forKey: "hoverAnimationDamping") as? Double {
            hoverAnimationDamping = val
        }
        if let val = UserDefaults.standard.object(forKey: "expansionAnimationResponse") as? Double {
            expansionAnimationResponse = val
        }
        if let val = UserDefaults.standard.object(forKey: "expansionAnimationDamping") as? Double {
            expansionAnimationDamping = val
        }
        if let val = UserDefaults.standard.object(forKey: "collapseAnimationResponse") as? Double {
            collapseAnimationResponse = val
        }
        if let val = UserDefaults.standard.object(forKey: "collapseAnimationDamping") as? Double {
            collapseAnimationDamping = val
        }
        if let val = UserDefaults.standard.object(forKey: "positionUpdateResponse") as? Double {
            positionUpdateResponse = val
        }
        if let val = UserDefaults.standard.object(forKey: "positionUpdateDamping") as? Double {
            positionUpdateDamping = val
        }
        if let val = UserDefaults.standard.object(forKey: "stateTransitionDuration") as? Double {
            stateTransitionDuration = val
        }
        if let val = UserDefaults.standard.object(forKey: "windowUpdateDuration") as? Double {
            windowUpdateDuration = val
        }
        if let val = UserDefaults.standard.object(forKey: "autoScrollDuration") as? Double {
            autoScrollDuration = val
        }
        if let val = UserDefaults.standard.object(forKey: "fadeMaskDuration") as? Double {
            fadeMaskDuration = val
        }
        if let val = UserDefaults.standard.object(forKey: "notchHUDFadeInDuration") as? Double {
            notchHUDFadeInDuration = val
        }
        if let val = UserDefaults.standard.object(forKey: "notchHUDFadeOutDuration") as? Double {
            notchHUDFadeOutDuration = val
        }
        if let val = UserDefaults.standard.object(forKey: "hoverEffectDuration") as? Double {
            hoverEffectDuration = val
        }

        // Dynamic Visuals
        if let val = UserDefaults.standard.object(forKey: "hoveredButtonScale") as? Double {
            hoveredButtonScale = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "hoveredIconScale") as? Double {
            hoveredIconScale = CGFloat(val)
        }

        // Notch Settings
        if let val = UserDefaults.standard.object(forKey: "notchWidth") as? Double {
            notchWidth = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "notchPadding") as? Double {
            notchPadding = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "notchHUDWidth") as? Double {
            notchHUDWidth = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "notchHUDHeight") as? Double {
            notchHUDHeight = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "notchHUDTopPadding") as? Double {
            notchHUDTopPadding = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "notchHUDAutoHideDelay") as? Double {
            notchHUDAutoHideDelay = val
        }
        if let val = UserDefaults.standard.object(forKey: "minimalHUDVerticalPadding") as? Double {
            minimalHUDVerticalPadding = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "musicHUDVerticalPadding") as? Double {
            musicHUDVerticalPadding = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "albumArtSize") as? Double {
            albumArtSize = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "albumArtPadding") as? Double {
            albumArtPadding = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "visualizerHeight") as? Double {
            visualizerHeight = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "visualizerPadding") as? Double {
            visualizerPadding = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "visualizerBarCount") as? Int {
            visualizerBarCount = val
        }
        if let val = UserDefaults.standard.object(forKey: "visualizerBarSpacing") as? Double {
            visualizerBarSpacing = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "visualizerBarWidth") as? Double {
            visualizerBarWidth = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "visualizerBarMinHeight") as? Double {
            visualizerBarMinHeight = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "visualizerBarMaxHeight") as? Double {
            visualizerBarMaxHeight = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "visualizerAnimationDuration") as? Double {
            visualizerAnimationDuration = val
        }
        if let val = UserDefaults.standard.object(forKey: "visualizerUseBlurEffect") as? Bool {
            visualizerUseBlurEffect = val
        }
        if let val = UserDefaults.standard.object(forKey: "showMusicHUD") as? Bool {
            showMusicHUD = val
        }
        if let val = UserDefaults.standard.string(forKey: "musicHUDRightPanelMode"),
           let mode = MusicHUDRightPanelMode(rawValue: val) {
            musicHUDRightPanelMode = mode
        }
        if let val = UserDefaults.standard.object(forKey: "musicHUDAutoHide") as? Bool {
            musicHUDAutoHide = val
        }
        if let val = UserDefaults.standard.object(forKey: "musicHUDAutoHideDelay") as? Double {
            musicHUDAutoHideDelay = val
        }
        if let val = UserDefaults.standard.object(forKey: "notchHUDIconSize") as? Double {
            notchHUDIconSize = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "notchHUDValueFontSize") as? Double {
            notchHUDValueFontSize = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "notchHUDInnerPadding") as? Double {
            notchHUDInnerPadding = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "notchHUDShowBackground") as? Bool {
            notchHUDShowBackground = val
        }
        if let val = UserDefaults.standard.object(forKey: "notchHUDUseProgressBar") as? Bool {
            notchHUDUseProgressBar = val
        }
        if let val = UserDefaults.standard.object(forKey: "notchHUDProgressBarWidth") as? Double {
            notchHUDProgressBarWidth = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "notchHUDProgressBarHeight") as? Double {
            notchHUDProgressBarHeight = CGFloat(val)
        }

        // SystemStatus Settings
        if let val = UserDefaults.standard.object(forKey: "systemStatusFrameHeight") as? Double {
            systemStatusFrameHeight = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "systemStatusHorizontalPadding") as? Double {
            systemStatusHorizontalPadding = CGFloat(val)
        }
        if let val = UserDefaults.standard.object(forKey: "wifiStrongThreshold") as? Double {
            wifiStrongThreshold = val
        }
        if let val = UserDefaults.standard.object(forKey: "wifiMediumThreshold") as? Double {
            wifiMediumThreshold = val
        }
        if let val = UserDefaults.standard.object(forKey: "batteryHighThreshold") as? Double {
            batteryHighThreshold = val
        }
        if let val = UserDefaults.standard.object(forKey: "batteryMediumThreshold") as? Double {
            batteryMediumThreshold = val
        }
        if let val = UserDefaults.standard.object(forKey: "batteryLowThreshold") as? Double {
            batteryLowThreshold = val
        }
        if let val = UserDefaults.standard.object(forKey: "batteryCriticalThreshold") as? Double {
            batteryCriticalThreshold = val
        }
        if let val = UserDefaults.standard.object(forKey: "showFocusName") as? Bool {
            showFocusName = val
        }
        if let val = UserDefaults.standard.string(forKey: "dateFormat"),
           let format = DateFormat(rawValue: val) {
            dateFormat = format
        }
    }

    func resetToDefaults() {
        // Reset all values to their default state
        menuBarHeight = NSScreen.main?.safeAreaInsets.top ?? 37
        menuBarEdgePadding = 100
        spaceIndicatorSpacing = 8
        systemIconSpacing = 12
        systemIconSize = 14
        layoutButtonWidth = 32
        buttonLabelExpandedWidth = 95
        systemStatusWidth = 150

        spaceCircleSize = 32
        appIconSize = 28
        appIconSpacing = 4
        maxAppIconsPerSpace = 3
        windowIconFrameWidth = 22
        windowIconFrameHeight = 22
        maxExpandedWidth = 100
        stackBadgeSize = 10
        focusDotSize = 3
        overflowButtonSize = 20

        spaceContentSpacing = 6
        spaceIndicatorHorizontalPadding = 8
        spaceIndicatorVerticalPadding = 5
        dropZoneHorizontalPadding = 4
        dropZoneVerticalPadding = 8

        spaceNumberFontSize = 12
        windowTitleFontSize = 11
        appNameFontSize = 9
        overflowButtonFontSize = 9
        stackBadgeFontSize = 6
        systemStatusFontSize = 13

        spaceIndicatorCornerRadius = 8
        overflowButtonCornerRadius = 4
        systemStatusCornerRadius = 8
        layoutButtonCornerRadius = 8

        activeSpaceBgOpacity = 0.18
        hoveredSpaceBgOpacity = 0.15
        inactiveSpaceBgOpacity = 0.12
        activeButtonBgOpacity = 0.2
        hoveredButtonBgOpacity = 0.15
        inactiveButtonBgOpacity = 0.12
        overflowMenuShowingBgOpacity = 0.25
        overflowButtonBgOpacity = 0.12
        systemStatusBgOpacity = 0.12
        activeBorderOpacity = 0.18
        systemStatusBorderOpacity = 0.2
        primaryTextOpacity = 1.0
        secondaryTextOpacity = 0.9
        tertiaryTextOpacity = 0.6
        iconHoverGlowOpacity = 0.15
        iconHoverBgOpacity = 0.2
        buttonBackdropBlurOpacity = 0.4
        spaceShadowOpacity = 0.12
        spaceShadowRadius = 4
        systemStatusShadowRadius = 1

        showAppNameInExpansion = false
        useSwipeToDestroySpace = true
        enableLayoutActionHaptics = true
        windowIconExpansionAutoCollapseDelay = 2.0
        actionLabelAutoHideDelay = 1.5

        dragDistanceThreshold = 3
        swipeDestroyThreshold = -120
        scrollActionThreshold = 3

        hoverAnimationResponse = 0.3
        hoverAnimationDamping = 0.7
        expansionAnimationResponse = 0.35
        expansionAnimationDamping = 0.75
        collapseAnimationResponse = 0.25
        collapseAnimationDamping = 0.8
        positionUpdateResponse = 0.3
        positionUpdateDamping = 0.7
        stateTransitionDuration = 0.25
        windowUpdateDuration = 0.2
        autoScrollDuration = 0.3
        fadeMaskDuration = 0.2
        notchHUDFadeInDuration = 0.2
        notchHUDFadeOutDuration = 0.3
        hoverEffectDuration = 0.2

        hoveredButtonScale = 1.02
        hoveredIconScale = 1.0

        notchWidth = 200
        notchPadding = 20
        notchHUDWidth = 50
        notchHUDHeight = 50
        notchHUDTopPadding = 8
        notchHUDAutoHideDelay = 1.5
        minimalHUDVerticalPadding = 12
        musicHUDVerticalPadding = 8
        albumArtSize = 40
        albumArtPadding = 10
        visualizerHeight = 40
        visualizerPadding = 10
        visualizerBarCount = 5
        visualizerBarSpacing = 4
        visualizerBarWidth = 3
        visualizerBarMinHeight = 5
        visualizerBarMaxHeight = 20
        visualizerAnimationDuration = 0.3
        visualizerUseBlurEffect = false
        showMusicHUD = true
        musicHUDRightPanelMode = .visualizer
        musicHUDAutoHide = false
        musicHUDAutoHideDelay = 5.0
        notchHUDIconSize = 13
        notchHUDValueFontSize = 13
        notchHUDInnerPadding = 8
        notchHUDShowBackground = false
        notchHUDUseProgressBar = false
        notchHUDProgressBarWidth = 60
        notchHUDProgressBarHeight = 4

        systemStatusFrameHeight = 20
        systemStatusHorizontalPadding = 6
        wifiStrongThreshold = 0.66
        wifiMediumThreshold = 0.33
        batteryHighThreshold = 0.75
        batteryMediumThreshold = 0.5
        batteryLowThreshold = 0.25
        batteryCriticalThreshold = 0.1
        showFocusName = false
        dateFormat = .long

        savePreferences()
    }
}
