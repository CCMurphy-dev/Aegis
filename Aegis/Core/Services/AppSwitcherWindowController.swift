import AppKit
import SwiftUI
import Combine  // Required for @Published property wrapper

/// Custom NSPanel subclass that can become key to receive mouse clicks
/// while still being a non-activating panel (won't steal app focus)
class ClickablePanel: AegisOverlayPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Window controller for the app switcher overlay
/// Displays windows organized by space in a centered panel
/// Transparent overlay view that renders the selection highlight via CALayer
class SelectionOverlayView: NSView {
    let selectionLayer = CALayer()
    private var palette: AegisSurfacePalette?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(selectionLayer)

        apply(palette: AegisSurfaceAppearance.palette(
            theme: AegisConfig.shared.appTheme,
            isDarkMode: ThemeManager.shared.isDarkMode,
            customBackground: AegisConfig.shared.customBackgroundColor,
            customForeground: AegisConfig.shared.customTextColor,
            customBorder: AegisConfig.shared.customBorderColor
        ))
        selectionLayer.borderWidth = 1
        selectionLayer.cornerRadius = 6
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(palette: AegisSurfacePalette) {
        self.palette = palette
        updateResolvedColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateResolvedColors()
    }

    private func updateResolvedColors() {
        guard let palette else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let fill = palette.selectionFill.usingColorSpace(.deviceRGB) ?? palette.selectionFill
            let border = palette.selectionBorder.usingColorSpace(.deviceRGB) ?? palette.selectionBorder
            selectionLayer.backgroundColor = fill.cgColor
            selectionLayer.borderColor = border.cgColor
        }
    }

    // Pass through all mouse events to underlying views
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}

final class AppSwitcherWindowController {

    private var window: NSWindow?
    private var viewModel = AppSwitcherViewModel()

    // Selection overlay view with CALayer - positioned on top of SwiftUI content
    private var selectionOverlay: SelectionOverlayView?
    private var hostingView: NSHostingView<AppSwitcherView>?
    private var themeObserver: NSObjectProtocol?
    private var appearanceObserver: NSObjectProtocol?
    private var configCancellable: AnyCancellable?

    // Layout constants for calculating selection position
    private let iconRowHeight: CGFloat = 32
    private let previewRowHeight: CGFloat = 87
    private let padding: CGFloat = 12
    private let dividerHeight: CGFloat = 13
    private let searchBarHeight: CGFloat = 28 + 8  // height + padding

    private var rowHeight: CGFloat {
        AegisConfig.shared.appSwitcherShowPreviews ? previewRowHeight : iconRowHeight
    }

    // Rapid scroll detection - disable animation during fast input
    private var lastUpdateTime: CFTimeInterval = 0
    private let rapidScrollThreshold: CFTimeInterval = 0.15  // If updates < 150ms apart, skip animation

    /// Callback when selection changes via mouse hover
    var onSelectionChanged: ((Int) -> Void)?

    /// Callback when user clicks to confirm selection
    var onSelectionConfirmed: ((Int) -> Void)?

    /// Callback when user scrolls to cycle selection (direction: -1 for previous, +1 for next)
    var onScrollCycle: ((Int) -> Void)?

    init() {
        setupWindow()
        setupCallbacks()
        setupAppearanceObservers()
    }

    deinit {
        if let themeObserver { NotificationCenter.default.removeObserver(themeObserver) }
        if let appearanceObserver { NotificationCenter.default.removeObserver(appearanceObserver) }
    }

    private func setupAppearanceObservers() {
        themeObserver = NotificationCenter.default.addObserver(
            forName: .themeDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.updateAppearance() }
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { [weak self] _ in self?.updateAppearance() }
        configCancellable = AegisConfig.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateAppearance() }
    }

    private func updateAppearance() {
        let config = AegisConfig.shared
        let palette = AegisSurfaceAppearance.palette(
            theme: config.appTheme,
            isDarkMode: ThemeManager.shared.isDarkMode,
            customBackground: config.customBackgroundColor,
            customForeground: config.customTextColor,
            customBorder: config.customBorderColor
        )
        selectionOverlay?.apply(palette: palette)
        hostingView?.rootView = AppSwitcherView(viewModel: viewModel)
    }

    private func setupCallbacks() {
        viewModel.onHover = { [weak self] index in
            self?.onSelectionChanged?(index)
        }
        viewModel.onClick = { [weak self] index in
            self?.onSelectionConfirmed?(index)
        }
        viewModel.onScroll = { [weak self] direction in
            self?.onScrollCycle?(direction)
        }
    }

    private func setupWindow() {
        let window = ClickablePanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.becomesKeyOnlyIfNeeded = true

        // Create container view to hold both SwiftUI content and selection overlay
        let containerView = NSView()
        containerView.wantsLayer = true

        let hosting = NSHostingView(rootView: AppSwitcherView(viewModel: viewModel))
        hosting.translatesAutoresizingMaskIntoConstraints = false

        let overlay = SelectionOverlayView()
        overlay.translatesAutoresizingMaskIntoConstraints = false

        containerView.addSubview(hosting)
        containerView.addSubview(overlay)  // Overlay on top

        // Constrain both to fill container
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: containerView.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            overlay.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: containerView.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        window.contentView = containerView
        self.hostingView = hosting
        self.selectionOverlay = overlay
        self.window = window
    }

    func show(spaceGroups: [SpaceGroup], allWindows: [SwitcherWindow], selectedIndex: Int, searchQuery: String = "") {
        // Batch updates to reduce SwiftUI view recalculations
        // Update data properties first (before isVisible triggers display)
        viewModel.searchQuery = searchQuery
        viewModel.commands = []  // Clear command mode
        viewModel.spaceGroups = spaceGroups
        viewModel.allWindows = allWindows
        viewModel.updateWindowIndexMap()  // Pre-compute once when windows change
        viewModel.setSelectedIndex(selectedIndex)
        viewModel.resetMouseTracking()

        // Calculate window size based on content and mode
        let showPreviews = AegisConfig.shared.appSwitcherShowPreviews
        let windowWidth: CGFloat = showPreviews ? 460 : 380
        let windowHeight: CGFloat = calculateHeight(for: spaceGroups, hasSearchQuery: !searchQuery.isEmpty)
        let windowSize = NSSize(width: windowWidth, height: windowHeight)

        positionAndShow(size: windowSize, selectedIndex: selectedIndex)
    }

    func showCommands(commands: [PaletteCommand], selectedIndex: Int, searchQuery: String) {
        viewModel.searchQuery = searchQuery
        viewModel.commands = commands
        viewModel.spaceGroups = []
        viewModel.allWindows = []
        viewModel.setSelectedIndex(selectedIndex)
        viewModel.resetMouseTracking()

        let windowWidth: CGFloat = 380
        // Search bar + command rows
        var height: CGFloat = 24 + 36  // padding + search bar
        if commands.isEmpty {
            height += 36
        } else {
            height += CGFloat(commands.count) * iconRowHeight
        }
        height = min(height, 500)

        positionAndShow(size: NSSize(width: windowWidth, height: height), selectedIndex: selectedIndex)
    }

    private func positionAndShow(size: NSSize, selectedIndex: Int) {
        // Center on main screen - only update frame if size changed significantly
        if let screen = NSScreen.main {
            let screenFrame = screen.frame
            let origin = NSPoint(
                x: screenFrame.midX - size.width / 2,
                y: screenFrame.midY - size.height / 2 + 50
            )
            let newFrame = NSRect(origin: origin, size: size)

            // Only call setFrame if frame actually changed (avoid expensive window resize)
            if let currentFrame = window?.frame, !currentFrame.equalTo(newFrame) {
                window?.setFrame(newFrame, display: false)  // display: false - view will update via SwiftUI
            }
        }

        // Set visible last to trigger single view update with all data ready
        viewModel.isVisible = true

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: false)  // Don't steal focus from current app

        // Update selection position after view is laid out
        DispatchQueue.main.async { [weak self] in
            self?.updateSelectionPosition(selectedIndex, animated: false)
        }
    }

    private func calculateHeight(for groups: [SpaceGroup], hasSearchQuery: Bool) -> CGFloat {
        var height: CGFloat = 24  // Top/bottom padding

        // Add search bar height if there's a query
        if hasSearchQuery {
            height += 36  // Search bar height + padding
        }

        // Empty state
        if groups.isEmpty && hasSearchQuery {
            height += 36  // "No matching windows" text
            return height
        }

        let effectiveRowHeight = rowHeight
        for (index, group) in groups.enumerated() {
            height += CGFloat(group.windows.count) * effectiveRowHeight
            if index < groups.count - 1 {
                height += 13  // Divider line + padding (1 + 6 + 6)
            }
        }
        let maxHeight: CGFloat = AegisConfig.shared.appSwitcherShowPreviews ? 700 : 500
        return min(height, maxHeight)
    }

    func update(selectedIndex: Int) {
        viewModel.setSelectedIndex(selectedIndex)

        // Detect rapid scrolling - skip animation if updates are too fast
        let now = CACurrentMediaTime()
        let isRapidScroll = (now - lastUpdateTime) < rapidScrollThreshold
        lastUpdateTime = now

        updateSelectionPosition(selectedIndex, animated: !isRapidScroll)
    }

    /// Update selection highlight position via CALayer (no SwiftUI involvement)
    private func updateSelectionPosition(_ index: Int, animated: Bool) {
        guard let overlay = selectionOverlay, let hostingView = hostingView else { return }
        let layer = overlay.selectionLayer

        let viewHeight = hostingView.bounds.height
        var y = padding  // Start from top padding

        // Account for search bar if visible
        if !viewModel.searchQuery.isEmpty {
            y += searchBarHeight
        }

        // Command mode — flat list, no space groups
        if !viewModel.commands.isEmpty || viewModel.searchQuery.hasPrefix(":") {
            y += CGFloat(index) * iconRowHeight
            let rowY = viewHeight - y - iconRowHeight

            let rowFrame = CGRect(
                x: padding,
                y: rowY,
                width: hostingView.bounds.width - padding * 2,
                height: iconRowHeight
            )

            CATransaction.begin()
            if animated {
                CATransaction.setAnimationDuration(0.1)
                CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
            } else {
                CATransaction.setDisableActions(true)
            }
            layer.frame = rowFrame
            CATransaction.commit()
            return
        }

        // Window mode — find the row position across space groups
        var currentIndex = 0
        for (groupIndex, group) in viewModel.spaceGroups.enumerated() {
            for _ in group.windows {
                if currentIndex == index {
                    let rowY = viewHeight - y - rowHeight

                    let rowFrame = CGRect(
                        x: padding + 20 + 8,  // padding + space number width + spacing
                        y: rowY,
                        width: hostingView.bounds.width - padding * 2 - 20 - 8,
                        height: rowHeight
                    )

                    CATransaction.begin()
                    if animated {
                        CATransaction.setAnimationDuration(0.1)
                        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
                    } else {
                        CATransaction.setDisableActions(true)
                    }
                    layer.frame = rowFrame
                    CATransaction.commit()
                    return
                }
                y += rowHeight
                currentIndex += 1
            }
            if groupIndex < viewModel.spaceGroups.count - 1 {
                y += dividerHeight
            }
        }
    }

    func hide() {
        viewModel.isVisible = false
        window?.orderOut(nil)
    }

    /// Returns the window frame in screen coordinates (for hit testing)
    var windowFrame: CGRect? {
        window?.frame
    }
}

// MARK: - ViewModel

class AppSwitcherViewModel: ObservableObject {
    @Published var spaceGroups: [SpaceGroup] = []
    @Published var allWindows: [SwitcherWindow] = []
    @Published var commands: [PaletteCommand] = []
    @Published var isVisible: Bool = false
    @Published var searchQuery: String = ""

    /// Whether to show window preview thumbnails instead of app icons
    var showPreviews: Bool { AegisConfig.shared.appSwitcherShowPreviews }

    var isCommandMode: Bool { searchQuery.hasPrefix(":") }

    // Selection is NOT @Published - managed via direct CALayer updates
    private(set) var selectedIndex: Int = 0

    // Pre-computed window ID to index map - updated when allWindows changes
    // Avoids O(N) dictionary creation on every render
    private(set) var windowIndexMap: [Int: Int] = [:]

    private var mouseHasMovedInside: Bool = false
    private var initialHoverIndex: Int? = nil
    private var lastHoveredIndex: Int? = nil

    /// Update selection index (called from controller, updates CALayer directly)
    func setSelectedIndex(_ index: Int) {
        selectedIndex = index
    }

    /// Update window index map when windows change
    func updateWindowIndexMap() {
        windowIndexMap = Dictionary(uniqueKeysWithValues: allWindows.enumerated().map { ($1.id, $0) })
    }

    /// Callback when user hovers over a window row
    var onHover: ((Int) -> Void)?

    /// Callback when user clicks a window row
    var onClick: ((Int) -> Void)?

    /// Callback when user scrolls to change selection
    var onScroll: ((Int) -> Void)?

    func resetMouseTracking() {
        mouseHasMovedInside = false
        initialHoverIndex = nil
        lastHoveredIndex = nil
    }

    func handleHover(index: Int) {
        // Skip if same index as last hover (reduces callback spam)
        guard lastHoveredIndex != index else { return }
        lastHoveredIndex = index

        // First hover - just record it, don't activate
        if initialHoverIndex == nil {
            initialHoverIndex = index
            return
        }

        // If hovering a different row than initial, user has moved the mouse
        if initialHoverIndex != index {
            mouseHasMovedInside = true
        }

        // Only trigger callback if mouse has moved
        if mouseHasMovedInside {
            onHover?(index)
        }
    }
}

// MARK: - SwiftUI Views

struct AppSwitcherView: View {
    @ObservedObject var viewModel: AppSwitcherViewModel
    @ObservedObject private var config = AegisConfig.shared
    @ObservedObject private var surfaceAppearance = AegisSurfaceAppearance.shared
    @ObservedObject private var themeManager = ThemeManager.shared

    // Row height for mouse position calculation - must match controller constants
    private var rowHeight: CGFloat { viewModel.showPreviews ? 87 : 32 }
    private let commandRowHeight: CGFloat = 32
    private let padding: CGFloat = 12
    private let dividerHeight: CGFloat = 13
    private let searchBarHeight: CGFloat = 28 + 8  // height (28) + padding (8)

    private var nativeGlassAvailable: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    private var renderingMode: AegisSurfaceRenderingMode {
        AegisSurfaceAppearance.switcherRenderingMode(
            theme: config.appTheme,
            reduceTransparency: surfaceAppearance.reduceTransparency,
            nativeGlassAvailable: nativeGlassAvailable
        )
    }

    private var palette: AegisSurfacePalette {
        AegisSurfaceAppearance.palette(
            theme: config.appTheme,
            isDarkMode: themeManager.isDarkMode,
            customBackground: config.customBackgroundColor,
            customForeground: config.customTextColor,
            customBorder: config.customBorderColor
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Search bar (shown when there's a query)
            if !viewModel.searchQuery.isEmpty {
                    SearchBarView(query: viewModel.searchQuery, isCommandMode: viewModel.isCommandMode, palette: palette)
                    .padding(.bottom, 8)
            }

            if viewModel.isCommandMode {
                // Command palette mode
                ForEach(Array(viewModel.commands.enumerated()), id: \.element.id) { index, command in
                    CommandRowView(command: command, index: index, palette: palette)
                }

                if viewModel.commands.isEmpty {
                    HStack {
                        Spacer()
                        Text("No matching commands")
                            .font(.system(size: 11))
                            .foregroundColor(Color(nsColor: palette.secondaryForeground))
                        Spacer()
                    }
                    .padding(.vertical, 12)
                }
            } else {
                // Window list - selection highlight rendered via CALayer overlay
                ForEach(Array(viewModel.spaceGroups.enumerated()), id: \.element.id) { index, group in
                    SpaceGroupView(
                        group: group,
                        windowIndexMap: viewModel.windowIndexMap,
                        isLast: index == viewModel.spaceGroups.count - 1,
                        showPreview: viewModel.showPreviews,
                        palette: palette
                    )
                }

                // Empty state when no matches
                if viewModel.spaceGroups.isEmpty && !viewModel.searchQuery.isEmpty {
                    HStack {
                        Spacer()
                        Text("No matching windows")
                            .font(.system(size: 11))
                            .foregroundColor(Color(nsColor: palette.secondaryForeground))
                        Spacer()
                    }
                    .padding(.vertical, 12)
                }
            }
        }
        .padding(padding)
        .background {
            switch renderingMode {
            case .solid:
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: palette.background))
            case .legacyMaterial:
                RoundedRectangle(cornerRadius: 10)
                    .fill(.thinMaterial)
            case .nativeGlass:
                if #available(macOS 26.0, *) {
                    AegisNativeGlassBackground(cornerRadius: 10)
                }
            }
        }
        .overlay {
            if renderingMode != .nativeGlass {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color(nsColor: palette.border), lineWidth: 1)
            }
        }
        .overlay(
            MouseTrackingView(
                onMouseMoved: { location in
                    let index = indexForMouseLocation(location)
                    if let index = index {
                        viewModel.handleHover(index: index)
                    }
                },
                onMouseClicked: { location in
                    let index = indexForMouseLocation(location)
                    if let index = index {
                        viewModel.onClick?(index)
                    }
                },
                onScrolled: { direction in
                    viewModel.onScroll?(direction)
                },
                isVisible: viewModel.isVisible
            )
        )
        .opacity(viewModel.isVisible ? 1 : 0)
        .scaleEffect(viewModel.isVisible ? 1 : 0.96)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: viewModel.isVisible)
    }

    /// Calculate which window/command index the mouse is over based on Y position
    private func indexForMouseLocation(_ location: CGPoint) -> Int? {
        var y = location.y - padding

        // Account for search bar if visible
        if !viewModel.searchQuery.isEmpty {
            y -= searchBarHeight
        }

        // Command mode — flat list
        if viewModel.isCommandMode {
            guard y >= 0 else { return nil }
            let index = Int(y / commandRowHeight)
            return index < viewModel.commands.count ? index : nil
        }

        // Window mode
        var windowIndex = 0

        for (groupIndex, group) in viewModel.spaceGroups.enumerated() {
            for _ in group.windows {
                if y >= 0 && y < rowHeight {
                    return windowIndex
                }
                y -= rowHeight
                windowIndex += 1
            }
            // Account for divider between groups
            if groupIndex < viewModel.spaceGroups.count - 1 {
                y -= dividerHeight
            }
        }
        return nil
    }
}

/// NSViewRepresentable for efficient mouse tracking without SwiftUI overhead
struct MouseTrackingView: NSViewRepresentable {
    let onMouseMoved: (CGPoint) -> Void
    let onMouseClicked: (CGPoint) -> Void
    let onScrolled: ((Int) -> Void)?  // Direction: -1 for up/previous, +1 for down/next
    let isVisible: Bool  // Track visibility to reset scroll state on show

    func makeNSView(context: Context) -> MouseTrackingNSView {
        let view = MouseTrackingNSView()
        view.onMouseMoved = onMouseMoved
        view.onMouseClicked = onMouseClicked
        view.onScrolled = onScrolled
        return view
    }

    func updateNSView(_ nsView: MouseTrackingNSView, context: Context) {
        nsView.onMouseMoved = onMouseMoved
        nsView.onMouseClicked = onMouseClicked
        nsView.onScrolled = onScrolled

        // Reset scroll state when becoming visible
        // This prevents residual scroll from menu bar from affecting app switcher
        if isVisible {
            nsView.resetScrollState()
        }
    }
}

class MouseTrackingNSView: NSView {
    var onMouseMoved: ((CGPoint) -> Void)?
    var onMouseClicked: ((CGPoint) -> Void)?
    var onScrolled: ((Int) -> Void)?
    private var trackingArea: NSTrackingArea?

    // Scroll accumulation for two-finger gesture
    private var scrollAccumulator: CGFloat = 0

    // Timestamp when the view became active - used to ignore residual scroll momentum
    private var activationTime: Date = Date()

    // Throttle scroll events to reduce CPU usage
    private var lastScrollTime: CFTimeInterval = 0
    private let scrollThrottleInterval: CFTimeInterval = 0.05  // ~20fps max

    /// Reset scroll state when the switcher appears
    /// Call this when showing the app switcher to prevent residual scroll from previous context
    func resetScrollState() {
        scrollAccumulator = 0
        activationTime = Date()
        lastScrollTime = 0
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existing = trackingArea {
            removeTrackingArea(existing)
        }

        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        // Flip Y coordinate (NSView origin is bottom-left, SwiftUI is top-left)
        let flippedLocation = CGPoint(x: location.x, y: bounds.height - location.y)
        onMouseMoved?(flippedLocation)
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        // Flip Y coordinate (NSView origin is bottom-left, SwiftUI is top-left)
        let flippedLocation = CGPoint(x: location.x, y: bounds.height - location.y)
        onMouseClicked?(flippedLocation)
    }

    override func scrollWheel(with event: NSEvent) {
        // Ignore scroll events for 200ms after activation
        // This prevents residual scroll momentum from previous context (e.g., menu bar)
        // from immediately cycling the app switcher selection
        let cooldownPeriod: TimeInterval = 0.2
        guard Date().timeIntervalSince(activationTime) > cooldownPeriod else {
            return
        }

        // Ignore momentum phase - only respond to actual finger gestures
        // This prevents over-scrolling after the user lifts their fingers
        guard event.phase == .began || event.phase == .changed || event.phase == [] else {
            // Reset accumulator when gesture ends
            if event.phase == .ended || event.phase == .cancelled {
                scrollAccumulator = 0
            }
            return
        }

        // Use deltaY for trackpad (same as menu bar scroll behavior)
        let delta = event.deltaY

        // Throttle scroll event processing to reduce CPU usage
        let now = CACurrentMediaTime()
        guard now - lastScrollTime >= scrollThrottleInterval else {
            // Still accumulate delta even when throttled
            scrollAccumulator += delta
            return
        }
        lastScrollTime = now

        // Accumulate scroll delta
        scrollAccumulator += delta

        // Use configurable threshold (default 3, matching menu bar)
        let threshold = AegisConfig.shared.scrollActionThreshold

        // Calculate how many steps to move
        let steps = Int(scrollAccumulator / threshold)
        if steps != 0 {
            // Scroll down (positive delta) = next window (+1)
            // Scroll up (negative delta) = previous window (-1)
            onScrolled?(steps > 0 ? 1 : -1)

            // Notched behavior: full reset gives deliberate "click" feel
            // Continuous behavior: subtract consumed amount for smoother rapid scrolling
            if AegisConfig.shared.scrollNotchedBehavior {
                scrollAccumulator = 0
            } else {
                scrollAccumulator -= CGFloat(steps) * threshold
            }
        }
    }

    // Return self to receive mouse events
    override func hitTest(_ point: NSPoint) -> NSView? {
        return self
    }
}

struct SpaceGroupView: View {
    let group: SpaceGroup
    let windowIndexMap: [Int: Int]  // Pre-computed: window.id -> global index
    let isLast: Bool
    let showPreview: Bool
    let palette: AegisSurfacePalette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                // Space number on the left with vertical connector line
                VStack(spacing: 0) {
                    Text("\(group.spaceIndex)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(nsColor: palette.foreground).opacity(group.isFocused ? 1 : 0.5))
                        .frame(width: 20, alignment: .center)
                }
                .frame(width: 20)
                .overlay(alignment: .trailing) {
                    // Vertical connector line
                    Rectangle()
                        .fill(Color(nsColor: palette.tertiaryForeground))
                        .frame(width: 1)
                        .padding(.vertical, 4)
                        .offset(x: 12)
                }

                // Windows column - selection highlight is rendered via CALayer overlay
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(group.windows) { window in
                        let globalIndex = windowIndexMap[window.id] ?? 0
                        WindowRowView(window: window, index: globalIndex, showPreview: showPreview, palette: palette)
                    }
                }
            }

            // Divider line between space groups (except after last group)
            if !isLast {
                Rectangle()
                    .fill(Color(nsColor: palette.tertiaryForeground))
                    .frame(height: 1)
                    .padding(.vertical, 6)
                    .padding(.leading, 32)
            }
        }
    }
}

/// Search bar showing the current filter query
struct SearchBarView: View {
    let query: String
    var isCommandMode: Bool = false
    let palette: AegisSurfacePalette

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isCommandMode ? "terminal" : "magnifyingglass")
                .font(.system(size: 10))
                .foregroundColor(isCommandMode ? .cyan.opacity(0.7) : Color(nsColor: palette.secondaryForeground))

            Text(query)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(nsColor: palette.foreground))

            Spacer()

            Text(isCommandMode ? "command mode" : "⌫ to clear")
                .font(.system(size: 9))
                .foregroundColor(Color(nsColor: palette.tertiaryForeground))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isCommandMode ? Color.cyan.opacity(0.08) : Color(nsColor: palette.tertiaryForeground).opacity(0.12))
        )
    }
}

struct CommandRowView: View {
    let command: PaletteCommand
    let index: Int
    let palette: AegisSurfacePalette

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: command.icon)
                .font(.system(size: 12))
                .foregroundColor(.cyan.opacity(0.8))
                .frame(width: 20, height: 20)

            Text(command.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(nsColor: palette.foreground))
                .lineLimit(1)

            Text(command.description)
                .font(.system(size: 10))
                .foregroundColor(Color(nsColor: palette.secondaryForeground))
                .lineLimit(1)

            Spacer()

            Text(command.category)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(Color(nsColor: palette.tertiaryForeground))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: palette.tertiaryForeground).opacity(0.12)))

            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Color(nsColor: palette.tertiaryForeground))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
        .contentShape(Rectangle())
    }
}

struct WindowRowView: View {
    let window: SwitcherWindow
    let index: Int
    let showPreview: Bool
    let palette: AegisSurfacePalette

    var body: some View {
        if showPreview {
            previewRow
        } else {
            iconRow
        }
    }

    // MARK: - Icon Mode (default)

    private var iconRow: some View {
        HStack(spacing: 8) {
            appIconView
                .frame(width: 20, height: 20)

            Text(window.appName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(nsColor: palette.foreground).opacity(dimmed ? 0.5 : 0.9))
                .lineLimit(1)
                .frame(width: 90, alignment: .leading)

            Text(displayTitle)
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: palette.secondaryForeground).opacity(dimmed ? 0.55 : 0.8))
                .lineLimit(1)

            Spacer()

            shortcutHint
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    // MARK: - Preview Mode

    private var previewRow: some View {
        HStack(spacing: 10) {
            // Thumbnail or fallback icon
            if let thumbnail = window.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 75)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color(nsColor: palette.tertiaryForeground), lineWidth: 0.5)
                    )
                    .opacity(dimmed ? 0.5 : 1.0)
            } else {
                // Fallback: large app icon for minimized/hidden windows
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: palette.tertiaryForeground).opacity(0.12))
                        .frame(width: 120, height: 75)

                    appIconView
                        .frame(width: 32, height: 32)
                }
            }

            // App name + title stacked vertically
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    appIconView
                        .frame(width: 14, height: 14)

                    Text(window.appName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(nsColor: palette.foreground).opacity(dimmed ? 0.5 : 0.9))
                        .lineLimit(1)
                }

                Text(displayTitle)
                    .font(.system(size: 10))
                    .foregroundColor(Color(nsColor: palette.secondaryForeground).opacity(dimmed ? 0.55 : 0.8))
                    .lineLimit(2)

                if window.isMinimized || window.isHidden {
                    Text(window.isMinimized ? "Minimized" : "Hidden")
                        .font(.system(size: 9))
                        .foregroundColor(Color(nsColor: palette.tertiaryForeground))
                }
            }

            Spacer()

            shortcutHint
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    // MARK: - Shared Subviews

    private var dimmed: Bool { window.isMinimized || window.isHidden }

    private var displayTitle: String {
        window.title.isEmpty ? window.appName : window.title
    }

    @ViewBuilder
    private var appIconView: some View {
        ZStack(alignment: .bottomTrailing) {
            if let icon = window.icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .opacity(dimmed ? 0.5 : 1.0)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Color(nsColor: palette.secondaryForeground))
            }

            WindowStatusBadge(
                isMinimized: window.isMinimized,
                isHidden: window.isHidden,
                stackIndex: 0,
                stackBackground: Color(nsColor: palette.selectionFill),
                stackForeground: Color(nsColor: palette.foreground)
            )
        }
    }

    @ViewBuilder
    private var shortcutHint: some View {
        if index < 9 {
            Text("⌘\(index + 1)")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(Color(nsColor: palette.tertiaryForeground))
        }
    }
}
