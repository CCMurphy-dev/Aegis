# Aegis

A macOS menu bar replacement for tiling window managers. Transforms your menu bar and notch into a control center for spaces, windows, and system status. Supports **Yabai**, **AeroSpace**, and **Rift** — auto-detected at launch.

![macOS 14.0+](https://img.shields.io/badge/macOS-14.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
[![GitHub release](https://img.shields.io/github/v/release/CCMurphy-Dev/Aegis)](https://github.com/CCMurphy-Dev/Aegis/releases)
[![Downloads](https://img.shields.io/github/downloads/CCMurphy-Dev/Aegis/total)](https://github.com/CCMurphy-Dev/Aegis/releases)

<img width="1800" height="40" alt="image" src="https://github.com/user-attachments/assets/3e694fd5-1e14-4e96-a39e-e35979bd3603" />

## Window Manager Support

Aegis auto-detects your window manager at launch. No configuration required.

| Feature | Yabai | AeroSpace | Rift |
|---|:---:|:---:|:---:|
| **Workspace display** | macOS native spaces | Virtual (1–9) | Virtual |
| **Click to switch workspace** | ✓ | ✓ | ✓ |
| **Window icons per workspace** | ✓ | ✓ | ✓ (cached) |
| **Drag reorder workspaces** | ✓ | — | — |
| **Create workspace** | ✓ | ✓ | ✓ |
| **Destroy workspace** | ✓ | — | — |
| **Send window to workspace** | ✓ | ✓ | ✓ |
| **Focus window (click)** | ✓ | ✓ | ✓ |
| **Drag window between workspaces** | ✓ | — | ✓ |
| **Float / unfloat window** | ✓ | ✓ | ✓ |
| **Toggle fullscreen** | ✓ | ✓ | ✓ |
| **Stack windows** | ✓ | — | — |
| **BSP / tiling layout toggle** | ✓ | ✓ | ✓ |
| **Close / minimize window** | — | ✓ | — |
| **Resize window** | — | ✓ | — |
| **Multi-monitor focus/move** | — | ✓ | — |
| **App switcher (Cmd+Tab) by workspace** | ✓ | ✓ | ✓ |
| **Event system** | FIFO pipe | FIFO pipe | Mach subscription |
| **Setup prompt** | ✓ | ✓ | Auto |

> Full feature matrix in [WINDOW_MANAGERS.md](WINDOW_MANAGERS.md)

## Features

### Menu Bar

**Space indicators** - Visual workspace display with app icons, click to switch, scroll to navigate, drag to reorder. Focused window title auto-expands with live updates

![Space indicators](https://github.com/user-attachments/assets/3a02ec56-9989-473c-a468-c46f97b0ce74)

**App launcher** - Quick-access floating apps button with configurable app list (e.g. finder, iTerm, passwords etc)

https://github.com/user-attachments/assets/9291ffb2-c68c-4b17-8cf9-52b5d76a1c27

**Context button** - a scroll-able button to cycle through yabai commands. Right click menu for expanded commands (stack windows, move to/destroy space, access settings etc)

https://github.com/user-attachments/assets/3c384235-ff87-451d-add1-aac5967bf806

- **System status** - Battery, WiFi, Focus mode, clock
- **Multi-display support** - Menu bars on all connected monitors with configurable modes (auto, primary only, per-monitor, all show all)

### Notch HUD

<table>
<tr>
<td align="center"><strong>Volume</strong></td>
<td align="center"><strong>Brightness</strong></td>
</tr>
<tr>
<td>

https://github.com/user-attachments/assets/6f992786-983b-4ba7-89fc-6fb285375cae

</td>
<td>

https://github.com/user-attachments/assets/75b30230-6137-4ece-96ce-2e1c06c53700

</td>
</tr>
<tr>
<td align="center"><strong>Focus Mode</strong></td>
<td align="center"><strong>Device Connect</strong></td>
</tr>
<tr>
<td>

https://github.com/user-attachments/assets/e88d539d-3218-4a96-b2ec-71525ed0bbe7

</td>
<td>

https://github.com/user-attachments/assets/1c089f72-73f9-48e5-b499-ec7f5ae9ed4e

</td>
</tr>
<tr>
<td align="center" colspan="2"><strong>Media</strong></td>
</tr>
<tr>
<td colspan="2">

https://github.com/user-attachments/assets/95c7d4cf-5b05-4b03-b176-f2a5e10938bd

</td>
</tr>
</table>

- **Media** - Album art with visualizer or track info (static or marquee scrolling for long titles)
  - Works with Music, Spotify, Safari, Chrome, Firefox, YouTube, and more
- **Notifications** - Intercepts system notifications, click to open source app

### App Switcher
- **Cmd+Tab replacement** - Window previews with app icons
- **Scroll navigation** - Two-finger scroll to cycle through windows
- **Cmd+scroll activation** - Optional gesture to open switcher (configurable)

### Other
- **Customizable** - JSON config file with hot-reload, plus Settings panel with custom theme color pickers and saveable presets
- **Auto-updates** - Built-in update checking via Sparkle
- **Energy efficient** - Coalescing event gate, fixed-duration animations, and non-reactive view isolation for minimal CPU usage

## Quick Start

### 1. Install a supported window manager

**Yabai:**
```bash
brew install koekeishiya/formulae/yabai
```
See the [Yabai wiki](https://github.com/koekeishiya/yabai/wiki) for SIP and scripting addition setup.

**AeroSpace:**
```bash
brew install --cask nikitabobko/tap/aerospace
```
See [AeroSpace docs](https://nikitabobko.github.io/AeroSpace/guide) for configuration.

**Rift:** Download from [Rift](https://github.com/acsandmann/rift) or your preferred source.

### 2. Install Aegis

Download from [Releases](https://github.com/CCMurphy-Dev/Aegis/releases) or build from source:

```bash
git clone https://github.com/CCMurphy-Dev/Aegis.git
cd Aegis
open Aegis.xcodeproj
```

### 3. Launch — Aegis auto-detects your WM

On first launch, Aegis detects your running window manager and prompts for any required setup (FIFO pipe integration for Yabai/AeroSpace). You can also run setup manually:

```bash
# Yabai
~/.config/aegis/setup-aegis-yabai.sh

# AeroSpace
~/.config/aegis/setup-aegis-aerospace.sh
```

Rift connects automatically via its Mach subscription API — no setup needed.

### 4. Grant Permissions

- **Accessibility** - System Settings → Privacy & Security → Accessibility

## Requirements

- macOS 14.0+ (Sonoma)
- Apple Silicon Mac with notch (recommended)
- One of: Yabai, AeroSpace, or Rift

## Documentation

- **[User Guide](docs/GUIDE.md)** - Full documentation, configuration, and troubleshooting
- **[Changelog](CHANGELOG.md)** - Version history
- **[Architecture](docs/ARCHITECTURE.md)** - Technical overview for developers
- **[Roadmap](docs/ROADMAP.md)** - Completed features and future ideas

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- [Yabai](https://github.com/koekeishiya/yabai) - Tiling window manager
- [AeroSpace](https://github.com/nikitabobko/AeroSpace) - i3-inspired tiling window manager
- [Rift](https://github.com/acsandmann/rift) - Modern macOS tiling window manager
- [skhd](https://github.com/koekeishiya/skhd) - Hotkey daemon
- [Sparkle](https://github.com/sparkle-project/Sparkle) - Auto-update framework
- [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) - Media integration (Now Playing)
- [Barik](https://github.com/mocki-toki/barik) & [Mew-Notch](https://github.com/monuk7735/mew-notch) - Inspiration

---

**Aegis** - A shield for your macOS menu bar.
