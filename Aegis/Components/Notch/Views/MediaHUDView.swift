import SwiftUI
import Cocoa
import Combine

// Shared font definitions for track info display
private let trackTitleFont = NSFont.systemFont(ofSize: 11, weight: .medium)
private let trackArtistFont = NSFont.systemFont(ofSize: 9, weight: .regular)

struct MediaHUDView: View {
    @ObservedObject var viewModel: MediaHUDViewModel
    let notchDimensions: NotchDimensions
    @Binding var isVisible: Bool
    // When true, this indicates the HUD was shown for a fullscreen track change.
    // In that mode we should avoid collapsing the expanded width before sliding out.
    @Binding var isFullscreenTrackChangeMode: Bool

    // State to control which mode we're in
    @State private var showingTrackInfo = false
    @State private var trackInfoTimer: Timer?

    @ObservedObject private var config = AegisConfig.shared

    // Convenience accessor for info
    private var info: MediaInfo {
        viewModel.info
    }

    // Panel widths - match Volume/Brightness HUD for consistency
    // Left side (album art): fixed square size
    private var leftPanelWidth: CGFloat {
        notchDimensions.height
    }

    // Base right panel width (for visualizer)
    private var baseRightPanelWidth: CGFloat {
        config.notchHUDProgressBarWidth + 16
    }

    // Whether to use expanded width for track info
    @State private var useExpandedWidth = false
    @State private var collapseTimer: Timer?
    // Internal guard to persist "skip collapse" behavior across the brief
    // window during which the controller may reset its public flag.
    @State private var skipCollapseOnHide = false
    // Cached expanded width - recalculated only when track changes
    @State private var cachedExpandedWidth: CGFloat = 0
    @State private var cachedExpandedTrackId: String = ""

    // Calculate expanded width based on track info text (cached)
    private var expandedRightPanelWidth: CGFloat {
        // Return cached value if track hasn't changed
        if info.trackIdentifier == cachedExpandedTrackId && cachedExpandedWidth > 0 {
            return cachedExpandedWidth
        }
        return baseRightPanelWidth  // Fallback until cache is updated
    }

    // Calculate expanded width for a track (pure function for cache updates)
    private func calculateExpandedWidth() -> CGFloat {
        let titleWidth = info.title.width(using: trackTitleFont)
        let artistWidth = info.artist.width(using: trackArtistFont)

        // Take the wider of title/artist, add padding
        let textWidth = max(titleWidth, artistWidth) + 24  // 24 for horizontal padding

        // Cap at a reasonable max width, but allow expansion beyond base
        let maxWidth: CGFloat = 200
        return min(max(baseRightPanelWidth, textWidth), maxWidth)
    }

    // Current right panel width (animated between base and expanded)
    private var rightPanelWidth: CGFloat {
        if shouldShowTrackInfo && useExpandedWidth {
            return expandedRightPanelWidth
        }
        return baseRightPanelWidth
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
        return config.mediaHUDRightPanelMode == .trackInfo
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
                        .frame(width: rightPanelWidth + notchGapFill, height: notchDimensions.height)
                    Spacer(minLength: 0)
                }
                .frame(width: sideMaxWidth + notchGapFill, alignment: .leading)
                .opacity(showRightPanel ? 1 : 0)
                .offset(x: showRightPanel ? 0 : -(notchDimensions.width / 2 + notchGapFill))
            }
            .frame(width: sideMaxWidth + notchDimensions.width + sideMaxWidth, height: notchDimensions.height)
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
                        // Track info: left-aligned, clipped to panel width
                        TrackInfoView(
                            info: info,
                            containerWidth: rightPanelWidth,
                            collapsedWidth: baseRightPanelWidth,
                            isExpanded: useExpandedWidth
                        )
                            .frame(height: notchDimensions.height, alignment: .leading)
                        Spacer(minLength: 0)
                    } else {
                        // Visualizer: centered
                        MediaVisualizerView(isPlaying: info.isPlaying, useBlurEffect: config.visualizerUseBlurEffect)
                            .frame(width: rightPanelWidth, height: notchDimensions.height)
                    }
                }
                .frame(width: sideMaxWidth, alignment: shouldShowTrackInfo ? .leading : .center)
                .clipped()
                .opacity(showRightPanel ? 1 : 0)
                .offset(x: showRightPanel ? 0 : -notchDimensions.width / 2)
            }
            .frame(width: sideMaxWidth + notchDimensions.width + sideMaxWidth, height: notchDimensions.height)
        }
        // Total width: sideMaxWidth + notchWidth + sideMaxWidth (animates with content)
        .frame(width: sideMaxWidth + notchDimensions.width + sideMaxWidth, height: notchDimensions.height)
        // Consolidated animations - single animation block for all state changes
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isVisible)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: viewModel.isOverlayActive)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: shouldShowTrackInfo)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: useExpandedWidth)
        .onChange(of: info.trackIdentifier) { _ in
            // Reset pinned state when track changes so auto-display works for new songs
            trackInfoPinned = false
            // Update cached expanded width for new track
            cachedExpandedWidth = calculateExpandedWidth()
            cachedExpandedTrackId = info.trackIdentifier
            // Show track info temporarily on track change
            showTrackInfo()
        }
        .onChange(of: isVisible) { newVisible in
            // When HUD is hidden, cancel any pending collapse timer. If we were
            // shown as a fullscreen track-change, keep the expanded width until
            // the slide-out animation completes (avoid collapsing first).
            if !newVisible {
                collapseTimer?.invalidate()
                collapseTimer = nil

                if skipCollapseOnHide {
                    // Reset the guard after animations finish on the controller side
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        skipCollapseOnHide = false
                    }
                } else {
                    // Ensure we collapse to default width when fully hidden
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        useExpandedWidth = false
                    }
                }
            }
        }
        .onAppear {
            // Initialize cached expanded width
            cachedExpandedWidth = calculateExpandedWidth()
            cachedExpandedTrackId = info.trackIdentifier
            // Publish initial width to view model
            viewModel.currentRightPanelWidth = rightPanelWidth
            // Initialize based on config
            if config.mediaHUDRightPanelMode == .trackInfo {
                showingTrackInfo = true
                trackInfoPinned = true  // Don't auto-hide if config says track info
            } else if info.isPlaying {
                showTrackInfo()
            }
        }
        .onChange(of: config.mediaHUDRightPanelMode) { newMode in
            // Respond to config changes
            trackInfoPinned = false
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                showingTrackInfo = (newMode == .trackInfo)
            }
            if newMode == .trackInfo {
                trackInfoPinned = true  // Pin it so it doesn't auto-hide
            }
        }
        .onChange(of: rightPanelWidth) { newWidth in
            // Publish width to view model so overlay HUD can match it
            viewModel.currentRightPanelWidth = newWidth
        }
        .onReceive(NotificationCenter.default.publisher(for: .mediaHUDToggleDisplay)) { _ in
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
        collapseTimer?.invalidate()

        // Expand width and show track info
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showingTrackInfo = true
            useExpandedWidth = true
        }

        // If we're in fullscreen track-change mode, avoid scheduling the
        // collapse animation so the HUD can slide out directly without
        // first collapsing to the default width.
        if isFullscreenTrackChangeMode {
            skipCollapseOnHide = true
        } else {
            // Schedule collapse to standard width after 3 seconds
            collapseTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    useExpandedWidth = false
                }
            }
        }

        // If config is visualizer mode, switch back to visualizer after 5 seconds
        // If config is track info mode, keep showing track info (just collapse width)
        if config.mediaHUDRightPanelMode == .visualizer {
            trackInfoTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showingTrackInfo = false
                }
            }
        }
    }
}

extension Notification.Name {
    static let mediaHUDToggleDisplay = Notification.Name("mediaHUDToggleDisplay")
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
struct MediaVisualizerView: View {
    let isPlaying: Bool
    let useBlurEffect: Bool

    @State private var h0: CGFloat = 6
    @State private var h1: CGFloat = 10
    @State private var h2: CGFloat = 14
    @State private var h3: CGFloat = 10
    @State private var h4: CGFloat = 6
    @State private var animationTimer: Timer?

    var body: some View {
        HStack(spacing: 2) {
            VisualizerBar(height: isPlaying ? h0 : 3, useBlur: useBlurEffect)
            VisualizerBar(height: isPlaying ? h1 : 3, useBlur: useBlurEffect)
            VisualizerBar(height: isPlaying ? h2 : 3, useBlur: useBlurEffect)
            VisualizerBar(height: isPlaying ? h3 : 3, useBlur: useBlurEffect)
            VisualizerBar(height: isPlaying ? h4 : 3, useBlur: useBlurEffect)
        }
        .frame(height: 22)
        .onAppear {
            if isPlaying { startTimer() }
        }
        .onDisappear {
            stopTimer()
        }
        .onChange(of: isPlaying) { newValue in
            if newValue {
                startTimer()
            } else {
                stopTimer()
                withAnimation(.easeInOut(duration: 0.2)) {
                    h0 = 3; h1 = 3; h2 = 3; h3 = 3; h4 = 3
                }
            }
        }
    }

    private func startTimer() {
        guard animationTimer == nil else { return }
        updateBars()
        // 2.5 FPS - optimized for low CPU usage (background ambient indicator)
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            updateBars()
        }
    }

    private func stopTimer() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func updateBars() {
        // Batch update with single animation
        withAnimation(.easeInOut(duration: 0.25)) {
            h0 = .random(in: 4...10)
            h1 = .random(in: 6...14)
            h2 = .random(in: 8...18)
            h3 = .random(in: 6...14)
            h4 = .random(in: 4...10)
        }
    }
}

// MARK: - Single Visualizer Bar
private struct VisualizerBar: View {
    let height: CGFloat
    let useBlur: Bool

    var body: some View {
        if useBlur {
            Capsule()
                .fill(.ultraThinMaterial)
                .frame(width: 2, height: height)
        } else {
            Capsule()
                .fill(Color.white.opacity(0.9))
                .frame(width: 2, height: height)
        }
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
    let info: MediaInfo
    let containerWidth: CGFloat      // Current width (may be expanded or collapsed)
    let collapsedWidth: CGFloat      // Fixed collapsed width for overflow calculation
    let isExpanded: Bool             // Whether panel is expanded

    // Cached text widths - only recalculated when title/artist changes
    @State private var cachedTitleWidth: CGFloat = 0
    @State private var cachedArtistWidth: CGFloat = 0
    @State private var cachedTrackId: String = ""

    // Available width for text when collapsed (minus padding)
    private var collapsedTextWidth: CGFloat {
        collapsedWidth - 16  // 8pt padding on each side
    }

    // Use cached text widths
    private var titleTextWidth: CGFloat { cachedTitleWidth }
    private var artistTextWidth: CGFloat { cachedArtistWidth }

    // Check which texts overflow (only valid if cache is initialized)
    // Small tolerance (2pt) to account for text rendering variations
    private let overflowTolerance: CGFloat = 2

    private var titleOverflows: Bool {
        cachedTitleWidth > 0 && titleTextWidth > (collapsedTextWidth + overflowTolerance)
    }
    private var artistOverflows: Bool {
        cachedArtistWidth > 0 && artistTextWidth > (collapsedTextWidth + overflowTolerance)
    }
    private var anyTextOverflows: Bool {
        titleOverflows || artistOverflows
    }
    private var bothOverflow: Bool {
        titleOverflows && artistOverflows
    }

    // Synced scroll distance - when both overflow, use the longer one for both
    private var syncedScrollDistance: CGFloat {
        if bothOverflow {
            return max(titleTextWidth, artistTextWidth) + gap
        }
        return 0  // Not used when only one overflows
    }

    // Scroll state managed by MarqueeController
    @StateObject private var scrollController = MarqueeScrollController()

    // Timing configuration
    private let gap: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            // Track title - only scrolls if title overflows
            MarqueeTextRow(
                text: info.title,
                font: trackTitleFont,
                textColor: .white.opacity(0.9),
                textWidth: titleTextWidth,
                scrollOffset: titleOverflows ? scrollController.offset : 0,
                isScrolling: scrollController.isScrolling && titleOverflows,
                gap: gap,
                syncedDistance: bothOverflow ? syncedScrollDistance : nil
            )
            .frame(height: 14)

            // Artist name - only scrolls if artist overflows
            MarqueeTextRow(
                text: info.artist,
                font: trackArtistFont,
                textColor: .white.opacity(0.6),
                textWidth: artistTextWidth,
                scrollOffset: artistOverflows ? scrollController.offset : 0,
                isScrolling: scrollController.isScrolling && artistOverflows,
                gap: gap,
                syncedDistance: bothOverflow ? syncedScrollDistance : nil
            )
            .frame(height: 12)
        }
        .padding(.horizontal, 8)
        .frame(width: containerWidth, alignment: .leading)
        .clipped()
        .onAppear {
            // Calculate initial text widths
            updateCachedWidths()
            // Start scrolling if already in collapsed state with overflow
            if !isExpanded && anyTextOverflows {
                startScrolling()
            }
        }
        .onDisappear {
            scrollController.stop()
        }
        .onChange(of: isExpanded) { newIsExpanded in
            handleExpandedChange(newIsExpanded: newIsExpanded)
        }
        .onChange(of: info.trackIdentifier) { _ in
            // Track changed - FIRST stop any existing scrolling, then recalculate widths
            scrollController.stop()
            updateCachedWidths()
        }
    }

    /// Update cached text widths - called when track changes
    private func updateCachedWidths() {
        // Always recalculate when called - the caller decides when to call this
        // (on appear, on track change)
        cachedTitleWidth = info.title.width(using: trackTitleFont)
        cachedArtistWidth = info.artist.width(using: trackArtistFont)
        cachedTrackId = info.trackIdentifier
    }

    private func handleExpandedChange(newIsExpanded: Bool) {
        if newIsExpanded {
            scrollController.stop()
        } else {
            // Ensure cache is fresh before checking overflow
            updateCachedWidths()
            if anyTextOverflows {
                startScrolling()
            }
        }
    }

    private func startScrolling() {
        // Double-check overflow with fresh calculation as a safety measure
        let currentTitleWidth = info.title.width(using: trackTitleFont)
        let currentArtistWidth = info.artist.width(using: trackArtistFont)
        let availableWidth = collapsedTextWidth + overflowTolerance

        let titleDistance = currentTitleWidth > availableWidth ? currentTitleWidth + gap : 0
        let artistDistance = currentArtistWidth > availableWidth ? currentArtistWidth + gap : 0
        let maxDistance = max(titleDistance, artistDistance)

        // Only start scrolling if there's actually a distance to scroll
        guard maxDistance > 0 else { return }
        scrollController.start(distance: maxDistance)
    }
}

// MARK: - Marquee Scroll Controller (energy-efficient timer-based animation)
/// Uses a low-frequency timer instead of SwiftUI animation for reduced energy impact
final class MarqueeScrollController: ObservableObject {
    @Published private(set) var offset: CGFloat = 0
    @Published private(set) var isScrolling: Bool = false

    private var displayLink: CVDisplayLink?
    private var timer: Timer?
    private var startTime: CFTimeInterval = 0
    private var scrollDistance: CGFloat = 0
    private var phase: ScrollPhase = .idle

    // Timing configuration
    private let initialDelay: Double = 2.1  // 600ms settle + 1500ms start delay
    private let scrollSpeed: Double = 30.0  // points per second
    private let endPause: Double = 1.0
    private let resetPause: Double = 0.3

    private enum ScrollPhase {
        case idle
        case initialDelay
        case scrolling
        case endPause
        case resetPause
    }

    deinit {
        stop()
    }

    func start(distance: CGFloat) {
        guard !isScrolling else { return }
        scrollDistance = distance
        isScrolling = true
        offset = 0
        phase = .initialDelay
        startTime = CACurrentMediaTime()

        // Use a 20fps timer - sufficient for smooth text scrolling, 67% less energy than 60fps
        let newTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer = newTimer
        RunLoop.current.add(newTimer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        phase = .idle
        isScrolling = false
        offset = 0
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let elapsed = now - startTime

        switch phase {
        case .idle:
            break

        case .initialDelay:
            if elapsed >= initialDelay {
                phase = .scrolling
                startTime = now
            }

        case .scrolling:
            let scrollDuration = scrollDistance / scrollSpeed
            let progress = min(elapsed / scrollDuration, 1.0)
            offset = scrollDistance * progress

            if progress >= 1.0 {
                phase = .endPause
                startTime = now
            }

        case .endPause:
            if elapsed >= endPause {
                offset = 0
                phase = .resetPause
                startTime = now
            }

        case .resetPause:
            if elapsed >= resetPause {
                phase = .scrolling
                startTime = now
            }
        }
    }
}

// MARK: - Marquee Text Row (handles individual text scrolling)
struct MarqueeTextRow: View {
    let text: String
    let font: NSFont
    let textColor: Color
    let textWidth: CGFloat
    let scrollOffset: CGFloat
    let isScrolling: Bool  // Whether THIS row should be scrolling
    let gap: CGFloat
    let syncedDistance: CGFloat?  // When both rows scroll, use this to position duplicate

    var body: some View {
        HStack(spacing: 0) {
            Text(text)
                .font(Font(font))
                .foregroundColor(textColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            // Only show duplicate if this specific row is scrolling
            if isScrolling {
                // Spacer to position duplicate at correct distance
                // If synced, use synced distance; otherwise use own text width + gap
                let spacerWidth = (syncedDistance ?? (textWidth + gap)) - textWidth

                Spacer()
                    .frame(width: spacerWidth)

                Text(text)
                    .font(Font(font))
                    .foregroundColor(textColor)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        // Use drawingGroup to rasterize and animate as a single layer (GPU-accelerated)
        .drawingGroup()
        .offset(x: -scrollOffset)
    }
}

// Helper extension for safe array access
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

