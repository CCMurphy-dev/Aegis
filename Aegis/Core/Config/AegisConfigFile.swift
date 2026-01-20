//
//  AegisConfigFile.swift
//  Aegis
//
//  JSON file-based configuration support for ~/.config/aegis/config.json
//

import Foundation

// MARK: - JSON Configuration Data Structure

/// Codable struct that mirrors AegisConfig for JSON serialization
/// All properties are optional to allow partial configs (only override what you need)
struct AegisConfigData: Codable {
    // Menu Bar Layout
    var menuBarHeight: Double?
    var menuBarEdgePadding: Double?
    var spaceIndicatorSpacing: Double?
    var systemIconSpacing: Double?
    var systemIconSize: Double?
    var layoutButtonWidth: Double?
    var buttonLabelExpandedWidth: Double?
    var systemStatusWidth: Double?

    // Space Indicator Dimensions
    var spaceCircleSize: Double?
    var appIconSize: Double?
    var appIconSpacing: Double?
    var maxAppIconsPerSpace: Int?
    var windowIconFrameWidth: Double?
    var windowIconFrameHeight: Double?
    var maxExpandedWidth: Double?
    var stackBadgeSize: Double?
    var focusDotSize: Double?
    var overflowButtonSize: Double?

    // Spacing & Padding
    var spaceContentSpacing: Double?
    var spaceIndicatorHorizontalPadding: Double?
    var spaceIndicatorVerticalPadding: Double?
    var dropZoneHorizontalPadding: Double?
    var dropZoneVerticalPadding: Double?

    // Typography
    var spaceNumberFontSize: Double?
    var windowTitleFontSize: Double?
    var appNameFontSize: Double?
    var overflowButtonFontSize: Double?
    var stackBadgeFontSize: Double?
    var systemStatusFontSize: Double?

    // Corner Radii
    var spaceIndicatorCornerRadius: Double?
    var overflowButtonCornerRadius: Double?
    var systemStatusCornerRadius: Double?
    var layoutButtonCornerRadius: Double?

    // Colors - Background Opacity
    var activeSpaceBgOpacity: Double?
    var hoveredSpaceBgOpacity: Double?
    var inactiveSpaceBgOpacity: Double?
    var activeButtonBgOpacity: Double?
    var hoveredButtonBgOpacity: Double?
    var inactiveButtonBgOpacity: Double?
    var overflowMenuShowingBgOpacity: Double?
    var overflowButtonBgOpacity: Double?
    var systemStatusBgOpacity: Double?

    // Colors - Border & Stroke Opacity
    var activeBorderOpacity: Double?
    var systemStatusBorderOpacity: Double?

    // Colors - Text & Icon Opacity
    var primaryTextOpacity: Double?
    var secondaryTextOpacity: Double?
    var tertiaryTextOpacity: Double?

    // Colors - Hover & Glow Effects
    var iconHoverGlowOpacity: Double?
    var iconHoverBgOpacity: Double?
    var buttonBackdropBlurOpacity: Double?

    // Colors - Shadows
    var spaceShadowOpacity: Double?
    var spaceShadowRadius: Double?
    var systemStatusShadowRadius: Double?

    // Window Filtering
    var excludedApps: [String]?

    // App Switcher Settings
    var appSwitcherEnabled: Bool?
    var appSwitcherShowMinimized: Bool?
    var appSwitcherShowHidden: Bool?
    var appSwitcherCmdScrollEnabled: Bool?

    // Behavior Flags
    var showAppNameInExpansion: Bool?
    var useSwipeToDestroySpace: Bool?
    var enableLayoutActionHaptics: Bool?
    var expandContextButtonOnScroll: Bool?
    var launchAtLogin: Bool?

    // Behavior Settings - Auto-Hide & Delays
    var windowIconExpansionAutoCollapseDelay: Double?
    var actionLabelAutoHideDelay: Double?

    // Interaction Thresholds
    var dragDistanceThreshold: Double?
    var swipeDestroyThreshold: Double?
    var scrollActionThreshold: Double?
    var scrollNotchedBehavior: Bool?

    // Animation Settings - Spring Animations
    var hoverAnimationResponse: Double?
    var hoverAnimationDamping: Double?
    var expansionAnimationResponse: Double?
    var expansionAnimationDamping: Double?
    var collapseAnimationResponse: Double?
    var collapseAnimationDamping: Double?
    var positionUpdateResponse: Double?
    var positionUpdateDamping: Double?

    // Animation Settings - Durations
    var stateTransitionDuration: Double?
    var windowUpdateDuration: Double?
    var autoScrollDuration: Double?
    var fadeMaskDuration: Double?
    var notchHUDFadeInDuration: Double?
    var notchHUDFadeOutDuration: Double?
    var hoverEffectDuration: Double?

    // Dynamic Visuals - Scale Effects
    var hoveredButtonScale: Double?
    var hoveredIconScale: Double?

    // Notch Settings - Screen & Layout
    var notchWidth: Double?
    var notchPadding: Double?

    // Notch Settings - HUD Dimensions
    var notchHUDWidth: Double?
    var notchHUDHeight: Double?
    var notchHUDTopPadding: Double?
    var notchHUDAutoHideDelay: Double?
    var minimalHUDVerticalPadding: Double?
    var musicHUDVerticalPadding: Double?

    // Notch Settings - Music HUD
    var albumArtSize: Double?
    var albumArtPadding: Double?
    var visualizerHeight: Double?
    var visualizerPadding: Double?
    var visualizerBarCount: Int?
    var visualizerBarSpacing: Double?
    var visualizerBarWidth: Double?
    var visualizerBarMinHeight: Double?
    var visualizerBarMaxHeight: Double?
    var visualizerAnimationDuration: Double?
    var visualizerUseBlurEffect: Bool?
    var showMusicHUD: Bool?
    var showMediaHUD: Bool?  // Alias for showMusicHUD
    var musicHUDRightPanelMode: String?  // "visualizer" or "trackInfo"
    var musicHUDAutoHide: Bool?
    var musicHUDAutoHideDelay: Double?
    var mediaHUDEnableMarquee: Bool?  // Enable carousel scrolling for long track titles

    // Device Connection HUD Settings
    var showDeviceHUD: Bool?
    var deviceHUDAutoHideDelay: Double?
    var excludedBluetoothDevices: [String]?

    // Focus HUD Settings
    var showFocusHUD: Bool?
    var focusHUDAutoHideDelay: Double?

    // App Launcher Settings
    var launcherApps: [String]?

    // Notch HUD Icon & Text Settings
    var notchHUDIconSize: Double?
    var notchHUDValueFontSize: Double?
    var notchHUDInnerPadding: Double?
    var notchHUDShowBackground: Bool?
    var notchHUDUseProgressBar: Bool?
    var notchHUDProgressBarWidth: Double?
    var notchHUDProgressBarHeight: Double?

    // SystemStatus Settings
    var systemStatusFrameHeight: Double?
    var systemStatusHorizontalPadding: Double?
    var wifiStrongThreshold: Double?
    var wifiMediumThreshold: Double?
    var batteryHighThreshold: Double?
    var batteryMediumThreshold: Double?
    var batteryLowThreshold: Double?
    var batteryCriticalThreshold: Double?
    var showFocusName: Bool?
    var dateFormat: String?  // "long" or "short"
}

// MARK: - AegisConfig File Extension

extension AegisConfig {
    /// Path to the JSON config file
    static let configFilePath: URL = {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config")
            .appendingPathComponent("aegis")
        return configDir.appendingPathComponent("config.json")
    }()

    /// Load configuration from JSON file if it exists
    /// Returns true if config was loaded, false otherwise
    @discardableResult
    func loadFromJSONFile() -> Bool {
        let fileURL = Self.configFilePath
        let configDir = fileURL.deletingLastPathComponent()

        // Create config directory if needed, and starter files if they don't exist
        if !FileManager.default.fileExists(atPath: configDir.path) {
            try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        }

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                try Self.starterConfigContent.write(to: fileURL, atomically: true, encoding: .utf8)
                print("📁 AegisConfig: Created starter config at \(fileURL.path)")
            } catch {
                print("⚠️ AegisConfig: Failed to create starter config: \(error)")
            }
        }

        // Create documentation file if it doesn't exist
        let docsURL = configDir.appendingPathComponent("CONFIG_OPTIONS.md")
        if !FileManager.default.fileExists(atPath: docsURL.path) {
            try? Self.configDocumentation.write(to: docsURL, atomically: true, encoding: .utf8)
            print("📁 AegisConfig: Created config documentation at \(docsURL.path)")
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("📁 AegisConfig: No config.json found at \(fileURL.path)")
            return false
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            let configData = try decoder.decode(AegisConfigData.self, from: data)
            applyConfigData(configData)
            print("✅ AegisConfig: Loaded config from \(fileURL.path)")
            return true
        } catch {
            print("⚠️ AegisConfig: Failed to load config.json: \(error)")
            return false
        }
    }

    /// Apply values from AegisConfigData to this config
    /// Only applies non-nil values (allows partial configs)
    private func applyConfigData(_ data: AegisConfigData) {
        // Menu Bar Layout
        if let v = data.menuBarHeight { menuBarHeight = CGFloat(v) }
        if let v = data.menuBarEdgePadding { menuBarEdgePadding = CGFloat(v) }
        if let v = data.spaceIndicatorSpacing { spaceIndicatorSpacing = CGFloat(v) }
        if let v = data.systemIconSpacing { systemIconSpacing = CGFloat(v) }
        if let v = data.systemIconSize { systemIconSize = CGFloat(v) }
        if let v = data.layoutButtonWidth { layoutButtonWidth = CGFloat(v) }
        if let v = data.buttonLabelExpandedWidth { buttonLabelExpandedWidth = CGFloat(v) }
        if let v = data.systemStatusWidth { systemStatusWidth = CGFloat(v) }

        // Space Indicator Dimensions
        if let v = data.spaceCircleSize { spaceCircleSize = CGFloat(v) }
        if let v = data.appIconSize { appIconSize = CGFloat(v) }
        if let v = data.appIconSpacing { appIconSpacing = CGFloat(v) }
        if let v = data.maxAppIconsPerSpace { maxAppIconsPerSpace = v }
        if let v = data.windowIconFrameWidth { windowIconFrameWidth = CGFloat(v) }
        if let v = data.windowIconFrameHeight { windowIconFrameHeight = CGFloat(v) }
        if let v = data.maxExpandedWidth { maxExpandedWidth = CGFloat(v) }
        if let v = data.stackBadgeSize { stackBadgeSize = CGFloat(v) }
        if let v = data.focusDotSize { focusDotSize = CGFloat(v) }
        if let v = data.overflowButtonSize { overflowButtonSize = CGFloat(v) }

        // Spacing & Padding
        if let v = data.spaceContentSpacing { spaceContentSpacing = CGFloat(v) }
        if let v = data.spaceIndicatorHorizontalPadding { spaceIndicatorHorizontalPadding = CGFloat(v) }
        if let v = data.spaceIndicatorVerticalPadding { spaceIndicatorVerticalPadding = CGFloat(v) }
        if let v = data.dropZoneHorizontalPadding { dropZoneHorizontalPadding = CGFloat(v) }
        if let v = data.dropZoneVerticalPadding { dropZoneVerticalPadding = CGFloat(v) }

        // Typography
        if let v = data.spaceNumberFontSize { spaceNumberFontSize = CGFloat(v) }
        if let v = data.windowTitleFontSize { windowTitleFontSize = CGFloat(v) }
        if let v = data.appNameFontSize { appNameFontSize = CGFloat(v) }
        if let v = data.overflowButtonFontSize { overflowButtonFontSize = CGFloat(v) }
        if let v = data.stackBadgeFontSize { stackBadgeFontSize = CGFloat(v) }
        if let v = data.systemStatusFontSize { systemStatusFontSize = CGFloat(v) }

        // Corner Radii
        if let v = data.spaceIndicatorCornerRadius { spaceIndicatorCornerRadius = CGFloat(v) }
        if let v = data.overflowButtonCornerRadius { overflowButtonCornerRadius = CGFloat(v) }
        if let v = data.systemStatusCornerRadius { systemStatusCornerRadius = CGFloat(v) }
        if let v = data.layoutButtonCornerRadius { layoutButtonCornerRadius = CGFloat(v) }

        // Colors - Background Opacity
        if let v = data.activeSpaceBgOpacity { activeSpaceBgOpacity = v }
        if let v = data.hoveredSpaceBgOpacity { hoveredSpaceBgOpacity = v }
        if let v = data.inactiveSpaceBgOpacity { inactiveSpaceBgOpacity = v }
        if let v = data.activeButtonBgOpacity { activeButtonBgOpacity = v }
        if let v = data.hoveredButtonBgOpacity { hoveredButtonBgOpacity = v }
        if let v = data.inactiveButtonBgOpacity { inactiveButtonBgOpacity = v }
        if let v = data.overflowMenuShowingBgOpacity { overflowMenuShowingBgOpacity = v }
        if let v = data.overflowButtonBgOpacity { overflowButtonBgOpacity = v }
        if let v = data.systemStatusBgOpacity { systemStatusBgOpacity = v }

        // Colors - Border & Stroke Opacity
        if let v = data.activeBorderOpacity { activeBorderOpacity = v }
        if let v = data.systemStatusBorderOpacity { systemStatusBorderOpacity = v }

        // Colors - Text & Icon Opacity
        if let v = data.primaryTextOpacity { primaryTextOpacity = v }
        if let v = data.secondaryTextOpacity { secondaryTextOpacity = v }
        if let v = data.tertiaryTextOpacity { tertiaryTextOpacity = v }

        // Colors - Hover & Glow Effects
        if let v = data.iconHoverGlowOpacity { iconHoverGlowOpacity = v }
        if let v = data.iconHoverBgOpacity { iconHoverBgOpacity = v }
        if let v = data.buttonBackdropBlurOpacity { buttonBackdropBlurOpacity = v }

        // Colors - Shadows
        if let v = data.spaceShadowOpacity { spaceShadowOpacity = v }
        if let v = data.spaceShadowRadius { spaceShadowRadius = CGFloat(v) }
        if let v = data.systemStatusShadowRadius { systemStatusShadowRadius = CGFloat(v) }

        // Window Filtering
        if let v = data.excludedApps { baseExcludedApps = Set(v) }

        // App Switcher Settings
        if let v = data.appSwitcherEnabled { appSwitcherEnabled = v }
        if let v = data.appSwitcherShowMinimized { appSwitcherShowMinimized = v }
        if let v = data.appSwitcherShowHidden { appSwitcherShowHidden = v }
        if let v = data.appSwitcherCmdScrollEnabled { appSwitcherCmdScrollEnabled = v }

        // Behavior Flags
        if let v = data.showAppNameInExpansion { showAppNameInExpansion = v }
        if let v = data.useSwipeToDestroySpace { useSwipeToDestroySpace = v }
        if let v = data.enableLayoutActionHaptics { enableLayoutActionHaptics = v }
        if let v = data.expandContextButtonOnScroll { expandContextButtonOnScroll = v }
        if let v = data.launchAtLogin { launchAtLogin = v }

        // Behavior Settings - Auto-Hide & Delays
        if let v = data.windowIconExpansionAutoCollapseDelay { windowIconExpansionAutoCollapseDelay = v }
        if let v = data.actionLabelAutoHideDelay { actionLabelAutoHideDelay = v }

        // Interaction Thresholds
        if let v = data.dragDistanceThreshold { dragDistanceThreshold = CGFloat(v) }
        if let v = data.swipeDestroyThreshold { swipeDestroyThreshold = CGFloat(v) }
        if let v = data.scrollActionThreshold { scrollActionThreshold = CGFloat(v) }
        if let v = data.scrollNotchedBehavior { scrollNotchedBehavior = v }

        // Animation Settings - Spring Animations
        if let v = data.hoverAnimationResponse { hoverAnimationResponse = v }
        if let v = data.hoverAnimationDamping { hoverAnimationDamping = v }
        if let v = data.expansionAnimationResponse { expansionAnimationResponse = v }
        if let v = data.expansionAnimationDamping { expansionAnimationDamping = v }
        if let v = data.collapseAnimationResponse { collapseAnimationResponse = v }
        if let v = data.collapseAnimationDamping { collapseAnimationDamping = v }
        if let v = data.positionUpdateResponse { positionUpdateResponse = v }
        if let v = data.positionUpdateDamping { positionUpdateDamping = v }

        // Animation Settings - Durations
        if let v = data.stateTransitionDuration { stateTransitionDuration = v }
        if let v = data.windowUpdateDuration { windowUpdateDuration = v }
        if let v = data.autoScrollDuration { autoScrollDuration = v }
        if let v = data.fadeMaskDuration { fadeMaskDuration = v }
        if let v = data.notchHUDFadeInDuration { notchHUDFadeInDuration = v }
        if let v = data.notchHUDFadeOutDuration { notchHUDFadeOutDuration = v }
        if let v = data.hoverEffectDuration { hoverEffectDuration = v }

        // Dynamic Visuals - Scale Effects
        if let v = data.hoveredButtonScale { hoveredButtonScale = CGFloat(v) }
        if let v = data.hoveredIconScale { hoveredIconScale = CGFloat(v) }

        // Notch Settings - Screen & Layout
        if let v = data.notchWidth { notchWidth = CGFloat(v) }
        if let v = data.notchPadding { notchPadding = CGFloat(v) }

        // Notch Settings - HUD Dimensions
        if let v = data.notchHUDWidth { notchHUDWidth = CGFloat(v) }
        if let v = data.notchHUDHeight { notchHUDHeight = CGFloat(v) }
        if let v = data.notchHUDTopPadding { notchHUDTopPadding = CGFloat(v) }
        if let v = data.notchHUDAutoHideDelay { notchHUDAutoHideDelay = v }
        if let v = data.minimalHUDVerticalPadding { minimalHUDVerticalPadding = CGFloat(v) }
        if let v = data.musicHUDVerticalPadding { mediaHUDVerticalPadding = CGFloat(v) }

        // Notch Settings - Media HUD
        if let v = data.albumArtSize { albumArtSize = CGFloat(v) }
        if let v = data.albumArtPadding { albumArtPadding = CGFloat(v) }
        if let v = data.visualizerHeight { visualizerHeight = CGFloat(v) }
        if let v = data.visualizerPadding { visualizerPadding = CGFloat(v) }
        if let v = data.visualizerBarCount { visualizerBarCount = v }
        if let v = data.visualizerBarSpacing { visualizerBarSpacing = CGFloat(v) }
        if let v = data.visualizerBarWidth { visualizerBarWidth = CGFloat(v) }
        if let v = data.visualizerBarMinHeight { visualizerBarMinHeight = CGFloat(v) }
        if let v = data.visualizerBarMaxHeight { visualizerBarMaxHeight = CGFloat(v) }
        if let v = data.visualizerAnimationDuration { visualizerAnimationDuration = v }
        if let v = data.visualizerUseBlurEffect { visualizerUseBlurEffect = v }
        // Support both showMusicHUD and showMediaHUD (alias) - showMediaHUD takes precedence
        if let v = data.showMusicHUD { showMediaHUD = v }
        if let v = data.showMediaHUD { showMediaHUD = v }
        if let v = data.musicHUDRightPanelMode, let mode = MediaHUDRightPanelMode(rawValue: v) {
            mediaHUDRightPanelMode = mode
        }
        if let v = data.musicHUDAutoHide { mediaHUDAutoHide = v }
        if let v = data.musicHUDAutoHideDelay { mediaHUDAutoHideDelay = v }
        if let v = data.mediaHUDEnableMarquee { mediaHUDEnableMarquee = v }

        // Device Connection HUD Settings
        if let v = data.showDeviceHUD { showDeviceHUD = v }
        if let v = data.deviceHUDAutoHideDelay { deviceHUDAutoHideDelay = v }
        if let v = data.excludedBluetoothDevices { excludedBluetoothDevices = v }

        // Focus HUD Settings
        if let v = data.showFocusHUD { showFocusHUD = v }
        if let v = data.focusHUDAutoHideDelay { focusHUDAutoHideDelay = v }

        // App Launcher Settings
        if let v = data.launcherApps { launcherApps = v }

        // Notch HUD Icon & Text Settings
        if let v = data.notchHUDIconSize { notchHUDIconSize = CGFloat(v) }
        if let v = data.notchHUDValueFontSize { notchHUDValueFontSize = CGFloat(v) }
        if let v = data.notchHUDInnerPadding { notchHUDInnerPadding = CGFloat(v) }
        if let v = data.notchHUDShowBackground { notchHUDShowBackground = v }
        if let v = data.notchHUDUseProgressBar { notchHUDUseProgressBar = v }
        if let v = data.notchHUDProgressBarWidth { notchHUDProgressBarWidth = CGFloat(v) }
        if let v = data.notchHUDProgressBarHeight { notchHUDProgressBarHeight = CGFloat(v) }

        // SystemStatus Settings
        if let v = data.systemStatusFrameHeight { systemStatusFrameHeight = CGFloat(v) }
        if let v = data.systemStatusHorizontalPadding { systemStatusHorizontalPadding = CGFloat(v) }
        if let v = data.wifiStrongThreshold { wifiStrongThreshold = v }
        if let v = data.wifiMediumThreshold { wifiMediumThreshold = v }
        if let v = data.batteryHighThreshold { batteryHighThreshold = v }
        if let v = data.batteryMediumThreshold { batteryMediumThreshold = v }
        if let v = data.batteryLowThreshold { batteryLowThreshold = v }
        if let v = data.batteryCriticalThreshold { batteryCriticalThreshold = v }
        if let v = data.showFocusName { showFocusName = v }
        if let v = data.dateFormat, let format = DateFormat(rawValue: v) {
            dateFormat = format
        }
    }

    /// Export current config to JSON file
    func saveToJSONFile() {
        let configData = toConfigData()

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(configData)

            // Ensure directory exists
            let configDir = Self.configFilePath.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

            try data.write(to: Self.configFilePath)
            print("✅ AegisConfig: Saved config to \(Self.configFilePath.path)")
        } catch {
            print("⚠️ AegisConfig: Failed to save config.json: \(error)")
        }
    }

    /// Convert current config to AegisConfigData
    private func toConfigData() -> AegisConfigData {
        AegisConfigData(
            // Menu Bar Layout
            menuBarHeight: Double(menuBarHeight),
            menuBarEdgePadding: Double(menuBarEdgePadding),
            spaceIndicatorSpacing: Double(spaceIndicatorSpacing),
            systemIconSpacing: Double(systemIconSpacing),
            systemIconSize: Double(systemIconSize),
            layoutButtonWidth: Double(layoutButtonWidth),
            buttonLabelExpandedWidth: Double(buttonLabelExpandedWidth),
            systemStatusWidth: Double(systemStatusWidth),

            // Space Indicator Dimensions
            spaceCircleSize: Double(spaceCircleSize),
            appIconSize: Double(appIconSize),
            appIconSpacing: Double(appIconSpacing),
            maxAppIconsPerSpace: maxAppIconsPerSpace,
            windowIconFrameWidth: Double(windowIconFrameWidth),
            windowIconFrameHeight: Double(windowIconFrameHeight),
            maxExpandedWidth: Double(maxExpandedWidth),
            stackBadgeSize: Double(stackBadgeSize),
            focusDotSize: Double(focusDotSize),
            overflowButtonSize: Double(overflowButtonSize),

            // Spacing & Padding
            spaceContentSpacing: Double(spaceContentSpacing),
            spaceIndicatorHorizontalPadding: Double(spaceIndicatorHorizontalPadding),
            spaceIndicatorVerticalPadding: Double(spaceIndicatorVerticalPadding),
            dropZoneHorizontalPadding: Double(dropZoneHorizontalPadding),
            dropZoneVerticalPadding: Double(dropZoneVerticalPadding),

            // Typography
            spaceNumberFontSize: Double(spaceNumberFontSize),
            windowTitleFontSize: Double(windowTitleFontSize),
            appNameFontSize: Double(appNameFontSize),
            overflowButtonFontSize: Double(overflowButtonFontSize),
            stackBadgeFontSize: Double(stackBadgeFontSize),
            systemStatusFontSize: Double(systemStatusFontSize),

            // Corner Radii
            spaceIndicatorCornerRadius: Double(spaceIndicatorCornerRadius),
            overflowButtonCornerRadius: Double(overflowButtonCornerRadius),
            systemStatusCornerRadius: Double(systemStatusCornerRadius),
            layoutButtonCornerRadius: Double(layoutButtonCornerRadius),

            // Colors - Background Opacity
            activeSpaceBgOpacity: activeSpaceBgOpacity,
            hoveredSpaceBgOpacity: hoveredSpaceBgOpacity,
            inactiveSpaceBgOpacity: inactiveSpaceBgOpacity,
            activeButtonBgOpacity: activeButtonBgOpacity,
            hoveredButtonBgOpacity: hoveredButtonBgOpacity,
            inactiveButtonBgOpacity: inactiveButtonBgOpacity,
            overflowMenuShowingBgOpacity: overflowMenuShowingBgOpacity,
            overflowButtonBgOpacity: overflowButtonBgOpacity,
            systemStatusBgOpacity: systemStatusBgOpacity,

            // Colors - Border & Stroke Opacity
            activeBorderOpacity: activeBorderOpacity,
            systemStatusBorderOpacity: systemStatusBorderOpacity,

            // Colors - Text & Icon Opacity
            primaryTextOpacity: primaryTextOpacity,
            secondaryTextOpacity: secondaryTextOpacity,
            tertiaryTextOpacity: tertiaryTextOpacity,

            // Colors - Hover & Glow Effects
            iconHoverGlowOpacity: iconHoverGlowOpacity,
            iconHoverBgOpacity: iconHoverBgOpacity,
            buttonBackdropBlurOpacity: buttonBackdropBlurOpacity,

            // Colors - Shadows
            spaceShadowOpacity: spaceShadowOpacity,
            spaceShadowRadius: Double(spaceShadowRadius),
            systemStatusShadowRadius: Double(systemStatusShadowRadius),

            // Window Filtering
            excludedApps: Array(baseExcludedApps),

            // App Switcher Settings
            appSwitcherEnabled: appSwitcherEnabled,
            appSwitcherShowMinimized: appSwitcherShowMinimized,
            appSwitcherShowHidden: appSwitcherShowHidden,
            appSwitcherCmdScrollEnabled: appSwitcherCmdScrollEnabled,

            // Behavior Flags
            showAppNameInExpansion: showAppNameInExpansion,
            useSwipeToDestroySpace: useSwipeToDestroySpace,
            enableLayoutActionHaptics: enableLayoutActionHaptics,
            expandContextButtonOnScroll: expandContextButtonOnScroll,
            launchAtLogin: launchAtLogin,

            // Behavior Settings - Auto-Hide & Delays
            windowIconExpansionAutoCollapseDelay: windowIconExpansionAutoCollapseDelay,
            actionLabelAutoHideDelay: actionLabelAutoHideDelay,

            // Interaction Thresholds
            dragDistanceThreshold: Double(dragDistanceThreshold),
            swipeDestroyThreshold: Double(swipeDestroyThreshold),
            scrollActionThreshold: Double(scrollActionThreshold),
            scrollNotchedBehavior: scrollNotchedBehavior,

            // Animation Settings - Spring Animations
            hoverAnimationResponse: hoverAnimationResponse,
            hoverAnimationDamping: hoverAnimationDamping,
            expansionAnimationResponse: expansionAnimationResponse,
            expansionAnimationDamping: expansionAnimationDamping,
            collapseAnimationResponse: collapseAnimationResponse,
            collapseAnimationDamping: collapseAnimationDamping,
            positionUpdateResponse: positionUpdateResponse,
            positionUpdateDamping: positionUpdateDamping,

            // Animation Settings - Durations
            stateTransitionDuration: stateTransitionDuration,
            windowUpdateDuration: windowUpdateDuration,
            autoScrollDuration: autoScrollDuration,
            fadeMaskDuration: fadeMaskDuration,
            notchHUDFadeInDuration: notchHUDFadeInDuration,
            notchHUDFadeOutDuration: notchHUDFadeOutDuration,
            hoverEffectDuration: hoverEffectDuration,

            // Dynamic Visuals - Scale Effects
            hoveredButtonScale: Double(hoveredButtonScale),
            hoveredIconScale: Double(hoveredIconScale),

            // Notch Settings - Screen & Layout
            notchWidth: Double(notchWidth),
            notchPadding: Double(notchPadding),

            // Notch Settings - HUD Dimensions
            notchHUDWidth: Double(notchHUDWidth),
            notchHUDHeight: Double(notchHUDHeight),
            notchHUDTopPadding: Double(notchHUDTopPadding),
            notchHUDAutoHideDelay: notchHUDAutoHideDelay,
            minimalHUDVerticalPadding: Double(minimalHUDVerticalPadding),
            musicHUDVerticalPadding: Double(mediaHUDVerticalPadding),

            // Notch Settings - Media HUD
            albumArtSize: Double(albumArtSize),
            albumArtPadding: Double(albumArtPadding),
            visualizerHeight: Double(visualizerHeight),
            visualizerPadding: Double(visualizerPadding),
            visualizerBarCount: visualizerBarCount,
            visualizerBarSpacing: Double(visualizerBarSpacing),
            visualizerBarWidth: Double(visualizerBarWidth),
            visualizerBarMinHeight: Double(visualizerBarMinHeight),
            visualizerBarMaxHeight: Double(visualizerBarMaxHeight),
            visualizerAnimationDuration: visualizerAnimationDuration,
            visualizerUseBlurEffect: visualizerUseBlurEffect,
            showMusicHUD: showMediaHUD,
            musicHUDRightPanelMode: mediaHUDRightPanelMode.rawValue,
            musicHUDAutoHide: mediaHUDAutoHide,
            musicHUDAutoHideDelay: mediaHUDAutoHideDelay,
            mediaHUDEnableMarquee: mediaHUDEnableMarquee,

            // Device Connection HUD Settings
            showDeviceHUD: showDeviceHUD,
            deviceHUDAutoHideDelay: deviceHUDAutoHideDelay,
            excludedBluetoothDevices: excludedBluetoothDevices,

            // Focus HUD Settings
            showFocusHUD: showFocusHUD,
            focusHUDAutoHideDelay: focusHUDAutoHideDelay,

            // App Launcher Settings
            launcherApps: launcherApps,

            // Notch HUD Icon & Text Settings
            notchHUDIconSize: Double(notchHUDIconSize),
            notchHUDValueFontSize: Double(notchHUDValueFontSize),
            notchHUDInnerPadding: Double(notchHUDInnerPadding),
            notchHUDShowBackground: notchHUDShowBackground,
            notchHUDUseProgressBar: notchHUDUseProgressBar,
            notchHUDProgressBarWidth: Double(notchHUDProgressBarWidth),
            notchHUDProgressBarHeight: Double(notchHUDProgressBarHeight),

            // SystemStatus Settings
            systemStatusFrameHeight: Double(systemStatusFrameHeight),
            systemStatusHorizontalPadding: Double(systemStatusHorizontalPadding),
            wifiStrongThreshold: wifiStrongThreshold,
            wifiMediumThreshold: wifiMediumThreshold,
            batteryHighThreshold: batteryHighThreshold,
            batteryMediumThreshold: batteryMediumThreshold,
            batteryLowThreshold: batteryLowThreshold,
            batteryCriticalThreshold: batteryCriticalThreshold,
            showFocusName: showFocusName,
            dateFormat: dateFormat.rawValue
        )
    }

    /// Starter config content created on first run
    /// Only includes commonly-changed settings
    static let starterConfigContent = """
{
    "_docs": "See CONFIG_OPTIONS.md for all available settings",

    "appSwitcherEnabled": true,
    "appSwitcherCmdScrollEnabled": false,

    "showDeviceHUD": true,
    "deviceHUDAutoHideDelay": 3.0,
    "excludedBluetoothDevices": ["watch"],

    "showMusicHUD": true,
    "musicHUDRightPanelMode": "visualizer",

    "showFocusHUD": true,

    "launcherApps": [
        "com.apple.finder",
        "com.apple.systempreferences",
        "com.apple.ActivityMonitor",
        "com.apple.Terminal"
    ],

    "maxAppIconsPerSpace": 3,
    "excludedApps": ["Finder", "Aegis"]
}
"""

    /// Documentation for all config options
    static let configDocumentation = """
# Aegis Configuration Options

Edit `config.json` in this directory. Changes are applied automatically.

Only include settings you want to change - defaults are used for anything not specified.

---

## App Switcher

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `appSwitcherEnabled` | bool | `true` | Enable custom Cmd+Tab app switcher |
| `appSwitcherCmdScrollEnabled` | bool | `false` | Enable Cmd+scroll to open/cycle app switcher |
| `appSwitcherShowMinimized` | bool | `true` | Show minimized windows in switcher |
| `appSwitcherShowHidden` | bool | `false` | Show hidden windows in switcher |

---

## Notch HUD - Bluetooth Devices

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `showDeviceHUD` | bool | `true` | Show HUD when Bluetooth devices connect/disconnect |
| `deviceHUDAutoHideDelay` | number | `3.0` | Seconds before HUD auto-hides |
| `excludedBluetoothDevices` | [string] | `["watch"]` | Device names to ignore (case-insensitive substring match) |

---

## Notch HUD - Now Playing

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `showMusicHUD` | bool | `true` | Show Now Playing HUD when music plays (alias: `showMediaHUD`) |
| `musicHUDRightPanelMode` | string | `"visualizer"` | Right panel content: `"visualizer"` or `"trackInfo"` |
| `musicHUDAutoHide` | bool | `false` | Auto-hide after showing track info |
| `musicHUDAutoHideDelay` | number | `5.0` | Seconds before auto-hide (if enabled) |
| `mediaHUDEnableMarquee` | bool | `true` | Enable carousel scrolling for long track titles (disable to reduce CPU) |

---

## Notch HUD - Focus Mode

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `showFocusHUD` | bool | `true` | Show HUD when Focus mode changes |
| `focusHUDAutoHideDelay` | number | `2.0` | Seconds before HUD auto-hides |

---

## App Launcher

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `launcherApps` | [string] | See below | Bundle IDs for apps in the launcher (scroll to select) |

**Default launcherApps:**
```json
["com.apple.finder", "com.apple.systempreferences", "com.apple.ActivityMonitor", "com.apple.Terminal"]
```

To find an app's bundle identifier, run in Terminal:
```bash
osascript -e 'id of app "AppName"'
```

---

## Menu Bar

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `maxAppIconsPerSpace` | int | `3` | Max window icons per space before overflow menu |
| `excludedApps` | [string] | `["Finder", "Aegis"]` | Base apps to hide from space indicators (launcher apps are automatically excluded) |
| `showAppNameInExpansion` | bool | `false` | Show app name below window title when expanded |
| `useSwipeToDestroySpace` | bool | `true` | Enable swipe-up gesture to destroy spaces |

---

## Behavior

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `launchAtLogin` | bool | `true` | Start Aegis when macOS starts |
| `enableLayoutActionHaptics` | bool | `true` | Haptic feedback on layout actions |
| `expandContextButtonOnScroll` | bool | `true` | Show label when scrolling context button (disable to save CPU) |
| `windowIconExpansionAutoCollapseDelay` | number | `2.0` | Seconds before expanded window collapses |

---

## Interaction Thresholds

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `dragDistanceThreshold` | number | `3` | Pixels before drag starts |
| `swipeDestroyThreshold` | number | `-120` | Swipe distance to destroy space |
| `scrollActionThreshold` | number | `3` | Scroll amount for action selection |

---

## Animation Timings

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stateTransitionDuration` | number | `0.25` | Duration for state changes |
| `notchHUDFadeInDuration` | number | `0.2` | HUD fade-in duration |
| `notchHUDFadeOutDuration` | number | `0.3` | HUD fade-out duration |

---

## Visual Customization

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `activeSpaceBgOpacity` | number | `0.18` | Background opacity for active space |
| `hoveredSpaceBgOpacity` | number | `0.15` | Background opacity for hovered space |
| `inactiveSpaceBgOpacity` | number | `0.12` | Background opacity for inactive space |

---

## System Status

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `dateFormat` | string | `"long"` | Date format: `"long"` (Mon Jan 13) or `"short"` (13/01/26) |
| `showFocusName` | bool | `false` | Show Focus mode name alongside symbol |

---

## Export Full Config

To see all current values, you can export the full config by adding this to a Swift file or running in Xcode console:

```swift
AegisConfig.shared.saveToJSONFile()
```

This will overwrite `config.json` with all settings and their current values.
"""
}
