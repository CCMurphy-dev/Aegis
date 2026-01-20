# Aegis

A macOS menu bar replacement for [Yabai](https://github.com/koekeishiya/yabai) window manager. Transforms your menu bar and notch into a control center for spaces, windows, and system status.

![macOS 14.0+](https://img.shields.io/badge/macOS-14.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
[![Yabai](https://img.shields.io/badge/Yabai-Required-green)](https://github.com/asmvik/yabai)
[![GitHub release](https://img.shields.io/github/v/release/CCMurphy-Dev/Aegis)](https://github.com/CCMurphy-Dev/Aegis/releases)
[![Downloads](https://img.shields.io/github/downloads/CCMurphy-Dev/Aegis/total)](https://github.com/CCMurphy-Dev/Aegis/releases)

<img width="1800" height="48" alt="image" src="https://github.com/user-attachments/assets/295f138a-5bb4-4230-bfb5-50c135b53cfe" />

## Features

- **Workspace indicators** - Visual space display with window icons, click to focus, drag to move
- **Layout controls** - Rotate, flip, balance, stack windows via scroll wheel or menu
- **Notch HUD** - Volume, brightness, now-playing media, Bluetooth devices, Focus mode, and system notifications with smooth animations
- **System status** - Battery, WiFi, Focus mode, clock in the menu bar
- **Customizable** - Simple settings panel with advanced options
- **Auto-updates** - Built-in update checking via Sparkle

## Quick Start

### 1. Install Yabai

```bash
brew install koekeishiya/formulae/yabai
```

See the [Yabai wiki](https://github.com/koekeishiya/yabai/wiki) for setup (SIP configuration, scripting addition).

### 2. Install Aegis

Download from [Releases](https://github.com/CCMurphy-Dev/Aegis/releases) or build from source:

```bash
git clone https://github.com/CCMurphy-Dev/Aegis.git
cd Aegis
open Aegis.xcodeproj
```

### 3. Run Setup (Optional)

On first launch, Aegis will prompt you to run the setup if needed. Alternatively, run manually:

```bash
~/.config/aegis/setup-aegis-yabai.sh
```

This configures the FIFO pipe integration for instant space/window updates.

### 4. Grant Permissions

- **Accessibility** - System Settings → Privacy & Security → Accessibility

## Requirements

- macOS 14.0+ (Sonoma)
- Apple Silicon Mac with notch (recommended)
- Yabai window manager

## Documentation

- **[User Guide](docs/GUIDE.md)** - Full documentation, configuration, and troubleshooting
- **[Changelog](CHANGELOG.md)** - Version history
- **[Architecture](docs/ARCHITECTURE.md)** - Technical overview for developers

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- [Yabai](https://github.com/koekeishiya/yabai) - Tiling window manager
- [skhd](https://github.com/koekeishiya/skhd) - Hotkey daemon
- [Sparkle](https://github.com/sparkle-project/Sparkle) - Auto-update framework
- [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) - Media integration (Now Playing)
- [Barik](https://github.com/mocki-toki/barik) & [Mew-Notch](https://github.com/monuk7735/mew-notch) - Inspiration

---

**Aegis** - A shield for your macOS menu bar.
