import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Space Indicator View

struct SpaceIndicatorView: View {
    let space: Space
    let isActive: Bool
    let windowIcons: [WindowIcon]
    let allWindowIcons: [WindowIcon]
    let focusedIndex: Int?  // Pre-computed by ViewModel (avoids O(N) search per render)
    let onWindowClick: ((Int) -> Void)?
    let onSpaceClick: (() -> Void)?
    let onSpaceDestroy: ((Int) -> Void)?
    let onWindowDrop: ((Int, Int, Int?, Bool) -> Void)?  // (windowId, targetSpaceIndex, insertBeforeWindowId, shouldStack)
    @Binding var draggedWindowId: Int?  // Shared: ID of window currently being dragged
    @Binding var expandedWindowId: Int?  // Shared: ID of currently expanded window icon (persists across updates)

    @State private var showOverflowMenu = false
    @State private var autoCollapseTask: Task<Void, Never>?
    @State private var isDraggingOver = false  // True when actively dragging over this space

    private let config = AegisConfig.shared

    var body: some View {
        Group {
            if config.useSwipeToDestroySpace {
                SwipeableSpaceContainer(
                    spaceIndex: space.index,
                    onSwipeUp: { [space] in
                        onSpaceDestroy?(space.index)
                    }
                ) {
                    spaceContentWithModifiers
                }
            } else {
                spaceContentWithModifiers
            }
        }
    }

    // MARK: - Sub-views to help type checker

    private var spaceNumberView: some View {
        Text("\(space.index)")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white.opacity(isActive ? 1.0 : 0.6))
            .frame(width: 16)
            .onTapGesture {
                onSpaceClick?()
            }
    }

    private var spaceContent: some View {
        HStack(alignment: .center, spacing: 6) {
            spaceNumberView

            if windowIcons.isEmpty {
                // Invisible spacer that matches the height of populated space indicators
                // Height matches the VStack intrinsic height (title 13px + app name 11px + spacing 2px = ~26px)
                Spacer()
                    .frame(width: 0, height: 26)
            } else {
                windowIconsContent
            }
        }
    }

    private var windowIconsContent: some View {
        HStack(alignment: .center, spacing: 6) {
                    ForEach(Array(windowIcons.enumerated()), id: \.element.id) { index, windowIcon in
                        HStack(alignment: .center, spacing: 6) {
                            ZStack(alignment: .bottomTrailing) {
                                RightClickableIcon(
                                    windowId: windowIcon.id,
                                    icon: windowIcon.icon ?? NSImage(),
                                    isMinimized: windowIcon.isMinimized,
                                    isHidden: windowIcon.isHidden,
                                    onLeftClick: {
                                        // Left-click just focuses the window, doesn't affect expansion state
                                        onWindowClick?(windowIcon.id)
                                    },
                                    onRightClick: {
                                        toggleExpansion(for: windowIcon)
                                    },
                                    onDragStarted: {
                                        draggedWindowId = windowIcon.id
                                    },
                                    onDragEnded: {
                                        draggedWindowId = nil
                                    }
                                )

                                // Status indicator badge
                                WindowStatusBadge(
                                    isMinimized: windowIcon.isMinimized,
                                    isHidden: windowIcon.isHidden,
                                    stackIndex: windowIcon.stackIndex
                                )
                            }
                            .frame(width: 22, height: 22)
                            .opacity(draggedWindowId == windowIcon.id ? 0.0 : 1.0)

                            // Expandable title area (dynamic width)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(windowIcon.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.9))
                                    .lineLimit(1)

                                if config.showAppNameInExpansion {
                                    Text(windowIcon.appName)
                                        .font(.system(size: 9))
                                        .foregroundColor(.white.opacity(0.6))
                                        .lineLimit(1)
                                }
                            }
                            .frame(
                                width: expandedWindowId == windowIcon.id
                                    ? windowIcon.expandedWidth  // Use pre-computed width
                                    : 0,
                                alignment: .leading
                            )
                            .opacity(expandedWindowId == windowIcon.id ? 1 : 0)
                            .clipped()
                            .animation(
                                .spring(response: 0.35, dampingFraction: 0.75),
                                value: expandedWindowId
                            )
                        }
                        .id(windowIcon.id)  // Stable ID prevents re-creation when windows reorder
                    }

            // Overflow button
            if allWindowIcons.count > windowIcons.count {
                overflowButton
            }
        }
    }

    private var overflowButton: some View {
        Button {
            showOverflowMenu.toggle()
        } label: {
            Text("+\(allWindowIcons.count - windowIcons.count)")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(showOverflowMenu ? 0.25 : 0.12))
                )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showOverflowMenu, arrowEdge: .bottom) {
            OverflowWindowMenu(
                hiddenIcons: Array(allWindowIcons.dropFirst(windowIcons.count)),
                onWindowClick: { id in
                    showOverflowMenu = false
                    onWindowClick?(id)
                }
            )
        }
    }

    // Pre-compute dot position to avoid recalculation in view body
    private var dotXPosition: CGFloat {
        guard let idx = focusedIndex else { return 0 }
        // Starting position: left padding + space number + spacing after space number
        var xPosition: CGFloat = 8 + 16 + 6

        // Add width of all icons before the focused one
        for i in 0..<idx {
            xPosition += 22  // Icon width
            xPosition += 6   // Spacing in icon's HStack

            // If this icon is expanded, add the title width
            if i < windowIcons.count && expandedWindowId == windowIcons[i].id {
                xPosition += windowIcons[i].expandedWidth
            }

            xPosition += 6  // Spacing after this icon
        }

        // Center on the focused icon: half icon width
        xPosition += 11
        return xPosition
    }

    private var spaceContentWithModifiers: some View {
        spaceContent
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? Color.white.opacity(0.18) : Color.white.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isActive ? Color.white.opacity(0.18) : .clear, lineWidth: 1)
            )
            .overlay(alignment: .bottomLeading) {
                // Focus indicator dot at bottom edge
                Circle()
                    .fill(Color.white)
                    .frame(width: 3, height: 3)
                    .offset(x: dotXPosition - 1.5, y: 1.5)
                    .opacity(focusedIndex != nil ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .shadow(color: isActive ? .white.opacity(0.12) : .clear, radius: 6)
            // Single animation for isActive changes only - removed hover animation to reduce CPU
            .animation(.easeOut(duration: 0.15), value: isActive)
        // Add invisible padding to expand drop zone
        // Use asymmetric padding: no top padding to maintain alignment, bottom padding for drop zone
        .padding(.horizontal, 4)
        .contentShape(Rectangle())  // Make the entire padded area droppable
        .onDrop(of: [.text], delegate: WindowDropDelegate(
            onDragEntered: {
                isDraggingOver = true
            },
            onDragUpdate: { _ in
                // No-op: We don't show drop indicators for reordering
            },
            onDragEnded: {
                isDraggingOver = false
            },
            onDrop: { providers, _ in
                let result = handleDrop(providers: providers)
                isDraggingOver = false
                return result
            }
        ))
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: "public.text", options: nil) { item, error in
            guard let data = item as? Data,
                  let windowIdString = String(data: data, encoding: .utf8),
                  let windowId = Int(windowIdString) else {
                return
            }

            // Check if the window is from this space - if so, reject the drop
            let isFromThisSpace = self.windowIcons.contains(where: { $0.id == windowId })
            guard !isFromThisSpace else {
                return
            }

            // Always append to end (nil = insert at end)
            DispatchQueue.main.async {
                self.onWindowDrop?(windowId, self.space.index, nil, false)
            }
        }

        return true
    }

    // MARK: - Expansion Logic

    private func toggleExpansion(for icon: WindowIcon) {
        autoCollapseTask?.cancel()

        // If clicking the same icon → just collapse (toggle off)
        if expandedWindowId == icon.id {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                expandedWindowId = nil
            }
            return
        }

        // Step 1: force collapse the previous expanded icon
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            expandedWindowId = nil
        }

        // Step 2: expand the new icon on the next run loop
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                expandedWindowId = icon.id
            }
        }

        // No auto-collapse - expansion stays until user right-clicks again to toggle off
        // or right-clicks a different icon (which will collapse this one)
    }
}

// MARK: - Overflow Menu

struct OverflowWindowMenu: View {
    let hiddenIcons: [WindowIcon]
    let onWindowClick: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(hiddenIcons) { icon in
                Button {
                    onWindowClick(icon.id)
                } label: {
                    HStack(spacing: 8) {
                        if let iconImage = icon.icon {
                            Image(nsImage: iconImage)
                                .resizable()
                                .frame(width: 24, height: 24)
                                .cornerRadius(4)
                        }

                        Text(icon.appName)
                            .font(.system(size: 13))

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .frame(minWidth: 180)
    }
}

// MARK: - Right Clickable Icon

struct RightClickableIcon: NSViewRepresentable {
    let windowId: Int
    let icon: NSImage
    let isMinimized: Bool
    let isHidden: Bool
    let onLeftClick: () -> Void
    let onRightClick: () -> Void
    let onDragStarted: () -> Void
    let onDragEnded: () -> Void

    func makeNSView(context: Context) -> ClickableIconView {
        let view = ClickableIconView()
        view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 22),
            view.heightAnchor.constraint(equalToConstant: 22)
        ])

        view.windowId = windowId
        view.icon = icon
        view.isMinimized = isMinimized
        view.isWindowHidden = isHidden
        view.onLeftClick = onLeftClick
        view.onRightClick = onRightClick
        view.onDragStarted = onDragStarted
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ nsView: ClickableIconView, context: Context) {
        // Only update properties that changed to avoid unnecessary redraws
        if nsView.windowId != windowId {
            nsView.windowId = windowId
        }
        if nsView.icon !== icon {
            nsView.icon = icon
        }
        if nsView.isMinimized != isMinimized {
            nsView.isMinimized = isMinimized
        }
        if nsView.isWindowHidden != isHidden {
            nsView.isWindowHidden = isHidden
        }
        // Note: Closures recreated but this is unavoidable
        // Hover state is tracked internally by ClickableIconView (no SwiftUI round-trip)
    }
}

// MARK: - AppKit View (ClickableIconView)

final class ClickableIconView: NSView {
    var windowId: Int = 0
    var icon: NSImage? {
        didSet {
            if icon !== oldValue {
                cachedImage = nil
                needsDisplay = true
            }
        }
    }
    var isHovered = false {
        didSet {
            guard isHovered != oldValue else { return }
            // Use layer opacity for hover - much cheaper than redrawing
            layer?.opacity = isHovered ? 1.0 : 0.85
        }
    }
    var isMinimized = false {
        didSet {
            guard isMinimized != oldValue else { return }
            cachedImage = nil
            needsDisplay = true
        }
    }
    var isWindowHidden = false {
        didSet {
            guard isWindowHidden != oldValue else { return }
            cachedImage = nil
            needsDisplay = true
        }
    }

    // Cached rendered image to avoid expensive redraws
    private var cachedImage: NSImage?
    private var cachedBounds: NSRect = .zero

    var onLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    var onDragStarted: (() -> Void)?
    var onDragEnded: (() -> Void)?

    private var trackingArea: NSTrackingArea?
    private var dragStartLocation: NSPoint?
    private var isDragging = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.opacity = 0.85  // Default non-hovered opacity
        registerForDraggedTypes([.string])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.opacity = 0.85
        registerForDraggedTypes([.string])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }

        let newTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        trackingArea = newTrackingArea
        addTrackingArea(newTrackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func mouseDown(with event: NSEvent) {
        dragStartLocation = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startLocation = dragStartLocation else { return }

        let currentLocation = event.locationInWindow
        let dragDistance = hypot(currentLocation.x - startLocation.x, currentLocation.y - startLocation.y)

        guard dragDistance > 3, let icon = icon else { return }

        if !isDragging {
            isDragging = true
            onDragStarted?()
        }

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString("\(windowId)", forType: .string)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(bounds, contents: icon)

        beginDraggingSession(with: [draggingItem], event: event, source: self)
        dragStartLocation = nil
    }

    override func mouseUp(with event: NSEvent) {
        if let startLocation = dragStartLocation {
            let currentLocation = event.locationInWindow
            let distance = hypot(currentLocation.x - startLocation.x, currentLocation.y - startLocation.y)

            if distance <= 3 {
                onLeftClick?()
            }
        }
        dragStartLocation = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let icon = icon else { return }

        // Use cached image if available
        if let cached = cachedImage, cachedBounds == bounds {
            cached.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0)
            return
        }

        // Calculate opacity based on window state (minimized/hidden)
        let stateOpacity: CGFloat = (isMinimized || isWindowHidden) ? 0.5 : 1.0

        // Simple icon draw - no expensive glow/shadow effects
        icon.draw(
            in: bounds,
            from: .zero,
            operation: .sourceOver,
            fraction: stateOpacity
        )

        // Cache for next draw
        let rendered = NSImage(size: bounds.size)
        rendered.lockFocus()
        icon.draw(in: NSRect(origin: .zero, size: bounds.size), from: .zero, operation: .sourceOver, fraction: stateOpacity)
        rendered.unlockFocus()

        cachedImage = rendered
        cachedBounds = bounds
    }
}

// MARK: - Dragging Source

extension ClickableIconView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .move
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        // Drag ended - reset state
        if isDragging {
            isDragging = false
            onDragEnded?()
        }
    }
}

// MARK: - Swipeable Space Container

struct SwipeableSpaceContainer<Content: View>: View {
    let spaceIndex: Int
    let onSwipeUp: () -> Void
    let content: Content

    @State private var opacity: Double = 1.0
    @State private var yOffset: CGFloat = 0
    @State private var scale: CGFloat = 1.0

    init(spaceIndex: Int, onSwipeUp: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.spaceIndex = spaceIndex
        self.onSwipeUp = onSwipeUp
        self.content = content()
    }

    var body: some View {
        content
            .opacity(opacity)
            .offset(y: yOffset)
            .scaleEffect(scale)
            .overlay(
                SwipeDetectorRepresentable(
                    onSwipeUp: { [onSwipeUp] in
                        // Animate upward movement, fade, and scale down
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            yOffset = -40  // Move up
                            opacity = 0    // Fade out
                            scale = 0.8    // Scale down
                        }

                        // Call the destroy handler after animation
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onSwipeUp()
                        }
                    }
                )
                .allowsHitTesting(false)
            )
    }
}

// MARK: - Swipe Detector Representable

struct SwipeDetectorRepresentable: NSViewRepresentable {
    let onSwipeUp: () -> Void

    func makeNSView(context: Context) -> SwipeDetectorView {
        let view = SwipeDetectorView()
        view.onSwipeUp = onSwipeUp
        return view
    }

    func updateNSView(_ nsView: SwipeDetectorView, context: Context) {
        nsView.onSwipeUp = onSwipeUp
    }
}

class SwipeDetectorView: NSView {
    var onSwipeUp: (() -> Void)?

    private var scrollAccumulator: CGFloat = 0
    private var eventMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupEventMonitor()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupEventMonitor()
    }

    private func setupEventMonitor() {
        // Use local event monitor to capture scroll events even when hit testing is disabled
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self, let window = self.window else { return event }

            // Check if the event is within our bounds
            let locationInWindow = event.locationInWindow
            let locationInView = self.convert(locationInWindow, from: nil)

            if self.bounds.contains(locationInView) {
                self.handleScrollWheel(event)
            }

            return event
        }
    }

    private func handleScrollWheel(_ event: NSEvent) {
        let deltaY = event.scrollingDeltaY

        switch event.phase {
        case .began:
            scrollAccumulator = 0

        case .changed:
            scrollAccumulator += deltaY

        case .ended:
            scrollAccumulator += deltaY

            // Check if we scrolled up enough
            // With natural scrolling: swipe up = negative deltaY
            // Increased threshold from -50 to -120 to prevent accidental triggers
            if scrollAccumulator < -120 {
                onSwipeUp?()
            }
            scrollAccumulator = 0

        case .cancelled:
            scrollAccumulator = 0

        default:
            break
        }
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

// MARK: - Window Drop Delegate

struct WindowDropDelegate: DropDelegate {
    let onDragEntered: () -> Void
    let onDragUpdate: (CGPoint) -> Void
    let onDragEnded: () -> Void
    let onDrop: ([NSItemProvider], CGPoint) -> Bool

    func dropEntered(info: DropInfo) {
        onDragEntered()
        onDragUpdate(info.location)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        onDragUpdate(info.location)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        onDragEnded()
    }

    func performDrop(info: DropInfo) -> Bool {
        let location = info.location
        return onDrop(info.itemProviders(for: [.text]), location)
    }

    func validateDrop(info: DropInfo) -> Bool {
        return info.hasItemsConforming(to: [.text])
    }
}

