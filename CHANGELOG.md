# Changelog

All notable changes to Aegis will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.6.0] - 2025-01-15

### Added
- Bluetooth device connection HUD
  - Shows device name, icon, and battery level when AirPods/headphones connect
  - Animated battery ring indicator
  - Separate notifications for connect/disconnect events
- Focus mode HUD in notch display
  - Shows Focus mode name and icon when enabled/disabled
  - Displays specific mode (e.g., "Study / Off") when turning off
  - Uses actual SF Symbols from Focus configuration

### Fixed
- Space indicator scroll position no longer resets when switching spaces
  - Scroll position now preserved when clicking spaces behind the notch

## [0.5.2] - 2025-01-15

### Added
- Setup prompt on first launch when yabai integration not configured
- "Yabai Integration" status button in Settings panel
- Setup window with copy command and open Terminal buttons

### Changed
- Moved notify script from /usr/local/bin to ~/.config/aegis/ (no sudo required)
- All Aegis config files now in ~/.config/aegis/ for easy management

## [0.5.1] - 2025-01-15

### Fixed
- Version numbers now display correctly across the app (startup notification, context menu, settings panel)
- Sparkle update window now appears above the Settings panel
- Auto-sync version from VERSION file to Info.plist on build

## [0.5.0] - 2025-01-15

### Added
- Sparkle auto-update framework integration
  - "Check for Updates" button in Settings > General
  - Automatic update checks with EdDSA signature verification
  - Seamless in-app update installation
- Update signing infrastructure (scripts/sign-update.sh)
- Appcast feed for distributing updates via GitHub

## [0.4.0] - 2025-01-15

### Added
- Focus mode indicator in system status panel
  - Displays macOS Focus mode icon using actual SF Symbol from user's config
  - Animated slide in/out matching NotchHUD style
  - Optional Focus name display alongside icon (configurable in settings)
- Critical battery indicator (red when ≤10%)
- Text shadow on battery percentage for improved readability
- "Show Focus Name" toggle in settings

## [0.3.2] - 2025-01-15

### Fixed
- Aegis windows no longer appear in space indicators (added to excluded apps)

## [0.3.1] - 2025-01-15

### Added
- Launch at Login setting (enabled by default)
- Simplified Settings panel with essential settings upfront
- Collapsible Advanced Settings section for power users

### Changed
- Settings panel reorganized: ~12 essential settings visible, 70+ advanced options collapsed
- Removed tab-based navigation in favor of single scrollable view

## [0.3.0] - 2025-01-14

### Added
- Stack Windows submenu in context menu with window selection and app icons
- Yabai scripting addition (SA) status check at startup
- Clickable SA status in context menu to load SA with admin prompt
- LogService for file-based logging at ~/Library/Logs/Aegis/aegis.log
- Automatic log rotation at 5MB

### Changed
- Status section in context menu now shows: Yabai, SA, Aegis, Link (reordered)
- Shortened status labels for cleaner display

## [0.2.3] - 2025-01-14

### Added
- Startup notification showing Aegis version, Yabai version, and link status
- Link status display in context menu (Active/Not configured/Inactive)
- VERSION file for centralized version management
- Build script to auto-update version from VERSION file
- ROADMAP.md with planned features

### Changed
- Updated README with comprehensive documentation
- Version now read from bundle at runtime

### Removed
- Unused LayoutActionHandler.swift
- Obsolete documentation files (DIAGNOSTICS_GUIDE.md, MEDIAREMOTE_SETUP.md, SPRING_PHYSICS_IMPLEMENTATION.md)
- Empty test target files

## [0.2.2] - 2025-01-14

### Fixed
- Menu bar vertical alignment issues
- Space indicators now properly aligned with button and notch HUD
- Click pass-through for notifications fixed
- Duplicate Messages windows filtered by role field

## [0.2.1] - 2025-01-13

### Added
- Music HUD enhancements with visualizer
- Space indicator improvements

### Fixed
- Various space indicator display issues

## [0.2.0] - 2025-01-13

### Added
- Custom menu bar replacement
- System status panel (time, date, WiFi, battery)
- Notch HUD for volume, brightness, and music
- Visual space indicators with window icons
- Drag & drop window management
- Layout actions via scroll wheel and context menu
- 100+ configurable settings

### Changed
- Complete rewrite of menu bar architecture

## [0.1.0] - 2025-01-12

### Added
- Initial release
- Basic Yabai integration
- Space switching functionality
