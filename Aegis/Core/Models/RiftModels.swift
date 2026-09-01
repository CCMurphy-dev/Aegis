//
//  RiftModels.swift
//  Aegis
//
//  Codable structs that decode directly from rift-cli JSON output.
//  These are Rift-specific — the adapter layer converts them into WM* protocol types.
//

import Foundation

// MARK: - Workspace

struct RiftWorkspace: Codable {
    let id: String              // e.g. "VirtualWorkspaceId(123)"
    let index: Int              // 0-based workspace index
    let name: String
    let layoutMode: String      // "bsp", "stack", "master_stack", "scrolling", "traditional"
    let isActive: Bool
    let windowCount: Int
    let windows: [RiftWindow]

    enum CodingKeys: String, CodingKey {
        case id, index, name, windows
        case layoutMode = "layout_mode"
        case isActive = "is_active"
        case windowCount = "window_count"
    }
}

// MARK: - Window

struct RiftWindowId: Codable, Hashable {
    let pid: Int
    let idx: Int
}

struct RiftWindow: Codable {
    let id: RiftWindowId
    let title: String
    let frame: RiftFrame
    let isFloating: Bool
    let isFocused: Bool
    let bundleId: String?
    let appName: String?
    let windowServerId: UInt32?     // macOS CGWindowID — used as WMWindow.id

    enum CodingKeys: String, CodingKey {
        case id, title, frame
        case isFloating = "is_floating"
        case isFocused = "is_focused"
        case bundleId = "bundle_id"
        case appName = "app_name"
        case windowServerId = "window_server_id"
    }
}

// MARK: - Frame

struct RiftFrame: Codable {
    let origin: RiftPoint
    let size: RiftSize

    var cgRect: CGRect {
        CGRect(x: origin.x, y: origin.y, width: size.width, height: size.height)
    }
}

struct RiftPoint: Codable {
    let x: CGFloat
    let y: CGFloat
}

struct RiftSize: Codable {
    let width: CGFloat
    let height: CGFloat
}

// MARK: - Display

struct RiftDisplay: Codable {
    let uuid: String
    let name: String?
    let screenId: UInt32
    let frame: RiftFrame
    let space: UInt64?
    let isActiveSpace: Bool
    let isActiveContext: Bool
    let activeSpaceIds: [UInt64]
    let inactiveSpaceIds: [UInt64]

    enum CodingKeys: String, CodingKey {
        case uuid, name, frame, space
        case screenId = "screen_id"
        case isActiveSpace = "is_active_space"
        case isActiveContext = "is_active_context"
        case activeSpaceIds = "active_space_ids"
        case inactiveSpaceIds = "inactive_space_ids"
    }
}

/// The display fields that affect native-space visibility and display-local
/// menu bars. Space IDs are sets because Rift does not promise an ordering for
/// the active/inactive lists.
struct RiftDisplayChangeSnapshot: Equatable {
    let screenId: UInt32
    let uuid: String
    let space: UInt64?
    let isActiveSpace: Bool
    let isActiveContext: Bool
    let activeSpaceIds: Set<UInt64>
    let inactiveSpaceIds: Set<UInt64>

    var isUnknown: Bool {
        space == nil && screenId == 0 && uuid.isEmpty
            && activeSpaceIds.isEmpty && inactiveSpaceIds.isEmpty
    }

    init(display: RiftDisplay) {
        self.screenId = display.screenId
        self.uuid = display.uuid
        self.space = display.space
        self.isActiveSpace = display.isActiveSpace
        self.isActiveContext = display.isActiveContext
        self.activeSpaceIds = Set(display.activeSpaceIds)
        self.inactiveSpaceIds = Set(display.inactiveSpaceIds)
    }
}

/// A native Space notification can arrive before Rift has a useful display
/// snapshot. Retry while the snapshot is still the pre-transition value or is
/// unknown; stop retrying as soon as Rift reports a different known snapshot.
enum RiftActiveSpaceRetryPolicy {
    static func shouldRetry(
        baseline: [Int: RiftDisplayChangeSnapshot],
        current: [Int: RiftDisplayChangeSnapshot]
    ) -> Bool {
        current.isEmpty || current.values.contains(where: { $0.isUnknown }) || current == baseline
    }
}

/// Pure change detection for the display state used by menu-bar visibility.
enum RiftDisplayChangeDetector {
    static func hasChanges(
        previous: [Int: RiftDisplayChangeSnapshot],
        current: [Int: RiftDisplayChangeSnapshot]
    ) -> Bool {
        guard previous.count == current.count,
              Set(previous.keys) == Set(current.keys) else {
            return true
        }
        return current.contains { key, snapshot in
            previous[key] != snapshot
        }
    }
}

/// Converts Rift's native-space fields into the WM-neutral visibility state.
enum RiftDisplaySpaceStateClassifier {
    static func state(space: UInt64?, isActiveSpace: Bool) -> WMDisplaySpaceState {
        if space == nil {
            return .nativeFullscreen
        }
        return isActiveSpace ? .managed : .unmanaged
    }

    static func state(for display: RiftDisplay) -> WMDisplaySpaceState {
        // A completely empty record is a startup/reconnect placeholder, not
        // evidence that a real display entered native fullscreen. A real
        // null-space display retains its screen identity or space-id sets and
        // is still classified as native fullscreen.
        if display.space == nil,
           display.screenId == 0,
           display.uuid.isEmpty,
           display.activeSpaceIds.isEmpty,
           display.inactiveSpaceIds.isEmpty {
            return .unknown
        }
        return state(space: display.space, isActiveSpace: display.isActiveSpace)
    }
}

// MARK: - Event

struct RiftWorkspaceIdRef: Codable {
    let idx: Int
    let version: Int
}

struct RiftEvent: Codable {
    let type: String
    let spaceId: UInt64?
    let workspaceId: RiftWorkspaceIdRef?
    let workspaceName: String?
    let workspaceIndex: UInt64?
    let displayUuid: String?

    // windows_changed
    let windows: [String]?

    // window_title_changed
    let windowId: RiftWindowId?
    let previousTitle: String?
    let newTitle: String?

    enum CodingKeys: String, CodingKey {
        case type, windows
        case spaceId = "space_id"
        case workspaceId = "workspace_id"
        case workspaceName = "workspace_name"
        case workspaceIndex = "workspace_index"
        case displayUuid = "display_uuid"
        case windowId = "window_id"
        case previousTitle = "previous_title"
        case newTitle = "new_title"
    }
}
