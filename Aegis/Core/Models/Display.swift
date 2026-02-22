//
//  Display.swift
//  Aegis
//
//  Model for yabai display information
//

import Foundation

struct Display: Identifiable, Codable, Equatable {
    var id: Int           // Yabai display ID
    var uuid: String      // Persistent UUID for the display
    var index: Int        // 1-based display index
    var frame: CGRect     // Display frame coordinates
    var spaces: [Int]     // Array of space indices on this display
    var hasFocus: Bool    // Whether this display has focus

    enum CodingKeys: String, CodingKey {
        case id
        case uuid
        case index
        case frame
        case spaces
        case hasFocus = "has-focus"
    }

    // Custom decoding to handle frame dictionary from yabai
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(Int.self, forKey: .id)
        uuid = try container.decode(String.self, forKey: .uuid)
        index = try container.decode(Int.self, forKey: .index)
        spaces = try container.decode([Int].self, forKey: .spaces)
        hasFocus = try container.decode(Bool.self, forKey: .hasFocus)

        // Decode frame from yabai's dictionary format: {"x": 0, "y": 0, "w": 100, "h": 100}
        if let frameDict = try? container.decode([String: CGFloat].self, forKey: .frame),
           let x = frameDict["x"],
           let y = frameDict["y"],
           let w = frameDict["w"],
           let h = frameDict["h"] {
            frame = CGRect(x: x, y: y, width: w, height: h)
        } else {
            frame = .zero
        }
    }

    // Custom encoding to maintain Codable conformance
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(uuid, forKey: .uuid)
        try container.encode(index, forKey: .index)
        try container.encode(spaces, forKey: .spaces)
        try container.encode(hasFocus, forKey: .hasFocus)

        let frameDict: [String: CGFloat] = [
            "x": frame.origin.x,
            "y": frame.origin.y,
            "w": frame.width,
            "h": frame.height
        ]
        try container.encode(frameDict, forKey: .frame)
    }

    // Memberwise initializer for testing/manual creation
    init(id: Int, uuid: String, index: Int, frame: CGRect, spaces: [Int], hasFocus: Bool) {
        self.id = id
        self.uuid = uuid
        self.index = index
        self.frame = frame
        self.spaces = spaces
        self.hasFocus = hasFocus
    }
}
