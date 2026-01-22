import SwiftUI

/// Main Settings Panel for configuring Aegis
/// Mirrors the options available in config.json
struct SettingsPanelView: View {
    @ObservedObject var config = AegisConfig.shared
    @ObservedObject var updater = UpdaterService.shared
    @Environment(\.presentationMode) var presentationMode

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
                    VStack(alignment: .leading, spacing: 16) {
                        // App Switcher
                        appSwitcherSection

                        // Notch HUD
                        notchHUDSection

                        // Menu Bar
                        menuBarSection

                        // System Status
                        systemStatusSection

                        // Behavior
                        behaviorSection

                        // Visual
                        visualSection

                        // Config File
                        configFileSection
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

    // MARK: - App Switcher Section

    private var appSwitcherSection: some View {
        SettingsSection(title: "App Switcher", icon: "rectangle.on.rectangle.angled") {
            SettingsToggle(
                label: "Enable App Switcher",
                description: "Intercept Cmd+Tab to show custom switcher",
                isOn: $config.appSwitcherEnabled
            )

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

    // MARK: - Notch HUD Section

    private var notchHUDSection: some View {
        SettingsSection(title: "Notch HUD", icon: "rectangle.topthird.inset.filled") {
            // Media
            SettingsSubsection(title: "Media (Now Playing)") {
                SettingsToggle(
                    label: "Show Media HUD",
                    description: "Show Now Playing HUD when media is playing",
                    isOn: $config.showMediaHUD
                )

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
                    label: "Auto-Hide Media HUD",
                    description: "Hide after showing track info",
                    isOn: $config.mediaHUDAutoHide
                )

                if config.mediaHUDAutoHide {
                    SettingsDoubleSlider(
                        label: "Auto-Hide Delay",
                        value: $config.mediaHUDAutoHideDelay,
                        range: 1.0...10.0,
                        step: 0.5,
                        unit: "s"
                    )
                }
            }

            // Bluetooth
            SettingsSubsection(title: "Bluetooth Devices") {
                SettingsToggle(
                    label: "Show Device HUD",
                    description: "Show HUD when Bluetooth devices connect/disconnect",
                    isOn: $config.showDeviceHUD
                )

                SettingsDoubleSlider(
                    label: "Auto-Hide Delay",
                    value: $config.deviceHUDAutoHideDelay,
                    range: 1.0...10.0,
                    step: 0.5,
                    unit: "s"
                )
            }

            // Focus Mode
            SettingsSubsection(title: "Focus Mode") {
                SettingsToggle(
                    label: "Show Focus HUD",
                    description: "Show HUD when Focus mode changes",
                    isOn: $config.showFocusHUD
                )

                SettingsDoubleSlider(
                    label: "Auto-Hide Delay",
                    value: $config.focusHUDAutoHideDelay,
                    range: 1.0...10.0,
                    step: 0.5,
                    unit: "s"
                )
            }

            // Notifications
            SettingsSubsection(title: "Notifications") {
                SettingsToggle(
                    label: "Show Notification HUD",
                    description: "Intercept system notifications in notch area",
                    isOn: $config.showNotificationHUD
                )

                SettingsToggle(
                    label: "Auto-Hide Notifications",
                    description: "Automatically hide notification HUD",
                    isOn: $config.notificationHUDAutoHide
                )

                if config.notificationHUDAutoHide {
                    SettingsDoubleSlider(
                        label: "Auto-Hide Delay",
                        value: $config.notificationHUDAutoHideDelay,
                        range: 2.0...15.0,
                        step: 1.0,
                        unit: "s"
                    )
                }
            }

            // Volume/Brightness
            SettingsSubsection(title: "Volume/Brightness") {
                SettingsDoubleSlider(
                    label: "Auto-Hide Delay",
                    value: $config.notchHUDAutoHideDelay,
                    range: 0.5...5.0,
                    step: 0.5,
                    unit: "s"
                )
            }
        }
    }

    // MARK: - Menu Bar Section

    private var menuBarSection: some View {
        SettingsSection(title: "Menu Bar", icon: "menubar.rectangle") {
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

    // MARK: - System Status Section

    private var systemStatusSection: some View {
        SettingsSection(title: "System Status", icon: "clock") {
            SettingsEnumPicker(
                label: "Date Format",
                selection: $config.dateFormat
            )

            SettingsToggle(
                label: "Show Focus Name",
                description: "Display Focus mode name alongside icon",
                isOn: $config.showFocusName
            )
        }
    }

    // MARK: - Behavior Section

    private var behaviorSection: some View {
        SettingsSection(title: "Behavior", icon: "gearshape") {
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

            SettingsDoubleSlider(
                label: "Window Expansion Collapse Delay",
                value: $config.windowIconExpansionAutoCollapseDelay,
                range: 0.5...5.0,
                step: 0.5,
                unit: "s"
            )

            // Thresholds subsection
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

    // MARK: - Visual Section

    private var visualSection: some View {
        SettingsSection(title: "Visual", icon: "paintbrush") {
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

    // MARK: - Config File Section

    private var configFileSection: some View {
        SettingsSection(title: "Configuration", icon: "doc.text") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Config File")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)

                    Text("~/.config/aegis/config.json")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                }

                Spacer()

                Button("Open in Editor") {
                    let url = AegisConfig.configFilePath
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(SettingsButtonStyle())
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Documentation")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)

                    Text("CONFIG_OPTIONS.md")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
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

            // Update button
            SettingsUpdateButton(updater: updater)

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

// MARK: - Settings Section

struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    let content: () -> Content

    init(title: String, icon: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section Header
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.blue)

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.bottom, 4)

            // Section Content
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(.leading, 4)

            Divider()
                .background(Color.white.opacity(0.1))
        }
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
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .padding(.leading, 8)
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
