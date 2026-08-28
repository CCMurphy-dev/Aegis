//
//  PaneruModels.swift
//  Aegis
//
//  Codable structs that decode directly from paneru JSON output.
//  These are Paneru-specific — the adapter layer converts them into WM* protocol types.
//

import Foundation

// MARK: - State Snapshot (`paneru query state --json`)

struct PaneruState: Codable {
    let version: Int
    let active: PaneruActive
    let virtualWorkspaces: [PaneruVirtualWorkspace]

    enum CodingKeys: String, CodingKey {
        case version, active
        case virtualWorkspaces = "virtual_workspaces"
    }
}

struct PaneruActive: Codable {
    let displayId: Int?            // Can be null
    let nativeWorkspaceId: Int?    // Can be null when no row is active
    let virtualWorkspaceNumber: Int
    let focusedWindowId: Int?
    let focusedBundleId: String?
    let focusedAppName: String?
    let focusedWindowTitle: String?

    enum CodingKeys: String, CodingKey {
        case displayId = "display_id"
        case nativeWorkspaceId = "native_workspace_id"
        case virtualWorkspaceNumber = "virtual_workspace_number"
        case focusedWindowId = "focused_window_id"
        case focusedBundleId = "focused_bundle_id"
        case focusedAppName = "focused_app_name"
        case focusedWindowTitle = "focused_window_title"
    }
}

// MARK: - Virtual Workspace (row)

struct PaneruVirtualWorkspace: Codable {
    let number: Int                // 1-based row number
    let nativeWorkspaceId: Int
    let active: Bool
    let windows: [PaneruWindow]    // Already in strip order

    enum CodingKeys: String, CodingKey {
        case number, active, windows
        case nativeWorkspaceId = "native_workspace_id"
    }
}

// MARK: - Window

struct PaneruWindow: Codable {
    let windowId: Int              // macOS CGWindowID — used as WMWindow.id
    let bundleId: String
    let appName: String
    let title: String
    let focused: Bool
    let floating: Bool

    enum CodingKeys: String, CodingKey {
        case title, focused, floating
        case windowId = "window_id"
        case bundleId = "bundle_id"
        case appName = "app_name"
    }
}

// MARK: - Event (`paneru subscribe --json`, NDJSON)

struct PaneruEvent: Codable {
    let event: String
    let active: PaneruActive?

    // windows_changed / window_focused
    let virtualWorkspaceNumber: Int?

    // window_focused / window_title_changed
    let windowId: Int?
    let bundleId: String?
    let title: String?

    // display_changed (can be null)
    let displayId: Int?

    enum CodingKeys: String, CodingKey {
        case event, active, title
        case virtualWorkspaceNumber = "virtual_workspace_number"
        case windowId = "window_id"
        case bundleId = "bundle_id"
        case displayId = "display_id"
    }
}
