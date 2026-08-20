import SwiftUI

/// Appearance settings tab: theme, colors, opacity, typography, corners, animations
struct SettingsAppearanceTab: View {
    @ObservedObject var config = AegisConfig.shared
    @State private var presetName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Theme
            SettingsEnumPicker(
                label: "Theme",
                selection: $config.appTheme
            )

            // Liquid Glass details
            if config.appTheme == .liquidGlass {
                HStack(spacing: 12) {
                    // Glassmorphic preview swatch
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.22), Color.white.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(stops: [
                                        .init(color: .white.opacity(0.35), location: 0),
                                        .init(color: .clear, location: 0.42)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.45), .white.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .frame(width: 52, height: 28)
                    .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Liquid Glass")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                        Text("macOS 26 Tahoe aesthetic — refractive blur with specular glass edges")
                            .font(.system(size: 10))
                            .foregroundColor(Color.white.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                        if #unavailable(macOS 26) {
                            Text("Uses ultraThinMaterial on your current macOS version")
                                .font(.system(size: 10))
                                .foregroundColor(Color.orange.opacity(0.8))
                        }
                    }
                }
                .padding(.vertical, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))

                SettingsSubsection(title: "Glass Intensity") {
                    SettingsDoubleSlider(
                        label: "Specular Highlight",
                        value: $config.liquidGlassSpecularOpacity,
                        range: 0.0...0.5,
                        step: 0.02,
                        unit: ""
                    )
                    SettingsDoubleSlider(
                        label: "Blur Opacity",
                        value: $config.liquidGlassBlurOpacity,
                        range: 0.3...1.0,
                        step: 0.05,
                        unit: ""
                    )
                }
            }

            Divider().background(Color.white.opacity(0.1))

            // Custom Colors
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

                Divider().background(Color.white.opacity(0.1))
            }

            // Opacity (hidden for Liquid Glass)
            if !config.isLiquidGlass {
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

                SettingsCollapsibleSection(title: "Button & Text Opacity", icon: "circle.lefthalf.filled", initiallyExpanded: false) {
                    SettingsDoubleSlider(label: "Active Button BG", value: $config.activeButtonBgOpacity, range: 0.0...0.5, step: 0.02, unit: "")
                    SettingsDoubleSlider(label: "Hovered Button BG", value: $config.hoveredButtonBgOpacity, range: 0.0...0.5, step: 0.02, unit: "")
                    SettingsDoubleSlider(label: "Inactive Button BG", value: $config.inactiveButtonBgOpacity, range: 0.0...0.5, step: 0.02, unit: "")
                    SettingsDoubleSlider(label: "Overflow Button BG", value: $config.overflowButtonBgOpacity, range: 0.0...0.5, step: 0.02, unit: "")
                    SettingsDoubleSlider(label: "Overflow Showing BG", value: $config.overflowMenuShowingBgOpacity, range: 0.0...0.5, step: 0.02, unit: "")
                    SettingsDoubleSlider(label: "Active Border", value: $config.activeBorderOpacity, range: 0.0...0.5, step: 0.02, unit: "")
                    SettingsDoubleSlider(label: "Primary Text", value: $config.primaryTextOpacity, range: 0.5...1.0, step: 0.05, unit: "")
                    SettingsDoubleSlider(label: "Secondary Text", value: $config.secondaryTextOpacity, range: 0.3...1.0, step: 0.05, unit: "")
                    SettingsDoubleSlider(label: "Tertiary Text", value: $config.tertiaryTextOpacity, range: 0.2...1.0, step: 0.05, unit: "")
                    SettingsDoubleSlider(label: "Icon Hover Glow", value: $config.iconHoverGlowOpacity, range: 0.0...0.5, step: 0.02, unit: "")
                    SettingsDoubleSlider(label: "Icon Hover BG", value: $config.iconHoverBgOpacity, range: 0.0...0.5, step: 0.02, unit: "")
                    SettingsDoubleSlider(label: "Backdrop Blur", value: $config.buttonBackdropBlurOpacity, range: 0.0...1.0, step: 0.05, unit: "")
                }

                Divider().background(Color.white.opacity(0.1))
            }

            // Fine Tuning sections
            SettingsCollapsibleSection(title: "Shadows", icon: "shadow", initiallyExpanded: false) {
                SettingsDoubleSlider(label: "Space Shadow Opacity", value: $config.spaceShadowOpacity, range: 0.0...0.5, step: 0.02, unit: "")
                SettingsSlider(label: "Space Shadow Radius", value: $config.spaceShadowRadius, range: 0...12, step: 1, unit: "px")
                SettingsSlider(label: "Status Shadow Radius", value: $config.systemStatusShadowRadius, range: 0...8, step: 1, unit: "px")
            }

            SettingsCollapsibleSection(title: "Scale Effects", icon: "arrow.up.left.and.arrow.down.right", initiallyExpanded: false) {
                SettingsSlider(label: "Hovered Button Scale", value: $config.hoveredButtonScale, range: 1.0...1.2, step: 0.01, unit: "x")
                SettingsSlider(label: "Hovered Icon Scale", value: $config.hoveredIconScale, range: 0.9...1.3, step: 0.05, unit: "x")
            }

            SettingsCollapsibleSection(title: "Typography", icon: "textformat.size", initiallyExpanded: false) {
                SettingsSlider(label: "Space Number", value: $config.spaceNumberFontSize, range: 8...20, step: 1, unit: "pt")
                SettingsSlider(label: "Window Title", value: $config.windowTitleFontSize, range: 8...16, step: 1, unit: "pt")
                SettingsSlider(label: "App Name", value: $config.appNameFontSize, range: 7...14, step: 1, unit: "pt")
                SettingsSlider(label: "Overflow Button", value: $config.overflowButtonFontSize, range: 7...14, step: 1, unit: "pt")
                SettingsSlider(label: "Stack Badge", value: $config.stackBadgeFontSize, range: 4...12, step: 1, unit: "pt")
            }

            SettingsCollapsibleSection(title: "Corner Radii", icon: "rectangle.roundedtop", initiallyExpanded: false) {
                SettingsSlider(label: "Space Indicator", value: $config.spaceIndicatorCornerRadius, range: 0...20, step: 1, unit: "px")
                SettingsSlider(label: "Overflow Button", value: $config.overflowButtonCornerRadius, range: 0...12, step: 1, unit: "px")
                SettingsSlider(label: "System Status", value: $config.systemStatusCornerRadius, range: 0...20, step: 1, unit: "px")
                SettingsSlider(label: "Layout Button", value: $config.layoutButtonCornerRadius, range: 0...20, step: 1, unit: "px")
            }

            SettingsCollapsibleSection(title: "Animations", icon: "wand.and.stars", initiallyExpanded: false) {
                SettingsSectionHeader(title: "Spring Animations")
                SettingsDoubleSlider(label: "Hover Response", value: $config.hoverAnimationResponse, range: 0.1...1.0, step: 0.05, unit: "s")
                SettingsDoubleSlider(label: "Hover Damping", value: $config.hoverAnimationDamping, range: 0.3...1.0, step: 0.05, unit: "")
                SettingsDoubleSlider(label: "Expansion Response", value: $config.expansionAnimationResponse, range: 0.1...1.0, step: 0.05, unit: "s")
                SettingsDoubleSlider(label: "Expansion Damping", value: $config.expansionAnimationDamping, range: 0.3...1.0, step: 0.05, unit: "")
                SettingsDoubleSlider(label: "Collapse Response", value: $config.collapseAnimationResponse, range: 0.1...1.0, step: 0.05, unit: "s")
                SettingsDoubleSlider(label: "Collapse Damping", value: $config.collapseAnimationDamping, range: 0.3...1.0, step: 0.05, unit: "")
                SettingsDoubleSlider(label: "Position Response", value: $config.positionUpdateResponse, range: 0.1...1.0, step: 0.05, unit: "s")
                SettingsDoubleSlider(label: "Position Damping", value: $config.positionUpdateDamping, range: 0.3...1.0, step: 0.05, unit: "")

                SettingsSectionHeader(title: "Durations")
                SettingsDoubleSlider(label: "State Transition", value: $config.stateTransitionDuration, range: 0.1...0.5, step: 0.05, unit: "s")
                SettingsDoubleSlider(label: "Window Update", value: $config.windowUpdateDuration, range: 0.05...0.5, step: 0.05, unit: "s")
                SettingsDoubleSlider(label: "Auto Scroll", value: $config.autoScrollDuration, range: 0.1...1.0, step: 0.05, unit: "s")
                SettingsDoubleSlider(label: "Fade Mask", value: $config.fadeMaskDuration, range: 0.05...0.5, step: 0.05, unit: "s")
                SettingsDoubleSlider(label: "Hover Effect", value: $config.hoverEffectDuration, range: 0.05...0.5, step: 0.05, unit: "s")
            }
        }
    }
}
