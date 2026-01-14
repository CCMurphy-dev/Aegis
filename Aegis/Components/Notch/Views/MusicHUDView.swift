import SwiftUI
import Combine

struct MusicHUDView: View {
    @ObservedObject var viewModel: MusicHUDViewModel
    let notchDimensions: NotchDimensions
    @Binding var isVisible: Bool

    // State to control which mode we're in
    @State private var showingTrackInfo = false
    @State private var trackInfoTimer: Timer?

    @ObservedObject private var config = AegisConfig.shared

    // Convenience accessor for info
    private var info: MusicInfo {
        viewModel.info
    }

    // Fixed max width for both side containers (ensures symmetry for centering)
    private var sideMaxWidth: CGFloat {
        notchDimensions.height * 4
    }

    // How far the black background extends into the notch area to fill the gap
    // This only affects the background shape, not the content position
    private let notchGapFill: CGFloat = 8

    // Right side content width (dynamic)
    private var rightContentWidth: CGFloat {
        if showingTrackInfo {
            return calculateTrackInfoWidth()
        } else {
            return notchDimensions.height
        }
    }

    var body: some View {
        // SYMMETRICAL three-column layout
        // Both containers have the same max width for proper centering
        // Content within each container is pinned to the notch edge

        ZStack {
            // BACKGROUND LAYER: Black shapes that extend into notch area to fill gaps
            HStack(spacing: 0) {
                // Left background - extends right into notch area
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    LeftPanelShape(cornerRadius: 10, topCornerRadius: 6, innerCornerRadius: 8)
                        .fill(Color.black)
                        .frame(width: notchDimensions.height + notchGapFill, height: notchDimensions.height)
                }
                .frame(width: sideMaxWidth + notchGapFill, alignment: .trailing)
                .opacity(isVisible ? 1 : 0)
                .offset(x: isVisible ? 0 : notchDimensions.width / 2 + notchGapFill)

                // Notch spacer (reduced by gap fill on both sides)
                Color.clear
                    .frame(width: notchDimensions.width - (notchGapFill * 2), height: notchDimensions.height)

                // Right background - extends left into notch area
                HStack(spacing: 0) {
                    RightPanelShape(cornerRadius: 10, topCornerRadius: 6, innerCornerRadius: 8)
                        .fill(Color.black)
                        .frame(width: rightContentWidth + notchGapFill, height: notchDimensions.height)
                    Spacer(minLength: 0)
                }
                .frame(width: sideMaxWidth + notchGapFill, alignment: .leading)
                .opacity(isVisible ? 1 : 0)
                .offset(x: isVisible ? 0 : -(notchDimensions.width / 2 + notchGapFill))
            }
            .frame(width: sideMaxWidth + notchDimensions.width + sideMaxWidth, height: notchDimensions.height)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isVisible)

            // CONTENT LAYER: Positioned normally without overlap
            HStack(spacing: 0) {
                // Left content container
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    AlbumArtView(albumArt: info.albumArt, isPlaying: info.isPlaying)
                        .frame(width: notchDimensions.height, height: notchDimensions.height)
                }
                .frame(width: sideMaxWidth, alignment: .trailing)
                .opacity(isVisible ? 1 : 0)
                .offset(x: isVisible ? 0 : notchDimensions.width / 2)

                // Notch spacer
                Color.clear
                    .frame(width: notchDimensions.width, height: notchDimensions.height)

                // Right content container
                HStack(spacing: 0) {
                    Group {
                        if showingTrackInfo {
                            TrackInfoView(info: info)
                        } else {
                            MusicVisualizerView(isPlaying: info.isPlaying)
                        }
                    }
                    .frame(width: rightContentWidth, height: notchDimensions.height)
                    Spacer(minLength: 0)
                }
                .frame(width: sideMaxWidth, alignment: .leading)
                .opacity(isVisible ? 1 : 0)
                .offset(x: isVisible ? 0 : -notchDimensions.width / 2)
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: showingTrackInfo)
            }
            .frame(width: sideMaxWidth + notchDimensions.width + sideMaxWidth, height: notchDimensions.height)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isVisible)
        }
        // Total width: sideMaxWidth + notchWidth + sideMaxWidth (FIXED, never changes)
        .frame(width: sideMaxWidth + notchDimensions.width + sideMaxWidth, height: notchDimensions.height)
        .onChange(of: info.trackIdentifier) { _ in
            showTrackInfo()
        }
        .onAppear {
            if info.isPlaying {
                showTrackInfo()
            }
        }
    }

    /// Calculate the width needed for track info based on text content
    private func calculateTrackInfoWidth() -> CGFloat {
        let titleFont = NSFont.systemFont(ofSize: 11, weight: .medium)
        let artistFont = NSFont.systemFont(ofSize: 9, weight: .regular)

        let titleWidth = info.title.width(using: titleFont)
        let artistWidth = info.artist.width(using: artistFont)

        let textWidth = max(titleWidth, artistWidth)

        // Add padding and clamp to reasonable bounds
        let paddedWidth = textWidth + 16
        let minWidth = notchDimensions.height  // At least as wide as visualizer
        let maxWidth = sideMaxWidth  // Max width of container

        return min(max(paddedWidth, minWidth), maxWidth)
    }

    private func showTrackInfo() {
        trackInfoTimer?.invalidate()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showingTrackInfo = true
        }

        trackInfoTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showingTrackInfo = false
            }
        }
    }
}

/// Shape for LEFT panel - curved outer edges, inner edge curves outward to connect with notch
struct LeftPanelShape: Shape {
    let cornerRadius: CGFloat
    let topCornerRadius: CGFloat
    let innerCornerRadius: CGFloat  // Curves outward to match notch's bottom corner

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Top-left: outward curve (curves away from center)
        path.move(to: CGPoint(x: topCornerRadius, y: 0))
        path.addQuadCurve(
            to: CGPoint(x: 0, y: topCornerRadius),
            control: CGPoint(x: 0, y: 0)
        )

        // Left edge down to bottom corner
        path.addLine(to: CGPoint(x: 0, y: rect.height - cornerRadius))

        // Bottom-left rounded corner (inward curve)
        path.addQuadCurve(
            to: CGPoint(x: cornerRadius, y: rect.height),
            control: CGPoint(x: 0, y: rect.height)
        )

        // Bottom edge to inner corner
        path.addLine(to: CGPoint(x: rect.width - innerCornerRadius, y: rect.height))

        // Bottom-right: outward curve (concave - matches notch's corner)
        path.addQuadCurve(
            to: CGPoint(x: rect.width, y: rect.height - innerCornerRadius),
            control: CGPoint(x: rect.width, y: rect.height)
        )

        // Right edge straight up to top
        path.addLine(to: CGPoint(x: rect.width, y: 0))

        // Top edge back to start
        path.addLine(to: CGPoint(x: topCornerRadius, y: 0))

        return path
    }
}

/// Shape for RIGHT panel - curved outer edges, inner edge curves outward to connect with notch
struct RightPanelShape: Shape {
    let cornerRadius: CGFloat
    let topCornerRadius: CGFloat
    let innerCornerRadius: CGFloat  // Curves outward to match notch's bottom corner

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Start at top-left (connects to notch)
        path.move(to: CGPoint(x: 0, y: 0))

        // Left edge straight down to inner corner
        path.addLine(to: CGPoint(x: 0, y: rect.height - innerCornerRadius))

        // Bottom-left: outward curve (concave - matches notch's corner)
        path.addQuadCurve(
            to: CGPoint(x: innerCornerRadius, y: rect.height),
            control: CGPoint(x: 0, y: rect.height)
        )

        // Bottom edge to outer corner
        path.addLine(to: CGPoint(x: rect.width - cornerRadius, y: rect.height))

        // Bottom-right rounded corner (inward curve)
        path.addQuadCurve(
            to: CGPoint(x: rect.width, y: rect.height - cornerRadius),
            control: CGPoint(x: rect.width, y: rect.height)
        )

        // Right edge up to top corner
        path.addLine(to: CGPoint(x: rect.width, y: topCornerRadius))

        // Top-right: outward curve (curves away from center)
        path.addQuadCurve(
            to: CGPoint(x: rect.width - topCornerRadius, y: 0),
            control: CGPoint(x: rect.width, y: 0)
        )

        // Top edge back to start
        path.addLine(to: CGPoint(x: 0, y: 0))

        return path
    }
}

// MARK: - Album Art
struct AlbumArtView: View {
    let albumArt: NSImage?
    let isPlaying: Bool

    var body: some View {
        Group {
            if let albumArt = albumArt {
                Image(nsImage: albumArt)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .id(albumArt) // Force view update when image changes
            } else {
                // Use Music.app icon as placeholder
                Image(nsImage: NSWorkspace.shared.icon(forFile: "/System/Applications/Music.app"))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .frame(width: 22, height: 22)  // Match window icon size
        .scaleEffect(isPlaying ? 1.0 : 0.9)
        .opacity(isPlaying ? 1.0 : 0.5)
        .animation(.easeOut(duration: 0.3), value: isPlaying)
    }
}

// MARK: - Music Visualizer (compact 5 bars)
struct MusicVisualizerView: View {
    let isPlaying: Bool

    @State private var barHeights: [CGFloat] = [6, 10, 14, 10, 6]
    private let barCount = 5
    private let timer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: 2, height: isPlaying ? barHeights[safe: i] ?? 8 : 3)
                    .animation(
                        .easeInOut(duration: 0.35),
                        value: barHeights[safe: i]
                    )
            }
        }
        .frame(height: 22)  // Match window icon height
        .onAppear {
            if isPlaying {
                updateBars()
            }
        }
        .onReceive(timer) { _ in
            if isPlaying {
                updateBars()
            }
        }
        .onChange(of: isPlaying) { newValue in
            if !newValue {
                resetBars()
            } else {
                updateBars()
            }
        }
    }

    private func updateBars() {
        // Randomize heights - scaled down for compact display
        barHeights = [
            CGFloat.random(in: 4...10),
            CGFloat.random(in: 6...14),
            CGFloat.random(in: 8...18),
            CGFloat.random(in: 6...14),
            CGFloat.random(in: 4...10)
        ]
    }

    private func resetBars() {
        barHeights = [3, 3, 3, 3, 3]
    }
}

// MARK: - Track Info Display (shows on track change)
struct TrackInfoView: View {
    let info: MusicInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            // Track title - compact sizing
            Text(info.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)

            // Artist name - compact sizing
            Text(info.artist)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }
}

// Helper extension for safe array access
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// Helper extension for string width measurement
private extension String {
    func width(using font: NSFont) -> CGFloat {
        let attributes = [NSAttributedString.Key.font: font]
        return (self as NSString).size(withAttributes: attributes).width
    }
}
