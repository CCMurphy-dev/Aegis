# Aegis User Guide

A comprehensive guide to installing, configuring, and using Aegis - a macOS menu bar replacement for Yabai window manager.

## Table of Contents

1. [Overview](#overview)
2. [Requirements](#requirements)
3. [Installation](#installation)
4. [Yabai Integration Setup](#yabai-integration-setup)
5. [Features](#features)
6. [Usage](#usage)
7. [Configuration](#configuration)
8. [Troubleshooting](#troubleshooting)
9. [FAQ](#faq)

---

## Overview

Aegis transforms your macOS menu bar and notch area into a powerful control center for managing workspaces and windows. It provides:

- **Visual workspace indicators** showing all spaces with window icons
- **Notch HUD** for volume, brightness, and now-playing music
- **System status** display (battery, WiFi, clock)
- **Window management** via drag-drop and context menus

Aegis communicates with Yabai in real-time via a FIFO pipe, ensuring instant updates when you switch spaces or move windows.

---

## Requirements

### System Requirements

| Requirement | Details |
|-------------|---------|
| macOS | 14.0+ (Sonoma or later) |
| Hardware | Apple Silicon Mac (M1/M2/M3) with notch recommended |
| Yabai | 7.0+ installed and running |

### Permissions Required

Aegis requires the following permissions:

1. **Accessibility** - For menu bar display and window tracking
2. **Automation** - For controlling Yabai and Music.app
3. **Notifications** - For startup status notifications (optional)

---

## Installation

### Step 1: Install Yabai

If you haven't already installed Yabai:

```bash
brew install koekeishiya/formulae/yabai
```

For full functionality (space management, window moving between spaces), you need to:

1. Partially disable SIP (System Integrity Protection)
2. Install the Yabai scripting addition

See the [Yabai Wiki](https://github.com/koekeishiya/yabai/wiki) for detailed instructions.

### Step 2: Install Aegis

**Option A: Download Release**

Download the latest `.dmg` from [Releases](https://github.com/yourusername/aegis/releases) and drag Aegis to Applications.

**Option B: Build from Source**

```bash
git clone https://github.com/yourusername/aegis.git
cd aegis
open Aegis.xcodeproj
# Press Cmd+B to build, Cmd+R to run
```

### Step 3: Grant Permissions

On first launch:

1. Go to **System Settings → Privacy & Security → Accessibility**
2. Enable Aegis in the list
3. You may be prompted to grant Automation access - click Allow

---

## Yabai Integration Setup

Aegis communicates with Yabai via a FIFO pipe. This requires a one-time setup.

### Automatic Setup

Run the setup script bundled with Aegis:

```bash
/Applications/Aegis.app/Contents/Resources/setup-aegis-yabai.sh
```

Or if running from Xcode:

```bash
~/Library/Developer/Xcode/DerivedData/Aegis-*/Build/Products/Debug/Aegis.app/Contents/Resources/setup-aegis-yabai.sh
```

The script will:

1. Create `~/.config/aegis/` directory
2. Install `/usr/local/bin/aegis-yabai-notify` notification script
3. Register Yabai signals for real-time events
4. Optionally add integration to `~/.yabairc` for persistence

### Manual Setup

If you prefer manual setup, add this to your `~/.yabairc`:

```bash
# AEGIS_INTEGRATION_START
AEGIS_NOTIFY="/usr/local/bin/aegis-yabai-notify"
yabai -m signal --add event=space_changed action="YABAI_EVENT_TYPE=space_changed $AEGIS_NOTIFY" label=aegis_space_changed
yabai -m signal --add event=space_destroyed action="YABAI_EVENT_TYPE=space_destroyed $AEGIS_NOTIFY" label=aegis_space_destroyed
yabai -m signal --add event=window_focused action="YABAI_EVENT_TYPE=window_focused $AEGIS_NOTIFY" label=aegis_window_focused
yabai -m signal --add event=window_created action="YABAI_EVENT_TYPE=window_created $AEGIS_NOTIFY" label=aegis_window_created
yabai -m signal --add event=window_destroyed action="YABAI_EVENT_TYPE=window_destroyed $AEGIS_NOTIFY" label=aegis_window_destroyed
yabai -m signal --add event=window_moved action="YABAI_EVENT_TYPE=window_moved $AEGIS_NOTIFY" label=aegis_window_moved
yabai -m signal --add event=application_front_switched action="YABAI_EVENT_TYPE=application_front_switched $AEGIS_NOTIFY" label=aegis_application_front_switched
# AEGIS_INTEGRATION_END
```

### Scripting Addition (SA)

For full functionality, the Yabai scripting addition should be loaded. Add to your `~/.yabairc`:

```bash
# Load scripting addition (requires sudoers entry)
sudo yabai --load-sa
yabai -m signal --add event=dock_did_restart action="sudo yabai --load-sa"
```

See [Yabai Wiki - Installing the Scripting Addition](https://github.com/koekeishiya/yabai/wiki/Installing-yabai-(latest-release)#configure-scripting-addition) for sudoers configuration.

### Verifying Setup

After setup, check the status in Aegis:

1. Right-click the layout button (left side of menu bar)
2. Look at the **Status** section:
   - **Yabai**: Should show version number
   - **SA**: Should show "Loaded"
   - **Aegis**: Shows Aegis version
   - **Link**: Should show "Active"

If SA shows "Not loaded", click it to load with an admin prompt.

---

## Features

### Menu Bar Components

```
┌─────────────────────────────────────────────────────────────────────┐
│ [Layout] │ [1 🌐📧] │ [2 💻📝] │ [3 🎵] │     ⊙     │ 🔋 📶 10:30 │
└─────────────────────────────────────────────────────────────────────┘
     ↑            ↑                              ↑           ↑
  Actions   Space indicators               Notch area   System status
```

### Space Indicators

Each space shows:
- **Space number** (1, 2, 3...)
- **Window icons** for apps on that space
- **Active state** highlighting for the current space
- **Stack badges** showing stacked window count

### Layout Actions Button

Left-click cycles through layout actions. Right-click opens the full context menu.

**Scroll wheel actions:**
- Scroll up/down to cycle through: Rotate 90°, Rotate 180°, Rotate 270°, Balance, Flip X, Flip Y, Toggle Layout

### Notch HUD

The notch area displays contextual information:

| Trigger | Display |
|---------|---------|
| Volume change | Volume icon + progress bar |
| Brightness change | Brightness icon + progress bar |
| Music playing | Album art + visualizer or track info |
| Device connected | Device name + battery ring (AirPods, etc.) |
| Focus mode change | Focus mode icon + name |

The HUD slides in from under the notch with smooth spring animation and auto-hides after a configurable delay.

#### Music HUD

The Music HUD shows album art on the left and either a **visualizer** or **track info** on the right:

- **Visualizer mode** (default): Animated bars that respond to playback
- **Track Info mode**: Song title and artist name
  - Expands to show full text when track changes
  - Collapses after 3 seconds
  - Long text scrolls with marquee animation
  - Tap album art to toggle between modes

### System Status

Right side of the menu bar shows:
- **Battery** - Color-coded (green/yellow/orange/red) with charging indicator
- **WiFi** - Signal strength with 3-level indicator
- **Clock** - Current time
- **Date** - Configurable format (long or short)

---

## Usage

### Basic Operations

| Action | How |
|--------|-----|
| Focus a space | Click the space indicator |
| Focus a window | Click the window icon |
| See window title | Right-click a window icon |
| Move window to space | Drag window icon to another space |
| Delete a space | Swipe up on space indicator |
| Create new space | Context menu → Spaces → Create Space |

### Context Menu

Right-click the layout button to access:

**Layout**
- Rotate (90°, 180°, 270°)
- Flip (horizontal/vertical)
- Balance windows
- Toggle BSP/float mode
- Stack/unstack windows

**Windows**
- Focus next/previous window
- Swap windows left/right
- Warp window (north/south/east/west)
- Toggle float/fullscreen
- Send to specific space

**Stack Windows**
- Stack current window onto another
- Submenu shows available target windows with icons

**Spaces**
- Focus left/right space
- Create/destroy space

**System**
- Restart Yabai
- Restart skhd
- Restart Aegis
- Open Settings

**Status**
- Yabai version and status
- SA status (clickable to load if not loaded)
- Aegis version
- Link status

### Keyboard Shortcuts

Aegis doesn't define global hotkeys - use [skhd](https://github.com/koekeishiya/skhd) for that. However, you can configure skhd to trigger Yabai commands that Aegis will reflect instantly.

Example skhd configuration:

```bash
# Focus spaces
alt - 1 : yabai -m space --focus 1
alt - 2 : yabai -m space --focus 2
alt - 3 : yabai -m space --focus 3

# Move windows
shift + alt - 1 : yabai -m window --space 1
shift + alt - 2 : yabai -m window --space 2
shift + alt - 3 : yabai -m window --space 3

# Layout
alt - r : yabai -m space --rotate 90
alt - b : yabai -m space --balance
alt - t : yabai -m window --toggle float
```

---

## Configuration

### Accessing Settings

Right-click any space indicator → **Settings**

### Key Settings Categories

#### Menu Bar
- Height, padding, spacing
- Corner radii
- Background opacity

#### Spaces
- Indicator size
- Maximum icons displayed
- Icon size
- Stack badge position

#### Notch HUD
- Auto-hide delay
- Progress bar dimensions
- Animation settings

#### System Status
- Battery level thresholds
- WiFi strength thresholds
- Date format (long/short)

#### Animation
- Spring response (snappiness)
- Spring damping (bounciness)
- Fade durations

### Configuration File

Settings are stored in UserDefaults and persist across launches. To reset to defaults, delete the Aegis preferences:

```bash
defaults delete com.aegis.Aegis
```

---

## Troubleshooting

### Aegis doesn't show spaces

**Check Yabai is running:**
```bash
yabai -m query --spaces
```

**Check signals are registered:**
```bash
yabai -m signal --list | grep aegis
```

**Check FIFO pipe exists:**
```bash
ls -la ~/.config/aegis/yabai.pipe
```

**Check link status:**
Right-click → Status → Link should show "Active"

### SA shows "Not loaded"

1. Click the SA status in the context menu to load with admin prompt
2. Or run manually: `sudo yabai --load-sa`
3. For automatic loading, ensure your `~/.yabairc` includes the load command and you have a sudoers entry

### Volume/Brightness HUD doesn't appear

1. Verify Accessibility permission is granted
2. Check if another app is suppressing the system HUD
3. Look for errors in Console.app (filter by "Aegis")

### Music HUD shows wrong info

1. Check Music.app or Spotify is actually playing
2. Album art is cached per-track - if wrong, quit and reopen Aegis
3. The MediaRemote framework sometimes has delays - wait a moment

### Link shows "Not configured"

Run the setup script:
```bash
/Applications/Aegis.app/Contents/Resources/setup-aegis-yabai.sh
```

Then restart Yabai:
```bash
yabai --restart-service
```

### Performance issues

1. Check Activity Monitor for high CPU usage
2. Verify CVDisplayLink is not duplicated (should see ~60 callbacks/sec)
3. Reduce max displayed icons in Settings if needed

### Logs

Aegis logs to `~/Library/Logs/Aegis/aegis.log`. View with:

```bash
tail -f ~/Library/Logs/Aegis/aegis.log
```

Or open in Console.app.

---

## FAQ

### Q: Does Aegis work without Yabai?

Partially. The Notch HUD (volume/brightness/music) works independently. However, the space indicators require Yabai.

### Q: Does Aegis work on Intel Macs?

Yes, but the notch HUD features are designed for MacBooks with a notch. On other Macs, the HUD appears at the top center of the screen.

### Q: Can I use Aegis with other window managers?

Currently, Aegis is designed specifically for Yabai. Support for other window managers is not planned.

### Q: Does Aegis replace the native menu bar?

Aegis displays its own window at the top of the screen. It doesn't technically replace the native menu bar - you can still access it by moving your mouse to the very top of the screen.

### Q: How do I completely hide the native menu bar?

Use Yabai's `menubar_opacity` setting in your `.yabairc`:

```bash
yabai -m config menubar_opacity 0.0
```

### Q: Why does SA need to be reloaded after restart?

The scripting addition is injected into Dock.app and doesn't persist across system restarts. Your `.yabairc` should automatically reload it. If not working, check your sudoers configuration.

### Q: Can I customize the colors/theme?

Currently, Aegis uses system accent colors and a dark theme. Custom themes are on the roadmap.

### Q: How do I uninstall Aegis?

1. Quit Aegis
2. Delete `/Applications/Aegis.app`
3. Remove the integration from `~/.yabairc` (the section between `AEGIS_INTEGRATION_START` and `AEGIS_INTEGRATION_END`)
4. Delete `/usr/local/bin/aegis-yabai-notify`
5. Delete `~/.config/aegis/`
6. Delete preferences: `defaults delete com.aegis.Aegis`

---

## Getting Help

- **Issues**: [GitHub Issues](https://github.com/CCMurphy-Dev/Aegis/issues)
- **Yabai Help**: [Yabai Wiki](https://github.com/koekeishiya/yabai/wiki)

---

## Version History

See [CHANGELOG.md](../CHANGELOG.md) for detailed release notes.

---

**Aegis** - A shield for your macOS menu bar.
