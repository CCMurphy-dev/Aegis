# Aegis

A sleek macOS menu bar replacement that integrates with [Yabai](https://github.com/koekeishiya/yabai) window manager, inspired by [Barik](https://github.com/mocki-toki/barik) and [Mew-Notch](https://github.com/monuk7735/mew-notch). Aegis provides visual workspace indicators, window management, system status monitoring, and a notch-area HUD for volume, brightness, and music playback.

![macOS 12.0+](https://img.shields.io/badge/macOS-12.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![Yabai](https://img.shields.io/badge/Yabai-Required-green)

## Features

### Workspace Management
- **Visual space indicators** - See all workspaces at a glance with active state highlighting
- **Window icons** - App icons for windows in each space (configurable limit)
- **Drag & drop** - Move windows between spaces by dragging icons
- **Quick actions** - Click to focus spaces or windows
- **Right-click expansion** - View full window titles
- **Swipe to destroy** - Remove spaces with an upward swipe gesture

### Notch HUD
- **Volume display** - Shows current volume with mute state
- **Brightness display** - Shows current display brightness
- **Music playback** - Album art, track info, and visualizer
- **Smooth animations** - Frame-locked interpolation at 60fps
- **Smart auto-hide** - Configurable timeout (default 1.5s)

### System Status
- **Battery** - Level with color-coded states and charging indicator
- **Network** - WiFi signal strength (3 levels) or ethernet status
- **Clock** - 24-hour time display
- **Date** - Configurable format (long/short)

### Configuration
- **100+ settings** - Fine-tune every aspect of the interface
- **Animation tuning** - Spring physics parameters
- **Layout control** - Sizes, spacing, padding, corner radii
- **Color customization** - Opacity values for all states
- **Behavior toggles** - Haptics, gestures, thresholds
- **Persistent settings** - Saved across app restarts

## Screenshots

*Coming soon*

## Requirements

- **macOS 12.0+** (Monterey or later)
- **Apple Silicon Mac** with notch (for full HUD features)
- **[Yabai](https://github.com/koekeishiya/yabai)** window manager installed
- **Accessibility permission** for window management
- **Automation permission** for Yabai control

## Installation

### 1. Install Yabai

```bash
brew install koekeishiya/formulae/yabai
```

Follow the [Yabai wiki](https://github.com/koekeishiya/yabai/wiki) for initial setup. I have installed yabai via -HEAD with SIP disabled. 

### 2. Install Aegis

Download the latest release from the [Releases](https://github.com/yourusername/aegis/releases) page, or build from source:

```bash
git clone https://github.com/yourusername/aegis.git
cd aegis
open Aegis.xcodeproj
# Build and run in Xcode
```

### 3. Configure Yabai Integration

On first launch, Aegis will prompt you to run the setup script:

```bash
# The setup script will:
# 1. Create ~/.config/aegis/ directory
# 2. Install the notification script to /usr/local/bin/
# 3. Register Yabai signals for real-time updates
# 4. Optionally add config to ~/.yabairc for persistence

/path/to/Aegis.app/Contents/Resources/setup-aegis-yabai.sh
```

### 4. Grant Permissions

Aegis requires the following permissions:
- **Accessibility** - System Settings → Privacy & Security → Accessibility
- **Automation** - Will prompt on first launch

## Architecture

```
Aegis/
├── App/                     # Application entry & lifecycle
├── Core/
│   ├── Config/              # AegisConfig (all settings)
│   ├── Models/              # Space, WindowInfo, MusicInfo
│   └── Services/            # Yabai, SystemInfo, EventRouter
├── Components/
│   ├── MenuBar/             # Workspace indicators
│   ├── Notch/               # Volume/brightness/music HUD
│   ├── SystemStatus/        # Battery, network, clock
│   └── SettingsPanel/       # Preferences UI
└── AegisYabaiIntegration/   # Setup scripts
```

### Key Design Patterns

- **Event-driven architecture** - Pub/sub via EventRouter for decoupled components
- **FIFO pipe integration** - Real-time Yabai events without polling
- **Frame-locked animation** - CVDisplayLink for smooth 60fps interpolation
- **Persistent ViewModels** - State survives SwiftUI view rebuilds
- **Window reuse** - Windows created once at startup, shown/hidden as needed

## Configuration

Access settings via **right-click → Settings** on any space indicator.

### Key Settings

| Category | Settings |
|----------|----------|
| Menu Bar | Height, padding, spacing, corner radii |
| Spaces | Circle size, icon size, max icons, overflow behavior |
| Notch HUD | Width, height, auto-hide delay, progress bar style |
| System Status | Battery thresholds, WiFi thresholds, date format |
| Animation | Spring response, damping, durations |
| Interaction | Drag threshold, swipe distance, scroll sensitivity |

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Click space | Focus workspace |
| Click window | Focus window |
| Right-click window | Expand title |
| Drag window icon | Move to different space |
| Swipe up on space | Destroy space |
| ⌘Q | Quit Aegis |

## Context Menu Actions

Right-click on any space indicator to access:

- **Focus Left/Right** - Navigate workspaces
- **Rotate/Flip Layout** - Change window arrangement
- **Balance Windows** - Equalize window sizes
- **Toggle Layout** - Switch between BSP and float
- **Stack Windows** - Stack all windows in space
- **Create/Destroy Space** - Manage workspaces
- **Restart Yabai/skhd** - Quick service restart
- **Settings** - Open preferences panel

## Troubleshooting

### Aegis doesn't show workspaces
1. Ensure Yabai is running: `yabai -m query --spaces`
2. Run the setup script to register signals
3. Check that the FIFO pipe exists: `ls ~/.config/aegis/yabai.pipe`

### Volume/brightness HUD doesn't appear
1. Aegis suppresses native macOS HUDs
2. Ensure Accessibility permission is granted
3. Check Console.app for error messages

### Notifications appear behind Aegis
This was fixed in v0.2.0 - ensure you're running the latest version.

### Music HUD shows wrong album art
Album art is now cached per-track. Restart Aegis if issues persist.

## Building from Source

```bash
git clone https://github.com/yourusername/aegis.git
cd aegis
open Aegis.xcodeproj
```

Select **Product → Build** (⌘B) in Xcode.

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- [Yabai](https://github.com/koekeishiya/yabai) - The excellent tiling window manager that makes this possible
- [skhd](https://github.com/koekeishiya/skhd) - Simple hotkey daemon for macOS
- [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) - MediaRemote framework bridge for music integration
[Barik](https://github.com/mocki-toki/barik) and [Mew-Notch](https://github.com/monuk7735/mew-notch) - For inspiration on the structure and implementation.


---

**Aegis** - A shield for your macOS menu bar.
