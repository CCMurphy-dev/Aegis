//
//  WindowManagerProtocol.swift
//  Aegis
//
//  Abstraction layer for window manager integration.
//  Allows Aegis to work with Yabai, Rift, AeroSpace, or any other WM.
//

import Foundation
import AppKit


// MARK: - Unified Data Models

struct WMSpace: Identifiable, Equatable {
    let id: Int
    var index: Int             // Mutable for optimistic reorder
    let display: Int           // Display index (1-based)
    let label: String?
    let layoutType: WMLayoutType
    let isFocused: Bool
    let isFullscreen: Bool     // Native macOS fullscreen
}

struct WMWindow: Identifiable {
    let id: Int
    let pid: pid_t
    let title: String
    let app: String            // Bundle ID or process name
    let bundleIdentifier: String?
    let appName: String        // Human-readable display name
    let space: Int             // Space index this window belongs to
    let frame: CGRect?
    let hasFocus: Bool
    let stackIndex: Int        // 0 = not stacked
    let isMinimized: Bool
    let isHidden: Bool
    let isVisible: Bool
    let isFloating: Bool
    let isFullscreen: Bool     // Native macOS fullscreen
}

struct WMDisplay: Identifiable, Equatable {
    let id: Int
    let uuid: String
    let index: Int             // 1-based display index
    let frame: CGRect
    let spaces: [Int]          // Space indices on this display
    let hasFocus: Bool
}

enum WMLayoutType: String {
    case bsp
    case float
    case stack
    case tiling
    case fullscreen
    case scrolling
    case masterStack
    case unknown
}


// MARK: - Capabilities

struct WMCapabilities: OptionSet {
    let rawValue: Int

    static let createSpace      = WMCapabilities(rawValue: 1 << 0)
    static let destroySpace     = WMCapabilities(rawValue: 1 << 1)
    static let reorderSpaces    = WMCapabilities(rawValue: 1 << 2)
    static let rotateLayout     = WMCapabilities(rawValue: 1 << 3)
    static let balanceLayout    = WMCapabilities(rawValue: 1 << 4)
    static let flipLayout       = WMCapabilities(rawValue: 1 << 5)
    static let stackWindows     = WMCapabilities(rawValue: 1 << 6)
    static let floatWindows     = WMCapabilities(rawValue: 1 << 7)
    static let moveWindows      = WMCapabilities(rawValue: 1 << 8)
    static let toggleLayout     = WMCapabilities(rawValue: 1 << 9)

    /// All capabilities — used by WMs with full feature parity (e.g. Yabai)
    static let all: WMCapabilities = [
        .createSpace, .destroySpace, .reorderSpaces,
        .rotateLayout, .balanceLayout, .flipLayout,
        .stackWindows, .floatWindows, .moveWindows, .toggleLayout
    ]
}


// MARK: - WM Events

/// Events that the window manager can emit
enum WMEvent: CaseIterable {
    case spacesChanged
    case windowsChanged
    case displaysChanged
}

enum WMAppSwitcherTargetScope {
    case window(id: Int)
    /// Window-manager IDs are captured before a quit request. The process ID
    /// remains part of the scope so adapters never broaden a check to another
    /// process that happens to share the same application bundle.
    case application(
        processIdentifier: pid_t,
        bundleIdentifier: String,
        windowManagerIDs: Set<Int>
    )
}

enum WMAppSwitcherTargetCheck: Equatable {
    case present
    case absent
    case unavailable
}

struct WMAppSwitcherTargetResult: Equatable {
    let check: WMAppSwitcherTargetCheck
    let absentWindowManagerIDs: Set<Int>

    init(
        check: WMAppSwitcherTargetCheck,
        absentWindowManagerIDs: Set<Int> = []
    ) {
        self.check = check
        self.absentWindowManagerIDs = absentWindowManagerIDs
    }
}


// MARK: - Protocol

/// Abstraction for window manager operations.
/// Each adapter (Yabai, Rift, AeroSpace) conforms to this protocol.
protocol WindowManagerProtocol: AnyObject {

    // MARK: Identity

    /// Human-readable name (e.g. "Yabai", "Rift", "AeroSpace")
    var name: String { get }

    /// What this WM supports — UI elements are hidden for missing capabilities
    var capabilities: WMCapabilities { get }

    /// Shared event router for WM-related events
    var eventRouter: EventRouter { get }

    // MARK: Lifecycle

    /// Start listening for events and populate initial state
    func start()

    /// Stop event listeners and clean up
    func stop()

    // MARK: Queries — Spaces

    /// All spaces sorted by index
    func getCurrentSpaces() -> [WMSpace]

    /// Spaces for a specific display
    func getSpacesForDisplay(_ displayIndex: Int) -> [WMSpace]

    /// Currently focused space
    func getFocusedSpace() -> WMSpace?

    /// Index of the currently focused space
    func getFocusedSpaceIndex() -> Int

    /// Whether a space has any focused window
    func spaceHasFocusedWindow(_ spaceIndex: Int) -> Bool

    // MARK: Queries — Windows

    /// All tracked windows
    func getAllWindows() -> [WMWindow]

    /// Windows on a specific space
    func getWindowsForSpace(_ spaceIndex: Int) -> [WMWindow]

    /// Single window lookup
    func getWindow(_ id: Int) -> WMWindow?

    /// Read-only confirmation for a window action. Managers must not mutate
    /// their caches here; this is used to decide whether a switcher row may be
    /// removed after W/Q.
    func checkAppSwitcherTarget(_ scope: WMAppSwitcherTargetScope) async -> WMAppSwitcherTargetResult

    /// Which space a window is on
    func getWindowSpace(_ windowId: Int) -> Int?

    /// Window icons for a space (includes ordering, icon lookup, expanded width)
    func getWindowIconsForSpace(_ spaceIndex: Int) -> [WindowIcon]

    /// App icons for a space (deduplicated by app)
    func getAppIconsForSpace(_ spaceIndex: Int) -> [NSImage]

    /// App icon by name
    func getAppIcon(for appName: String) -> NSImage?

    // MARK: Queries — Displays

    /// All displays sorted by index
    func getCurrentDisplays() -> [WMDisplay]

    // MARK: Commands — Focus

    /// Focus a space by index
    func focusSpace(_ index: Int)

    /// Focus a window by ID
    func focusWindow(_ id: Int)

    /// Focus the first window matching an app name. Returns true if found.
    func focusWindowByAppName(_ appName: String) -> Bool

    // MARK: Commands — Window Movement

    /// Move a window to another space
    func moveWindow(_ id: Int, toSpace index: Int)

    /// Move a window to a space and focus it
    func moveWindowAndFocus(_ id: Int, toSpace index: Int)

    /// Move a window to a space with optional stacking
    func moveWindowToSpace(_ windowId: Int, spaceIndex: Int, insertBeforeWindowId: Int?, shouldStack: Bool)

    /// Move a window to a space, float it, and focus
    func moveWindowToSpaceFloatAndFocus(_ id: Int, spaceIndex: Int)

    /// Float and center a window on its current space
    func floatAndCenterWindow(_ id: Int)

    /// Close one exact window. Implementations must not fall back to the
    /// focused window, because callers may be acting on a background row.
    func closeWindow(_ id: Int, completion: @escaping (Result<Void, Error>) -> Void)

    // MARK: Commands — Space Management

    /// Create a new space on the focused display
    func createSpace()

    /// Destroy a space by index
    func destroySpace(_ index: Int)

    /// Move a space from one position to another
    func moveSpace(from: Int, to: Int)

    // MARK: Commands — Layout

    /// Toggle between layout modes (e.g. BSP ↔ float)
    func toggleLayout()

    /// Rotate the layout tree by degrees (90, 180, 270)
    func rotateLayout(_ degrees: Int)

    /// Balance/equalize the layout tree
    func balanceLayout()

    /// Flip the layout tree along an axis ("x" or "y")
    func flipLayout(axis: String)

    // MARK: Commands — Stacking

    /// Toggle stacking all windows on the current space
    func toggleStackAllWindows()

    /// Stack a source window onto a target window
    func stackWindow(_ sourceId: Int, onto targetId: Int)

    /// Stack all windows onto a target window
    func stackAllWindowsOnto(_ targetId: Int)

    /// Unstack specific windows
    func unstackWindows(_ windowIds: [Int])

    // MARK: Commands — Raw / WM-Specific

    /// Execute a raw WM command (args format is WM-specific).
    /// Used for context menu actions that don't have dedicated protocol methods yet.
    func executeRawCommand(args: [String], completion: @escaping (Result<String, Error>) -> Void)

    /// Get the WM version string
    func getVersion() -> String
}


// MARK: - Default Implementations for Optional Capabilities

extension WindowManagerProtocol {

    // Default no-ops for capabilities a WM may not support.
    // Adapters override only what they support.

    func createSpace() {}
    func destroySpace(_ index: Int) {}
    func moveSpace(from: Int, to: Int) {}

    func rotateLayout(_ degrees: Int) {}
    func balanceLayout() {}
    func flipLayout(axis: String) {}

    func toggleStackAllWindows() {}
    func stackWindow(_ sourceId: Int, onto targetId: Int) {}
    func unstackWindows(_ windowIds: [Int]) {}

    func moveWindowToSpaceFloatAndFocus(_ id: Int, spaceIndex: Int) {}
    func floatAndCenterWindow(_ id: Int) {}

    func closeWindow(_ id: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        completion(.failure(NSError(
            domain: "WindowManager",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Closing windows is not supported"]
        )))
    }

    func stackAllWindowsOnto(_ targetId: Int) {}

    func executeRawCommand(args: [String], completion: @escaping (Result<String, Error>) -> Void) {
        completion(.failure(NSError(domain: "WindowManager", code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "Raw commands not supported"])))
    }

    func getVersion() -> String { return "Unknown" }

    func checkAppSwitcherTarget(_ scope: WMAppSwitcherTargetScope) async -> WMAppSwitcherTargetResult {
        WMAppSwitcherTargetResult(check: .unavailable)
    }
}
