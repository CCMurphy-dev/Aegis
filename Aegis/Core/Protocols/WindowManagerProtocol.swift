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

/// Controls the text shown in the menu bar for each workspace.
enum WorkspaceLabelStyle: String, CaseIterable, Codable {
    case index = "index"
    case nameInitial = "nameInitial"

    var displayName: String {
        switch self {
        case .index: return "Index"
        case .nameInitial: return "Name Initials"
        }
    }
}

struct WMSpace: Identifiable, Equatable {
    let id: Int
    var index: Int             // Mutable for optimistic reorder
    let display: Int           // Display index (1-based)
    let label: String?
    let workspaceName: String? // Semantic name, independent of the display label
    let layoutType: WMLayoutType
    let isFocused: Bool
    let isFullscreen: Bool     // Native macOS fullscreen
    /// Number of managed windows in this workspace, including windows that
    /// are hidden from the menu-bar icon list.
    let windowCount: Int
    /// False while the WM has not completed a window snapshot. A failed or
    /// partial refresh must not turn previously occupied spaces into empty
    /// ones for the bar.
    let windowCountIsKnown: Bool

    init(
        id: Int,
        index: Int,
        display: Int,
        label: String?,
        workspaceName: String?,
        layoutType: WMLayoutType,
        isFocused: Bool,
        isFullscreen: Bool,
        windowCount: Int = 0,
        windowCountIsKnown: Bool = false
    ) {
        self.id = id
        self.index = index
        self.display = display
        self.label = label
        self.workspaceName = workspaceName
        self.layoutType = layoutType
        self.isFocused = isFocused
        self.isFullscreen = isFullscreen
        self.windowCount = windowCount
        self.windowCountIsKnown = windowCountIsKnown
    }
}

/// Selects which workspaces the menu-bar indicator displays. This does not
/// change the workspaces exposed to shortcuts, menus, or WM commands.
enum WorkspaceVisibilityPolicy {
    static func visibleSpaces(
        _ spaces: [WMSpace],
        hideEmpty: Bool,
        previousCounts: [Int: Int] = [:]
    ) -> [WMSpace] {
        guard hideEmpty else { return spaces }
        return spaces.filter {
            let count = $0.windowCountIsKnown ? $0.windowCount : (previousCounts[$0.id] ?? 0)
            return count > 0 || $0.isFocused
        }
    }
}

/// Produces the compact labels used by menu bar workspace indicators.
///
/// Name labels start with one Unicode grapheme and grow only when needed to
/// disambiguate a case-insensitive collision. Empty or indistinguishable
/// names retain the window manager's existing numeric label.
enum WorkspaceLabelFormatter {
    static func numericLabel(for space: WMSpace) -> String {
        guard let label = space.label?.trimmingCharacters(in: .whitespacesAndNewlines),
              !label.isEmpty else {
            return "\(space.index)"
        }
        return label
    }

    static func labels(
        for spaces: [WMSpace],
        style: WorkspaceLabelStyle,
        overrides: [String: String] = [:]
    ) -> [Int: String] {
        let selectedLabels: [Int: String]
        if style == .nameInitial {
            let names = spaces.map { $0.workspaceName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
            let graphemes = names.map(Array.init)
            var lengths = graphemes.map { $0.isEmpty ? 0 : 1 }
            var numericFallbacks = Set<Int>()

            // Resolve collisions across generated prefixes and original-label
            // fallbacks. A fallback label is reserved, so a name such as
            // "0Ops" grows beyond "0" when another workspace falls back to
            // its original "0" label.
            while true {
                var groups: [String: [Int]] = [:]
                for index in spaces.indices {
                    let label: String
                    if numericFallbacks.contains(index) || graphemes[index].isEmpty {
                        label = numericLabel(for: spaces[index])
                    } else {
                        label = String(graphemes[index].prefix(lengths[index]))
                    }
                    groups[comparisonKey(label), default: []].append(index)
                }

                var changed = false
                for indices in groups.values where indices.count > 1 {
                    let extendable = indices.filter {
                        !numericFallbacks.contains($0) && lengths[$0] < graphemes[$0].count
                    }
                    if extendable.isEmpty {
                        let generated = indices.filter { !numericFallbacks.contains($0) }
                        if !generated.isEmpty {
                            numericFallbacks.formUnion(generated)
                            changed = true
                        }
                    } else {
                        for index in extendable {
                            lengths[index] += 1
                        }
                        changed = true
                    }
                }

                if !changed { break }
            }

            selectedLabels = Dictionary(uniqueKeysWithValues: spaces.enumerated().map { index, space in
                guard !graphemes[index].isEmpty, !numericFallbacks.contains(index) else {
                    return (space.id, numericLabel(for: space))
                }
                return (space.id, String(graphemes[index].prefix(lengths[index])))
            })
        } else {
            selectedLabels = Dictionary(uniqueKeysWithValues: spaces.map { ($0.id, numericLabel(for: $0)) })
        }

        // Explicit labels win over either generated name labels or the
        // original WM label. Whitespace-only values intentionally do nothing.
        return Dictionary(uniqueKeysWithValues: spaces.map { space in
            let originalLabel = numericLabel(for: space)
            if let override = overrides[originalLabel]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !override.isEmpty {
                return (space.id, override)
            }
            return (space.id, selectedLabels[space.id] ?? numericLabel(for: space))
        })
    }

    private static func comparisonKey(_ value: String) -> String {
        // lowercased() is locale-independent and preserves Unicode grapheme
        // boundaries while making prefix comparisons case-insensitive.
        value.lowercased().precomposedStringWithCanonicalMapping
    }
}

struct WMWindow: Identifiable {
    let id: Int
    let pid: pid_t
    let title: String
    let app: String            // Bundle ID or process name
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

    func stackAllWindowsOnto(_ targetId: Int) {}

    func executeRawCommand(args: [String], completion: @escaping (Result<String, Error>) -> Void) {
        completion(.failure(NSError(domain: "WindowManager", code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "Raw commands not supported"])))
    }

    func getVersion() -> String { return "Unknown" }
}
