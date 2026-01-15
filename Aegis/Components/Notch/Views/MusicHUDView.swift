import SwiftUI
import Combine
import Cocoa

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

    // Panel widths - match Volume/Brightness HUD for consistency
    // Left side (album art): fixed square size
    private var leftPanelWidth: CGFloat {
        notchDimensions.height
    }

    // Right side (visualizer or track info): match progress bar width
    private var rightPanelWidth: CGFloat {
        config.notchHUDProgressBarWidth + 16
    }

    // Use symmetric max width for centering (same pattern as MinimalHUDWrapper)
    private var sideMaxWidth: CGFloat {
        max(leftPanelWidth, rightPanelWidth)
    }

    // How far the black background extends into the notch area to fill the gap
    // This only affects the background shape, not the content position
    private let notchGapFill: CGFloat = 18

    // Whether track info is pinned (user clicked to toggle, disables auto-timer)
    @State private var trackInfoPinned = false

    // Whether to show the right panel (hidden when overlay HUD is active)
    private var showRightPanel: Bool {
        isVisible && !viewModel.isOverlayActive
    }

    // Whether to show track info (based on config + temporary override state)
    private var shouldShowTrackInfo: Bool {
        // If user has pinned or temporarily toggled, use local state
        if trackInfoPinned || showingTrackInfo {
            return showingTrackInfo
        }
        // Otherwise, use config default
        return config.musicHUDRightPanelMode == .trackInfo
    }

    // Right side content width (fixed to match progress bar)
    private var rightContentWidth: CGFloat {
        rightPanelWidth
    }

    var body: some View {
        // SYMMETRICAL three-column layout
        // Both containers have the same max width for proper centering
        // Content within each container is pinned to the notch edge

        ZStack {
            // BACKGROUND LAYER: Black shapes that extend into notch area to fill gaps
            // Not interactive - clicks pass through
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
                // Hidden when overlay HUD (volume/brightness) is active
                HStack(spacing: 0) {
                    RightPanelShape(cornerRadius: 10, topCornerRadius: 6, innerCornerRadius: 8)
                        .fill(Color.black)
                        .frame(width: rightContentWidth + notchGapFill, height: notchDimensions.height)
                    Spacer(minLength: 0)
                }
                .frame(width: sideMaxWidth + notchGapFill, alignment: .leading)
                .opacity(showRightPanel ? 1 : 0)
                .offset(x: showRightPanel ? 0 : -(notchDimensions.width / 2 + notchGapFill))
            }
            .frame(width: sideMaxWidth + notchDimensions.width + sideMaxWidth, height: notchDimensions.height)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isVisible)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: viewModel.isOverlayActive)
            .allowsHitTesting(false)

            // CONTENT LAYER: Positioned normally without overlap
            HStack(spacing: 0) {
                // Left content container (album art - tap handled by separate interaction window)
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    AlbumArtView(albumArt: info.albumArt, isPlaying: info.isPlaying)
                        .frame(width: notchDimensions.height, height: notchDimensions.height)
                }
                .frame(width: sideMaxWidth, alignment: .trailing)
                .opacity(isVisible ? 1 : 0)
                .offset(x: isVisible ? 0 : notchDimensions.width / 2)

                // Notch spacer - clicks pass through
                Color.clear
                    .frame(width: notchDimensions.width, height: notchDimensions.height)
                    .allowsHitTesting(false)

                // Right content container - shows visualizer or track info based on config
                // Hidden when overlay HUD (volume/brightness) is active
                HStack(spacing: 0) {
                    if shouldShowTrackInfo {
                        // Track info: left-aligned
                        TrackInfoView(info: info)
                            .frame(width: rightContentWidth, height: notchDimensions.height)
                        Spacer(minLength: 0)
                    } else {
                        // Visualizer: centered
                        MusicVisualizerView(isPlaying: info.isPlaying)
                            .frame(width: rightContentWidth, height: notchDimensions.height)
                    }
                }
                .frame(width: sideMaxWidth, alignment: shouldShowTrackInfo ? .leading : .center)
                .opacity(showRightPanel ? 1 : 0)
                .offset(x: showRightPanel ? 0 : -notchDimensions.width / 2)
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: shouldShowTrackInfo)
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: viewModel.isOverlayActive)
            }
            .frame(width: sideMaxWidth + notchDimensions.width + sideMaxWidth, height: notchDimensions.height)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isVisible)
        }
        // Total width: sideMaxWidth + notchWidth + sideMaxWidth (FIXED, never changes)
        .frame(width: sideMaxWidth + notchDimensions.width + sideMaxWidth, height: notchDimensions.height)
        .onChange(of: info.trackIdentifier) { _ in
            // Reset pinned state when track changes so auto-display works for new songs
            trackInfoPinned = false
            // Only show temporary track info if config is set to visualizer mode
            // (if already showing track info by config, no need for temporary display)
            if config.musicHUDRightPanelMode == .visualizer {
                showTrackInfo()
            }
        }
        .onAppear {
            // Initialize based on config
            if config.musicHUDRightPanelMode == .trackInfo {
                showingTrackInfo = true
                trackInfoPinned = true  // Don't auto-hide if config says track info
            } else if info.isPlaying {
                showTrackInfo()
            }
        }
        .onChange(of: config.musicHUDRightPanelMode) { newMode in
            // Respond to config changes
            trackInfoPinned = false
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                showingTrackInfo = (newMode == .trackInfo)
            }
            if newMode == .trackInfo {
                trackInfoPinned = true  // Pin it so it doesn't auto-hide
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .musicHUDToggleDisplay)) { _ in
            toggleTrackInfoDisplay()
        }
    }

    /// Toggle between visualizer and track info display (user-initiated)
    private func toggleTrackInfoDisplay() {
        // Cancel any auto-timer
        trackInfoTimer?.invalidate()
        trackInfoTimer = nil

        // Toggle and pin the state
        trackInfoPinned = true
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            showingTrackInfo.toggle()
        }
    }

    /// Show track info temporarily (auto-triggered on track change)
    private func showTrackInfo() {
        // Don't override if user has pinned the display
        if trackInfoPinned { return }

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

// MARK: - Tap View for Interaction Window

/// Invisible tap target for toggling visualizer/track info
/// This is hosted in a separate small window over the album art
struct MusicHUDTapView: View {
    @ObservedObject var viewModel: MusicHUDViewModel

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                // Toggle the showTrackInfo state via notification
                NotificationCenter.default.post(
                    name: .musicHUDToggleDisplay,
                    object: nil
                )
            }
    }
}

extension Notification.Name {
    static let musicHUDToggleDisplay = Notification.Name("musicHUDToggleDisplay")
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

    // Track the current album art for fade transitions
    @State private var displayedArt: NSImage?
    @State private var artOpacity: Double = 1.0

    var body: some View {
        ZStack {
            // Black placeholder (always present, merges with notch)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.black)

            // Album art with fade transition
            if let art = displayedArt {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .opacity(artOpacity)
            }
        }
        .frame(width: 22, height: 22)  // Match window icon size
        .scaleEffect(isPlaying ? 1.0 : 0.9)
        .animation(.easeOut(duration: 0.3), value: isPlaying)
        .onChange(of: albumArt) { newArt in
            // Fade out, swap, fade in
            withAnimation(.easeOut(duration: 0.15)) {
                artOpacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                displayedArt = newArt
                withAnimation(.easeIn(duration: 0.2)) {
                    artOpacity = 1.0
                }
            }
        }
        .onAppear {
            displayedArt = albumArt
        }
    }
}

// MARK: - Music Visualizer (compact 5 bars)
struct MusicVisualizerView: View {
    let isPlaying: Bool

    @ObservedObject private var config = AegisConfig.shared
    @State private var barHeights: [CGFloat] = [6, 10, 14, 10, 6]
    private let barCount = 5
    private let timer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if config.visualizerUseBlurEffect {
                // Blur effect mode: bars show blurred wallpaper
                BlurVisualizerBars(barHeights: barHeights, isPlaying: isPlaying)
            } else {
                // Standard mode: solid white bars
                SolidVisualizerBars(barHeights: barHeights, isPlaying: isPlaying)
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

// MARK: - Solid Visualizer Bars (default mode)
private struct SolidVisualizerBars: View {
    let barHeights: [CGFloat]
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 2, height: isPlaying ? barHeights[safe: i] ?? 8 : 3)
                    .animation(
                        .easeInOut(duration: 0.35),
                        value: barHeights[safe: i]
                    )
            }
        }
    }
}

// MARK: - Blur Visualizer Bars (transparent blur effect)
private struct BlurVisualizerBars: View {
    let barHeights: [CGFloat]
    let isPlaying: Bool

    // Calculate total width of all bars + spacing
    private var totalWidth: CGFloat {
        let barWidth: CGFloat = 2
        let spacing: CGFloat = 2
        return (barWidth * 5) + (spacing * 4)
    }

    var body: some View {
        // Use a blur rectangle masked by the bar shapes
        VisualizerBlurView()
            .frame(width: totalWidth, height: 22)
            .mask(
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { i in
                        Capsule()
                            .frame(width: 2, height: isPlaying ? barHeights[safe: i] ?? 8 : 3)
                            .animation(
                                .easeInOut(duration: 0.35),
                                value: barHeights[safe: i]
                            )
                    }
                }
            )
    }
}

// MARK: - Visualizer Blur View (NSVisualEffectView wrapper)
private struct VisualizerBlurView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        // Use a light material that shows the wallpaper through
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        // No updates needed
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

