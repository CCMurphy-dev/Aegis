import SwiftUI

/// Menu Bar settings tab: components, space indicators, system status, launcher, interaction
struct SettingsMenuBarTab: View {
    @ObservedObject var config = AegisConfig.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Component Toggles
            SettingsSubsection(title: "Components") {
                SettingsToggle(
                    label: "Context Button",
                    description: "Show layout actions button (rotate, flip, balance)",
                    isOn: $config.showContextButton
                )

                SettingsToggle(
                    label: "Menu-Only Context Button",
                    description: "Open the full context menu on click instead of cycling actions",
                    isOn: $config.contextButtonMenuOnly
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

            // Space Indicators
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

                    SettingsWorkspaceLabelStylePicker(
                        label: "Workspace Labels",
                        selection: $config.workspaceLabelStyle
                    )

                    SettingsStringDictionaryEditor(
                        label: "Workspace Label Overrides",
                        description: "Optional labels keyed by the original workspace label (for example, 0 → Flow)",
                        items: $config.workspaceLabelOverrides
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

                    SettingsDoubleSlider(
                        label: "Window Expansion Auto-Hide",
                        value: $config.windowIconExpansionAutoCollapseDelay,
                        range: 0.5...5.0,
                        step: 0.5,
                        unit: "s"
                    )

                    SettingsStringSetEditor(
                        label: "Excluded Apps",
                        description: "Apps hidden from space indicators (by name)",
                        items: $config.baseExcludedApps,
                        placeholder: "App name (e.g. Finder)"
                    )
                }

                SettingsCollapsibleSection(title: "Fine Tuning: Space Indicators", icon: "square.grid.3x1.below.line.grid.1x2", initiallyExpanded: false) {
                    SettingsSlider(label: "Circle Size", value: $config.spaceCircleSize, range: 20...50, step: 2, unit: "px")
                    SettingsSlider(label: "Indicator Spacing", value: $config.spaceIndicatorSpacing, range: 2...20, step: 1, unit: "px")
                    SettingsSlider(label: "App Icon Size", value: $config.appIconSize, range: 16...40, step: 2, unit: "px")
                    SettingsSlider(label: "App Icon Spacing", value: $config.appIconSpacing, range: 0...12, step: 1, unit: "px")
                    SettingsSlider(label: "Window Icon Width", value: $config.windowIconFrameWidth, range: 14...40, step: 2, unit: "px")
                    SettingsSlider(label: "Window Icon Height", value: $config.windowIconFrameHeight, range: 14...40, step: 2, unit: "px")
                    SettingsSlider(label: "Max Expanded Width", value: $config.maxExpandedWidth, range: 60...200, step: 10, unit: "px")
                    SettingsSlider(label: "Content Spacing", value: $config.spaceContentSpacing, range: 2...16, step: 1, unit: "px")
                    SettingsSlider(label: "H Padding", value: $config.spaceIndicatorHorizontalPadding, range: 2...20, step: 1, unit: "px")
                    SettingsSlider(label: "V Padding", value: $config.spaceIndicatorVerticalPadding, range: 2...16, step: 1, unit: "px")
                    SettingsSlider(label: "Stack Badge Size", value: $config.stackBadgeSize, range: 6...20, step: 1, unit: "px")
                    SettingsSlider(label: "Focus Dot Size", value: $config.focusDotSize, range: 2...8, step: 1, unit: "px")
                    SettingsSlider(label: "Overflow Button Size", value: $config.overflowButtonSize, range: 14...30, step: 1, unit: "px")
                    SettingsSlider(label: "Drop Zone H Padding", value: $config.dropZoneHorizontalPadding, range: 0...16, step: 1, unit: "px")
                    SettingsSlider(label: "Drop Zone V Padding", value: $config.dropZoneVerticalPadding, range: 0...20, step: 1, unit: "px")
                }
            }

            // System Status
            if config.showSystemStatus {
                Divider().background(Color.white.opacity(0.1))

                SettingsSubsection(title: "System Status") {
                    SettingsToggle(
                        label: "CPU Monitor",
                        description: "Show CPU usage in system status",
                        isOn: $config.showCPUMonitor
                    )

                    SettingsToggle(
                        label: "RAM Monitor",
                        description: "Show RAM usage in system status",
                        isOn: $config.showRAMMonitor
                    )

                    if config.showCPUMonitor || config.showRAMMonitor {
                        SettingsEnumPicker(
                            label: "Monitor Style",
                            selection: $config.monitorDisplayStyle
                        )
                    }

                    SettingsOrderEditor(
                        label: "Status Bar Order",
                        description: "Drag to reorder, hide items you don't need",
                        items: $config.systemStatusOrder,
                        allOptions: ["focus", "cpu", "ram", "wifi", "clock", "date", "battery"]
                    )

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

                SettingsCollapsibleSection(title: "Fine Tuning: System Status", icon: "menubar.rectangle", initiallyExpanded: false) {
                    SettingsSlider(label: "System Icon Size", value: $config.systemIconSize, range: 10...22, step: 1, unit: "px")
                    SettingsSlider(label: "System Icon Spacing", value: $config.systemIconSpacing, range: 4...24, step: 1, unit: "px")
                    SettingsSlider(label: "Frame Height", value: $config.systemStatusFrameHeight, range: 14...30, step: 1, unit: "px")
                    SettingsSlider(label: "H Padding", value: $config.systemStatusHorizontalPadding, range: 2...16, step: 1, unit: "px")
                    SettingsSlider(label: "System Status Font", value: $config.systemStatusFontSize, range: 9...18, step: 1, unit: "pt")
                    SettingsDoubleSlider(label: "CPU Update Interval", value: $config.cpuUpdateInterval, range: 0.5...10.0, step: 0.5, unit: "s")
                    SettingsIntSlider(label: "CPU Sample Count", value: $config.cpuSampleCount, range: 5...60, unit: "")
                    SettingsDoubleSlider(label: "Battery High", value: $config.batteryHighThreshold, range: 0.5...1.0, step: 0.05, unit: "")
                    SettingsDoubleSlider(label: "Battery Medium", value: $config.batteryMediumThreshold, range: 0.25...0.75, step: 0.05, unit: "")
                    SettingsDoubleSlider(label: "Battery Low", value: $config.batteryLowThreshold, range: 0.1...0.5, step: 0.05, unit: "")
                    SettingsDoubleSlider(label: "Battery Critical", value: $config.batteryCriticalThreshold, range: 0.05...0.25, step: 0.05, unit: "")
                    SettingsDoubleSlider(label: "WiFi Strong", value: $config.wifiStrongThreshold, range: 0.5...1.0, step: 0.05, unit: "")
                    SettingsDoubleSlider(label: "WiFi Medium", value: $config.wifiMediumThreshold, range: 0.1...0.66, step: 0.05, unit: "")
                }
            }

            // App Launcher
            if config.showAppLauncher {
                Divider().background(Color.white.opacity(0.1))

                SettingsSubsection(title: "App Launcher") {
                    SettingsStringListEditor(
                        label: "Launcher Apps",
                        description: "Bundle identifiers for the app launcher (scroll to select)",
                        items: $config.launcherApps,
                        placeholder: "com.example.app"
                    )
                }
            }

            Divider().background(Color.white.opacity(0.1))

            // Scroll & Interaction
            SettingsSubsection(title: "Scroll & Interaction") {
                SettingsToggle(
                    label: "Notched Scrolling",
                    description: "Full reset after each step (vs. continuous smooth scrolling)",
                    isOn: $config.scrollNotchedBehavior
                )

                SettingsSlider(
                    label: "Scroll Action Threshold",
                    value: $config.scrollActionThreshold,
                    range: 1...10,
                    step: 1,
                    unit: ""
                )

                SettingsDoubleSlider(
                    label: "Action Label Auto-Hide",
                    value: $config.actionLabelAutoHideDelay,
                    range: 0.5...5.0,
                    step: 0.5,
                    unit: "s"
                )

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
            }

            SettingsCollapsibleSection(title: "Fine Tuning: Menu Bar Layout", icon: "rectangle.topthird.inset.filled", initiallyExpanded: false) {
                SettingsSlider(label: "Menu Bar Height", value: $config.menuBarHeight, range: 24...60, step: 1, unit: "px")
                SettingsSlider(label: "Edge Padding", value: $config.menuBarEdgePadding, range: 0...100, step: 5, unit: "px")
                SettingsSlider(label: "Layout Button Width", value: $config.layoutButtonWidth, range: 20...60, step: 2, unit: "px")
                SettingsSlider(label: "Button Label Width", value: $config.buttonLabelExpandedWidth, range: 60...150, step: 5, unit: "px")
                SettingsSlider(label: "System Status Width", value: $config.systemStatusWidth, range: 80...300, step: 10, unit: "px")
            }
        }
    }
}
