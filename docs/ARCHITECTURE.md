# Aegis Architecture Overview

**Last Updated**: January 2026
**Version**: v1.0.4 (January 21, 2026)

## Executive Summary

Aegis is a macOS menu bar application that integrates with Yabai window manager to provide:
- Visual workspace/space indicators in the menu bar
- Notch-area HUD for system status (volume, brightness, music, Bluetooth devices, Focus mode, notifications)
- System status display (battery, network, Focus mode, time)
- Window management via drag-drop and gestures

## Architecture Principles

1. **Event-driven**: EventRouter pub/sub decouples services from UI
2. **Split-state architecture**: Per-space ViewModels minimize SwiftUI re-renders
3. **Lightweight animation**: Timer-based interpolation for smooth progress bars
4. **Window lifecycle**: Windows created once at startup, reused throughout session
5. **Configuration-driven**: Centralized AegisConfig singleton for all customization
6. **CALayer rendering**: GPU-accelerated AppKit views bypass SwiftUI overhead

---

## Component Hierarchy

```
Aegis/
├── App/                    # Application entry point
├── Core/                   # Configuration and services
│   ├── Config/            # Centralized settings
│   ├── Models/            # Core data models
│   └── Services/          # Business logic services
├── Components/            # UI components
│   ├── MenuBar/          # Workspace indicator UI
│   ├── Notch/            # Notch HUD system
│   ├── Systemstatus/     # System monitoring UI
│   └── SettingsPanel/    # Settings interface
├── Helpers/              # Shared utilities
└── AegisYabaiIntegration/ # Shell scripts
```

---

## Core Components

### 1. App Layer (`App/`)

#### AegisApp.swift
- SwiftUI app entry point
- Registers AppDelegate for lifecycle management
- Provides Settings window

#### AppDelegate.swift
- **Responsibilities**:
  - Initialize all services (Yabai, SystemInfo, Music)
  - Create EventRouter and inject into services
  - Setup MenuBar and Notch components
  - Subscribe to events and route to UI
  - Request automation permissions

- **Key Methods**:
  - `setupServices()`: Initialize EventRouter, YabaiService, SystemInfoService, MusicService
  - `setupMenuBar()`: Create MenuBarController and connect to services
  - `setupNotchHUD()`: Create NotchHUDController, prepare windows, connect to MenuBar
  - `startEventListening()`: Subscribe to events (spaceChanged, windowsChanged, volumeChanged, etc.)

---

### 2. Core Configuration (`Core/Config/`)

#### AegisConfig.swift (1045 lines)
- **Purpose**: Centralized configuration singleton
- **Scope**: 100+ @Published properties for every UI/behavior setting
- **Categories**:
  - Menu bar layout (height, padding, spacing, corner radii)
  - Space indicators (size, icon display, overflow behavior)
  - Typography (font sizes for labels, values, headers)
  - Animation settings (spring response, damping, durations)
  - System status thresholds (battery levels, WiFi strength)
  - Notch HUD (size, position, progress bar dimensions)
  - Color schemes and opacity values

- **Persistence**: UserDefaults for settings recovery across launches
- **Access Pattern**: All views use `@ObservedObject private var config = AegisConfig.shared`

---

### 3. Core Services (`Core/Services/`)

#### EventRouter.swift (60 lines)
- **Purpose**: Pub/sub event bus decoupling services from UI
- **Events**:
  - `.spaceChanged`: Workspace switched
  - `.windowsChanged`: Window added/removed/moved
  - `.volumeChanged`: System volume adjusted
  - `.brightnessChanged`: Display brightness adjusted
  - `.musicPlaybackChanged`: Music track changed
  - `.deviceConnected` / `.deviceDisconnected`: Bluetooth device state
  - `.focusChanged`: Focus mode enabled/disabled
  - `.notificationReceived`: System notification intercepted

- **API**:
  ```swift
  func publish(_ event: EventType, data: [String: Any])
  func subscribe(to: EventType, handler: @escaping ([String: Any]) -> Void)
  ```

- **Thread Safety**: All handler calls dispatched to main thread

#### YabaiService.swift (500 lines)
- **Purpose**: Interface to Yabai window manager
- **Responsibilities**:
  1. **Query spaces and windows**: `getSpaces()`, `getWindowsOnSpace()`
  2. **Execute commands**: Focus, move, create, destroy spaces/windows
  3. **Monitor Yabai events**: Listen to FIFO pipe for real-time updates
  4. **Provide window icons**: Lookup app bundle identifiers for icons

- **Event Monitoring**:
  - Reads from Yabai's FIFO pipe (configured in yabairc)
  - Parses JSON events (space_changed, window_created, etc.)
  - Publishes via EventRouter

- **Command Execution**: Uses `YabaiCommandActor` for async shell commands

#### SystemInfoService.swift (291 lines)
- **Purpose**: Monitor hardware state (volume, brightness, battery)
- **Components**:
  - **Volume**: CoreAudio API for system volume and mute state
  - **Brightness**: Private DisplayServices API via Objective-C helper (`Brightness/`)
  - **Battery**: IOKit for battery level, charging state, time remaining

- **Event Sources**:
  - Volume: Event-driven (CoreAudio property listener)
  - Brightness: Event-driven (DisplayServices callback registration)
  - Battery: Polled every 10s

- **Events Published**: `.volumeChanged`, `.brightnessChanged`

#### BluetoothDeviceService.swift
- **Purpose**: Monitor Bluetooth device connections/disconnections
- **Capabilities**:
  - Detect device connect/disconnect events via IOBluetooth
  - Identify device types (AirPods, AirPods Pro, AirPods Max, Beats, keyboards, mice, etc.)
  - Fetch battery levels via system_profiler
  - Debounce rapid connect/disconnect events

- **Implementation**:
  - Registers for IOBluetooth notifications
  - Maps device names to types with appropriate SF Symbols
  - Handles battery key variations (device_batteryLevel, device_batteryLevelLeft, etc.)
  - Ignores spurious reconnect notifications within 2s of disconnect

- **Events Published**: `.deviceConnected`, `.deviceDisconnected`

#### MediaService.swift (280 lines)
- **Purpose**: Monitor system-wide now-playing information from ALL media sources
- **Capabilities**:
  - Query current track (title, artist, album) from any app
  - Fetch album artwork (base64-encoded from MediaRemote)
  - Detect playback state (playing/paused)
  - Control playback (play, pause, next, previous)
  - Works with Music, Spotify, Safari, Chrome, Firefox, YouTube, video players, etc.

- **Implementation**:
  - Uses `mediaremote-adapter` (Perl script + MediaRemote framework)
  - Event-driven via continuous JSON stream (not polling)
  - 50ms debounce on stream to reduce CPU during rapid updates
  - Album art cached per-track with LRU eviction (max 10 entries)

- **Events Published**: `.mediaPlaybackChanged`

#### NotificationService.swift
- **Purpose**: Intercept macOS system notifications via Accessibility API
- **Capabilities**:
  - Detect notification banners from any app
  - Extract notification content (app name, title, body)
  - Dismiss native banners to replace with custom HUD
  - Identify source app via bundle identifier lookup

- **Implementation**:
  - Uses `AXObserver` to watch `com.apple.notificationcenterui` process
  - Listens for `kAXWindowCreatedNotification` events (event-driven, zero idle CPU)
  - Traverses AX hierarchy to find `AXNotificationCenterBanner` elements
  - Parses banner description attribute for app name, title, body
  - Dismisses native banner via AX "Close" action
  - Runs on background thread with CFRunLoop

- **Dismissal Optimization**:
  - Dismisses banner BEFORE content extraction to minimize visible flash
  - Some flash (~50-150ms) is unavoidable due to macOS architecture limitation
  - AX events fire AFTER notification is already rendered

- **Bundle ID Resolution**:
  - Hardcoded lookup table for common apps (Messages, WhatsApp, Slack, etc.)
  - Case-insensitive matching against running applications
  - Partial match fallback for locale differences

- **Events Published**: `.notificationReceived`
- **Permissions Required**: Accessibility (already needed for Yabai)

#### AppSwitcherService.swift (612 lines)
- **Purpose**: Custom Cmd+Tab window switcher with space-aware organization
- **Capabilities**:
  - Intercept Cmd+Tab via CGEvent tap
  - Display windows organized by space in a centered overlay
  - Multiple input methods: keyboard, mouse hover, two-finger scroll
  - Type-to-filter search while switcher is active
  - Focus any window via Yabai commands

- **Event Tap**:
  - Captures keyDown, keyUp, flagsChanged, leftMouseDown
  - Intercepts Cmd+Tab to activate switcher
  - Handles Escape to cancel, arrow keys to navigate
  - Cmd+1-9 for direct window selection

- **Input Methods**:
  - **Keyboard**: Cmd+Tab/Cmd+Shift+Tab cycles, Cmd+1-9 direct select
  - **Mouse**: Hover highlights, click confirms selection
  - **Scroll**: Two-finger scroll cycles with configurable threshold/notched behavior

- **Components**:
  - `AppSwitcherWindowController`: Manages overlay NSPanel
  - `AppSwitcherViewModel`: Published state for SwiftUI views
  - `MouseTrackingNSView`: Efficient mouse/scroll event handling

- **Models**:
  - `SpaceGroup`: Windows grouped by space index
  - `SwitcherWindow`: Window info with icon, state (minimized/hidden)

---

### 4. MenuBar Component (`Components/MenuBar/`)

**Purpose**: Display Yabai workspaces as interactive indicators in menu bar

#### Architecture Pattern
```
MenuBarController (Facade)
    ↓
MenuBarCoordinator (Orchestrator)
    ↓ creates
MenuBarWindowController (Window management)
MenuBarViewModel (State)
MenuBarInteractionMonitor (Native menu bar tracking)
    ↓ renders
SpaceIndicatorView (UI)
```

#### MenuBarCoordinator.swift
- **Central orchestrator** for menu bar component
- **Responsibilities**:
  - Create and manage window, view model, and interactions
  - Route user actions to YabaiService
  - Subscribe to EventRouter events (spaceChanged, windowsChanged)
  - Update spaces and windows on events
  - Handle native macOS menu bar conflicts (hide when system menu bar active)

- **Key Methods**:
  - `show()`: Initialize and display menu bar
  - `updateSpaces()`: Query Yabai and refresh space list
  - `updateWindows()`: Query Yabai for windows on each space
  - `handleSpaceClick()`, `handleWindowClick()`, etc.

#### MenuBarController.swift
- **Facade** for backward compatibility
- Delegates all calls to `MenuBarCoordinator`
- Public interface used by `AppDelegate`

#### MenuBarViewModel.swift
- **State management** for menu bar UI using split-state architecture
- **Components**:
  - `SpaceViewModelStore`: Manages collection of per-space ViewModels
  - `SharedMenuBarState`: Cross-space coordination (drag, expansion, HUD)
  - Private caches for raw spaces, window icons, focused indices

- **Split-State Architecture**:
  - Each `SpaceViewModel` is observed only by its own `SpaceIndicatorView`
  - Changes to one space don't trigger re-renders of other spaces
  - Reduces CPU usage by ~95% during focus changes

- **Fallback Polling**: Updates every 60s as safety net (event-driven is primary)
- **Icon Management**: Async loading of app icons with caching

#### MenuBarWindowController.swift
- **Window lifecycle management**
- Creates borderless NSWindow at top of screen
- Handles window positioning and z-ordering
- Manages visibility and interaction

#### SpaceIndicatorView.swift (776 lines)
- **Main UI view** for individual workspace display
- **Layout**:
  - Space number/label
  - Grid of window icons (up to `maxDisplayedIcons`)
  - Overflow menu ("..." button) for additional windows
  - Stack badge indicators

- **Interactions**:
  - Click space: Focus that workspace
  - Click window: Focus that window
  - Right-click window: Expand to show title
  - Drag window: Move to different space (via SpaceDropController)
  - Swipe-to-destroy: Delete space (via SwipeableSpaceContainer)

- **Visual States**:
  - Active space: Highlighted background
  - Focused window: Blue accent
  - Hidden windows: Dimmed opacity
  - Stack indicators: Badge count

#### Supporting Views
- **SpaceIndicatorViewContainer.swift**: Isolates per-space re-renders via @ObservedObject
- **AppKitActionButton.swift**: CALayer-based buttons (context menu, app launcher)
  - GPU-accelerated rendering bypasses SwiftUI overhead
  - Scroll throttling at 20fps max to reduce CPU
- **SpaceStyleView.swift**: Visual styling helpers

#### Split-State Components
- **SpaceViewModel.swift**: Per-space observable state (space data, window icons, focus)
- **SpaceViewModelStore.swift**: Manages SpaceViewModel lifecycle, routes updates
- **SharedMenuBarState.swift**: Shared state for drag/expansion/HUD coordination

#### Interaction Handlers
- **SpaceDropController.swift**: Drag-drop delegate for moving windows
- **SwipeableSpaceContainer.swift**: Swipe gesture for space destruction
- **MenuBarInteractionMonitor.swift**: Track native macOS menu bar state
- **SwipeDetectorView.swift**: Scroll event handling with 50ms throttle

---

### 5. Notch HUD Component (`Components/Notch/`)

**Purpose**: Display system notifications (volume, brightness, music, Bluetooth devices, Focus mode, app notifications) at notch location

#### Architecture Pattern
```
NotchHUDController (Window + visibility management)
    ↓ owns
OverlayHUDViewModel (Volume/brightness state)
    ↓ contains
ProgressBarAnimator (Frame-locked interpolation)
    ↓ renders
MinimalHUDWrapper (UI)

NotchHUDController
    ↓ owns
MusicHUDViewModel (Music state)
    ↓ renders
MusicHUDView (UI)

NotchHUDController
    ↓ owns
DeviceHUDViewModel (Bluetooth device state)
    ↓ renders
DeviceHUDView (UI)

NotchHUDController
    ↓ owns
FocusHUDViewModel (Focus mode state)
    ↓ renders
FocusHUDView (UI)

NotchHUDController
    ↓ owns
NotificationHUDViewModel (Notification state)
    ↓ renders
NotificationHUDView (UI)
```

#### NotchHUDController.swift
- **Responsibilities**:
  - Create and manage overlay and music windows
  - Handle visibility and auto-hide logic
  - Route events from EventRouter to ViewModels
  - Coordinate with MenuBar for visibility toggling

- **Window Management**:
  - `prepareWindows()`: Called at app startup to create windows once
  - Windows created with `isReleasedWhenClosed = false` for reuse
  - Ordered front but invisible initially (alpha = 0)
  - Force layout pass to prevent first-show jank

- **Overlay HUD Methods**:
  - `showVolume(level:isMuted:)`: Update animator target, show if hidden
  - `showBrightness(level:)`: Update animator target, show if hidden
  - `bumpHideDeadline()`: Extend auto-hide timer
  - `hideOverlayHUD()`: Animate out and hide window

- **Media HUD Methods**:
  - `showMedia(info:)`: Update media view with track info
  - `hideMediaHUD()`: Hide media display

- **Auto-hide Logic**:
  - Timestamp-based deadline (not timer recreation)
  - Single polling timer checks deadline every 0.1s
  - Timer only created once when showing, invalidated when hiding

#### OverlayHUDViewModel.swift
- **Persistent state** for volume/brightness HUD
- **Properties**:
  - `@Published var isVisible: Bool`: Drives slide-in animation
  - `@Published var level: Float`: Current value (only updated on first show)
  - `@Published var isMuted: Bool`: Mute state
  - `@Published var iconName: String`: Icon to display
  - `let progressAnimator: ProgressBarAnimator`: Frame-locked animator instance

- **Why Persistent**: Survives view rebuilds, prevents animation restarts

#### ProgressBarAnimator.swift (142 lines)
- **Lightweight timer-based interpolation** for smooth progress bar
- **Implementation**:
  - Uses `DispatchSourceTimer` on main queue at 60fps (~16ms interval)
  - Timer starts on-demand when animation needed, stops when settled
  - Exponential ease-out: `displayed += (target - displayed) * 0.35`
  - Auto-stops when within 0.5% of target to save energy

- **API**:
  - `setTarget(_ value: Double)`: Update target (called from controller)
  - `start()` / `stop()`: Called when HUD shows/hides
  - `@Published displayed: Double`: Actual displayed value (observed by view)

- **Performance**:
  - ~1-2% CPU during animation (vs 10-15% with CVDisplayLink)
  - Zero CPU when animation settled (timer stops)
  - Snap-to-target on first show after hide (no stale state)

#### MinimalHUDWrapper.swift (160+ lines)
- **UI view** for volume/brightness HUD
- **Layout**:
  - Left side: Icon (slides from under notch)
  - Center: Notch spacer (transparent)
  - Right side: Progress bar or numeric value (slides from under notch)

- **Animation**:
  - Slide-in from under notch (offset by `notchWidth/2`)
  - Spring animation (0.25s response, 0.8 damping)
  - Only animates when expanding, not collapsing

- **HUDProgressBar**:
  - Observes `animator.displayed` directly
  - Disables SwiftUI animation (`.animation(nil)`)
  - Freezes layout during updates (`.transaction`)
  - Width calculated as `barWidth * CGFloat(animator.displayed)`

#### MediaHUDViewModel.swift
- **Persistent state** for media HUD
- **Properties**:
  - `@Published var isVisible: Bool`: Drives animation
  - `@Published var info: MediaInfo`: Current track info
  - `@Published var isOverlayActive: Bool`: Whether overlay HUDs (volume/brightness/device/focus/notification) are showing
  - `overlayCount: Int`: Counter for active overlays (prevents race conditions with async hide timers)
- **Overlay Counter Pattern**:
  - `overlayDidShow()`: Increments counter when any overlay HUD shows
  - `overlayDidHide()`: Decrements counter when any overlay HUD hides
  - `resetOverlayState()`: Safety valve to reset counter if it gets stuck
  - Right panel hides when `isOverlayActive == true` to avoid overlap with overlays

#### MediaHUDView.swift
- **UI view** for media playback display (works with all media sources)
- **Layout**:
  - Left: Album art with scale/opacity animation
  - Right: Either media visualizer OR track info (configurable via `mediaHUDRightPanelMode`)

- **Right Panel Modes**:
  - **Visualizer mode** (default): 5 animated capsule bars with randomized heights
  - **Track Info mode**: Song title and artist with marquee scrolling for long text

- **Visualizer**:
  - 5 capsule bars with randomized heights
  - Updates every 0.2s when playing
  - Resets to flat bars when paused
  - Optional blur effect (shows wallpaper through bars)

- **Track Info Display** (TrackInfoView):
  - Shows song title and artist name
  - Auto-expands width on track change to show full text
  - Collapses after 3 seconds to standard width
  - **Marquee scrolling** for text that overflows collapsed width:
    - Title and artist scroll independently (each only if it overflows)
    - When both overflow, they scroll in sync at same speed
    - Energy-efficient 30fps timer-based animation (not 60fps SwiftUI animation)
    - GPU-accelerated via `.drawingGroup()` modifier
  - Tap album art to toggle between visualizer and track info modes

- **MarqueeScrollController**:
  - State machine with phases: idle → initialDelay → scrolling → endPause → resetPause
  - Uses `CACurrentMediaTime()` for accurate timing
  - 30fps `Timer` for energy efficiency (half the energy of 60fps)
  - Configurable scroll speed (30 points/second), delays, and gap between text copies

#### DeviceHUDView.swift
- **UI view** for Bluetooth device connection notifications
- **Layout**:
  - Left: Device type icon (AirPods, headphones, keyboard, etc.)
  - Right: Device type name, connection status, battery ring indicator

- **Components**:
  - `DeviceHUDViewModel`: Holds device info, connection state, visibility
  - `BatteryRingView`: Circular progress ring showing battery level (color-coded: green/orange/red)

- **Device Types Supported**:
  - AirPods, AirPods Pro, AirPods Max
  - Beats headphones, generic headphones
  - Speakers, keyboards, mice, trackpads

#### FocusHUDView.swift
- **UI view** for Focus mode change notifications
- **Layout**:
  - Left: Focus mode icon (SF Symbol from user's Focus configuration)
  - Right: Focus name and On/Off status

- **Components**:
  - `FocusHUDViewModel`: Holds focus status, visibility
  - Shows actual Focus mode name (e.g., "Study", "Work", "Do Not Disturb")
  - Purple status color when enabled, gray when disabled
  - When disabling, shows which mode was turned off (e.g., "Study / Off")

#### NotificationHUDView.swift
- **UI view** for system notification display
- **Layout**:
  - Left: App icon (from bundle identifier or app name lookup)
  - Right: Notification title and body text

- **Components**:
  - `NotificationHUDViewModel`: Holds app name, title, body, app icon, visibility
  - Dynamic width calculation based on text content
  - `openAppHandler` callback for Yabai integration

- **Interaction**:
  - Click anywhere on HUD focuses/opens the source application
  - Uses Yabai `focusWindowByAppName()` first (respects window layout)
  - Falls back to `NSWorkspace.launchApplication()` if no window found
  - Auto-hide after configurable delay (default 8s)

#### HUDShapes.swift
- **Shared panel shapes** for all HUD views
- **Shapes**:
  - `HUDLeftPanelShape`: Curved outer edges, inner edge curves outward to connect with notch
  - `HUDRightPanelShape`: Mirror of left panel shape
- **Used by**: MediaHUDView, MinimalHUDWrapper, DeviceHUDView, FocusHUDView, NotificationHUDView

#### NotchDimensions.swift
- **Calculates notch geometry** from screen properties
- Uses `NSScreen.safeAreaInsets.top` for height
- Uses `auxiliaryTopLeftArea` and `auxiliaryTopRightArea` for width
- Provides padding constants for content positioning

---

### 6. System Status Component (`Components/Systemstatus/`)

**Purpose**: Display system information in menu bar

#### Architecture
```
SystemStatusMonitor (Aggregates all status)
    ↓
BatteryStatusMonitor (Battery specific)
NetworkStatus (Network model)
FocusStatusMonitor (Focus mode)
    ↓
SystemStatusView (Container)
    ↓
Individual icon views (Battery, Network, Focus, Clock, Date)
```

#### SystemStatusMonitor.swift
- Aggregates battery, network, and other system state
- Publishes updates for UI consumption

#### BatteryStatusMonitor.swift
- Uses IOKit to query battery status
- Tracks level, charging state, time remaining

#### FocusStatusMonitor.swift
- **Purpose**: Monitor macOS Focus mode status
- **Implementation**:
  - Watches `~/Library/DoNotDisturb/DB/` directory for file changes
  - Parses `Assertions.json` to detect active Focus mode
  - Reads `ModeConfigurations.json` for mode names and SF Symbols
  - Supports all built-in modes (Do Not Disturb, Work, Personal, Sleep, etc.)
  - Supports custom Focus modes with their user-defined symbols

- **Events Published**: `.focusChanged`
- **State Tracking**: Remembers last active Focus mode to show "Study / Off" when disabling

#### Views
- **SystemStatusView.swift**: Container orchestrator
- **BatteryStatusIconView.swift**: Battery icon with level indicator
- **NetworkStatusIconView.swift**: WiFi/Ethernet status icon
- **FocusStatusIconView.swift**: Focus mode icon (animated slide in/out)
- **ClockView.swift**: Current time display
- **DateView.swift**: Current date display

---

### 7. Settings Panel (`Components/SettingsPanel/`)

**Purpose**: User preferences interface

#### SettingsPanelController.swift
- Manages settings window lifecycle
- Shows/hides panel on demand

#### SettingsPanelView.swift (25,965 bytes)
- **Large monolithic view** with all settings
- **Categories**:
  - Menu bar appearance
  - Space indicators
  - Notch HUD
  - System status
  - Battery/network thresholds
  - Animation settings

- **Note**: Could be split into focused sub-views for better organization

#### SettingsHelpers.swift (11,241 bytes)
- Utility functions for settings UI
- Formatters, validators, converters

---

## Data Flow Diagrams

### Volume/Brightness HUD Flow
```
User presses volume key
    ↓
SystemInfoService detects change (CoreAudio listener)
    ↓
EventRouter.publish(.volumeChanged, level: 0.75)
    ↓
AppDelegate subscription fires
    ↓
NotchHUDController.showVolume(level: 0.75)
    ↓
overlayViewModel.progressAnimator.setTarget(0.75)  [BYPASS ViewModel]
    ↓
DispatchSourceTimer ticks at 60fps (~16ms)
    ↓
ProgressBarAnimator.tick() interpolates: displayed += (0.75 - displayed) * 0.35
    ↓
@Published displayed updates
    ↓
MinimalHUDWrapper observes animator.displayed
    ↓
SwiftUI re-renders progress bar with new width
    ↓
Timer auto-stops when displayed is within 0.5% of target
```

**Key Optimization**: Controller directly updates animator target, bypassing ViewModel to avoid SwiftUI re-render storm during rapid input. Timer-based animation uses ~1-2% CPU vs 10-15% with CVDisplayLink.

### Space Change Flow
```
User switches space (Yabai command)
    ↓
Yabai writes event to FIFO pipe
    ↓
YabaiService reads pipe, parses JSON
    ↓
EventRouter.publish(.spaceChanged)
    ↓
MenuBarCoordinator subscription fires
    ↓
MenuBarCoordinator.updateSpaces()
    ↓
YabaiService.getSpaces() queries Yabai
    ↓
MenuBarViewModel.spaces updated
    ↓
SpaceIndicatorView re-renders with new active state
```

### Window Management Flow
```
User drags window icon to different space
    ↓
SpaceDropController.performDrop()
    ↓
MenuBarCoordinator.handleWindowDrop()
    ↓
YabaiService.moveWindowToSpace()
    ↓
YabaiCommandActor executes: yabai -m window 123 --space 2
    ↓
Yabai moves window, writes event to pipe
    ↓
YabaiService detects window_moved event
    ↓
EventRouter.publish(.windowsChanged)
    ↓
MenuBarCoordinator updates windows on both spaces
```

### Bluetooth Device HUD Flow
```
User connects AirPods
    ↓
IOBluetooth notification fires
    ↓
BluetoothDeviceService.deviceConnected()
    ↓
Identify device type from name (e.g., "AirPods Pro")
    ↓
Fetch battery level via system_profiler (async)
    ↓
EventRouter.publish(.deviceConnected, deviceInfo)
    ↓
AppDelegate subscription fires
    ↓
NotchHUDController.showDevice(info:isConnecting:)
    ↓
DeviceHUDView displays: icon + name + "Connected" + battery ring
    ↓
Auto-hide after 1.5s
```

### Focus Mode HUD Flow
```
User enables Focus mode in Control Center
    ↓
macOS writes to ~/Library/DoNotDisturb/DB/Assertions.json
    ↓
FocusStatusMonitor detects directory change (DispatchSource)
    ↓
Parse Assertions.json for active mode identifier
    ↓
Lookup mode name and symbol from ModeConfigurations.json
    ↓
EventRouter.publish(.focusChanged, status)
    ↓
AppDelegate subscription fires
    ↓
NotchHUDController.showFocus(status:)
    ↓
FocusHUDView displays: icon + "Study" + "On" (purple)
    ↓
Auto-hide after 1.5s
```

### System Notification HUD Flow
```
App sends notification (e.g., Messages receives SMS)
    ↓
macOS creates notification banner window
    ↓
AXObserver receives kAXWindowCreatedNotification (background thread)
    ↓
NotificationService.handleNotificationWindow()
    ↓
IMMEDIATELY dismiss native banner via AX "Close" action  [OPTIMIZATION]
    ↓
Extract content from AXNotificationCenterBanner description
    ↓
Lookup bundle identifier (hardcoded table → running apps → partial match)
    ↓
EventRouter.publish(.notificationReceived, data)
    ↓
AppDelegate subscription fires (main thread)
    ↓
NotchHUDController.showNotification(...)
    ↓
NotificationHUDView displays: app icon + title + body
    ↓
Auto-hide after 8s (or tap to open source app)
```

**Key Limitation**: Native banner flashes briefly (~50-150ms) before dismissal. This is unavoidable - macOS renders the notification before firing the AX event. No public API exists to intercept notifications before display.

---

## Performance Optimizations

### 1. Lightweight Timer-Based Animation (ProgressBarAnimator)
**Problem**: SwiftUI animations lag during rapid input (15+ events/sec)
**Solution**: DispatchSourceTimer provides smooth interpolation with minimal CPU overhead

**Key Techniques**:
- DispatchSourceTimer on main queue at 60fps (~16ms interval)
- Timer starts on-demand when animation needed, auto-stops when settled
- Exponential ease-out: `displayed += (target - displayed) * 0.35`
- Auto-stops when within 0.5% of target (zero CPU when idle)
- Bypass ViewModel updates during rapid input (only update animator target)
- Disable SwiftUI animation (`.animation(nil)`)
- ~1-2% CPU during animation vs 10-15% with CVDisplayLink

### 2. Window Lifecycle Management
**Problem**: Creating windows during interaction causes stutters
**Solution**: Prepare windows at app startup, reuse throughout session

**Key Techniques**:
- `isReleasedWhenClosed = false` to prevent deallocation
- Order front but invisible (alpha = 0) for proper initialization
- Force layout pass with `layoutIfNeeded()` before first show
- Never destroy windows, just hide and reshow

### 3. Event-Driven Architecture
**Problem**: Polling Yabai every frame is expensive
**Solution**: Yabai FIFO pipe provides real-time events, poll only as fallback

**Key Techniques**:
- FIFO pipe monitoring in background thread
- EventRouter decouples services from UI (no direct dependencies)
- All handler calls dispatched to main thread for UI updates
- Fallback polling every 60s if pipe not available

### 4. Persistent ViewModels
**Problem**: View rebuilds restart animations
**Solution**: Hoist ViewModels above view hierarchy, survive rebuilds

**Key Techniques**:
- ViewModels owned by controllers, not views
- Bindings passed down to views
- `ProgressBarAnimator` instance persists in ViewModel
- State survives SwiftUI view invalidation

### 5. Async Icon Loading
**Problem**: Loading app icons blocks UI
**Solution**: Async fetch with caching, show placeholder immediately

**Key Techniques**:
- Icons loaded in background queue
- Published updates trigger UI refresh when ready
- Icon cache prevents repeated disk access
- Placeholder shown while loading

---

## Configuration Categories (AegisConfig)

### Menu Bar Layout
- Height, padding, spacing, corner radii
- Background opacity and blur
- Divider spacing between spaces

### Space Indicators
- Circle size, icon size, overflow button size
- Max displayed icons before overflow
- Grid layout (rows, columns, spacing)
- Stack badge position and size

### Typography
- Font sizes for space labels, window titles, system status
- Font weights (regular, semibold, bold)

### Animation Settings
- Spring response (0.3s typical)
- Spring damping (0.7-0.8 typical)
- Fade durations (0.2-0.5s)
- Slide offsets

### System Status Thresholds
- Battery low level (20%)
- Battery critical level (10%)
- WiFi strength thresholds (good/fair/poor)

### Notch HUD
- Width, height, corner radius
- Icon size, value font size
- Progress bar dimensions (width, height)
- Animation timings
- Auto-hide delay (1.5s)

### Colors and Opacity
- Background opacity (0.9 typical)
- Icon opacity states (active, inactive, dimmed)
- Accent colors (system accent or custom)

---

## File Organization Best Practices

### Established Patterns
1. **Controllers** manage window lifecycle and visibility
2. **Coordinators** orchestrate component initialization and interactions
3. **ViewModels** hold persistent state with @Published properties
4. **Views** are stateless SwiftUI views observing ViewModels
5. **Services** handle business logic and external integrations
6. **Models** are simple data structures (structs with Codable/Identifiable)

### Directory Structure
```
Component/
├── Controllers/       # Window and lifecycle management
├── Coordinators/      # Orchestration and routing
├── ViewModels/        # Persistent state with @Published
├── Views/             # SwiftUI views (stateless)
├── Models/            # Data structures
├── Interaction/       # Gesture and input handlers
└── Helpers/           # Component-specific utilities
```

### Naming Conventions
- Controllers: `*Controller.swift` (lifecycle, window management)
- Coordinators: `*Coordinator.swift` (orchestration)
- ViewModels: `*ViewModel.swift` (state management)
- Views: `*View.swift` (UI rendering)
- Services: `*Service.swift` (business logic)
- Models: Noun without suffix (e.g., `Space.swift`, `MusicInfo.swift`)

---

## External Integrations

### Yabai Window Manager
- **Communication**: Shell commands via `Process` (async with YabaiCommandActor)
- **Event Monitoring**: FIFO pipe at `/tmp/yabai_$USER.socket`
- **Setup**: User configures yabairc to write events to pipe
- **Commands**: Focus, move, create, destroy spaces/windows; query state

### Media Sources (via MediaRemote)
- **Communication**: MediaRemote framework via mediaremote-adapter
- **Sources**: Music.app, Spotify, Safari, Chrome, Firefox, YouTube, video players, etc.
- **Queries**: Current track (title, artist, album), playback state, bundle identifier
- **Artwork**: Fetched asynchronously, cached per-track (LRU, max 10 entries)
- **Event-driven**: Continuous JSON stream via mediaremote-adapter (50ms debounce)

### System APIs
- **CoreAudio**: Volume level and mute state (event-driven)
- **IOKit**: Battery status (polled every 10s)
- **IOBluetooth**: Device connection/disconnection notifications
- **Private API**: Brightness monitoring via Objective-C helper
- **AppKit**: Window management, screen geometry, workspace integration
- **DispatchSource**: File system monitoring for Focus mode changes

---

## Testing and Debugging

### Debug Utilities
- Console logs with emoji prefixes (🚀 launch, 🔆 brightness, 🪟 window, etc.)
- Frame-time logging for performance analysis
- Yabai command output capture

### Common Issues
1. **Animation lag**: Check CVDisplayLink is running, verify no SwiftUI render storm
2. **HUD not showing**: Check window preparation at startup, verify alpha value
3. **Spaces not updating**: Check Yabai FIFO pipe, verify yabairc configuration
4. **Music not displaying**: Check Music.app permissions, verify osascript access

### Performance Profiling
- Use Instruments (Time Profiler) to identify bottlenecks
- Monitor main thread for blocking operations
- Check CVDisplayLink callback frequency

---

## Future Improvements

### Architecture
1. **Dependency Injection**: Replace `AegisConfig.shared` with injected dependencies
2. **Protocol-Oriented Design**: Define protocols for services, enable mocking for tests
3. **Split Large Files**: Break SettingsPanelView into focused sub-views

### Features
1. **Music Visualizers**: Implement audio spectrum analyzer (empty `/Visualisers/` directory)
2. **Persistent Layouts**: Save window positions per space
3. **Keyboard Shortcuts**: Global hotkeys for window management

### Performance
1. **Icon Caching**: Use NSCache for memory-managed icon storage
2. **Event Debouncing**: Consolidate rapid events (e.g., multiple window moves)
3. **Lazy Loading**: Defer icon loading for off-screen spaces

---

## Critical Code Patterns

### Bypass Pattern (Avoid Re-render Storm)
```swift
// ❌ BAD: Updates ViewModel on every event (triggers SwiftUI re-renders)
func showBrightness(level: Float) {
    overlayViewModel.level = level  // @Published property
    overlayViewModel.progressAnimator.setTarget(Double(level))
}

// ✅ GOOD: Bypass ViewModel, update animator directly
func showBrightness(level: Float) {
    overlayViewModel.progressAnimator.setTarget(Double(level))

    if !overlayViewModel.isVisible {
        overlayViewModel.level = level  // Only update on first show
        showOverlayHUD()
    }

    bumpHideDeadline()
}
```

### Lightweight Timer Interpolation
```swift
// DispatchSourceTimer for smooth progress bar animation
private func startTimer() {
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now(), repeating: .milliseconds(16))  // ~60fps
    timer.setEventHandler { [weak self] in
        self?.tick()
    }
    timer.resume()
    self.timer = timer
}

private func tick() {
    let delta = target - displayed
    if abs(delta) < snapThreshold {
        displayed = target
        stopTimer()  // Auto-stop when settled
        return
    }
    // Exponential ease-out
    displayed += delta * interpolationSpeed  // 0.35
}
```

### Window Preparation (Prevent First-Show Jank)
```swift
func prepareWindows() {
    // Create window ONCE at startup
    overlayWindow = NSWindow(...)
    overlayWindow.isReleasedWhenClosed = false

    // Order front immediately but invisible
    overlayWindow.orderFront(nil)
    overlayWindow.alphaValue = 0

    // Force initial layout pass
    overlayWindow.layoutIfNeeded()
}
```

---

## Appendix: File Count by Component

| Component | Files | Total Lines (approx) |
|-----------|-------|----------------------|
| App | 2 | 200 |
| Core/Config | 1 | 1,045 |
| Core/Services | 6 | 1,600 |
| MenuBar | 13 | 2,500 |
| Notch | 12 | 1,200 |
| SystemPanel | 12 | 900 |
| SettingsPanel | 3 | 1,500 |
| **Total** | **49** | **~8,945** |

---

## Quick Reference: Key Files

| File | Purpose | Lines |
|------|---------|-------|
| `AppDelegate.swift` | App initialization, service setup, event routing | 160 |
| `AegisConfig.swift` | Centralized configuration singleton | 1,045 |
| `EventRouter.swift` | Pub/sub event bus | 60 |
| `YabaiService.swift` | Yabai WM integration, window focus by app name | 530 |
| `BluetoothDeviceService.swift` | Bluetooth device monitoring | 400 |
| `NotificationService.swift` | System notification interception | 440 |
| `AppSwitcherService.swift` | Custom Cmd+Tab window switcher | 612 |
| `MenuBarCoordinator.swift` | Menu bar orchestration | 400+ |
| `SpaceIndicatorView.swift` | Workspace UI display | 776 |
| `NotchHUDController.swift` | Notch HUD window management, Yabai app focus | 350 |
| `NotchHUDViewModel.swift` | HUD state management, overlay counter | 150 |
| `ProgressBarAnimator.swift` | Lightweight timer interpolation | 142 |
| `HUDShapes.swift` | Shared panel shapes for all HUDs | 100 |
| `MinimalHUDWrapper.swift` | Volume/brightness UI | 255 |
| `MediaHUDView.swift` | Now Playing UI | 800+ |
| `DeviceHUDView.swift` | Bluetooth device connection UI | 165 |
| `FocusHUDView.swift` | Focus mode change UI | 142 |
| `NotificationHUDView.swift` | System notification UI | 142 |
| `FocusStatusMonitor.swift` | Focus mode detection | 200 |

---

**End of Architecture Document**
