# Aegis

A sleek macOS menu bar replacement that integrates with [Yabai](https://github.com/koekeishiya/yabai) window manager. Aegis transforms your menu bar and notch area into a powerful control center for managing spaces, windows, and system status.

Inspired by [Barik](https://github.com/mocki-toki/barik) and [Mew-Notch](https://github.com/monuk7735/mew-notch).

![macOS 14.0+](https://img.shields.io/badge/macOS-14.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![Yabai](https://img.shields.io/badge/Yabai-Required-green)
![Version](https://img.shields.io/badge/version-0.2.3-brightgreen)
[GitHub release](https://img.shields.io/github/v/release/yourusername/Aegis)
![GitHub commits](https://img.shields.io/github/commits-since/yourusername/Aegis/v0.3.0)


## Features

### Workspace Management
- **Visual space indicators** - See all workspaces at a glance with numbered indicators and active state highlighting
- **Window app icons** - Each space shows icons for windows it contains (configurable limit)
- **Click to focus** - Click any space or window icon to instantly switch focus
- **Drag & drop** - Move windows between spaces by dragging their icons
- **Window stacking** - Badge indicators show stacked window counts
- **Swipe to destroy** - Remove spaces with an upward swipe gesture (configurable)

### Layout Actions
Quick access to Yabai layout operations via scroll wheel or right-click menu:
- Rotate layout (90°, 180°, 270°)
- Flip layout (horizontal/vertical)
- Balance windows equally
- Toggle BSP/floating layout
- Stack/unstack windows
- Create/destroy spaces

### Notch HUD
Dynamic notifications that appear from your MacBook's notch:
- **Volume & Brightness** - Elegant progress bars when adjusting system levels
- **Now Playing** - Album art, track info, and animated 5-bar visualizer
- **Universal media support** - Works with Music.app, Spotify, Safari, YouTube, and more
- **Smooth animations** - Spring physics with 60fps interpolation
- **Smart auto-hide** - Configurable timeout (default 1.5s)

### System Status
Always-visible status indicators in the menu bar:
- **Clock & Date** - Configurable format (long "Mon Jan 13" or short "13/01/26")
- **WiFi** - Signal strength with 3-level indicators
- **Battery** - Color-coded levels (green/yellow/orange/red) with charging indicator

### Startup Notification
On launch, Aegis displays a notification showing:
- Aegis version
- Yabai version
- Link status (Active/Not configured/Inactive)

### Configuration
- **100+ settings** - Fine-tune every aspect of the interface
- **Animation tuning** - Spring physics parameters (response, damping)
- **Layout control** - Sizes, spacing, padding, corner radii
- **Color customization** - Opacity values for all states
- **Behavior toggles** - Haptics, gestures, thresholds
- **Persistent settings** - Saved automatically across restarts

## Screenshots

*Coming soon*

## Requirements

- **macOS 14.0+** (Sonoma or later)
- **Apple Silicon Mac** with notch (for full HUD features)
- **[Yabai](https://github.com/koekeishiya/yabai)** window manager installed and running
- **Accessibility permission** - For menu bar display and window management
- **Automation permission** - For Yabai and Music.app control
- **Notification permission** - For startup status notifications (optional)

## Installation

### 1. Install Yabai

```bash
brew install koekeishiya/formulae/yabai
```

Follow the [Yabai wiki](https://github.com/koekeishiya/yabai/wiki) for initial setup. I have installed yabai via -HEAD with SIP disabled. 

### 2. Install Aegis

Download the latest release from the [Releases](https://github.com/aegis/releases) page, or build from source:

```bash
git clone https://github.com/aegis.git
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

Right-click on the layout button (left side of menu bar) to access:

### Layout
- Rotate (90°, 180°, 270°)
- Flip (horizontal/vertical)
- Balance windows
- Toggle BSP/float

### Windows
- Focus next/previous
- Swap left/right
- Warp (north/south/east/west)
- Toggle float/fullscreen
- Send to space

### Spaces
- Focus left/right
- Create/destroy space

### System
- Restart Yabai/skhd/Aegis
- Open Settings

### Status
- Yabai version
- Aegis version
- Link status (Active/Not configured/etc.)

## Troubleshooting

### Aegis doesn't show workspaces
1. Ensure Yabai is running: `yabai -m query --spaces`
2. Run the setup script to register signals
3. Check that the FIFO pipe exists: `ls ~/.config/aegis/yabai.pipe`
4. Check link status in context menu - should show "Active"

### Volume/brightness HUD doesn't appear
1. Ensure Accessibility permission is granted
2. Check Console.app for error messages

### Startup notification is empty
1. Check System Settings > Notifications > Aegis
2. Ensure "Show Previews" is set to "Always" or "When Unlocked"

### Music HUD shows wrong album art
Album art is cached per-track. Restart Aegis if issues persist.

### Link status shows "Not configured"
1. Run the setup script: `/path/to/Aegis.app/Contents/Resources/setup-aegis-yabai.sh`
2. Restart Yabai: `yabai --restart-service`

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
- [Barik](https://github.com/mocki-toki/barik) and [Mew-Notch](https://github.com/monuk7735/mew-notch) - For inspiration

## Roadmap

See [ROADMAP.md](ROADMAP.md) for planned features including:
- Sparkle auto-updates
- Multi-monitor improvements
- Custom themes
- Keyboard shortcut customization UI

---

**Aegis** - A shield for your macOS menu bar.
