import Foundation
import AppKit

/// Model for music playback info
/// Used by MediaService to represent now playing information
struct MusicInfo: Equatable {
    let title: String
    let artist: String
    let album: String
    let isPlaying: Bool
    let albumArt: NSImage?
    let bundleIdentifier: String?

    /// Unique identifier for the track (used to detect track changes)
    var trackIdentifier: String {
        return "\(title)-\(artist)"
    }

    static var placeholder: MusicInfo {
        MusicInfo(title: "", artist: "", album: "", isPlaying: false, albumArt: nil, bundleIdentifier: nil)
    }

    static func == (lhs: MusicInfo, rhs: MusicInfo) -> Bool {
        return lhs.title == rhs.title &&
               lhs.artist == rhs.artist &&
               lhs.album == rhs.album &&
               lhs.isPlaying == rhs.isPlaying &&
               lhs.bundleIdentifier == rhs.bundleIdentifier
        // Note: We don't compare albumArt since it's an image
    }
}
