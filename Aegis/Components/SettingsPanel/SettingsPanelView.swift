import SwiftUI

/// Main Settings Panel for configuring Aegis
/// Organized into 4 tabs: Features, Appearance, Behavior, Advanced
struct SettingsPanelView: View {
    @ObservedObject var config = AegisConfig.shared
    @ObservedObject var updater = UpdaterService.shared
    @Environment(\.presentationMode) var presentationMode
    @State private var selectedTab: SettingsTab = .features
    @State private var presetName: String = ""

    enum SettingsTab: String, CaseIterable {
        case features = "Features"
        case appearance = "Appearance"
        case behavior = "Behavior"
        case advanced = "Advanced"

        var icon: String {
            switch self {
            case .features: return "switch.2"
            case .appearance: return "paintbrush"
            case .behavior: return "gearshape"
            case .advanced: return "wrench.and.screwdriver"
            }
        }
    }

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

                // Tab Bar
                tabBar

                Divider()
                    .background(Color.white.opacity(0.15))

                // Content Area
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch selectedTab {
                        case .features:
                            featuresContent
                        case .appearance:
                            appearanceContent
                        case .behavior:
                            behaviorContent
                        case .advanced:
                            advancedContent
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

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Aegis Settings")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)

                Text("Changes are saved automatically")
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.6))
            }

            Spacer()

            Button(action: {
                presentationMode.wrappedValue.dismiss()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Color.white.opacity(0.6))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding()
        .background(Color.black.opacity(0.3))
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedTab = tab
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 12, weight: .medium))

                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(selectedTab == tab ? .white : Color.white.opacity(0.5))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        selectedTab == tab
                            ? Color.white.opacity(0.1)
                            : Color.clear
                    )
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())

                if tab != SettingsTab.allCases.last {
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.2))
    }

    // MARK: - Features Tab Content

    private var featuresContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // App Switcher
            SettingsToggle(
                label: "App Switcher",
                description: "Intercept Cmd+Tab to show custom switcher",
                isOn: $config.appSwitcherEnabled
            )

            Divider().background(Color.white.opacity(0.1))

            // Notch HUD
            SettingsSubsection(title: "Notch HUD") {
                SettingsToggle(
                    label: "Media (Now Playing)",
                    description: "Show Now Playing HUD when media is playing",
                    isOn: $config.showMediaHUD
                )

                SettingsToggle(
                    label: "Bluetooth Devices",
                    description: "Show HUD when devices connect/disconnect",
                    isOn: $config.showDeviceHUD
                )

                SettingsToggle(
                    label: "Focus Mode",
                    description: "Show HUD when Focus mode changes",
                    isOn: $config.showFocusHUD
                )

                SettingsToggle(
                    label: "Notifications",
                    description: "Intercept system notifications in notch area",
                    isOn: $config.showNotificationHUD
                )

                SettingsToggle(
                    label: "Volume/Brightness",
                    description: "Show HUD when adjusting (restores native if disabled)",
                    isOn: $config.showOverlayHUD
                )
            }

            Divider().background(Color.white.opacity(0.1))

            // Menu Bar
            SettingsSubsection(title: "Menu Bar") {
                SettingsToggle(
                    label: "Context Button",
                    description: "Show layout actions button (rotate, flip, balance)",
                    isOn: $config.showContextButton
                )

                SettingsToggle(
                    label: "Space Indicators",
                    description: "Show space indicator buttons (Yabai integration)",
                    isOn: $config.showSpaceIndicators
                )

                SettingsToggle(
                    label: "App Launcher",
                    description: "Show app launcher button",
                    isOn: $config.showAppLauncher
                )

                SettingsToggle(
                    label: "System Status",
                    description: "Show WiFi, time, battery, focus panel",
                    isOn: $config.showSystemStatus
                )
            }
        }
    }

    // MARK: - Appearance Tab Content

    private var appearanceContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsEnumPicker(
                label: "Theme",
                selection: $config.appTheme
            )

            Divider().background(Color.white.opacity(0.1))

            if config.appTheme == .custom {
                SettingsSubsection(title: "Custom Colors") {
                    SettingsColorPicker(
                        label: "Background",
                        hex: $config.customBackgroundColor
                    )
                    SettingsColorPicker(
                        label: "Text & Icons",
                        hex: $config.customTextColor
                    )
                    SettingsColorPicker(
                        label: "Borders",
                        hex: $config.customBorderColor
                    )

                    Divider().background(Color.white.opacity(0.1))

                    // Save current colors as preset
                    HStack {
                        TextField("Preset name", text: $presetName)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 160)
                        Button("Save") {
                            let preset = ColorPreset(
                                id: UUID(),
                                name: presetName,
                                backgroundColor: config.customBackgroundColor,
                                textColor: config.customTextColor,
                                borderColor: config.customBorderColor
                            )
                            config.colorPresets.append(preset)
                            presetName = ""
                        }
                        .disabled(presetName.isEmpty)
                        Spacer()
                    }

                    // Saved presets
                    if !config.colorPresets.isEmpty {
                        ForEach(config.colorPresets) { preset in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(hex: preset.backgroundColor ?? "") ?? .black)
                                    .frame(width: 10, height: 10)
                                Circle()
                                    .fill(Color(hex: preset.textColor ?? "") ?? .white)
                                    .frame(width: 10, height: 10)
                                Circle()
                                    .fill(Color(hex: preset.borderColor ?? "") ?? .gray)
                                    .frame(width: 10, height: 10)

                                Text(preset.name)
                                    .font(.system(size: 12))

                                Spacer()

                                Button("Apply") {
                                    config.customBackgroundColor = preset.backgroundColor
                                    config.customTextColor = preset.textColor
                                    config.customBorderColor = preset.borderColor
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11))

                                Button("Delete") {
                                    config.colorPresets.removeAll { $0.id == preset.id }
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.red.opacity(0.7))
                                .font(.system(size: 11))
                            }
                        }
                    }
                }
            }

            Divider().background(Color.white.opacity(0.1))

            SettingsEnumPicker(
                label: "Date Format",
                selection: $config.dateFormat
            )

            SettingsToggle(
                label: "Show Focus Name",
                description: "Display Focus mode name alongside icon",
                isOn: $config.showFocusName
            )

            Divider().background(Color.white.opacity(0.1))

            SettingsSubsection(title: "Space Background Opacity") {
                SettingsDoubleSlider(
                    label: "Active Space",
                    value: $config.activeSpaceBgOpacity,
                    range: 0.0...0.5,
                    step: 0.02,
                    unit: ""
                )

                SettingsDoubleSlider(
                    label: "Hovered Space",
                    value: $config.hoveredSpaceBgOpacity,
                    range: 0.0...0.5,
                    step: 0.02,
                    unit: ""
                )

                SettingsDoubleSlider(
                    label: "Inactive Space",
                    value: $config.inactiveSpaceBgOpacity,
                    range: 0.0...0.5,
                    step: 0.02,
                    unit: ""
                )
            }

            Divider().background(Color.white.opacity(0.1))

            SettingsSubsection(title: "Notch HUD") {
                SettingsToggle(
                    label: "Show Border",
                    description: "Display border outline around HUD panels",
                    isOn: $config.notchHUDShowBorder
                )
            }

            Divider().background(Color.white.opacity(0.1))

            SettingsSubsection(title: "Animation Timings") {
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
        }
    }

    // MARK: - Behavior Tab Content

    private var behaviorContent: some View {
        VStack(alignment: .leading, spacing: 16) {
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

            Divider().background(Color.white.opacity(0.1))

            // Multi-Monitor Settings
            SettingsMultiMonitorPicker(
                label: "Multi-Monitor Mode",
                description: "How Aegis displays across multiple monitors",
                selection: $config.multiMonitorMode
            )

            // App Switcher options
            if config.appSwitcherEnabled {
                Divider().background(Color.white.opacity(0.1))

                SettingsSubsection(title: "App Switcher") {
                    SettingsToggle(
                        label: "Cmd+Scroll to Open",
                        description: "Enable Cmd+scroll to open/cycle app switcher",
                        isOn: $config.appSwitcherCmdScrollEnabled
                    )

                    SettingsToggle(
                        label: "Show Minimized Windows",
                        description: "Include minimized windows in the switcher",
                        isOn: $config.appSwitcherShowMinimized
                    )

                    SettingsToggle(
                        label: "Show Hidden Windows",
                        description: "Include hidden app windows in the switcher",
                        isOn: $config.appSwitcherShowHidden
                    )
                }
            }

            // Space Indicators options
            if config.showSpaceIndicators {
                Divider().background(Color.white.opacity(0.1))

                SettingsSubsection(title: "Space Indicators") {
                    SettingsIntSlider(
                        label: "Max Icons Per Space",
                        value: $config.maxAppIconsPerSpace,
                        range: 1...10,
                        unit: ""
                    )

                    SettingsToggle(
                        label: "Show App Names",
                        description: "Display app names under window titles when expanded",
                        isOn: $config.showAppNameInExpansion
                    )

                    SettingsToggle(
                        label: "Auto-Expand Focused Window",
                        description: "Always show the focused window's title",
                        isOn: $config.autoExpandFocusedWindow
                    )

                    SettingsToggle(
                        label: "Swipe to Destroy Space",
                        description: "Enable swipe-up gesture to destroy spaces",
                        isOn: $config.useSwipeToDestroySpace
                    )

                    SettingsToggle(
                        label: "Expand Context on Scroll",
                        description: "Expand context button when scrolling over it",
                        isOn: $config.expandContextButtonOnScroll
                    )
                }
            }

            // Media HUD options
            if config.showMediaHUD {
                Divider().background(Color.white.opacity(0.1))

                SettingsSubsection(title: "Media HUD") {
                    SettingsEnumPicker(
                        label: "Right Panel Mode",
                        selection: $config.mediaHUDRightPanelMode
                    )

                    SettingsToggle(
                        label: "Enable Marquee",
                        description: "Scroll long track/artist names",
                        isOn: $config.mediaHUDEnableMarquee
                    )

                    SettingsToggle(
                        label: "Auto-Hide",
                        description: "Hide after showing track info",
                        isOn: $config.mediaHUDAutoHide
                    )
                }
            }

            // Notifications options
            if config.showNotificationHUD {
                Divider().background(Color.white.opacity(0.1))

                SettingsSubsection(title: "Notifications") {
                    SettingsToggle(
                        label: "Auto-Hide",
                        description: "Automatically hide notification HUD",
                        isOn: $config.notificationHUDAutoHide
                    )
                }
            }

            Divider().background(Color.white.opacity(0.1))

            // Auto-hide delays
            SettingsSubsection(title: "Auto-Hide Delays") {
                if config.showMediaHUD && config.mediaHUDAutoHide {
                    SettingsDoubleSlider(
                        label: "Media HUD",
                        value: $config.mediaHUDAutoHideDelay,
                        range: 1.0...10.0,
                        step: 0.5,
                        unit: "s"
                    )
                }

                if config.showDeviceHUD {
                    SettingsDoubleSlider(
                        label: "Device HUD",
                        value: $config.deviceHUDAutoHideDelay,
                        range: 1.0...10.0,
                        step: 0.5,
                        unit: "s"
                    )
                }

                if config.showFocusHUD {
                    SettingsDoubleSlider(
                        label: "Focus HUD",
                        value: $config.focusHUDAutoHideDelay,
                        range: 1.0...10.0,
                        step: 0.5,
                        unit: "s"
                    )
                }

                if config.showNotificationHUD && config.notificationHUDAutoHide {
                    SettingsDoubleSlider(
                        label: "Notification HUD",
                        value: $config.notificationHUDAutoHideDelay,
                        range: 2.0...15.0,
                        step: 1.0,
                        unit: "s"
                    )
                }

                if config.showOverlayHUD {
                    SettingsDoubleSlider(
                        label: "Volume/Brightness HUD",
                        value: $config.notchHUDAutoHideDelay,
                        range: 0.5...5.0,
                        step: 0.5,
                        unit: "s"
                    )
                }

                SettingsDoubleSlider(
                    label: "Window Expansion",
                    value: $config.windowIconExpansionAutoCollapseDelay,
                    range: 0.5...5.0,
                    step: 0.5,
                    unit: "s"
                )
            }

            Divider().background(Color.white.opacity(0.1))

            // Interaction thresholds
            SettingsSubsection(title: "Interaction Thresholds") {
                SettingsSlider(
                    label: "Drag Distance",
                    value: $config.dragDistanceThreshold,
                    range: 1...10,
                    step: 1,
                    unit: "px"
                )

                SettingsSlider(
                    label: "Swipe Destroy Distance",
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

    // MARK: - Advanced Tab Content

    private var advancedContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Config File")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)

                    Text("~/.config/aegis/config.json")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.5))
                }

                Spacer()

                Button("Open in Editor") {
                    let url = AegisConfig.configFilePath
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(SettingsButtonStyle())
            }

            Divider().background(Color.white.opacity(0.1))

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Documentation")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)

                    Text("CONFIG_OPTIONS.md")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.5))
                }

                Spacer()

                Button("View Docs") {
                    let docsURL = AegisConfig.configFilePath
                        .deletingLastPathComponent()
                        .appendingPathComponent("CONFIG_OPTIONS.md")
                    NSWorkspace.shared.open(docsURL)
                }
                .buttonStyle(SettingsButtonStyle())
            }

            Divider().background(Color.white.opacity(0.1))

            // Update button
            SettingsUpdateButton(updater: updater)

            Divider().background(Color.white.opacity(0.1))

            // Yabai Setup button
            SettingsYabaiSetupButton()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            SettingsActionButton(
                title: "Reset to Defaults",
                icon: "arrow.counterclockwise",
                destructive: true
            ) {
                config.resetToDefaults()
            }

            Spacer()

            Button("Done") {
                config.savePreferences()
                presentationMode.wrappedValue.dismiss()
            }
            .buttonStyle(SettingsPrimaryButtonStyle())
        }
        .padding()
        .background(Color.black.opacity(0.3))
    }
}

// MARK: - Settings Subsection

struct SettingsSubsection<Content: View>: View {
    let title: String
    let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.7))
                .textCase(.uppercase)
                .tracking(0.5)

            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .padding(.leading, 4)
        }
    }
}

// MARK: - Button Styles

struct SettingsButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(configuration.isPressed ? 0.15 : 0.1))
            .cornerRadius(6)
    }
}

struct SettingsPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color.blue.opacity(configuration.isPressed ? 0.7 : 1.0))
            .cornerRadius(8)
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
