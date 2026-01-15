import SwiftUI

/// Main Settings Panel for configuring Aegis
/// Simplified view with essential settings and expandable Advanced section
struct SettingsPanelView: View {
    @ObservedObject var config = AegisConfig.shared
    @Environment(\.presentationMode) var presentationMode

    @State private var showAdvanced = false

    var body: some View {
        ZStack {
            // Background
            Color.black.opacity(0.95)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                header

                Divider()
                    .background(Color.white.opacity(0.2))

                // Content Area
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Essential Settings
                        essentialSettings

                        SettingsDivider()

                        // Advanced Section (Collapsible)
                        advancedSection
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

                Text("Customize appearance and behavior")
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

    private var essentialSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            // General
            SettingsSectionHeader(title: "General", icon: "gear")

            SettingsToggle(
                label: "Launch at Login",
                description: "Start Aegis automatically when macOS starts",
                isOn: $config.launchAtLogin
            )

            SettingsToggle(
                label: "Haptic Feedback",
                description: "Provide haptic feedback on layout actions",
                isOn: $config.enableLayoutActionHaptics
            )

            SettingsEnumPicker(
                label: "Date Format",
                selection: $config.dateFormat
            )

            SettingsDivider()

            // Appearance
            SettingsSectionHeader(title: "Appearance", icon: "paintbrush")

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
                label: "Album Art Size",
                value: $config.albumArtSize,
                range: 30...60,
                step: 5,
                unit: "px"
            )

            SettingsDivider()

            // Behavior
            SettingsSectionHeader(title: "Behavior", icon: "hand.tap")

            SettingsToggle(
                label: "Swipe to Destroy Space",
                description: "Enable swipe-up gesture to destroy spaces",
                isOn: $config.useSwipeToDestroySpace
            )

            SettingsToggle(
                label: "Show App Names",
                description: "Display app names under window titles when expanded",
                isOn: $config.showAppNameInExpansion
            )

            SettingsToggle(
                label: "Show Music HUD",
                description: "Show Now Playing HUD when music is playing",
                isOn: $config.showMusicHUD
            )

            SettingsToggle(
                label: "Use Progress Bar",
                description: "Show progress bar instead of numeric value for volume/brightness",
                isOn: $config.notchHUDUseProgressBar
            )

            SettingsDivider()

            // Timing
            SettingsSectionHeader(title: "Timing", icon: "clock")

            SettingsDoubleSlider(
                label: "HUD Auto-Hide Delay",
                value: $config.notchHUDAutoHideDelay,
                range: 0.5...5.0,
                step: 0.1,
                unit: "s"
            )

            SettingsDoubleSlider(
                label: "Window Expansion Auto-Collapse",
                value: $config.windowIconExpansionAutoCollapseDelay,
                range: 0.5...5.0,
                step: 0.1,
                unit: "s"
            )
        }
    }

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Advanced Header (Clickable)
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showAdvanced.toggle()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: showAdvanced ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))

                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.orange)

                    Text("Advanced Settings")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)

                    Spacer()

                    Text("\(showAdvanced ? "Hide" : "Show")")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            if showAdvanced {
                VStack(alignment: .leading, spacing: 8) {
                    // Layout & Dimensions
                    AdvancedSubsection(title: "Layout & Dimensions") {
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

                        SettingsSlider(
                            label: "Window Icon Frame Width",
                            value: $config.windowIconFrameWidth,
                            range: 16...32,
                            step: 2,
                            unit: "px"
                        )
                    }

                    // Typography
                    AdvancedSubsection(title: "Typography") {
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
                    }

                    // Corner Radii
                    AdvancedSubsection(title: "Corner Radii") {
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

                    // Notch HUD
                    AdvancedSubsection(title: "Notch HUD") {
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

                        SettingsSlider(
                            label: "HUD Icon Size",
                            value: $config.notchHUDIconSize,
                            range: 10...20,
                            step: 1,
                            unit: "pt"
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

                        SettingsToggle(
                            label: "Show HUD Background",
                            description: "Display background behind HUD icons",
                            isOn: $config.notchHUDShowBackground
                        )
                    }

                    // Music Visualizer
                    AdvancedSubsection(title: "Music Visualizer") {
                        SettingsIntSlider(
                            label: "Bar Count",
                            value: $config.visualizerBarCount,
                            range: 3...10,
                            unit: ""
                        )

                        SettingsSlider(
                            label: "Bar Width",
                            value: $config.visualizerBarWidth,
                            range: 2...6,
                            step: 1,
                            unit: "px"
                        )

                        SettingsSlider(
                            label: "Min Height",
                            value: $config.visualizerBarMinHeight,
                            range: 3...10,
                            step: 1,
                            unit: "px"
                        )

                        SettingsSlider(
                            label: "Max Height",
                            value: $config.visualizerBarMaxHeight,
                            range: 15...40,
                            step: 5,
                            unit: "px"
                        )
                    }

                    // System Status
                    AdvancedSubsection(title: "System Status") {
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
                    }

                    // Thresholds
                    AdvancedSubsection(title: "Battery & WiFi Thresholds") {
                        SettingsDoubleSlider(
                            label: "WiFi Strong",
                            value: $config.wifiStrongThreshold,
                            range: 0.5...1.0,
                            step: 0.01,
                            unit: ""
                        )

                        SettingsDoubleSlider(
                            label: "WiFi Medium",
                            value: $config.wifiMediumThreshold,
                            range: 0.2...0.5,
                            step: 0.01,
                            unit: ""
                        )

                        SettingsDoubleSlider(
                            label: "Battery High",
                            value: $config.batteryHighThreshold,
                            range: 0.5...1.0,
                            step: 0.01,
                            unit: ""
                        )

                        SettingsDoubleSlider(
                            label: "Battery Medium",
                            value: $config.batteryMediumThreshold,
                            range: 0.3...0.7,
                            step: 0.01,
                            unit: ""
                        )

                        SettingsDoubleSlider(
                            label: "Battery Low",
                            value: $config.batteryLowThreshold,
                            range: 0.15...0.4,
                            step: 0.01,
                            unit: ""
                        )

                        SettingsDoubleSlider(
                            label: "Battery Critical",
                            value: $config.batteryCriticalThreshold,
                            range: 0.05...0.2,
                            step: 0.01,
                            unit: ""
                        )
                    }

                    // Interaction Thresholds
                    AdvancedSubsection(title: "Interaction Thresholds") {
                        SettingsSlider(
                            label: "Drag Distance",
                            value: $config.dragDistanceThreshold,
                            range: 1...10,
                            step: 1,
                            unit: "px"
                        )

                        SettingsSlider(
                            label: "Swipe Destroy",
                            value: $config.swipeDestroyThreshold,
                            range: -200...(-50),
                            step: 10,
                            unit: "px"
                        )

                        SettingsSlider(
                            label: "Scroll Action",
                            value: $config.scrollActionThreshold,
                            range: 1...10,
                            step: 1,
                            unit: ""
                        )
                    }

                    // Background Opacity
                    AdvancedSubsection(title: "Background Opacity") {
                        SettingsDoubleSlider(
                            label: "Active Space",
                            value: $config.activeSpaceBgOpacity,
                            range: 0.0...0.5,
                            step: 0.01,
                            unit: ""
                        )

                        SettingsDoubleSlider(
                            label: "Hovered Space",
                            value: $config.hoveredSpaceBgOpacity,
                            range: 0.0...0.5,
                            step: 0.01,
                            unit: ""
                        )

                        SettingsDoubleSlider(
                            label: "Inactive Space",
                            value: $config.inactiveSpaceBgOpacity,
                            range: 0.0...0.5,
                            step: 0.01,
                            unit: ""
                        )
                    }

                    // Text Opacity
                    AdvancedSubsection(title: "Text Opacity") {
                        SettingsDoubleSlider(
                            label: "Primary Text",
                            value: $config.primaryTextOpacity,
                            range: 0.5...1.0,
                            step: 0.01,
                            unit: ""
                        )

                        SettingsDoubleSlider(
                            label: "Secondary Text",
                            value: $config.secondaryTextOpacity,
                            range: 0.5...1.0,
                            step: 0.01,
                            unit: ""
                        )

                        SettingsDoubleSlider(
                            label: "Tertiary Text",
                            value: $config.tertiaryTextOpacity,
                            range: 0.3...0.9,
                            step: 0.01,
                            unit: ""
                        )
                    }

                    // Animations
                    AdvancedSubsection(title: "Animation Timing") {
                        SettingsDoubleSlider(
                            label: "Hover Response",
                            value: $config.hoverAnimationResponse,
                            range: 0.1...1.0,
                            step: 0.05,
                            unit: "s"
                        )

                        SettingsDoubleSlider(
                            label: "Hover Damping",
                            value: $config.hoverAnimationDamping,
                            range: 0.3...1.0,
                            step: 0.05,
                            unit: ""
                        )

                        SettingsDoubleSlider(
                            label: "Expansion Response",
                            value: $config.expansionAnimationResponse,
                            range: 0.1...1.0,
                            step: 0.05,
                            unit: "s"
                        )

                        SettingsDoubleSlider(
                            label: "Expansion Damping",
                            value: $config.expansionAnimationDamping,
                            range: 0.3...1.0,
                            step: 0.05,
                            unit: ""
                        )

                        SettingsDoubleSlider(
                            label: "State Transition",
                            value: $config.stateTransitionDuration,
                            range: 0.1...0.5,
                            step: 0.05,
                            unit: "s"
                        )

                        SettingsDoubleSlider(
                            label: "HUD Fade In",
                            value: $config.notchHUDFadeInDuration,
                            range: 0.1...0.5,
                            step: 0.05,
                            unit: "s"
                        )

                        SettingsDoubleSlider(
                            label: "HUD Fade Out",
                            value: $config.notchHUDFadeOutDuration,
                            range: 0.1...0.5,
                            step: 0.05,
                            unit: "s"
                        )
                    }

                    // Shadows & Effects
                    AdvancedSubsection(title: "Shadows & Effects") {
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

                        SettingsSlider(
                            label: "Hovered Button Scale",
                            value: $config.hoveredButtonScale,
                            range: 1.0...1.1,
                            step: 0.01,
                            unit: "x"
                        )

                        SettingsDoubleSlider(
                            label: "Icon Hover Glow",
                            value: $config.iconHoverGlowOpacity,
                            range: 0.0...0.5,
                            step: 0.01,
                            unit: ""
                        )
                    }
                }
                .padding(.leading, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
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

// MARK: - Advanced Subsection

struct AdvancedSubsection<Content: View>: View {
    let title: String
    @State private var isExpanded: Bool = false
    let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))

                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))

                    Spacer()
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    content()
                }
                .padding(.leading, 16)
                .padding(.bottom, 8)
                .transition(.opacity)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct SettingsPanelView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsPanelView()
            .frame(width: 500, height: 700)
    }
}
#endif
