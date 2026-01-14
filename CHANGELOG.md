# Changelog

All notable changes to Aegis will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
