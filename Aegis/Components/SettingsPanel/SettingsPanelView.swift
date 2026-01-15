import SwiftUI

/// Main Settings Panel for configuring all Aegis UI elements, behaviors, and visual parameters
/// This panel provides live-updating controls that modify AegisConfig.shared
struct SettingsPanelView: View {
    @ObservedObject var config = AegisConfig.shared
    @Environment(\.presentationMode) var presentationMode

    @State private var searchText = ""
    @State private var selectedTab: SettingsTab = .ui

    enum SettingsTab: String, CaseIterable {
        case ui = "UI"
        case menuBar = "Menu Bar"
        case notch = "Notch"
        case systemStatus = "System"
        case dynamic = "Visuals"
        case animations = "Animation"
    }

    var body: some View {
        ZStack {
            // Background
            Color.black.opacity(0.95)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                header

                // Tab Bar
                tabBar

                Divider()
                    .background(Color.white.opacity(0.2))

                // Content Area
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        switch selectedTab {
                        case .ui:
                            UISettingsSection(config: config)
                        case .menuBar:
                            MenuBarSettingsSection(config: config)
                        case .notch:
                            NotchSettingsSection(config: config)
                        case .systemStatus:
                            SystemStatusSettingsSection(config: config)
                        case .dynamic:
                            DynamicVisualsSection(config: config)
                        case .animations:
                            AnimationSettingsSection(config: config)
                        }
                    }
                    .padding()
                }

                Divider()
                    .background(Color.white.opacity(0.2))

                // Footer with actions
                footer
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Aegis Settings")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)

                Text("Customize UI, behavior, and visual parameters")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()

            Button(action: {
                presentationMode.wrappedValue.dismiss()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.6))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding()
        .background(Color.black.opacity(0.3))
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                }) {
                    VStack(spacing: 4) {
                        Text(tab.rawValue)
                            .font(.system(size: 11, weight: selectedTab == tab ? .semibold : .regular))
                            .foregroundColor(selectedTab == tab ? .blue : .white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)

                        if selectedTab == tab {
                            Rectangle()
                                .fill(Color.blue)
                                .frame(height: 2)
                                .transition(.opacity)
                        } else {
                            Rectangle()
                                .fill(Color.clear)
                                .frame(height: 2)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .background(Color.black.opacity(0.2))
    }

    private var footer: some View {
        HStack(spacing: 12) {
            SettingsActionButton(
                title: "Reset to Defaults",
                icon: "arrow.counterclockwise",
                destructive: true
            ) {
                config.resetToDefaults()
            }

            SettingsActionButton(
                title: "Save Changes",
                icon: "checkmark.circle.fill",
                destructive: false
            ) {
                config.savePreferences()
                presentationMode.wrappedValue.dismiss()
            }
        }
        .padding()
        .background(Color.black.opacity(0.3))
    }
}

// MARK: - UI Settings Section

struct UISettingsSection: View {
    @ObservedObject var config: AegisConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionHeader(title: "Layout & Dimensions", icon: "rectangle.3.group")

            SettingsSlider(
                label: "Menu Bar Height",
                value: $config.menuBarHeight,
                range: 30...60,
                step: 1,
                unit: "px"
            )

            SettingsSlider(
                label: "Edge Padding",
                value: $config.menuBarEdgePadding,
                range: 50...150,
                step: 5,
                unit: "px"
            )

            SettingsSlider(
                label: "Space Indicator Spacing",
                value: $config.spaceIndicatorSpacing,
                range: 4...16,
                step: 1,
                unit: "px"
            )

            SettingsDivider()

            SettingsSectionHeader(title: "Typography", icon: "textformat")

            SettingsSlider(
                label: "Space Number Font Size",
                value: $config.spaceNumberFontSize,
                range: 10...16,
                step: 1,
                unit: "pt"
            )

            SettingsSlider(
                label: "Window Title Font Size",
                value: $config.windowTitleFontSize,
                range: 9...14,
                step: 1,
                unit: "pt"
            )

            SettingsSlider(
                label: "System Status Font Size",
                value: $config.systemStatusFontSize,
                range: 11...16,
                step: 1,
                unit: "pt"
            )

            SettingsDivider()

            SettingsSectionHeader(title: "Corner Radii", icon: "rectangle.roundedtop")

            SettingsSlider(
                label: "Space Indicator Corners",
                value: $config.spaceIndicatorCornerRadius,
                range: 0...16,
                step: 1,
                unit: "px"
            )

            SettingsSlider(
                label: "System Status Corners",
                value: $config.systemStatusCornerRadius,
                range: 0...16,
                step: 1,
                unit: "px"
            )
        }
    }
}

// MARK: - Menu Bar Settings Section

struct MenuBarSettingsSection: View {
    @ObservedObject var config: AegisConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionHeader(title: "Space Indicators", icon: "square.grid.3x1")

            SettingsIntSlider(
                label: "Max Icons Per Space",
                value: $config.maxAppIconsPerSpace,
                range: 1...10,
                unit: ""
            )

            SettingsSlider(
                label: "App Icon Size",
                value: $config.appIconSize,
                range: 20...36,
                step: 2,
                unit: "px"
            )

            SettingsSlider(
                label: "Window Icon Frame Width",
                value: $config.windowIconFrameWidth,
                range: 16...32,
                step: 2,
                unit: "px"
            )

            SettingsDivider()

            SettingsSectionHeader(title: "Behavior", icon: "hand.tap")

            SettingsToggle(
                label: "Show App Names in Expansion",
                description: "Display app names under window titles when expanded",
                isOn: $config.showAppNameInExpansion
            )

            SettingsToggle(
                label: "Swipe to Destroy Space",
                description: "Enable swipe-up gesture to destroy spaces",
                isOn: $config.useSwipeToDestroySpace
            )

            SettingsToggle(
                label: "Haptic Feedback",
                description: "Provide haptic feedback on layout actions",
                isOn: $config.enableLayoutActionHaptics
            )

            SettingsToggle(
                label: "Launch at Login",
                description: "Start Aegis automatically when macOS starts",
                isOn: $config.launchAtLogin
            )

            SettingsDivider()

            SettingsSectionHeader(title: "Auto-Hide Delays", icon: "clock")

            SettingsDoubleSlider(
                label: "Window Expansion Auto-Collapse",
                value: $config.windowIconExpansionAutoCollapseDelay,
                range: 0.5...5.0,
                step: 0.1,
                unit: "s"
            )

            SettingsDoubleSlider(
                label: "Action Label Auto-Hide",
                value: $config.actionLabelAutoHideDelay,
                range: 0.5...5.0,
                step: 0.1,
                unit: "s"
            )

            SettingsDivider()

            SettingsSectionHeader(title: "Interaction Thresholds", icon: "hand.point.up")

            SettingsSlider(
                label: "Drag Distance Threshold",
                value: $config.dragDistanceThreshold,
                range: 1...10,
                step: 1,
                unit: "px"
            )

            SettingsSlider(
                label: "Swipe Destroy Threshold",
                value: $config.swipeDestroyThreshold,
                range: -200...(-50),
                step: 10,
                unit: "px"
            )

            SettingsSlider(
                label: "Scroll Action Threshold",
                value: $config.scrollActionThreshold,
                range: 1...10,
                step: 1,
                unit: ""
            )
        }
    }
}

// MARK: - Notch Settings Section

struct NotchSettingsSection: View {
    @ObservedObject var config: AegisConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionHeader(title: "Notch Layout", icon: "rectangle.topthird.inset")

            SettingsSlider(
                label: "Notch Width",
                value: $config.notchWidth,
                range: 150...300,
                step: 10,
                unit: "px"
            )

            SettingsSlider(
                label: "Notch Padding",
                value: $config.notchPadding,
                range: 10...40,
                step: 2,
                unit: "px"
            )

            SettingsDivider()

            SettingsSectionHeader(title: "HUD Dimensions", icon: "rectangle.inset.filled")

            SettingsSlider(
                label: "HUD Width",
                value: $config.notchHUDWidth,
                range: 40...100,
                step: 5,
                unit: "px"
            )

            SettingsSlider(
                label: "HUD Height",
                value: $config.notchHUDHeight,
                range: 40...100,
                step: 5,
                unit: "px"
            )

            SettingsDoubleSlider(
                label: "HUD Auto-Hide Delay",
                value: $config.notchHUDAutoHideDelay,
                range: 0.5...5.0,
                step: 0.1,
                unit: "s"
            )

            SettingsDivider()

            SettingsSectionHeader(title: "HUD Appearance", icon: "textformat.size")

            SettingsSlider(
                label: "HUD Icon Size",
                value: $config.notchHUDIconSize,
                range: 10...20,
                step: 1,
                unit: "pt"
            )

            SettingsSlider(
                label: "HUD Value Font Size",
                value: $config.notchHUDValueFontSize,
                range: 10...20,
                step: 1,
                unit: "pt"
            )

            SettingsSlider(
                label: "HUD Inner Padding",
                value: $config.notchHUDInnerPadding,
                range: 4...16,
                step: 1,
                unit: "px"
            )

            SettingsToggle(
                label: "Show HUD Background",
                description: "Display background behind HUD icons and values",
                isOn: $config.notchHUDShowBackground
            )

            SettingsToggle(
                label: "Use Progress Bar",
                description: "Show progress bar instead of numeric value for volume and brightness",
                isOn: $config.notchHUDUseProgressBar
            )

            if config.notchHUDUseProgressBar {
                SettingsSlider(
                    label: "Progress Bar Width",
                    value: $config.notchHUDProgressBarWidth,
                    range: 40...100,
                    step: 5,
                    unit: "px"
                )

                SettingsSlider(
                    label: "Progress Bar Height",
                    value: $config.notchHUDProgressBarHeight,
                    range: 2...8,
                    step: 1,
                    unit: "px"
                )
            }

            SettingsDivider()

            SettingsSectionHeader(title: "Music HUD", icon: "music.note")

            SettingsSlider(
                label: "Album Art Size",
                value: $config.albumArtSize,
                range: 30...60,
                step: 5,
                unit: "px"
            )

            SettingsIntSlider(
                label: "Visualizer Bar Count",
                value: $config.visualizerBarCount,
                range: 3...10,
                unit: ""
            )

            SettingsSlider(
                label: "Visualizer Bar Width",
                value: $config.visualizerBarWidth,
                range: 2...6,
                step: 1,
                unit: "px"
            )

            SettingsSlider(
                label: "Visualizer Min Height",
                value: $config.visualizerBarMinHeight,
                range: 3...10,
                step: 1,
                unit: "px"
            )

            SettingsSlider(
                label: "Visualizer Max Height",
                value: $config.visualizerBarMaxHeight,
                range: 15...40,
                step: 5,
                unit: "px"
            )
        }
    }
}

// MARK: - System Status Settings Section

struct SystemStatusSettingsSection: View {
    @ObservedObject var config: AegisConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionHeader(title: "Layout & Styling", icon: "square.grid.2x2")

            SettingsSlider(
                label: "Frame Height",
                value: $config.systemStatusFrameHeight,
                range: 16...28,
                step: 2,
                unit: "px"
            )

            SettingsSlider(
                label: "Icon Spacing",
                value: $config.systemIconSpacing,
                range: 8...20,
                step: 2,
                unit: "px"
            )

            SettingsSlider(
                label: "Icon Size",
                value: $config.systemIconSize,
                range: 12...18,
                step: 1,
                unit: "px"
            )

            SettingsDivider()

            SettingsSectionHeader(title: "Date Format", icon: "calendar")

            SettingsEnumPicker(
                label: "Date Display",
                selection: $config.dateFormat
            )

            SettingsDivider()

            SettingsSectionHeader(title: "WiFi Thresholds", icon: "wifi")

            SettingsDoubleSlider(
                label: "Strong Signal Threshold",
                value: $config.wifiStrongThreshold,
                range: 0.5...1.0,
                step: 0.01,
                unit: ""
            )

            SettingsDoubleSlider(
                label: "Medium Signal Threshold",
                value: $config.wifiMediumThreshold,
                range: 0.2...0.5,
                step: 0.01,
                unit: ""
            )

            SettingsDivider()

            SettingsSectionHeader(title: "Battery Thresholds", icon: "battery.100")

            SettingsDoubleSlider(
                label: "High Level Threshold",
                value: $config.batteryHighThreshold,
                range: 0.5...1.0,
                step: 0.01,
                unit: ""
            )

            SettingsDoubleSlider(
                label: "Medium Level Threshold",
                value: $config.batteryMediumThreshold,
                range: 0.3...0.7,
                step: 0.01,
                unit: ""
            )

            SettingsDoubleSlider(
                label: "Low Level Threshold",
                value: $config.batteryLowThreshold,
                range: 0.15...0.4,
                step: 0.01,
                unit: ""
            )

            SettingsDoubleSlider(
                label: "Critical Level Threshold",
                value: $config.batteryCriticalThreshold,
                range: 0.05...0.2,
                step: 0.01,
                unit: ""
            )
        }
    }
}

// MARK: - Dynamic Visuals Section

struct DynamicVisualsSection: View {
    @ObservedObject var config: AegisConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionHeader(title: "Background Opacity", icon: "square.3.layers.3d")

            Text("Space Indicators")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .padding(.top, 4)

            SettingsDoubleSlider(
                label: "Active State",
                value: $config.activeSpaceBgOpacity,
                range: 0.0...0.5,
                step: 0.01,
                unit: ""
            )

            SettingsDoubleSlider(
                label: "Hovered State",
                value: $config.hoveredSpaceBgOpacity,
                range: 0.0...0.5,
                step: 0.01,
                unit: ""
            )

            SettingsDoubleSlider(
                label: "Inactive State",
                value: $config.inactiveSpaceBgOpacity,
                range: 0.0...0.5,
                step: 0.01,
                unit: ""
            )

            Text("Buttons")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .padding(.top, 8)

            SettingsDoubleSlider(
                label: "Active State",
                value: $config.activeButtonBgOpacity,
                range: 0.0...0.5,
                step: 0.01,
                unit: ""
            )

            SettingsDoubleSlider(
                label: "Hovered State",
                value: $config.hoveredButtonBgOpacity,
                range: 0.0...0.5,
                step: 0.01,
                unit: ""
            )

            SettingsDoubleSlider(
                label: "Inactive State",
                value: $config.inactiveButtonBgOpacity,
                range: 0.0...0.5,
                step: 0.01,
                unit: ""
            )

            SettingsDivider()

            SettingsSectionHeader(title: "Text & Border Opacity", icon: "textformat")

            SettingsDoubleSlider(
                label: "Primary Text (Active)",
                value: $config.primaryTextOpacity,
                range: 0.5...1.0,
                step: 0.01,
                unit: ""
            )

            SettingsDoubleSlider(
                label: "Secondary Text (Titles)",
                value: $config.secondaryTextOpacity,
                range: 0.5...1.0,
                step: 0.01,
                unit: ""
            )

            SettingsDoubleSlider(
                label: "Tertiary Text (Inactive)",
                value: $config.tertiaryTextOpacity,
                range: 0.3...0.9,
                step: 0.01,
                unit: ""
            )

            SettingsDoubleSlider(
                label: "Active Border",
                value: $config.activeBorderOpacity,
                range: 0.1...0.5,
                step: 0.01,
                unit: ""
            )

            SettingsDivider()

            SettingsSectionHeader(title: "Hover & Glow Effects", icon: "sparkles")

            SettingsDoubleSlider(
                label: "Icon Hover Glow",
                value: $config.iconHoverGlowOpacity,
                range: 0.0...0.5,
                step: 0.01,
                unit: ""
            )

            SettingsDoubleSlider(
                label: "Icon Hover Background",
                value: $config.iconHoverBgOpacity,
                range: 0.0...0.5,
                step: 0.01,
                unit: ""
            )

            SettingsSlider(
                label: "Hovered Button Scale",
                value: $config.hoveredButtonScale,
                range: 1.0...1.1,
                step: 0.01,
                unit: "x"
            )

            SettingsDivider()

            SettingsSectionHeader(title: "Shadows", icon: "shadow")

            SettingsDoubleSlider(
                label: "Space Shadow Opacity",
                value: $config.spaceShadowOpacity,
                range: 0.0...0.3,
                step: 0.01,
                unit: ""
            )

            SettingsSlider(
                label: "Space Shadow Radius",
                value: $config.spaceShadowRadius,
                range: 0...10,
                step: 1,
                unit: "px"
            )
        }
    }
}

// MARK: - Animation Settings Section

struct AnimationSettingsSection: View {
    @ObservedObject var config: AegisConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionHeader(title: "Spring Animations", icon: "waveform")

            Text("Hover Effects")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .padding(.top, 4)

            SettingsDoubleSlider(
                label: "Response",
                value: $config.hoverAnimationResponse,
                range: 0.1...1.0,
                step: 0.05,
                unit: "s"
            )

            SettingsDoubleSlider(
                label: "Damping",
                value: $config.hoverAnimationDamping,
                range: 0.3...1.0,
                step: 0.05,
                unit: ""
            )

            Text("Expansion")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .padding(.top, 8)

            SettingsDoubleSlider(
                label: "Response",
                value: $config.expansionAnimationResponse,
                range: 0.1...1.0,
                step: 0.05,
                unit: "s"
            )

            SettingsDoubleSlider(
                label: "Damping",
                value: $config.expansionAnimationDamping,
                range: 0.3...1.0,
                step: 0.05,
                unit: ""
            )

            Text("Collapse")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .padding(.top, 8)

            SettingsDoubleSlider(
                label: "Response",
                value: $config.collapseAnimationResponse,
                range: 0.1...1.0,
                step: 0.05,
                unit: "s"
            )

            SettingsDoubleSlider(
                label: "Damping",
                value: $config.collapseAnimationDamping,
                range: 0.3...1.0,
                step: 0.05,
                unit: ""
            )

            SettingsDivider()

            SettingsSectionHeader(title: "Transition Durations", icon: "timer")

            SettingsDoubleSlider(
                label: "State Transitions",
                value: $config.stateTransitionDuration,
                range: 0.1...0.5,
                step: 0.05,
                unit: "s"
            )

            SettingsDoubleSlider(
                label: "Window Updates",
                value: $config.windowUpdateDuration,
                range: 0.1...0.5,
                step: 0.05,
                unit: "s"
            )

            SettingsDoubleSlider(
                label: "Auto-Scroll",
                value: $config.autoScrollDuration,
                range: 0.1...0.5,
                step: 0.05,
                unit: "s"
            )

            SettingsDoubleSlider(
                label: "Notch HUD Fade In",
                value: $config.notchHUDFadeInDuration,
                range: 0.1...0.5,
                step: 0.05,
                unit: "s"
            )

            SettingsDoubleSlider(
                label: "Notch HUD Fade Out",
                value: $config.notchHUDFadeOutDuration,
                range: 0.1...0.5,
                step: 0.05,
                unit: "s"
            )
        }
    }
}

// MARK: - Preview

#if DEBUG
struct SettingsPanelView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsPanelView()
            .frame(width: 600, height: 700)
    }
}
#endif
