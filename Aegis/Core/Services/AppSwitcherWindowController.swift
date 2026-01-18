import AppKit
import SwiftUI
import Combine

/// Custom NSPanel subclass that can become key to receive mouse clicks
/// while still being a non-activating panel (won't steal app focus)
class ClickablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Window controller for the app switcher overlay
/// Displays windows organized by space in a centered panel
final class AppSwitcherWindowController {

    private var window: NSWindow?
    private var viewModel = AppSwitcherViewModel()

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

        let hostingView = NSHostingView(rootView: AppSwitcherView(viewModel: viewModel))
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        window.contentView = hostingView
        self.window = window
    }

    func show(spaceGroups: [SpaceGroup], allWindows: [SwitcherWindow], selectedIndex: Int, searchQuery: String = "") {
        // Batch updates to reduce SwiftUI view recalculations
        // Update data properties first (before isVisible triggers display)
        viewModel.searchQuery = searchQuery
        viewModel.spaceGroups = spaceGroups
        viewModel.allWindows = allWindows
        viewModel.selectedIndex = selectedIndex
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
        viewModel.selectedIndex = selectedIndex
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
    @Published var selectedIndex: Int = 0
    @Published var isVisible: Bool = false
    @Published var searchQuery: String = ""

    private var mouseHasMovedInside: Bool = false
    private var initialHoverIndex: Int? = nil
    private var lastHoveredIndex: Int? = nil

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

    // Row height for mouse position calculation
    private let rowHeight: CGFloat = 32
    private let padding: CGFloat = 12
    private let dividerHeight: CGFloat = 13
    private let searchBarHeight: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Search bar (shown when there's a query)
            if !viewModel.searchQuery.isEmpty {
                SearchBarView(query: viewModel.searchQuery)
                    .padding(.bottom, 8)
            }

            // Window list
            ForEach(Array(viewModel.spaceGroups.enumerated()), id: \.element.id) { index, group in
                SpaceGroupView(
                    group: group,
                    allWindows: viewModel.allWindows,
                    selectedIndex: viewModel.selectedIndex,
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
            y -= searchBarHeight + 8  // height + padding
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

    /// Reset scroll state when the switcher appears
    /// Call this when showing the app switcher to prevent residual scroll from previous context
    func resetScrollState() {
        scrollAccumulator = 0
        activationTime = Date()
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
    let allWindows: [SwitcherWindow]
    let selectedIndex: Int
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

                // Windows column
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(group.windows) { window in
                        let globalIndex = allWindows.firstIndex(where: { $0.id == window.id }) ?? 0
                        let isSelected = globalIndex == selectedIndex

                        WindowRowView(
                            window: window,
                            isSelected: isSelected,
                            index: globalIndex
                        )
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
    let isSelected: Bool
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
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.white.opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isSelected ? Color.white.opacity(0.2) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.1), value: isSelected)
    }
}
