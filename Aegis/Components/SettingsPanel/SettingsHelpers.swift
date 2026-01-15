import SwiftUI

// MARK: - Reusable Settings UI Components

/// Labeled slider for adjusting CGFloat values
struct SettingsSlider: View {
    let label: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    let step: CGFloat
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
                Text("\(value, specifier: "%.1f")\(unit)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(minWidth: 50, alignment: .trailing)
            }

            Slider(value: $value, in: range, step: step)
                .accentColor(.blue)
        }
        .padding(.vertical, 4)
    }
}

/// Labeled slider for adjusting Double values
struct SettingsDoubleSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let precision: String

    init(label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double = 0.01, unit: String = "", precision: String = "%.2f") {
        self.label = label
        self._value = value
        self.range = range
        self.step = step
        self.unit = unit
        self.precision = precision
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
                Text("\(value, specifier: precision)\(unit)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(minWidth: 50, alignment: .trailing)
            }

            Slider(value: $value, in: range, step: step)
                .accentColor(.blue)
        }
        .padding(.vertical, 4)
    }
}

/// Labeled slider for adjusting Int values
struct SettingsIntSlider: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
                Text("\(value)\(unit)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(minWidth: 50, alignment: .trailing)
            }

            Slider(value: Binding(
                get: { Double(value) },
                set: { value = Int($0) }
            ), in: Double(range.lowerBound)...Double(range.upperBound), step: 1.0)
                .accentColor(.blue)
        }
        .padding(.vertical, 4)
    }
}

/// Labeled toggle switch for boolean settings
struct SettingsToggle: View {
    let label: String
    let description: String?
    @Binding var isOn: Bool

    init(label: String, description: String? = nil, isOn: Binding<Bool>) {
        self.label = label
        self.description = description
        self._isOn = isOn
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.9))

                    if let description = description {
                        Text(description)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }

                Spacer()

                Toggle("", isOn: $isOn)
                    .toggleStyle(SwitchToggleStyle(tint: .blue))
                    .labelsHidden()
            }
        }
        .padding(.vertical, 4)
    }
}

/// Section header for grouping settings
struct SettingsSectionHeader: View {
    let title: String
    let icon: String?

    init(title: String, icon: String? = nil) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 8) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.blue)
            }

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            Spacer()
        }
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
}

/// Divider for separating sections
struct SettingsDivider: View {
    var body: some View {
        Divider()
            .background(Color.white.opacity(0.2))
            .padding(.vertical, 8)
    }
}

/// Picker for enum selections
struct SettingsEnumPicker<T: RawRepresentable & CaseIterable & Hashable>: View where T.RawValue == String {
    let label: String
    @Binding var selection: T

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.9))

            Picker("", selection: $selection) {
                ForEach(Array(T.allCases), id: \.self) { option in
                    Text(option.rawValue.capitalized)
                        .tag(option)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
        }
        .padding(.vertical, 4)
    }
}

/// Info text for displaying read-only information
struct SettingsInfoText: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.7))
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(.vertical, 4)
    }
}

/// Action button for triggering functions
struct SettingsActionButton: View {
    let title: String
    let icon: String?
    let action: () -> Void
    let destructive: Bool

    init(title: String, icon: String? = nil, destructive: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.destructive = destructive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                }
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(destructive ? .red : .blue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(destructive ? Color.red.opacity(0.1) : Color.blue.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(destructive ? Color.red.opacity(0.3) : Color.blue.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.vertical, 4)
    }
}

/// Update button for checking for app updates via Sparkle
struct SettingsUpdateButton: View {
    @ObservedObject var updater: UpdaterService

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Check for Updates")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.9))

                Text("Current version: v\(updater.currentVersion)")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()

            Button(action: {
                updater.checkForUpdates()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .medium))
                    Text("Check Now")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.blue.opacity(0.15))
                )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!updater.canCheckForUpdates)
            .opacity(updater.canCheckForUpdates ? 1.0 : 0.5)
        }
        .padding(.vertical, 4)
    }
}

/// Collapsible section container
struct SettingsCollapsibleSection<Content: View>: View {
    let title: String
    let icon: String?
    @State private var isExpanded: Bool = true
    let content: () -> Content

    init(title: String, icon: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))

                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.blue)
                    }

                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))

                    Spacer()
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            if isExpanded {
                content()
                    .padding(.leading, 20)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Preview Helpers

#if DEBUG
struct SettingsHelpers_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsSectionHeader(title: "Sample Section", icon: "gear")

                    SettingsSlider(
                        label: "Menu Bar Height",
                        value: .constant(40),
                        range: 30...60,
                        step: 1,
                        unit: "px"
                    )

                    SettingsDoubleSlider(
                        label: "Hover Opacity",
                        value: .constant(0.15),
                        range: 0.0...1.0,
                        step: 0.01,
                        unit: ""
                    )

                    SettingsIntSlider(
                        label: "Max Icons",
                        value: .constant(3),
                        range: 1...10,
                        unit: ""
                    )

                    SettingsToggle(
                        label: "Enable Haptics",
                        description: "Provide haptic feedback on actions",
                        isOn: .constant(true)
                    )

                    SettingsDivider()

                    SettingsInfoText(label: "Version", value: "1.0.1")

                    SettingsActionButton(
                        title: "Reset to Defaults",
                        icon: "arrow.counterclockwise",
                        destructive: true,
                        action: {}
                    )
                }
                .padding()
            }
        }
        .frame(width: 400, height: 600)
    }
}
#endif
