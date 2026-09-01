import SwiftUI

/// General settings tab: startup, window manager, app switcher, commands, desktop, updates
struct SettingsGeneralTab: View {
    @ObservedObject var config = AegisConfig.shared
    @ObservedObject var updater = UpdaterService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Startup & System
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

            Divider().background(SettingsPalette.separator.opacity(0.6))

            // Window Manager
            SettingsWindowManagerPicker(
                label: "Window Manager",
                description: "Which tiling window manager Aegis should connect to",
                selection: $config.windowManagerType
            )

            // WM Integration Setup
            switch config.activeWindowManagerName {
            case "AeroSpace":
                SettingsAeroSpaceSetupButton()
            case "Rift":
                SettingsWMInfoRow(wmName: "Rift")
            default:
                SettingsYabaiSetupButton()
            }

            Divider().background(SettingsPalette.separator.opacity(0.6))

            // Multi-Monitor
            SettingsMultiMonitorPicker(
                label: "Multi-Monitor Mode",
                description: "How Aegis displays across multiple monitors",
                selection: $config.multiMonitorMode
            )

            Divider().background(SettingsPalette.separator.opacity(0.6))

            // App Switcher
            SettingsToggle(
                label: "App Switcher",
                description: "Intercept Cmd+Tab to show custom switcher",
                isOn: $config.appSwitcherEnabled
            )

            if config.appSwitcherEnabled {
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

                    SettingsToggle(
                        label: "Window Previews",
                        description: "Show window thumbnails instead of app icons",
                        isOn: $config.appSwitcherShowPreviews
                    )
                }
            }

            Divider().background(SettingsPalette.separator.opacity(0.6))

            // Command Palette
            SettingsCustomCommandsEditor(
                label: "Command Palette",
                description: "Custom commands available via : prefix in the App Switcher",
                commands: $config.customCommands
            )

            Divider().background(SettingsPalette.separator.opacity(0.6))

            // Desktop
            SettingsSubsection(title: "Desktop") {
                SettingsToggle(
                    label: "Wallpaper Blur",
                    description: "Blur desktop wallpaper when windows are focused",
                    isOn: $config.enableWallpaperBlur
                )

                if config.enableWallpaperBlur {
                    SettingsDoubleSlider(
                        label: "Blur Intensity",
                        value: $config.wallpaperBlurIntensity,
                        range: 0.1...1.0,
                        step: 0.05,
                        unit: ""
                    )
                }
            }

            Divider().background(SettingsPalette.separator.opacity(0.6))

            // Updates & Config
            SettingsUpdateButton(updater: updater)

            Divider().background(SettingsPalette.separator.opacity(0.6))

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Config File")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(SettingsPalette.primaryText)

                    Text("~/.config/aegis/config.json")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(SettingsPalette.tertiaryText)
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
                        .foregroundColor(SettingsPalette.primaryText)

                    Text("CONFIG_OPTIONS.md")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(SettingsPalette.tertiaryText)
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
        }
    }
}
