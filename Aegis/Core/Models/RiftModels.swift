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

/// The workspace fields that affect Aegis's workspace indicators.
struct RiftWorkspaceChangeSnapshot: Equatable {
    let index: Int
    let name: String
    let layoutMode: String
    let isActive: Bool

    init(index: Int, name: String, layoutMode: String, isActive: Bool) {
        self.index = index
        self.name = name
        self.layoutMode = layoutMode
        self.isActive = isActive
    }

    init(workspace: RiftWorkspace) {
        self.init(
            index: workspace.index,
            name: workspace.name,
            layoutMode: workspace.layoutMode,
            isActive: workspace.isActive
        )
    }
}

/// Pure change detection for the subset of Rift workspace data Aegis displays.
enum RiftWorkspaceChangeDetector {
    static func hasChanges(
        previous: [Int: RiftWorkspaceChangeSnapshot],
        current: [Int: RiftWorkspaceChangeSnapshot]
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
