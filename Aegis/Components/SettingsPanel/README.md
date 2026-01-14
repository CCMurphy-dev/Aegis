# Aegis Settings Panel

A comprehensive SwiftUI-based settings interface for customizing all aspects of the Aegis menu bar application.

## Overview

The Settings Panel provides a centralized, user-friendly interface for configuring 130+ parameters that control Aegis's appearance, behavior, and animations. All settings are live-updating and persist across app launches using UserDefaults.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Settings Panel UI                         │
│  (SettingsPanelView.swift + SettingsHelpers.swift)          │
└────────────────────┬────────────────────────────────────────┘
                     │ @ObservedObject binding
                     ▼
┌─────────────────────────────────────────────────────────────┐
│                    AegisConfig.shared                        │
│              (130+ @Published properties)                    │
└────────────┬──────────────────────────────┬─────────────────┘
             │                              │
             │ Read values                  │ Save/Load
             ▼                              ▼
┌──────────────────────────┐    ┌─────────────────────────────┐
│   UI Components          │    │      UserDefaults           │
│  (MenuBar, Notch, etc.)  │    │   (Persistent Storage)      │
└──────────────────────────┘    └─────────────────────────────┘
```

## Components

### 1. AegisConfig.swift

**Location**: `/Core/Config/AegisConfig.swift`

Central configuration singleton containing all Aegis settings organized into 18 logical sections:

- **Menu Bar Layout**: Heights, padding, spacing, button dimensions
- **Space Indicator Dimensions**: Icon sizes, badge sizes, frames
- **Spacing & Padding**: Internal component spacing
- **Typography**: Font sizes for all text elements
- **Corner Radii**: Border radius for all components
- **Colors - Background Opacity**: Dynamic state opacity values
- **Colors - Borders**: Border opacity
- **Colors - Text & Icons**: Text hierarchy opacity
- **Colors - Hover & Glow**: Interactive effect opacity
- **Colors - Shadows**: Shadow properties
- **Behavior Flags**: Feature toggles
- **Auto-Hide & Delays**: Timing parameters
- **Interaction Thresholds**: Gesture sensitivity
- **Animation Settings - Spring**: Spring animation parameters
- **Animation Settings - Durations**: Transition durations
- **Dynamic Visuals - Scale**: Scale effects
- **Notch Settings**: Notch HUD and music visualizer
- **SystemStatus Settings**: System status thresholds and format

**Key Features**:
- All properties are `@Published` for live SwiftUI updates
- Computed color properties for convenience (e.g., `activeSpaceColor`)
- Full persistence via `savePreferences()`, `loadPreferences()`, and `resetToDefaults()`

**Usage Example**:
```swift
// Access config anywhere in the app
let config = AegisConfig.shared

// Use config values
let height = config.menuBarHeight
let color = config.activeSpaceColor

// Update values (automatically persists when using Settings Panel)
config.menuBarHeight = 45
```

### 2. SettingsHelpers.swift

**Location**: `/UI/SettingsPanel/SettingsHelpers.swift`

Reusable SwiftUI components for building consistent settings UI:

#### SettingsSlider
For adjusting CGFloat values with a labeled slider.

```swift
SettingsSlider(
    label: "Menu Bar Height",
    value: $config.menuBarHeight,
    range: 30...60,
    step: 1,
    unit: "px"
)
```

#### SettingsDoubleSlider
For adjusting Double values with custom precision.

```swift
SettingsDoubleSlider(
    label: "Hover Opacity",
    value: $config.hoveredSpaceBgOpacity,
    range: 0.0...1.0,
    step: 0.01,
    unit: "",
    precision: "%.2f"
)
```

#### SettingsIntSlider
For adjusting Int values.

```swift
SettingsIntSlider(
    label: "Max Icons Per Space",
    value: $config.maxAppIconsPerSpace,
    range: 1...10,
    unit: ""
)
```

#### SettingsToggle
For boolean settings with optional description.

```swift
SettingsToggle(
    label: "Enable Haptics",
    description: "Provide haptic feedback on actions",
    isOn: $config.enableLayoutActionHaptics
)
```

#### SettingsSectionHeader
For grouping settings with an icon.

```swift
SettingsSectionHeader(title: "Layout & Dimensions", icon: "rectangle.3.group")
```

#### SettingsDivider
Visual separator between sections.

```swift
SettingsDivider()
```

#### SettingsEnumPicker
For selecting from enum options.

```swift
SettingsEnumPicker(
    label: "Date Format",
    selection: $config.dateFormat
)
```

#### SettingsInfoText
Display read-only information.

```swift
SettingsInfoText(label: "Version", value: "1.0.1")
```

#### SettingsActionButton
For triggering actions like save/reset.

```swift
SettingsActionButton(
    title: "Reset to Defaults",
    icon: "arrow.counterclockwise",
    destructive: true
) {
    config.resetToDefaults()
}
```

#### SettingsCollapsibleSection
Expandable/collapsible sections for organizing many settings.

```swift
SettingsCollapsibleSection(title: "Advanced", icon: "gearshape.2") {
    // Your settings content here
}
```

### 3. SettingsPanelView.swift

**Location**: `/UI/SettingsPanel/SettingsPanelView.swift`

Main Settings Panel interface with tabbed navigation and 6 comprehensive sections:

#### Tabs:
1. **UI**: Layout dimensions, typography, corner radii
2. **Menu Bar**: Space indicators, behavior flags, delays, thresholds
3. **Notch**: Notch layout, HUD dimensions, music visualizer
4. **System**: System status layout, date format, WiFi/battery thresholds
5. **Visuals**: All opacity values for dynamic states (active, hovered, inactive)
6. **Animation**: Spring parameters and transition durations

**Structure**:
```swift
struct SettingsPanelView: View {
    @ObservedObject var config = AegisConfig.shared
    @State private var selectedTab: SettingsTab = .ui

    var body: some View {
        // Header with title and close button
        // Tab bar for navigation
        // Scrollable content area with section views
        // Footer with Save and Reset buttons
    }
}
```

### 4. SettingsPanelController.swift

**Location**: `/UI/SettingsPanel/SettingsPanelController.swift`

Singleton controller for managing the Settings Panel window.

**Usage**:
```swift
// Show settings panel
SettingsPanelController.shared.showSettings()

// Hide settings panel
SettingsPanelController.shared.hideSettings()

// Toggle settings panel
SettingsPanelController.shared.toggleSettings()
```

**Features**:
- Creates NSWindow with floating level
- Manages window lifecycle (create once, show/hide as needed)
- Brings window to front if already open
- Sets appropriate window styling and size constraints

## Integration

### Context Menu Integration

The Settings Panel is integrated into the Aegis context menu (right-click on the layout actions button):

**Location**: `/Components/MenuBar/Controllers/MenuBarController.swift`

```swift
// In showContextMenu() method (line ~613):
menu.addItem(NSMenuItem(title: "Settings...", action: #selector(LayoutActionsMenuTarget.openSettings), keyEquivalent: ","))

// In LayoutActionsMenuTarget class (line ~742):
@objc func openSettings() {
    print("⚙️ Opening Settings Panel...")
    SettingsPanelController.shared.showSettings()
}
```

The "Settings..." menu item appears between the Status section and System Actions section, with keyboard shortcut ⌘,

### Updating Components to Use Config

To update existing components to read from AegisConfig instead of hardcoded values:

**Before**:
```swift
.frame(height: 40)  // Hardcoded
.opacity(0.2)       // Hardcoded
```

**After**:
```swift
let config = AegisConfig.shared

.frame(height: config.menuBarHeight)
.opacity(config.activeSpaceBgOpacity)
```

**For SwiftUI Views** (recommended):
```swift
struct MyView: View {
    @ObservedObject var config = AegisConfig.shared

    var body: some View {
        Rectangle()
            .frame(height: config.menuBarHeight)  // Auto-updates when config changes
    }
}
```

**For AppKit/UIKit** (if needed):
```swift
class MyController {
    private let config = AegisConfig.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Observe config changes
        config.$menuBarHeight
            .sink { [weak self] newHeight in
                self?.updateLayout(height: newHeight)
            }
            .store(in: &cancellables)
    }
}
```

## Persistence

All settings automatically persist to UserDefaults:

- **Saved**: When "Save Changes" button is clicked in Settings Panel
- **Loaded**: Automatically on app launch via `AegisConfig.init()`
- **Reset**: When "Reset to Defaults" button is clicked

**Manual Persistence** (if needed):
```swift
// Save current config
AegisConfig.shared.savePreferences()

// Load from UserDefaults
AegisConfig.shared.loadPreferences()

// Reset to factory defaults
AegisConfig.shared.resetToDefaults()
```

**UserDefaults Keys**: All settings are stored with the prefix `"aegis."`, for example:
- `aegis.menuBarHeight`
- `aegis.activeSpaceBgOpacity`
- `aegis.spaceNumberFontSize`

## Customization

### Adding New Settings

To add a new setting:

1. **Add property to AegisConfig.swift**:
```swift
@Published var myNewSetting: CGFloat = 10.0
```

2. **Add persistence in savePreferences()**:
```swift
UserDefaults.standard.set(myNewSetting, forKey: "aegis.myNewSetting")
```

3. **Add loading in loadPreferences()**:
```swift
myNewSetting = UserDefaults.standard.object(forKey: "aegis.myNewSetting") as? CGFloat ?? 10.0
```

4. **Add reset in resetToDefaults()**:
```swift
myNewSetting = 10.0
```

5. **Add UI control in appropriate section view** (e.g., UISettingsSection):
```swift
SettingsSlider(
    label: "My New Setting",
    value: $config.myNewSetting,
    range: 5...20,
    step: 1,
    unit: "px"
)
```

### Creating Custom Section Views

To add a new settings section:

1. **Add tab to SettingsTab enum**:
```swift
enum SettingsTab: String, CaseIterable {
    case ui = "UI"
    case myNewSection = "My Section"
    // ...
}
```

2. **Create section view struct**:
```swift
struct MyNewSettingsSection: View {
    @ObservedObject var config: AegisConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionHeader(title: "My Group", icon: "star")

            SettingsSlider(
                label: "Some Value",
                value: $config.someValue,
                range: 0...100,
                step: 1,
                unit: "units"
            )
        }
    }
}
```

3. **Add to switch statement in SettingsPanelView**:
```swift
switch selectedTab {
case .ui:
    UISettingsSection(config: config)
case .myNewSection:
    MyNewSettingsSection(config: config)
// ...
}
```

## Testing

### Manual Testing Checklist

- [ ] Open Settings Panel from context menu (right-click button → Settings...)
- [ ] Navigate through all 6 tabs
- [ ] Adjust various sliders and verify value updates
- [ ] Toggle boolean settings
- [ ] Change enum selections (e.g., date format)
- [ ] Click "Reset to Defaults" and verify values reset
- [ ] Modify settings and verify they persist after app restart
- [ ] Verify live updates (changes immediately affect UI without restart)
- [ ] Test keyboard shortcut (⌘,) to open Settings
- [ ] Test window minimize/restore
- [ ] Verify window maintains position between opens

### Validation

To verify all settings are properly bound:

1. Open Settings Panel
2. Note current value of a setting
3. Change the value using the slider/toggle
4. Observe the main UI to confirm immediate visual update
5. Click "Save Changes"
6. Restart Aegis
7. Open Settings Panel again
8. Verify the value persisted

## Performance Considerations

- **@Published properties**: Each property triggers updates to observers when changed
- **Live updates**: Changes in Settings Panel immediately affect all views observing `AegisConfig.shared`
- **Persistence**: Only save to UserDefaults when "Save Changes" is clicked (not on every change)
- **Memory**: Single shared instance keeps memory footprint minimal

## Design Patterns Used

1. **Singleton Pattern**: `AegisConfig.shared` and `SettingsPanelController.shared`
2. **Observer Pattern**: `@Published` properties with `@ObservedObject` bindings
3. **Component Library**: Reusable UI components in SettingsHelpers.swift
4. **Separation of Concerns**: Config, UI, and persistence are cleanly separated
5. **Type Safety**: Custom slider components for CGFloat, Double, and Int
6. **Declarative UI**: SwiftUI for maintainable, reactive interface

## Future Enhancements

Potential improvements for future versions:

- [ ] Search/filter functionality across all settings
- [ ] Import/Export settings profiles (JSON)
- [ ] Preset themes (Dark, Light, High Contrast, etc.)
- [ ] Settings validation (prevent invalid value combinations)
- [ ] Keyboard shortcuts for common settings
- [ ] Undo/Redo for setting changes
- [ ] Settings backup/restore
- [ ] Cloud sync via iCloud
- [ ] Settings comparison (diff between current and default)
- [ ] Context-sensitive help/tooltips for each setting

## Troubleshooting

### Settings Not Persisting

**Problem**: Changes don't persist after restart.

**Solution**: Ensure you click "Save Changes" before closing Settings Panel or quitting Aegis.

### Settings Not Updating UI

**Problem**: UI doesn't update when settings change.

**Solution**: Ensure components use `@ObservedObject var config = AegisConfig.shared` instead of creating new instances.

### Window Won't Open

**Problem**: Settings Panel doesn't appear when clicking menu item.

**Solution**: Check console for errors. Verify SettingsPanelController.swift is included in Xcode target.

### Values Reset on Launch

**Problem**: Settings reset to defaults every time app launches.

**Solution**: Check UserDefaults permissions. Ensure `loadPreferences()` is called in `AegisConfig.init()`.

## File Summary

```
UI/SettingsPanel/
├── README.md                      # This documentation
├── SettingsPanelController.swift  # Window management
├── SettingsPanelView.swift        # Main UI with 6 section views
└── SettingsHelpers.swift          # Reusable UI components

Core/Config/
└── AegisConfig.swift              # Central config singleton (130+ settings)

Components/MenuBar/Controllers/
└── MenuBarController.swift        # Context menu integration
```

## Version History

**v1.0.1** (2026-01-13):
- Initial Settings Panel implementation
- 130+ configurable parameters
- 6 organized sections with tabbed navigation
- Full persistence via UserDefaults
- Context menu integration
- Live-updating UI
- Comprehensive reusable component library

---

For questions or issues, please refer to the main Aegis repository.
