# Aegis Window Manager Support Matrix

## Supported Window Managers

| WM | Status | Workspace Model | Event System |
|---|---|---|---|
| **Yabai** | Full support | macOS native spaces | FIFO pipe (yabai signals) |
| **Rift** | Full support | Virtual workspaces | Mach subscription |
| **Paneru** | Basic support | Virtual workspace rows (per native Space) | NDJSON subscription (`paneru subscribe --json`) |
| **AeroSpace** | Full support | Virtual workspaces (string-named) | FIFO pipe (`exec-on-workspace-change`) + NSWorkspace |

## Feature Matrix

### Space / Workspace Management

| Feature | Yabai | Rift | AeroSpace |
|---|---|---|---|
| Display spaces | macOS native spaces | Rift virtual workspaces | Virtual workspaces 1-9 |
| Window icons per space | Yes | Yes (cached for inactive) | Yes |
| Click to switch space | Yes | Yes | Yes |
| Drag reorder spaces | Yes | No | No |
| New space | Yes | Yes | Yes (focus first empty workspace) |
| Destroy space | Yes | No | No (virtual — disappear when empty) |

### Window Actions

| Feature | Yabai | Rift | AeroSpace |
|---|---|---|---|
| Click to focus window | Yes (by window ID) | Yes (AXUIElement) | Yes (by window ID) |
| Drag window between spaces | Yes | Yes (focus-first, then move) | No |
| Focus next / previous | Yes | Yes | Yes (`focus right/left`) |
| Focus monitor next/prev | No | No | Yes (`focus-monitor`) |
| Swap left / right | Yes (`--swap`) | Yes (`move-node`) | Yes (`move`) |
| Move window N/S/E/W | Yes (`--warp`) | Yes (`move-node`) | Yes (`move`) |
| Join with direction | No | No | Yes (`join-with`) |
| Send to space | Yes | Yes | Yes (workspaces 1-9) |
| Send to monitor | No | No | Yes (`move-node-to-monitor`) |
| Toggle float | Yes | Yes | Yes (`layout floating tiling`) |
| Toggle fullscreen | Yes | Yes | Yes (`fullscreen`) |
| Native fullscreen | No | No | Yes (`macos-native-fullscreen`) |
| Minimize | No | No | Yes (`macos-native-minimize`) |
| Close window | No | No | Yes (`close`) |
| Close all but current | No | No | Yes (`close-all-windows-but-current`) |
| Resize (grow/shrink) | No | No | Yes (`resize smart`) |

### Layout

| Feature | Yabai | Rift | AeroSpace |
|---|---|---|---|
| Set layout | BSP, Float, Stack | Traditional, BSP, Stack, Master-Stack, Scrolling | Tiling, Accordion, Floating |
| Toggle layout | Yes | Yes | Yes |
| Toggle orientation | No | No | Yes (`layout horizontal vertical`) |
| Rotate 90/180/270 | Yes | No | No |
| Flip horizontal/vertical | Yes | No | No |
| Balance | Yes | No | Yes (`balance-sizes`) |
| Flatten workspace tree | No | No | Yes (`flatten-workspace-tree`) |
| Last workspace toggle | No | No | Yes (`workspace-back-and-forth`) |

### Stacking

| Feature | Yabai | Rift | AeroSpace |
|---|---|---|---|
| Stack window onto another | Yes (by ID) | No | No |
| Stack all windows | Yes | No | No |
| Unstack windows | Yes | No | No |
| Stack/Unstack toggle | Yes | No | No |

> Rift has direction-based stacking (`join-window <dir>`, `toggle-stack`, `unjoin`) but doesn't support per-window stack-by-ID which is what the Aegis UI requires. Can be added in future with frame-based direction calculation.

### System

| Feature | Yabai | Rift | AeroSpace |
|---|---|---|---|
| Startup notification | Version + SA status | Daemon running status | Version |
| Restart / Reload | Reload yabai | Restart Rift (launchd) | Reload AeroSpace config |
| Auto-detect running WM | Yes | Yes | Yes |
| Daemon guard (no auto-launch) | N/A | Yes (pgrep check) | Yes (pgrep check) |
| Setup prompt | Yes (FIFO + signals) | N/A | Yes (FIFO + config hook) |
| Settings integration button | Yes | N/A | Yes |

## Implementation Notes

### AeroSpace-specific

- **Virtual workspaces**: String-named ("1"-"9"). Aegis maps them to stable integer indices (workspace "3" = index 3, always). Workspaces 1 through the highest in use are always shown, preventing empty workspaces from disappearing.
- **FIFO pipe**: `~/.config/aegis/aerospace.pipe` — created by Aegis, written to by `exec-on-workspace-change` callback in `.aerospace.toml`. No polling required.
- **Send to Space**: Shows all workspaces 1-9 (not just visible ones). Uses workspace name strings directly via `move-node-to-workspace --focus-follows-window`.
- **Context menu**: AeroSpace gets extra actions not available in yabai/Rift: close, minimize, native fullscreen, join-with, resize, monitor focus/move, orientation toggle, workspace back-and-forth.

### Rift-specific

- **Window focus**: Rift CLI doesn't support `focus_window` by ID. Aegis uses macOS Accessibility APIs (`AXUIElement`) to activate the app and raise the window by matching `CGWindowID`.
- **Window move**: `rift-cli execute workspace move-window` with explicit `window_server_id` silently fails. Aegis focuses the window first via AXUIElement, waits 100ms, then calls `move-window` without an ID.
- **Inactive workspace windows**: Rift's `query workspaces` only populates `windows[]` for the active workspace. Aegis maintains a global window cache (`windowToWorkspace` map) to display icons for inactive workspaces.
- **Workspace labels**: 0-based to match Rift keybindings (Alt+0, Alt+1, etc).

### Paneru-specific

- **Workspace model**: One-dimensional — only the virtual rows of the CURRENT native macOS Space are shown (rows filtered by `active.native_workspace_id` from `paneru query state --json`). Trailing empty rows are kept.
- **Complete snapshots**: `query state --json` includes full window lists for inactive rows too, so no merge cache is needed — each refresh replaces the cache wholesale.
- **Window order**: Paneru JSON has no window frames; each row's `windows[]` array is already in strip order and is used directly.
- **No PID in JSON**: PIDs are resolved from `bundle_id` via `NSRunningApplication.runningApplications(withBundleIdentifier:)` (needed for AXObserver window-title tracking).
- **Window focus**: Paneru has no focus-window-by-ID command (`send-cmd window focus <id>` is silently ignored). Aegis uses the same AXUIElement raise-by-CGWindowID hack as Rift.
- **Window move**: `send-cmd window virtualsendnum N` (don't follow) / `virtualmovenum N` (follow) operate on the FOCUSED window — Aegis focuses the target window via AXUIElement first, waits 100ms, then sends the command.
- **Single display**: `WMSpace.display` and `getCurrentDisplays()` are hardcoded to a single synthesized display (index 1).

### Adding a new window manager

1. Create `<WM>Service.swift` in `Core/Services/`
2. Create `<WM>Adapter.swift` in `Core/Adapters/` implementing `WindowManagerProtocol`
3. Add case to `WindowManagerType` enum in `WindowManagerFactory.swift`
4. Add auto-detection in `WindowManagerFactory.autoDetect()`
5. Gate WM-specific UI in menus by checking `windowManager.name` or `windowManager.capabilities`
6. Add startup notification case in `StartupNotificationService`
7. (Optional) Add FIFO pipe integration with setup script and setup checker
8. (Optional) Add settings panel setup button and launch-time setup prompt
