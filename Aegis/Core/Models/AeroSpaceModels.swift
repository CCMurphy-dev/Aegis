//
//  AeroSpaceModels.swift
//  Aegis
//
//  Codable structs that decode directly from aerospace CLI JSON output.
//  These are AeroSpace-specific — the adapter layer converts them into WM* protocol types.
//

import Foundation

// MARK: - Workspace

struct ASWorkspace: Codable {
    let workspace: String       // e.g. "1", "A", "B"
    let monitorId: Int?         // monitor-id (only present with format flag)

    enum CodingKeys: String, CodingKey {
        case workspace
        case monitorId = "monitor-id"
    }
}

// MARK: - Window

struct ASWindow: Codable {
    let windowId: Int
    let appName: String
    let windowTitle: String
    let appBundleId: String?
    let workspace: String?
    let monitorId: Int?

    enum CodingKeys: String, CodingKey {
        case windowId = "window-id"
        case appName = "app-name"
        case windowTitle = "window-title"
        case appBundleId = "app-bundle-id"
        case workspace
        case monitorId = "monitor-id"
    }
}

// MARK: - Monitor

struct ASMonitor: Codable {
    let monitorId: Int
    let monitorName: String

    enum CodingKeys: String, CodingKey {
        case monitorId = "monitor-id"
        case monitorName = "monitor-name"
    }
}
