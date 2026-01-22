# Changelog

All notable changes to Aegis will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.5] - 2026-01-22

### Changed
- Adaptive frame rate for progress bar animation
  - 60fps during large movements, 30fps moderate, 15fps settling
  - Further reduces CPU usage during HUD animations
- Album art memory optimization
  - Downscales images to 160x160 (2x retina for 80pt display)
  - Reduced cache from 10 to 5 entries
  - Uses autoreleasepool to immediately free full-size images
  - Reduces memory footprint from ~100MB to ~50MB during music playback
- Background thread album art decoding
  - Base64 decode and scaling moved off main thread
  - Prevents UI stutter when switching tracks rapidly

### Fixed
- Space indicator vertical alignment (was too high, now centered with notch)
- Yabai setup script now uses correct default config path (`~/.config/yabai/yabairc`)
  - Removed legacy `~/.yabairc` fallback
  - Added `YABAIRC` environment variable for custom config locations
- `YabaiSetupChecker.isPersisted()` now checks correct yabairc path

## [1.0.4] - 2026-01-21

### Changed
- Progress bar animation rewritten for energy efficiency
  - Replaced CVDisplayLink with lightweight DispatchSourceTimer
  - ~1-2% CPU during animation (down from 10-15%)
  - Auto-stops when animation settles (zero idle CPU)
  - Exponential ease-out interpolation for smooth visuals
- Documentation updated for current implementation
  - ARCHITECTURE.md: Updated for timer-based animation, event-driven services
  - GUIDE.md: Updated performance troubleshooting
  - ROADMAP.md: Added completed features list
  - README.md: Reorganized features section

## [1.0.3] - 2026-01-20

### Added
- Notification HUD click now uses Yabai to focus app window (respects window layout)
  - Falls back to NSWorkspace.launchApplication if no window exists
- `YabaiService.focusWindowByAppName()` method for app-based window focus
- `showMediaHUD` config alias for backward compatibility with `showMusicHUD`

### Changed
- Consolidated HUD panel shapes into shared `HUDShapes.swift` file
  - Removes ~160 lines of duplicate shape code across view files
- Overlay HUD visibility now uses counter instead of boolean
  - Prevents race conditions when multiple HUDs overlap with async hide timers
  - `resetOverlayState()` safety valve resets counter if stuck

### Fixed
- Media HUD right panel now shows correctly (was stuck hidden due to `isOverlayActive` race condition)

### Removed
- Unused `import Combine` from MediaService.swift
- Verbose debug print statements from NotchHUDViewModel
- Duplicate panel shape definitions (now in HUDShapes.swift)

## [1.0.2] - 2025-01-18

### Added
- `expandContextButtonOnScroll` config option to disable context button label expansion when scrolling
  - When disabled, only the icon changes during scroll - saves CPU from SwiftUI re-renders
  - Scroll handler optimized to skip all label-related work when disabled

### Changed
- Removed debug print statements from YabaiService and MenuBarController
- Removed unused `checkYabaiStatus()` method from MenuBarController

### Fixed
- App switcher no longer affected by residual scroll momentum from menu bar
  - 200ms cooldown after activation prevents unintended selection cycling

## [1.0.1] - 2025-01-18

### Fixed
- Launcher apps automatically excluded from space indicators
  - Apps in `launcherApps` config no longer appear in space indicators
  - Uses `CFBundleName` for accurate app name matching (e.g., iTerm2)
- Space indicator highlight now works correctly with launcher apps
  - Focus on excluded launcher apps still highlights the correct space
  - Finder focus no longer incorrectly highlights space 1

## [1.0.0] - 2025-01-18

### Added
- App launcher button for floating apps in the menu bar
  - Hover-reveal label animation
  - Configurable floating apps via `aegis.json` config file
- Auto-scroll for new spaces created behind the notch

### Changed
- Renamed Music HUD components to Media HUD for clarity
  - Now accurately reflects that it handles all media types (video, audio from any app)
  - Internal naming: MusicInfo → MediaInfo, MusicHUDView → MediaHUDView, etc.
  - Config properties renamed: `showMusicHUD` → `showMediaHUD`, `musicHUDRightPanelMode` → `mediaHUDRightPanelMode`
  - Backward compatible: existing UserDefaults and JSON config keys still work
- Reduced backup polling interval to 60 seconds (event-driven updates are primary)
- Consolidated window sorting logic into shared helper method

### Fixed
- Empty focused spaces now correctly show active/highlighted state
- Space destruction now focuses adjacent space (browser tab-like behavior)
- Fixed brief flash of native macOS menu bar during space transitions
- Fixed jarring double-scroll animation when spaces were destroyed
- Empty space indicators now match height of populated indicators
- Removed unused MediaHUDTapView dead code
- Removed duplicate battery polling
- Removed unused NetworkStatusMonitor code

## [0.8.0] - 2025-01-17

### Added
- JSON config file support at `~/.config/aegis/config.json`
  - Edit settings without rebuilding the app
  - Hot-reload: changes apply automatically when file is saved
  - Partial configs supported: only specify settings you want to change
- Auto-generated `CONFIG_OPTIONS.md` documentation
  - Full reference of all available settings with descriptions
  - Created automatically in config directory on first run
- Starter config file created on first run with common settings

### Fixed
- Space indicator highlight now stays in sync with focus dot
  - Both now derive from window focus state (single source of truth)
  - Previously could desync when space data and window data updated at different times
- Force refresh for critical yabai events (space_changed, window_focused)
  - Bypasses debounce to ensure UI updates immediately
- Synchronous cache writes prevent race conditions in refresh cycle

## [0.7.0] - 2025-01-17

### Added
- Music HUD track info display mode with marquee scrolling
  - Shows song title and artist name in the notch HUD
  - Auto-expands to show full text on track change, collapses after 3 seconds
  - Marquee scrolling for long text that overflows the collapsed width
  - Title and artist scroll independently (only if they overflow)
  - When both overflow, they scroll in sync for visual consistency
  - Tap album art to toggle between visualizer and track info modes
- Energy-efficient marquee animation using 30fps timer (50% energy savings vs 60fps)
- GPU-accelerated text scrolling via `.drawingGroup()` modifier
- App switcher two-finger scroll to cycle through windows
  - Scroll up/down to move selection between windows
  - Works seamlessly with keyboard (Cmd+Tab) and mouse hover
  - Configurable scroll threshold and notched/continuous behavior
- Cmd+scroll to activate app switcher (alternative to Cmd+Tab)
  - Hold Cmd and scroll to open switcher and cycle through windows
  - Release Cmd to confirm selection
  - Opt-in feature disabled by default (enable in settings)
- Bluetooth device exclusion list to prevent HUD for auto-connecting devices
  - Apple Watch excluded by default
  - Configure via `excludedBluetoothDevices` setting

### Changed
- Refactored MusicHUDView with shared font constants for consistency
- App switcher selection now syncs across all input methods (keyboard, mouse, scroll)
- Window icon title expansion is now toggle-based (right-click to expand, right-click again to collapse)
  - No longer auto-collapses after a delay
  - Only one window can be expanded at a time (expanding another collapses the previous)
  - Left-click focuses the window without affecting expansion state
  - Expansion now persists across focus changes and space switches

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
