import SwiftUI

/// Notch HUD settings tab: volume/brightness, media, bluetooth, focus, notifications, HUD layout
struct SettingsNotchHUDTab: View {
    @ObservedObject var config = AegisConfig.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Master Toggle
            SettingsToggle(
                label: "Notch HUD",
                description: "Master toggle for all notch HUD elements",
                isOn: $config.showNotchHUD
            )

            // Virtual Notch (for external monitors without a hardware notch)
            SettingsToggle(
                label: "Virtual Notch",
                description: "Draw a virtual notch on external monitors",
                isOn: $config.showVirtualNotch
            )

            if config.showVirtualNotch {
                SettingsSlider(label: "Virtual Notch Width", value: $config.virtualNotchWidth, range: 100...400, step: 10, unit: "px")
                SettingsSlider(label: "Virtual Notch Height", value: $config.virtualNotchHeight, range: 16...60, step: 2, unit: "px")
            }

            if config.showNotchHUD {
                Divider().background(SettingsPalette.separator.opacity(0.6))

                // Volume & Brightness
                SettingsSubsection(title: "Volume & Brightness") {
                    SettingsToggle(
                        label: "Volume/Brightness HUD",
                        description: "Show HUD when adjusting (restores native if disabled)",
                        isOn: $config.showOverlayHUD
                    )

                    if config.showOverlayHUD {
                        SettingsDoubleSlider(
                            label: "Auto-Hide Delay",
                            value: $config.notchHUDAutoHideDelay,
                            range: 0.5...5.0,
                            step: 0.5,
                            unit: "s"
                        )

                        SettingsToggle(
                            label: "Use Progress Bar",
                            description: "Show bar instead of numeric value",
                            isOn: $config.notchHUDUseProgressBar
                        )

                        if config.notchHUDUseProgressBar {
                            SettingsSlider(label: "Progress Bar Width", value: $config.notchHUDProgressBarWidth, range: 30...120, step: 5, unit: "px")
                            SettingsSlider(label: "Progress Bar Height", value: $config.notchHUDProgressBarHeight, range: 2...10, step: 1, unit: "px")
                        }
                    }
                }

                Divider().background(SettingsPalette.separator.opacity(0.6))

                // Media (Now Playing)
                SettingsSubsection(title: "Media (Now Playing)") {
                    SettingsToggle(
                        label: "Now Playing HUD",
                        description: "Show Now Playing HUD when media is playing",
                        isOn: $config.showMediaHUD
                    )

                    if config.showMediaHUD {
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
                }

                if config.showMediaHUD {
                    SettingsCollapsibleSection(title: "Fine Tuning: Media", icon: "music.note", initiallyExpanded: false) {
                        SettingsSlider(label: "Track Info Max Width", value: $config.mediaHUDTrackInfoMaxWidth, range: 100...400, step: 10, unit: "px")
                        SettingsSlider(label: "Album Art Size", value: $config.albumArtSize, range: 20...80, step: 5, unit: "px")
                        SettingsSlider(label: "Album Art Padding", value: $config.albumArtPadding, range: 0...20, step: 2, unit: "px")
                        SettingsSlider(label: "Media HUD V Padding", value: $config.mediaHUDVerticalPadding, range: 2...20, step: 1, unit: "px")

                        SettingsSectionHeader(title: "Visualizer", icon: "waveform")
                        SettingsIntSlider(label: "Bar Count", value: $config.visualizerBarCount, range: 1...12, unit: "")
                        SettingsSlider(label: "Bar Width", value: $config.visualizerBarWidth, range: 1...8, step: 1, unit: "px")
                        SettingsSlider(label: "Bar Spacing", value: $config.visualizerBarSpacing, range: 1...10, step: 1, unit: "px")
                        SettingsSlider(label: "Bar Min Height", value: $config.visualizerBarMinHeight, range: 1...10, step: 1, unit: "px")
                        SettingsSlider(label: "Bar Max Height", value: $config.visualizerBarMaxHeight, range: 10...40, step: 2, unit: "px")
                        SettingsSlider(label: "Visualizer Height", value: $config.visualizerHeight, range: 20...80, step: 5, unit: "px")
                        SettingsSlider(label: "Visualizer Padding", value: $config.visualizerPadding, range: 0...20, step: 2, unit: "px")
                        SettingsDoubleSlider(label: "Animation Duration", value: $config.visualizerAnimationDuration, range: 0.1...1.0, step: 0.05, unit: "s")
                        SettingsToggle(label: "Blur Effect", description: "Show wallpaper through bars (may impact performance)", isOn: $config.visualizerUseBlurEffect)
                    }
                }

                Divider().background(SettingsPalette.separator.opacity(0.6))

                // Bluetooth Devices
                SettingsSubsection(title: "Bluetooth Devices") {
                    SettingsToggle(
                        label: "Device Connection HUD",
                        description: "Show HUD when devices connect/disconnect",
                        isOn: $config.showDeviceHUD
                    )

                    if config.showDeviceHUD {
                        SettingsDoubleSlider(
                            label: "Auto-Hide Delay",
                            value: $config.deviceHUDAutoHideDelay,
                            range: 1.0...10.0,
                            step: 0.5,
                            unit: "s"
                        )

                        SettingsStringListEditor(
                            label: "Excluded Devices",
                            description: "Device names to ignore (case-insensitive substring match)",
                            items: $config.excludedBluetoothDevices,
                            placeholder: "Device name substring"
                        )
                    }
                }

                Divider().background(SettingsPalette.separator.opacity(0.6))

                // Focus Mode
                SettingsSubsection(title: "Focus Mode") {
                    SettingsToggle(
                        label: "Focus Mode HUD",
                        description: "Show HUD when Focus mode changes",
                        isOn: $config.showFocusHUD
                    )

                    if config.showFocusHUD {
                        SettingsDoubleSlider(
                            label: "Auto-Hide Delay",
                            value: $config.focusHUDAutoHideDelay,
                            range: 1.0...10.0,
                            step: 0.5,
                            unit: "s"
                        )
                    }
                }

                Divider().background(SettingsPalette.separator.opacity(0.6))

                // Notifications
                SettingsSubsection(title: "Notifications") {
                    SettingsToggle(
                        label: "Notification HUD",
                        description: "Intercept system notifications in notch area",
                        isOn: $config.showNotificationHUD
                    )

                    if config.showNotificationHUD {
                        SettingsToggle(
                            label: "Auto-Hide",
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

                        SettingsStringListEditor(
                            label: "Excluded Apps",
                            description: "Bundle IDs to ignore for notification HUD",
                            items: $config.notificationExcludedApps,
                            placeholder: "com.example.app"
                        )
                    }
                }

                Divider().background(SettingsPalette.separator.opacity(0.6))

                // Fine Tuning: HUD Layout
                SettingsCollapsibleSection(title: "Fine Tuning: HUD Layout", icon: "rectangle.center.inset.filled", initiallyExpanded: false) {
                    SettingsSlider(label: "Notch Width", value: $config.notchWidth, range: 100...400, step: 10, unit: "px")
                    SettingsSlider(label: "Notch Padding", value: $config.notchPadding, range: 0...40, step: 2, unit: "px")
                    SettingsSlider(label: "HUD Width", value: $config.notchHUDWidth, range: 30...100, step: 5, unit: "px")
                    SettingsSlider(label: "HUD Height", value: $config.notchHUDHeight, range: 30...100, step: 5, unit: "px")
                    SettingsSlider(label: "HUD Top Padding", value: $config.notchHUDTopPadding, range: 0...20, step: 1, unit: "px")
                    SettingsSlider(label: "HUD Inner Padding", value: $config.notchHUDInnerPadding, range: 2...20, step: 1, unit: "px")
                    SettingsSlider(label: "HUD Icon Size", value: $config.notchHUDIconSize, range: 10...30, step: 1, unit: "px")
                    SettingsSlider(label: "HUD Value Font", value: $config.notchHUDValueFontSize, range: 9...20, step: 1, unit: "pt")
                    SettingsSlider(label: "Minimal HUD V Padding", value: $config.minimalHUDVerticalPadding, range: 4...24, step: 1, unit: "px")
                    SettingsToggle(label: "Show HUD Background", isOn: $config.notchHUDShowBackground)
                    SettingsToggle(label: "Show HUD Border", description: "Display border outline around HUD panels", isOn: $config.notchHUDShowBorder)
                    SettingsDoubleSlider(label: "HUD Fade In", value: $config.notchHUDFadeInDuration, range: 0.1...0.5, step: 0.05, unit: "s")
                    SettingsDoubleSlider(label: "HUD Fade Out", value: $config.notchHUDFadeOutDuration, range: 0.1...0.5, step: 0.05, unit: "s")
                }
            }
        }
    }
}
