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
                    .foregroundColor(Color.white.opacity(0.9))
                Spacer()
                Text("\(value, specifier: "%.1f")\(unit)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.7))
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
                    .foregroundColor(Color.white.opacity(0.9))
                Spacer()
                Text("\(value, specifier: precision)\(unit)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.7))
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
                    .foregroundColor(Color.white.opacity(0.9))
                Spacer()
                Text("\(value)\(unit)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.7))
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
                        .foregroundColor(Color.white.opacity(0.9))

                    if let description = description {
                        Text(description)
                            .font(.system(size: 10))
                            .foregroundColor(Color.white.opacity(0.6))
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
                .foregroundColor(Color.white.opacity(0.9))

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

struct SettingsAppSwitcherKeyboardModePicker: View {
    let label: String
    @Binding var selection: AppSwitcherKeyboardMode

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(Color.white.opacity(0.9))

            Picker("", selection: $selection) {
                ForEach(AppSwitcherKeyboardMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
        }
        .padding(.vertical, 4)
    }
}
/// Picker specifically for MultiMonitorMode with proper display names
struct SettingsMultiMonitorPicker: View {
    let label: String
    let description: String?
    @Binding var selection: AegisConfig.MultiMonitorMode

    init(label: String, description: String? = nil, selection: Binding<AegisConfig.MultiMonitorMode>) {
        self.label = label
        self.description = description
        self._selection = selection
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.9))

                if let description = description {
                    Text(description)
                        .font(.system(size: 10))
                        .foregroundColor(Color.white.opacity(0.6))
                }
            }

            Picker("", selection: $selection) {
                ForEach(AegisConfig.MultiMonitorMode.allCases, id: \.self) { mode in
                    Text(mode.displayName)
                        .tag(mode)
                }
            }
            .pickerStyle(SegmentedPickerStyle())

            // Show description of selected mode
            Text(selection.description)
                .font(.system(size: 10))
                .foregroundColor(Color.white.opacity(0.5))
                .italic()
        }
        .padding(.vertical, 4)
    }
}

/// Picker for selecting which window manager to use
struct SettingsWindowManagerPicker: View {
    let label: String
    let description: String?
    @Binding var selection: WindowManagerType

    init(label: String, description: String? = nil, selection: Binding<WindowManagerType>) {
        self.label = label
        self.description = description
        self._selection = selection
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.9))

                if let description = description {
                    Text(description)
                        .font(.system(size: 10))
                        .foregroundColor(Color.white.opacity(0.6))
                }
            }

            Picker("", selection: $selection) {
                ForEach(WindowManagerType.allCases, id: \.self) { type in
                    Text(type.displayName)
                        .tag(type)
                }
            }
            .pickerStyle(SegmentedPickerStyle())

            Text(selection.description)
                .font(.system(size: 10))
                .foregroundColor(Color.white.opacity(0.5))
                .italic()

            Text("Requires restart to take effect")
                .font(.system(size: 9))
                .foregroundColor(Color.orange.opacity(0.7))
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
                .foregroundColor(Color.white.opacity(0.7))
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color.white.opacity(0.9))
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
                    .foregroundColor(Color.white.opacity(0.9))

                Text("Current version: v\(updater.currentVersion)")
                    .font(.system(size: 10))
                    .foregroundColor(Color.white.opacity(0.6))
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

/// Yabai setup button for running/re-running yabai integration setup
struct SettingsYabaiSetupButton: View {
    @State private var setupStatus: YabaiSetupChecker.SetupStatus = .ready

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Yabai Integration")
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.9))

                Text(statusText)
                    .font(.system(size: 10))
                    .foregroundColor(statusColor)
            }

            Spacer()

            Button(action: {
                showSetupWindow()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: setupStatus == .ready ? "checkmark.circle" : "wrench.and.screwdriver")
                        .font(.system(size: 11, weight: .medium))
                    Text(setupStatus == .ready ? "Configured" : "Run Setup")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(setupStatus == .ready ? .green : .orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(setupStatus == .ready ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 4)
        .onAppear {
            setupStatus = YabaiSetupChecker.check()
        }
    }

    private var statusText: String {
        switch setupStatus {
        case .ready:
            return "FIFO pipe integration is active"
        case .yabaiNotInstalled:
            return "Yabai not installed"
        case .notifyScriptMissing:
            return "Setup script not installed"
        case .signalsNotConfigured:
            return "Yabai signals not configured"
        }
    }

    private var statusColor: Color {
        setupStatus == .ready ? .green.opacity(0.8) : .orange.opacity(0.8)
    }

    private func showSetupWindow() {
        // Get the app delegate to show the setup window
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.showSetupWindow(status: setupStatus)
        }
    }
}

/// Simple info row for WMs that don't need a setup flow (e.g. Rift)
struct SettingsWMInfoRow: View {
    let wmName: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(wmName) Integration")
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.9))

                Text("Connected via event subscription")
                    .font(.system(size: 10))
                    .foregroundColor(.green.opacity(0.8))
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 11, weight: .medium))
                Text("Active")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.green)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.green.opacity(0.15))
            )
        }
        .padding(.vertical, 4)
    }
}

/// AeroSpace setup button for running/re-running AeroSpace integration setup
struct SettingsAeroSpaceSetupButton: View {
    @State private var setupStatus: AeroSpaceSetupChecker.SetupStatus = .configNotSetUp

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("AeroSpace Integration")
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.9))

                Text(statusText)
                    .font(.system(size: 10))
                    .foregroundColor(statusColor)
            }

            Spacer()

            Button(action: {
                showSetupWindow()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: setupStatus == .ready ? "checkmark.circle" : "wrench.and.screwdriver")
                        .font(.system(size: 11, weight: .medium))
                    Text(setupStatus == .ready ? "Configured" : "Run Setup")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(setupStatus == .ready ? .green : .orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(setupStatus == .ready ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 4)
        .onAppear {
            setupStatus = AeroSpaceSetupChecker.check()
        }
    }

    private var statusText: String {
        switch setupStatus {
        case .ready:
            return "FIFO pipe integration is active"
        case .aeroSpaceNotInstalled:
            return "AeroSpace not installed"
        case .notifyScriptMissing:
            return "Setup script not installed"
        case .configNotSetUp:
            return "Config not set up"
        }
    }

    private var statusColor: Color {
        setupStatus == .ready ? .green.opacity(0.8) : .orange.opacity(0.8)
    }

    private func showSetupWindow() {
        // Clear dismissed flag so auto-check resumes working after manual re-setup
        UserDefaults.standard.removeObject(forKey: "aegis.aerospace.setup.dismissed")
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.showAeroSpaceSetupWindow(status: setupStatus)
        }
    }
}

/// Collapsible section container
struct SettingsCollapsibleSection<Content: View>: View {
    let title: String
    let icon: String?
    @State private var isExpanded: Bool
    let content: () -> Content

    init(title: String, icon: String? = nil, initiallyExpanded: Bool = true, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self._isExpanded = State(initialValue: initiallyExpanded)
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
                        .foregroundColor(Color.white.opacity(0.7))

                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.blue)
                    }

                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.9))

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

/// Editable list of strings with add/remove (for excludedApps, launcherApps, etc.)
struct SettingsStringListEditor: View {
    let label: String
    let description: String?
    @Binding var items: [String]
    let placeholder: String

    @State private var newItem: String = ""

    init(label: String, description: String? = nil, items: Binding<[String]>, placeholder: String = "Add item...") {
        self.label = label
        self.description = description
        self._items = items
        self.placeholder = placeholder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.9))

                if let description = description {
                    Text(description)
                        .font(.system(size: 10))
                        .foregroundColor(Color.white.opacity(0.6))
                }
            }

            // Existing items
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 6) {
                    Text(item)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.8))
                        .lineLimit(1)

                    Spacer()

                    Button(action: {
                        items.remove(at: index)
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Color.red.opacity(0.6))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.05))
                .cornerRadius(4)
            }

            // Add new item
            HStack(spacing: 6) {
                TextField(placeholder, text: $newItem)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .onSubmit { addItem() }

                Button("Add") { addItem() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.blue)
                    .disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.vertical, 4)
    }

    private func addItem() {
        let trimmed = newItem.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        items.append(trimmed)
        newItem = ""
    }
}

/// Editable list for Set<String> (wraps to array binding)
struct SettingsStringSetEditor: View {
    let label: String
    let description: String?
    @Binding var items: Set<String>
    let placeholder: String

    init(label: String, description: String? = nil, items: Binding<Set<String>>, placeholder: String = "Add item...") {
        self.label = label
        self.description = description
        self._items = items
        self.placeholder = placeholder
    }

    var body: some View {
        SettingsStringListEditor(
            label: label,
            description: description,
            items: Binding(
                get: { Array(items).sorted() },
                set: { items = Set($0) }
            ),
            placeholder: placeholder
        )
    }
}

/// Reorderable list for system status order
struct SettingsOrderEditor: View {
    let label: String
    let description: String?
    @Binding var items: [String]
    let allOptions: [String]

    init(label: String, description: String? = nil, items: Binding<[String]>, allOptions: [String]) {
        self.label = label
        self.description = description
        self._items = items
        self.allOptions = allOptions
    }

    private let displayNames: [String: String] = [
        "focus": "Focus Mode",
        "cpu": "CPU Monitor",
        "ram": "RAM Monitor",
        "wifi": "WiFi",
        "clock": "Clock",
        "date": "Date",
        "battery": "Battery"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.9))

                if let description = description {
                    Text(description)
                        .font(.system(size: 10))
                        .foregroundColor(Color.white.opacity(0.6))
                }
            }

            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 8) {
                    // Move buttons
                    VStack(spacing: 0) {
                        Button(action: { moveUp(index) }) {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(index > 0 ? Color.white.opacity(0.6) : Color.white.opacity(0.2))
                        .disabled(index == 0)

                        Button(action: { moveDown(index) }) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(index < items.count - 1 ? Color.white.opacity(0.6) : Color.white.opacity(0.2))
                        .disabled(index >= items.count - 1)
                    }

                    Text(displayNames[item] ?? item.capitalized)
                        .font(.system(size: 11))
                        .foregroundColor(Color.white.opacity(0.8))

                    Spacer()

                    Button(action: { items.remove(at: index) }) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 10))
                            .foregroundColor(Color.white.opacity(0.4))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.05))
                .cornerRadius(4)
            }

            // Show hidden items that can be re-added
            let hidden = allOptions.filter { !items.contains($0) }
            if !hidden.isEmpty {
                HStack(spacing: 4) {
                    Text("Hidden:")
                        .font(.system(size: 10))
                        .foregroundColor(Color.white.opacity(0.4))

                    ForEach(hidden, id: \.self) { item in
                        Button(action: { items.append(item) }) {
                            Text(displayNames[item] ?? item.capitalized)
                                .font(.system(size: 10))
                                .foregroundColor(.blue.opacity(0.8))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(3)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func moveUp(_ index: Int) {
        guard index > 0 else { return }
        items.swapAt(index, index - 1)
    }

    private func moveDown(_ index: Int) {
        guard index < items.count - 1 else { return }
        items.swapAt(index, index + 1)
    }
}

// MARK: - Custom Commands Editor

/// Editor for custom command palette commands (array of [String: String] dicts)
struct SettingsCustomCommandsEditor: View {
    let label: String
    let description: String?
    @Binding var commands: [[String: String]]

    @State private var isAdding = false
    @State private var editingIndex: Int? = nil
    @State private var editLabel = ""
    @State private var editCommand = ""
    @State private var editIcon = ""
    @State private var editDescription = ""

    init(label: String, description: String? = nil, commands: Binding<[[String: String]]>) {
        self.label = label
        self.description = description
        self._commands = commands
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.9))

                if let description = description {
                    Text(description)
                        .font(.system(size: 10))
                        .foregroundColor(Color.white.opacity(0.6))
                }
            }

            // Existing commands
            ForEach(Array(commands.enumerated()), id: \.offset) { index, cmd in
                HStack(spacing: 8) {
                    if let iconName = cmd["icon"], !iconName.isEmpty {
                        Image(systemName: iconName)
                            .font(.system(size: 11))
                            .foregroundColor(Color.white.opacity(0.7))
                            .frame(width: 16)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(cmd["label"] ?? "")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.9))
                        Text(cmd["command"] ?? "")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color.white.opacity(0.5))
                            .lineLimit(1)
                    }

                    Spacer()

                    Button(action: { startEditing(index) }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                            .foregroundColor(Color.white.opacity(0.5))
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button(action: { commands.remove(at: index) }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Color.red.opacity(0.6))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.05))
                .cornerRadius(4)
            }

            // Add/Edit form
            if isAdding || editingIndex != nil {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Label")
                            .font(.system(size: 10))
                            .foregroundColor(Color.white.opacity(0.6))
                            .frame(width: 60, alignment: .trailing)
                        TextField("e.g. Restart Yabai", text: $editLabel)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11))
                    }
                    HStack(spacing: 6) {
                        Text("Command")
                            .font(.system(size: 10))
                            .foregroundColor(Color.white.opacity(0.6))
                            .frame(width: 60, alignment: .trailing)
                        TextField("e.g. yabai --restart-service", text: $editCommand)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                    }
                    HStack(spacing: 6) {
                        Text("Icon")
                            .font(.system(size: 10))
                            .foregroundColor(Color.white.opacity(0.6))
                            .frame(width: 60, alignment: .trailing)
                        TextField("SF Symbol (optional)", text: $editIcon)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11))
                    }
                    HStack(spacing: 6) {
                        Text("Description")
                            .font(.system(size: 10))
                            .foregroundColor(Color.white.opacity(0.6))
                            .frame(width: 60, alignment: .trailing)
                        TextField("Optional", text: $editDescription)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11))
                    }

                    HStack {
                        Spacer()
                        Button("Cancel") { cancelEdit() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundColor(Color.white.opacity(0.6))
                        Button(editingIndex != nil ? "Update" : "Add") { saveCommand() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.blue)
                            .disabled(editLabel.trimmingCharacters(in: .whitespaces).isEmpty || editCommand.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(8)
                .background(Color.white.opacity(0.03))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
            } else {
                Button(action: { isAdding = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 11))
                        Text("Add Command")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.blue.opacity(0.8))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.vertical, 4)
    }

    private func startEditing(_ index: Int) {
        let cmd = commands[index]
        editLabel = cmd["label"] ?? ""
        editCommand = cmd["command"] ?? ""
        editIcon = cmd["icon"] ?? ""
        editDescription = cmd["description"] ?? ""
        editingIndex = index
        isAdding = false
    }

    private func cancelEdit() {
        isAdding = false
        editingIndex = nil
        clearFields()
    }

    private func saveCommand() {
        var cmd: [String: String] = [
            "label": editLabel.trimmingCharacters(in: .whitespaces),
            "command": editCommand.trimmingCharacters(in: .whitespaces)
        ]
        let icon = editIcon.trimmingCharacters(in: .whitespaces)
        if !icon.isEmpty { cmd["icon"] = icon }
        let desc = editDescription.trimmingCharacters(in: .whitespaces)
        if !desc.isEmpty { cmd["description"] = desc }

        if let index = editingIndex {
            commands[index] = cmd
        } else {
            commands.append(cmd)
        }
        cancelEdit()
    }

    private func clearFields() {
        editLabel = ""
        editCommand = ""
        editIcon = ""
        editDescription = ""
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

/// Color picker with optional hex binding and reset button
struct SettingsColorPicker: View {
    let label: String
    @Binding var hex: String?

    @State private var hexText: String = ""

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 100, alignment: .leading)

            // Color preview swatch
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: hexText) ?? .clear)
                .frame(width: 24, height: 24)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )

            // Hex input field
            TextField("#RRGGBB", text: $hexText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
                .font(.system(size: 12, design: .monospaced))
                .onSubmit {
                    applyHex()
                }

            if hexText != (hex ?? "") && !hexText.isEmpty {
                Button("Apply") {
                    applyHex()
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .font(.system(size: 11))
            }

            if hex != nil {
                Button("Reset") {
                    hex = nil
                    hexText = ""
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .font(.system(size: 11))
            }

            Spacer()
        }
        .onAppear {
            hexText = hex ?? ""
        }
        .onChange(of: hex) { newHex in
            hexText = newHex ?? ""
        }
    }

    private func applyHex() {
        let cleaned = hexText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            hex = nil
            return
        }
        let withHash = cleaned.hasPrefix("#") ? cleaned : "#\(cleaned)"
        if Color(hex: withHash) != nil {
            hexText = withHash
            hex = withHash
        }
    }
}
