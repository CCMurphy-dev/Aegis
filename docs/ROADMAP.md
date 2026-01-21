# Aegis Roadmap

## Completed

### Auto-Updates (Sparkle) - v0.5.0
- Integrated Sparkle framework for automatic update notifications
- Checks GitHub releases for new versions
- Prompts users to download and install updates
- EdDSA signature verification for security

### JSON Config File - v0.8.0
- Edit settings at `~/.config/aegis/config.json`
- Hot-reload: changes apply automatically when saved
- Auto-generated documentation at `CONFIG_OPTIONS.md`

### Bluetooth Device HUD - v0.9.0
- Detect device connections/disconnections via IOBluetooth
- Show device type icon (AirPods, AirPods Pro, AirPods Max, Beats, keyboards, mice, etc.)
- Display battery level as circular ring indicator (color-coded)
- Separate notifications for connect and disconnect events

### Focus Mode HUD - v0.9.0
- Detect Focus mode changes via file system monitoring
- Show actual Focus mode icon from user's configuration
- Display mode name and On/Off status
- Support for all built-in and custom Focus modes

### Notification HUD - v0.9.0
- Intercept system notifications via Accessibility API
- Display app icon, title, and body in notch area
- Click to open/focus source application via Yabai
- Auto-dismiss native notification banner

### Media HUD Enhancements - v1.0.0
- Universal media source support via mediaremote-adapter
- Works with Music, Spotify, Safari, Chrome, Firefox, YouTube, etc.
- Visualizer mode with animated bars
- Track info mode with marquee scrolling for long text
- Album art caching with LRU eviction
- Tap album art to toggle between modes

### Split-State Architecture - v1.0.0
- Per-space ViewModels to minimize SwiftUI re-renders
- ~95% reduction in CPU usage during focus changes
- SpaceViewModelStore manages SpaceViewModel lifecycle

### Progress Bar Optimization - v1.0.4
- Lightweight DispatchSourceTimer-based animation
- ~1-2% CPU during animation (down from 10-15%)
- Auto-stops when animation settles (zero idle CPU)
- Exponential ease-out interpolation for smooth visuals

## Ideas

### UI Improvements
- Window preview thumbnails on hover
- Animate Media HUD panel expansion on track change

### Features
- Multi-monitor support improvements
- Custom themes/color schemes
- Keyboard shortcut customization UI
