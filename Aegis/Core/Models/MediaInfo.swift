import Foundation
import AppKit

/// Model for media playback info
/// Used by MediaService to represent now playing information
struct MediaInfo: Equatable {
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

    static var placeholder: MediaInfo {
        MediaInfo(title: "", artist: "", album: "", isPlaying: false, albumArt: nil, bundleIdentifier: nil)
    }

    static func == (lhs: MediaInfo, rhs: MediaInfo) -> Bool {
        return lhs.title == rhs.title &&
               lhs.artist == rhs.artist &&
               lhs.album == rhs.album &&
               lhs.isPlaying == rhs.isPlaying &&
               lhs.bundleIdentifier == rhs.bundleIdentifier
        // Note: We don't compare albumArt since it's an image
    }
}
