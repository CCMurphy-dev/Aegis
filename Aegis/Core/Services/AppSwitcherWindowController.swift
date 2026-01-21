import AppKit
import SwiftUI
import Combine  // Required for @Published property wrapper

/// Custom NSPanel subclass that can become key to receive mouse clicks
/// while still being a non-activating panel (won't steal app focus)
class ClickablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Window controller for the app switcher overlay
/// Displays windows organized by space in a centered panel
/// Transparent overlay view that renders the selection highlight via CALayer
class SelectionOverlayView: NSView {
    let selectionLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(selectionLayer)

        selectionLayer.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
        selectionLayer.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        selectionLayer.borderWidth = 1
        selectionLayer.cornerRadius = 6
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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

    // Layout constants for calculating selection position
    private let rowHeight: CGFloat = 32
    private let padding: CGFloat = 12
    private let dividerHeight: CGFloat = 13
    private let searchBarHeight: CGFloat = 28 + 8  // height + padding

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
        viewModel.spaceGroups = spaceGroups
        viewModel.allWindows = allWindows
        viewModel.updateWindowIndexMap()  // Pre-compute once when windows change
        viewModel.setSelectedIndex(selectedIndex)
        viewModel.resetMouseTracking()

        // Calculate window size based on content
        let windowWidth: CGFloat = 380
        let windowHeight: CGFloat = calculateHeight(for: spaceGroups, hasSearchQuery: !searchQuery.isEmpty)
        let windowSize = NSSize(width: windowWidth, height: windowHeight)

        // Center on main screen - only update frame if size changed significantly
        if let screen = NSScreen.main {
            let screenFrame = screen.frame
            let origin = NSPoint(
                x: screenFrame.midX - windowSize.width / 2,
                y: screenFrame.midY - windowSize.height / 2 + 50
            )
            let newFrame = NSRect(origin: origin, size: windowSize)

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

        for (index, group) in groups.enumerated() {
            height += CGFloat(group.windows.count) * 32  // Window rows
            if index < groups.count - 1 {
                height += 13  // Divider line + padding (1 + 6 + 6)
            }
        }
        return min(height, 500)  // Cap height (increased for search)
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

        // Calculate Y position for the selected row
        let viewHeight = hostingView.bounds.height
        var y = padding  // Start from top padding

        // Account for search bar if visible
        if !viewModel.searchQuery.isEmpty {
            y += searchBarHeight
        }

        // Find the row position
        var currentIndex = 0
        for (groupIndex, group) in viewModel.spaceGroups.enumerated() {
            for _ in group.windows {
                if currentIndex == index {
                    // Found our row - calculate frame
                    // Note: CALayer uses bottom-left origin, SwiftUI uses top-left
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
            // Account for divider between groups
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
    @Published var isVisible: Bool = false
    @Published var searchQuery: String = ""

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

    // Row height for mouse position calculation - must match controller constants
    private let rowHeight: CGFloat = 32
    private let padding: CGFloat = 12
    private let dividerHeight: CGFloat = 13
    private let searchBarHeight: CGFloat = 28 + 8  // height (28) + padding (8)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Search bar (shown when there's a query)
            if !viewModel.searchQuery.isEmpty {
                SearchBarView(query: viewModel.searchQuery)
                    .padding(.bottom, 8)
            }

            // Window list - selection highlight rendered via CALayer overlay
            ForEach(Array(viewModel.spaceGroups.enumerated()), id: \.element.id) { index, group in
                SpaceGroupView(
                    group: group,
                    windowIndexMap: viewModel.windowIndexMap,
                    isLast: index == viewModel.spaceGroups.count - 1
                )
            }

            // Empty state when no matches
            if viewModel.spaceGroups.isEmpty && !viewModel.searchQuery.isEmpty {
                HStack {
                    Spacer()
                    Text("No matching windows")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                }
                .padding(.vertical, 12)
            }
        }
        .padding(padding)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
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

    /// Calculate which window index the mouse is over based on Y position
    private func indexForMouseLocation(_ location: CGPoint) -> Int? {
        var y = location.y - padding

        // Account for search bar if visible
        if !viewModel.searchQuery.isEmpty {
            y -= searchBarHeight
        }

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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                // Space number on the left with vertical connector line
                VStack(spacing: 0) {
                    Text("\(group.spaceIndex)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(group.isFocused ? .white : .white.opacity(0.5))
                        .frame(width: 20, alignment: .center)
                }
                .frame(width: 20)
                .overlay(alignment: .trailing) {
                    // Vertical connector line
                    Rectangle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 1)
                        .padding(.vertical, 4)
                        .offset(x: 12)
                }

                // Windows column - selection highlight is rendered via CALayer overlay
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(group.windows) { window in
                        let globalIndex = windowIndexMap[window.id] ?? 0
                        WindowRowView(window: window, index: globalIndex)
                    }
                }
            }

            // Divider line between space groups (except after last group)
            if !isLast {
                Rectangle()
                    .fill(Color.white.opacity(0.1))
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

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.5))

            Text(query)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.9))

            Spacer()

            Text("⌫ to clear")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.35))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.08))
        )
    }
}

struct WindowRowView: View {
    let window: SwitcherWindow
    let index: Int

    var body: some View {
        HStack(spacing: 8) {
            // App icon with minimized/hidden overlay
            ZStack(alignment: .bottomTrailing) {
                if let icon = window.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                        .opacity(window.isMinimized || window.isHidden ? 0.5 : 1.0)
                } else {
                    Image(systemName: "app.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 20, height: 20)
                }

                // Status indicator badge
                WindowStatusBadge(
                    isMinimized: window.isMinimized,
                    isHidden: window.isHidden,
                    stackIndex: 0  // Switcher doesn't track stack state
                )
            }

            // App name
            Text(window.appName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(window.isMinimized || window.isHidden ? 0.5 : 0.9))
                .lineLimit(1)
                .frame(width: 90, alignment: .leading)

            // Window title
            Text(window.title.isEmpty ? window.appName : window.title)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(window.isMinimized || window.isHidden ? 0.4 : 0.6))
                .lineLimit(1)

            Spacer()

            // Keyboard shortcut hint
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.35))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        // Selection highlight is rendered via CALayer overlay - no SwiftUI involvement
        .contentShape(Rectangle())
    }
}
