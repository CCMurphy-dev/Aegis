//
//  Space.swift
//  Aegis
//
//  Created by Christopher Murphy on 13/01/2026.
//


import Foundation
import AppKit


struct Space: Identifiable, Codable, Equatable {
    var id: Int
    var index: Int
    var label: String?
    var type: String  // "bsp", "float", "fullscreen", etc.
    var focused: Bool
    var isNativeFullscreen: Bool  // True when a window on this space is in native macOS fullscreen

    enum CodingKeys: String, CodingKey {
        case id
        case index
        case label
        case type
        case focused = "has-focus"
        case isNativeFullscreen = "is-native-fullscreen"
    }
}

struct WindowInfo: Identifiable, Codable {
    var id: Int
    var title: String
    var app: String
    var space: Int
    var frame: CGRect?
    var hasFocus: Bool
    var stackIndex: Int
    var isNativeFullscreen: Bool
    var role: String  // "AXWindow" for real windows, "AXGroup" for popups/panels
    var subrole: String  // "AXStandardWindow" for real windows, "AXDialog"/"AXSystemDialog" for dialogs
    var isMinimized: Bool
    var isHidden: Bool
    var isVisible: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case app
        case space
        case frame
        case hasFocus = "has-focus"
        case stackIndex = "stack-index"
        case isNativeFullscreen = "is-native-fullscreen"
        case role
        case subrole
        case isMinimized = "is-minimized"
        case isHidden = "is-hidden"
        case isVisible = "is-visible"
    }

    // Custom decoding to handle frame dictionary from yabai
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(Int.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        app = try container.decode(String.self, forKey: .app)
        space = try container.decode(Int.self, forKey: .space)
        hasFocus = try container.decode(Bool.self, forKey: .hasFocus)
        stackIndex = try container.decode(Int.self, forKey: .stackIndex)
        isNativeFullscreen = try container.decode(Bool.self, forKey: .isNativeFullscreen)
        role = try container.decode(String.self, forKey: .role)
        subrole = try container.decode(String.self, forKey: .subrole)
        isMinimized = try container.decodeIfPresent(Bool.self, forKey: .isMinimized) ?? false
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true

        // Decode frame from yabai's dictionary format: {"x": 0, "y": 0, "w": 100, "h": 100}
        if let frameDict = try? container.decode([String: CGFloat].self, forKey: .frame),
           let x = frameDict["x"],
           let y = frameDict["y"],
           let w = frameDict["w"],
           let h = frameDict["h"] {
            frame = CGRect(x: x, y: y, width: w, height: h)
        } else {
            frame = nil
        }
    }

    // Custom encoding to maintain Codable conformance
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(app, forKey: .app)
        try container.encode(space, forKey: .space)
        try container.encode(hasFocus, forKey: .hasFocus)
        try container.encode(stackIndex, forKey: .stackIndex)
        try container.encode(isNativeFullscreen, forKey: .isNativeFullscreen)
        try container.encode(role, forKey: .role)
        try container.encode(subrole, forKey: .subrole)
        try container.encode(isMinimized, forKey: .isMinimized)
        try container.encode(isHidden, forKey: .isHidden)
        try container.encode(isVisible, forKey: .isVisible)

        if let frame = frame {
            let frameDict: [String: CGFloat] = [
                "x": frame.origin.x,
                "y": frame.origin.y,
                "w": frame.width,
                "h": frame.height
            ]
            try container.encode(frameDict, forKey: .frame)
        }
    }
}

struct WindowIcon: Identifiable, Equatable {
    let id: Int
    let title: String
    let app: String
    let appName: String  // Display name for app
    let icon: NSImage?
    let frame: CGRect?
    let hasFocus: Bool
    let stackIndex: Int  // Used for stack indicator badge
    let isMinimized: Bool
    let isHidden: Bool

    // Pre-computed expanded width to avoid repeated font measurements
    let expandedWidth: CGFloat

    init(id: Int, title: String, app: String, appName: String, icon: NSImage?, frame: CGRect?, hasFocus: Bool, stackIndex: Int, isMinimized: Bool, isHidden: Bool) {
        self.id = id
        self.title = title
        self.app = app
        self.appName = appName
        self.icon = icon
        self.frame = frame
        self.hasFocus = hasFocus
        self.stackIndex = stackIndex
        self.isMinimized = isMinimized
        self.isHidden = isHidden

        // Pre-compute expanded width once during init
        let titleFont = NSFont.systemFont(ofSize: 11, weight: .medium)
        let titleWidth = title.width(using: titleFont)
        let appFont = NSFont.systemFont(ofSize: 9)
        let appWidth = appName.width(using: appFont)
        self.expandedWidth = min(max(titleWidth, appWidth) + 8, 100)  // 100 = maxExpandedWidth
    }

    static func == (lhs: WindowIcon, rhs: WindowIcon) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.app == rhs.app &&
        lhs.hasFocus == rhs.hasFocus &&
        lhs.stackIndex == rhs.stackIndex &&
        lhs.isMinimized == rhs.isMinimized &&
        lhs.isHidden == rhs.isHidden
    }
}
