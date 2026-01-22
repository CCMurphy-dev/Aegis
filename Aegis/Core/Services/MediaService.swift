import Foundation
import AppKit

/// Service to monitor system-wide "Now Playing" information using MediaRemote framework
/// Works with ALL media sources: Music, Spotify, Safari, Firefox, Chrome, YouTube, etc.
///
/// Uses mediaremote-adapter (Perl script + framework) to bypass macOS 15.4+ entitlement restrictions
class MediaService {
    private let eventRouter: EventRouter
    private var currentInfo: MediaInfo?

    // Cache album art per track to handle payloads without artwork
    // Limited to 5 entries with downscaled images to prevent memory bloat
    private var cachedAlbumArt: [String: NSImage] = [:]
    private var albumArtCacheOrder: [String] = []  // Track insertion order for LRU eviction
    private let maxCachedAlbumArt = 5

    // Process running the mediaremote-adapter stream
    private var streamProcess: Process?
    private var streamTask: Task<Void, Never>?

    init(eventRouter: EventRouter) {
        self.eventRouter = eventRouter

        // Start monitoring after a short delay to ensure subscribers are registered
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startMonitoring()
        }
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Monitoring

    /// Start monitoring system-wide now playing information
    private func startMonitoring() {
        Task {
            await setupMediaRemoteStream()
        }
    }

    /// Stop monitoring and clean up resources
    private func stopMonitoring() {
        streamTask?.cancel()
        streamProcess?.terminate()
        streamProcess = nil
    }

    /// Set up the MediaRemote adapter stream
    private func setupMediaRemoteStream() async {
        // Locate adapter files in bundle
        guard let scriptURL = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
              let frameworkPath = Bundle.main.privateFrameworksPath?.appending("/MediaRemoteAdapter.framework") else {
            print("❌ MediaService: Unable to locate mediaremote-adapter.pl or MediaRemoteAdapter.framework")
            print("   Expected locations:")
            print("   - Script: Resources/mediaremote-adapter.pl")
            print("   - Framework: Frameworks/MediaRemoteAdapter.framework")
            return
        }

        print("🎵 MediaService: Starting media monitoring")
        print("   Script: \(scriptURL.path)")
        print("   Framework: \(frameworkPath)")

        // Set up process to run perl script
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [scriptURL.path, frameworkPath, "stream", "--no-diff", "--debounce=50"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe() // Suppress stderr

        self.streamProcess = process

        do {
            try process.run()
            print("🎵 MediaService: Stream started successfully")

            // Read JSON lines from stream
            streamTask = Task { [weak self] in
                await self?.processJSONStream(from: pipe)
            }
        } catch {
            print("❌ MediaService: Failed to start stream: \(error)")
        }
    }

    /// Process JSON stream from mediaremote-adapter
    private func processJSONStream(from pipe: Pipe) async {
        do {
            for try await line in pipe.fileHandleForReading.bytes.lines {
                guard !Task.isCancelled else { break }

                // Parse JSON line
                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let payload = json["payload"] as? [String: Any] else {
                    continue
                }

                await MainActor.run {
                    self.handleMediaUpdate(payload)
                }
            }
        } catch {
            if !Task.isCancelled {
                print("❌ MediaService: Stream error: \(error)")
            }
        }
    }

    /// Handle media update from adapter
    private func handleMediaUpdate(_ payload: [String: Any]) {
        // Extract basic info
        guard let title = payload["title"] as? String,
              !title.isEmpty else {
            // No media playing - clear current info
            if currentInfo != nil {
                currentInfo = nil
                eventRouter.publish(.mediaPlaybackChanged, data: ["info": MediaInfo.placeholder])
            }
            return
        }

        let artist = payload["artist"] as? String ?? "Unknown Artist"
        let album = payload["album"] as? String ?? ""
        let isPlaying = payload["playing"] as? Bool ?? false
        let bundleIdentifier = payload["bundleIdentifier"] as? String

        // Create track identifier for caching
        let trackId = "\(title)-\(artist)"

        // Check if we have new artwork to decode
        if let artworkDataString = payload["artworkData"] as? String,
           !artworkDataString.isEmpty {
            let trimmed = artworkDataString.trimmingCharacters(in: .whitespacesAndNewlines)

            // Decode on background queue to avoid main thread stutter
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let scaledImage = self?.decodeAndScaleAlbumArt(from: trimmed)

                DispatchQueue.main.async {
                    guard let self = self else { return }

                    // Cache the scaled image
                    if let image = scaledImage {
                        self.cacheAlbumArt(image, forTrack: trackId)
                    }

                    // Publish with decoded artwork (or nil if decode failed)
                    self.publishMediaInfo(
                        title: title,
                        artist: artist,
                        album: album,
                        isPlaying: isPlaying,
                        albumArt: scaledImage ?? self.cachedAlbumArt[trackId],
                        bundleIdentifier: bundleIdentifier,
                        trackId: trackId
                    )
                }
            }
        } else {
            // No new artwork - use cached version immediately
            let albumArt = cachedAlbumArt[trackId]
            publishMediaInfo(
                title: title,
                artist: artist,
                album: album,
                isPlaying: isPlaying,
                albumArt: albumArt,
                bundleIdentifier: bundleIdentifier,
                trackId: trackId
            )
        }
    }

    /// Publish media info if changed (extracted for reuse)
    private func publishMediaInfo(
        title: String,
        artist: String,
        album: String,
        isPlaying: Bool,
        albumArt: NSImage?,
        bundleIdentifier: String?,
        trackId: String
    ) {
        let newInfo = MediaInfo(
            title: title,
            artist: artist,
            album: album,
            isPlaying: isPlaying,
            albumArt: albumArt,
            bundleIdentifier: bundleIdentifier
        )

        // Only publish if state changed OR if we got new album art for same track
        let trackChanged = currentInfo?.trackIdentifier != newInfo.trackIdentifier
        let albumArtUpdated = trackChanged == false && currentInfo?.albumArt == nil && newInfo.albumArt != nil
        let playbackStateChanged = currentInfo?.isPlaying != newInfo.isPlaying

        if newInfo != currentInfo || albumArtUpdated {
            currentInfo = newInfo

            // Log for debugging
            if trackChanged && isPlaying {
                print("🎵 MediaService: Track changed - Now playing: \(title) by \(artist), isPlaying: \(isPlaying)")
            } else if playbackStateChanged {
                if isPlaying {
                    print("🎵 MediaService: Playback resumed - \(title) by \(artist)")
                } else {
                    print("🎵 MediaService: Playback stopped/paused - \(title) by \(artist)")
                }
            } else if albumArtUpdated {
                print("🎵 MediaService: Album art received for current track - updating")
            }

            // Publish to event router
            eventRouter.publish(.mediaPlaybackChanged, data: ["info": newInfo])
        }
    }

    // MARK: - Album Art Cache

    /// Decode and downscale album art for memory efficiency
    /// Album art displays at ~80pt, so 160px (2x retina) is sufficient
    /// Uses autoreleasepool to ensure full-size image is freed immediately
    private func decodeAndScaleAlbumArt(from base64String: String) -> NSImage? {
        autoreleasepool {
            guard let data = Data(base64Encoded: base64String),
                  let image = NSImage(data: data) else {
                return nil
            }

            // Scale to max 160x160 (2x retina for 80pt display)
            let maxSize: CGFloat = 160
            let size = image.size

            if size.width <= maxSize && size.height <= maxSize {
                return image  // Already small enough
            }

            let scale = min(maxSize / size.width, maxSize / size.height)
            let newSize = NSSize(width: size.width * scale, height: size.height * scale)

            let scaledImage = NSImage(size: newSize)
            scaledImage.lockFocus()
            image.draw(in: NSRect(origin: .zero, size: newSize),
                       from: NSRect(origin: .zero, size: size),
                       operation: .copy,
                       fraction: 1.0)
            scaledImage.unlockFocus()

            return scaledImage
        }
    }

    /// Cache album art with LRU eviction to prevent unbounded memory growth
    private func cacheAlbumArt(_ image: NSImage, forTrack trackId: String) {
        // Remove if already cached (will re-add at end)
        if let existingIndex = albumArtCacheOrder.firstIndex(of: trackId) {
            albumArtCacheOrder.remove(at: existingIndex)
        }

        // Evict oldest if at capacity
        while albumArtCacheOrder.count >= maxCachedAlbumArt {
            let oldest = albumArtCacheOrder.removeFirst()
            cachedAlbumArt.removeValue(forKey: oldest)
        }

        // Add new entry
        cachedAlbumArt[trackId] = image
        albumArtCacheOrder.append(trackId)
    }

    // MARK: - Public API

    /// Get current now playing info
    func getCurrentInfo() -> MediaInfo? {
        return currentInfo
    }

    // MARK: - Media Controls

    /// Toggle play/pause
    func togglePlayPause() {
        sendCommand(2) // MRTogglePlayPause
    }

    /// Play
    func play() {
        sendCommand(0) // MRPlay
    }

    /// Pause
    func pause() {
        sendCommand(1) // MRPause
    }

    /// Next track
    func nextTrack() {
        sendCommand(4) // MRNextTrack
    }

    /// Previous track
    func previousTrack() {
        sendCommand(5) // MRPreviousTrack
    }

    /// Send a media command via mediaremote-adapter
    private func sendCommand(_ commandID: Int) {
        guard let scriptURL = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
              let frameworkPath = Bundle.main.privateFrameworksPath?.appending("/MediaRemoteAdapter.framework") else {
            print("❌ MediaService: Cannot send command - adapter not found")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [scriptURL.path, frameworkPath, "send", "\(commandID)"]

        do {
            try process.run()
        } catch {
            print("❌ MediaService: Failed to send command \(commandID): \(error)")
        }
    }
}

// MARK: - Media Command IDs
// Reference: https://github.com/ungive/mediaremote-adapter

fileprivate enum MediaCommand: Int {
    case play = 0
    case pause = 1
    case togglePlayPause = 2
    case stop = 3
    case nextTrack = 4
    case previousTrack = 5
    case toggleShuffle = 6
    case toggleRepeat = 7
    case goBackFifteenSeconds = 12
    case skipFifteenSeconds = 13
}
