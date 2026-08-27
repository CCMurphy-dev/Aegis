# Aegis Feature Summary

**A macOS menu bar replacement for Yabai window manager**

---

## Core Features

### 1. Space Indicators
Visual workspace display showing which apps are on each space.

- **Window icons** for each space (configurable max before overflow)
- **Click** to switch spaces
- **Drag windows** between spaces
- **Scroll** to navigate when spaces exceed screen width
- **Swipe up** to destroy a space
- **Right-click** window icon to expand and show window title
- **Focus dot** indicates the currently focused window

### 2. Context Button
Shows the currently focused window with quick actions.

- Displays **focused app icon and window title**
- **Scroll** to cycle through layout actions:
  - Stack all windows
  - Float window
  - Toggle fullscreen
  - Split layouts
- **Expands on hover** to show full title

By default, left-click executes the selected layout action and scrolling cycles through actions. Right-click opens the full context menu. With `contextButtonMenuOnly` enabled, both clicks open the menu, scrolling is ignored, and the button shows `≡ Menu`.

### 3. App Launcher
Quick-access button for floating utility apps.

- **Scroll** to cycle through configured apps
- **Click** to toggle app (focus existing window or launch)
- **Right-click** for dropdown menu:
  - Shows all apps with icons
  - "Add App..." to add via file picker
  - "Remove App" submenu
- Launched apps **float and center** (50% screen size)
- Configuration persists across restarts

### 4. Notch HUD
The MacBook notch becomes a heads-up display.

| HUD Type | Trigger | Display |
|----------|---------|---------|
| **Volume** | Volume keys | Icon + progress bar |
| **Brightness** | Brightness keys | Icon + progress bar |
| **Media** | Music plays | Album art + visualizer/track info |
| **Bluetooth** | Device connects | Device icon + name + battery |
| **Focus Mode** | Focus changes | Focus icon + mode name |
| **Notifications** | App notification | App icon + title + body |

**Media HUD modes** (tap album art to switch):
- Visualizer: Animated bars
- Track Info: Song title + artist (marquee scrolls if long)

**Notification HUD**: Click to focus the source app.

### 5. App Switcher
Custom Cmd+Tab replacement with window previews.

- **Cmd+Tab** to open, release to confirm
- **Arrow keys** to navigate
- **Mouse hover** to select
- **Two-finger scroll** to cycle
- **Cmd+scroll** to activate (optional, disabled by default)
- Shows window previews with app icons
- Groups windows by space

### 6. System Status
Right side of menu bar shows system state.

- **Battery**: Level, charging indicator, turns red at ≤10%
- **WiFi**: Connection status icon
- **Focus Mode**: Shows icon when Focus is active
- **Clock**: Current time
- **Date**: Day and date (long or short format)

### 7. Multi-Display Support
Automatic menu bar management across multiple monitors.

- **Auto-detection** of display connect/disconnect via CoreGraphics callbacks
- **Configurable modes**:
  - **Auto**: Single monitor = primary only, multiple = per monitor
  - **Primary Only**: Menu bar only on main display
  - **Per Monitor**: Each display shows only its own spaces
  - **All Show All**: Every display shows all spaces
- **Per-display space filtering** based on Yabai display-space mapping
- **Instant updates** when monitors are connected or disconnected

---

## Architecture Overview

### Event-Driven Design
```
┌─────────────────┐     ┌─────────────┐     ┌──────────────┐
│   Services      │────▶│ EventRouter │────▶│     UI       │
│ (Yabai, System) │     │  (Pub/Sub)  │     │ (SwiftUI)    │
└─────────────────┘     └─────────────┘     └──────────────┘
```

Services detect changes and publish events. UI subscribes and reacts. No polling, no tight coupling.

### Key Components

| Component | Role |
|-----------|------|
| **YabaiService** | Monitors FIFO pipe for Yabai events, executes commands |
| **SystemInfoService** | Tracks volume/brightness via CoreAudio callbacks |
| **MediaService** | Streams now-playing data from mediaremote-adapter |
| **BluetoothDeviceService** | Monitors IOBluetooth for device connections |
| **NotificationService** | Intercepts notifications via Accessibility API |
| **FocusStatusMonitor** | Watches Focus mode files for changes |
| **EventRouter** | Decouples services from UI |
| **MenuBarViewModel** | Per-space state for efficient SwiftUI updates |
| **NotchHUDController** | Manages HUD windows and visibility |
| **DisplayMenuBarManager** | Manages menu bars across multiple displays |

### Performance Optimizations

1. **Split-state architecture**: Each space has its own ViewModel. Changing one space doesn't re-render others (~95% fewer re-renders).

2. **Timer-based animation**: ProgressBarAnimator uses DispatchSourceTimer instead of CVDisplayLink (~1-2% CPU vs 10-15%).

3. **Window reuse**: HUD windows created once at startup, shown/hidden as needed (no jank).

4. **Event-driven updates**: FIFO pipe for Yabai, callbacks for audio/bluetooth, file watching for Focus mode. Polling only as fallback.

5. **CALayer rendering**: AppKit buttons use GPU-accelerated layers, bypassing SwiftUI overhead.

---

## Configuration

Settings stored in `~/.config/aegis/config.json` with hot-reload.

### Key Options

| Category | Options |
|----------|---------|
| **Menu Bar** | `maxAppIconsPerSpace`, `excludedApps`, `showAppNameInExpansion` |
| **App Launcher** | `launcherApps` (bundle identifiers) |
| **Media HUD** | `showMediaHUD`, `mediaHUDRightPanelMode` ("visualizer" / "trackInfo") |
| **Device HUD** | `showDeviceHUD`, `excludedBluetoothDevices` |
| **Notifications** | `showNotificationHUD`, `notificationExcludedApps` |
| **Focus HUD** | `showFocusHUD`, `showFocusName` |
| **App Switcher** | `appSwitcherEnabled`, `appSwitcherCmdScrollEnabled` |
| **Multi-Display** | `multiMonitorMode` (auto / primaryOnly / perMonitor / allShowAll) |

Full reference: `~/.config/aegis/CONFIG_OPTIONS.md`

---

## Requirements

- **macOS 14.0+** (Sonoma)
- **Yabai** window manager
- **Apple Silicon Mac with notch** (recommended for HUD features)
- **Accessibility permission** (for notification interception and Yabai)

---

## Data Flow Examples

### Space Switch
```
User presses hotkey → Yabai switches space → FIFO pipe event
    → YabaiService publishes .spaceChanged
    → MenuBarViewModel updates active space
    → SpaceIndicatorView re-renders with new highlight
```

### Volume Change
```
User presses volume key → CoreAudio callback
    → SystemInfoService publishes .volumeChanged
    → NotchHUDController.showVolume()
    → ProgressBarAnimator interpolates value
    → HUD slides in, progress bar fills, auto-hides after 1.5s
```

### Notification
```
App sends notification → macOS renders banner → AX event fires
    → NotificationService dismisses native banner
    → Extracts content, looks up bundle ID
    → Publishes .notificationReceived
    → NotchHUDController shows notification HUD
    → User clicks → Yabai focuses app window
```

---

## File Structure

```
Aegis/
├── App/                    # Entry point, AppDelegate
├── Core/
│   ├── Config/            # AegisConfig singleton
│   ├── Models/            # Space, WindowIcon, MediaInfo, etc.
│   └── Services/          # Yabai, System, Media, Bluetooth, etc.
├── Components/
│   ├── MenuBar/           # Space indicators, context button, launcher
│   ├── Notch/             # All HUD views and controllers
│   ├── SystemStatus/      # Battery, WiFi, Focus, clock
│   └── SettingsPanel/     # Settings UI
└── Helpers/               # Shared utilities
```

---

## External Dependencies

| Dependency | Purpose |
|------------|---------|
| **Yabai** | Window management commands and events |
| **mediaremote-adapter** | Now Playing data from all media sources |
| **Sparkle** | Auto-update framework |

---

**Aegis** - A shield for your macOS menu bar.
