# Aegis

A macOS menu bar replacement for [Yabai](https://github.com/koekeishiya/yabai) window manager. Transforms your menu bar and notch into a control center for spaces, windows, and system status.

![macOS 14.0+](https://img.shields.io/badge/macOS-14.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
[![Yabai](https://img.shields.io/badge/Yabai-Required-green)](https://github.com/asmvik/yabai)
[![GitHub release](https://img.shields.io/github/v/release/CCMurphy-Dev/Aegis)](https://github.com/CCMurphy-Dev/Aegis/releases)
[![Downloads](https://img.shields.io/github/downloads/CCMurphy-Dev/Aegis/total)](https://github.com/CCMurphy-Dev/Aegis/releases)

*Screenshot coming soon*

## Features

- **Workspace indicators** - Visual space display with window icons, click to focus, drag to move
- **Layout controls** - Rotate, flip, balance, stack windows via scroll wheel or menu
- **Notch HUD** - Volume, brightness, and now-playing music with smooth animations
- **System status** - Battery, WiFi, clock in the menu bar
- **Customizable** - Simple settings panel with advanced options

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

### 3. Run Setup

```bash
/Applications/Aegis.app/Contents/Resources/setup-aegis-yabai.sh
```

### 4. Grant Permissions

- **Accessibility** - System Settings → Privacy & Security → Accessibility
- **Automation** - Prompted on first launch

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
- [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) - Music integration
- [Barik](https://github.com/mocki-toki/barik) & [Mew-Notch](https://github.com/monuk7735/mew-notch) - Inspiration

---

**Aegis** - A shield for your macOS menu bar.
