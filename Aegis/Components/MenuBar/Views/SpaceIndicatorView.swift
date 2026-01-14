import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Space Indicator View

struct SpaceIndicatorView: View {
    let space: Space
    let isActive: Bool
    let windowIcons: [WindowIcon]
    let allWindowIcons: [WindowIcon]
    let onWindowClick: ((Int) -> Void)?
    let onSpaceClick: (() -> Void)?
    let onSpaceDestroy: ((Int) -> Void)?
    let onWindowDrop: ((Int, Int, Int?, Bool) -> Void)?  // (windowId, targetSpaceIndex, insertBeforeWindowId, shouldStack)
    @Binding var draggedWindowId: Int?  // Shared: ID of window currently being dragged

    @State private var isHovered = false
    @State private var hoveredIconId: Int?
    @State private var expandedIconId: Int?
    @State private var showOverflowMenu = false
    @State private var autoCollapseTask: Task<Void, Never>?
    @State private var isDraggingOver = false  // True when actively dragging over this space

    private let config = AegisConfig.shared
    private let maxExpandedWidth: CGFloat = 100

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

    private var emptySpaceSpacer: some View {
        Spacer()
            .frame(width: 0, height: 22)
    }

    private var spaceContent: some View {
        HStack(alignment: .center, spacing: 6) {
            spaceNumberView

            if windowIcons.isEmpty {
                emptySpaceSpacer
            }

            if !windowIcons.isEmpty {
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
                                    isHovered: hoveredIconId == windowIcon.id,
                                    onHover: { hovering in
                                        hoveredIconId = hovering ? windowIcon.id : nil
                                    },
                                    onLeftClick: {
                                        // Collapse if this icon is expanded
                                        if expandedIconId == windowIcon.id {
                                            autoCollapseTask?.cancel()
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                                expandedIconId = nil
                                            }
                                        }
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

                                // Stack indicator badge
                                if windowIcon.stackIndex > 0 {
                                    ZStack {
                                        Circle()
                                            .fill(Color.white.opacity(0.2))
                                            .frame(width: 10, height: 10)

                                        Text("⧉")
                                            .font(.system(size: 6, weight: .bold))
                                            .foregroundColor(.white.opacity(0.9))
                                    }
                                    .offset(x: 2, y: 2)
                                }
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
                                width: expandedIconId == windowIcon.id
                                    ? calculatedWidth(for: windowIcon)
                                    : 0,
                                alignment: .leading
                            )
                            .opacity(expandedIconId == windowIcon.id ? 1 : 0)
                            .clipped()
                            .animation(
                                .spring(response: 0.35, dampingFraction: 0.75),
                                value: expandedIconId
                            )
                        }
                        .id("\(windowIcon.id)-\(index)")  // Include position in identity to detect reordering
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

    private var spaceContentWithModifiers: some View {
        spaceContent
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
                .animation(.easeInOut(duration: 0.25), value: isActive)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isActive ? Color.white.opacity(0.18) : .clear, lineWidth: 1)
                .animation(.easeInOut(duration: 0.25), value: isActive)
        )
        .overlay(alignment: .topLeading) {
            // Focus indicator dot on bottom border
            GeometryReader { geometry in
                if let focusedIndex = windowIcons.firstIndex(where: { $0.hasFocus }) {
                    let xPosition = calculateDotPosition(for: focusedIndex)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 3, height: 3)
                        .offset(x: xPosition - 1.5, y: geometry.size.height - 2.5)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: xPosition)
                        .transition(.opacity)
                }
            }
            .allowsHitTesting(false)
        }
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(color: isActive ? .white.opacity(0.12) : .clear, radius: 6)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .animation(.easeInOut(duration: 0.25), value: isActive)
        .onHover { isHovered = $0 }
        // Add invisible padding to expand drop zone
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
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
                print("🚫 Rejecting reorder within same space")
                return
            }

            // Always append to end (nil = insert at end)
            DispatchQueue.main.async {
                self.onWindowDrop?(windowId, self.space.index, nil, false)
            }
        }

        return true
    }

    // MARK: - Helper Functions

    private func calculateDotPosition(for focusedIndex: Int) -> CGFloat {
        // Starting position: left padding + space number + spacing after space number
        var xPosition: CGFloat = 8 + 16 + 6

        // Add width of all icons before the focused one
        for i in 0..<focusedIndex {
            xPosition += 22  // Icon width
            xPosition += 6   // Spacing in icon's HStack (always present between icon and title area)

            // If this icon is expanded, add the title width
            if expandedIconId == windowIcons[i].id {
                xPosition += calculatedWidth(for: windowIcons[i])
            }

            xPosition += 6  // Spacing after this icon (from parent HStack)
        }

        // Center on the focused icon: half icon width
        xPosition += 11

        return xPosition
    }

    // MARK: - Expansion Logic

    private func toggleExpansion(for icon: WindowIcon) {
        autoCollapseTask?.cancel()

        // If clicking the same icon → just collapse
        if expandedIconId == icon.id {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                expandedIconId = nil
            }
            return
        }

        // Step 1: force collapse the previous expanded icon
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            expandedIconId = nil
        }

        // Step 2: expand the new icon on the next run loop
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                expandedIconId = icon.id
            }
        }

        // Auto-collapse timer
        let delayNanoseconds = UInt64(config.windowIconExpansionAutoCollapseDelay * 1_000_000_000)
        autoCollapseTask = Task {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            await MainActor.run {
                withAnimation {
                    expandedIconId = nil
                }
            }
        }
    }

    private func calculatedWidth(for icon: WindowIcon) -> CGFloat {
        let titleFont = NSFont.systemFont(ofSize: 11, weight: .medium)
        let titleWidth = icon.title.width(using: titleFont)

        var maxWidth = titleWidth

        if config.showAppNameInExpansion {
            let appFont = NSFont.systemFont(ofSize: 9)
            let appWidth = icon.appName.width(using: appFont)
            maxWidth = max(titleWidth, appWidth)
        }

        return min(maxWidth + 8, maxExpandedWidth)
    }

    private var backgroundColor: Color {
        if isActive {
            return Color.white.opacity(0.18)  // Reduced from 0.25
        } else if isHovered {
            return Color.white.opacity(0.15)
        } else {
            return Color.white.opacity(0.12)
        }
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
    let isHovered: Bool
    let onHover: (Bool) -> Void
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
        view.onHover = onHover
        view.onLeftClick = onLeftClick
        view.onRightClick = onRightClick
        view.onDragStarted = onDragStarted
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ nsView: ClickableIconView, context: Context) {
        nsView.windowId = windowId
        nsView.icon = icon
        nsView.isHovered = isHovered
        nsView.onDragStarted = onDragStarted
        nsView.onDragEnded = onDragEnded
    }
}

// MARK: - AppKit View (ClickableIconView)

final class ClickableIconView: NSView {
    var windowId: Int = 0
    var icon: NSImage?
    var isHovered = false {
        didSet {
            needsDisplay = true
            // Animate scale on hover
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.layer?.transform = isHovered
                    ? CATransform3DMakeScale(1.1, 1.1, 1.0)
                    : CATransform3DIdentity
            }
        }
    }

    var onLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    var onDragStarted: (() -> Void)?
    var onDragEnded: (() -> Void)?

    private var trackingArea: NSTrackingArea?
    private var dragStartLocation: NSPoint?
    private var isDragging = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        registerForDraggedTypes([.string])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        registerForDraggedTypes([.string])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }

        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }

    override func mouseDown(with event: NSEvent) {
        dragStartLocation = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startLocation = dragStartLocation else { return }

        // Calculate drag distance
        let currentLocation = event.locationInWindow
        let dragDistance = hypot(currentLocation.x - startLocation.x, currentLocation.y - startLocation.y)

        // Only start drag if moved more than 3 pixels (avoids accidental drags)
        guard dragDistance > 3, let icon = icon else { return }

        // Notify that drag started
        if !isDragging {
            isDragging = true
            onDragStarted?()
        }

        // Create dragging item with window ID
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString("\(windowId)", forType: .string)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(bounds, contents: icon)

        beginDraggingSession(with: [draggingItem], event: event, source: self)
        dragStartLocation = nil
    }

    override func mouseUp(with event: NSEvent) {
        // If we didn't drag, treat as click
        if let startLocation = dragStartLocation {
            let currentLocation = event.locationInWindow
            let distance = hypot(currentLocation.x - startLocation.x, currentLocation.y - startLocation.y)

            if distance <= 3 {
                print("🖱️ Window icon clicked")
                onLeftClick?()
            }
        }

        // Don't call onDragEnded here - it will be called in draggingSession:endedAt:
        // Only reset local state
        dragStartLocation = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let icon = icon else { return }

        NSGraphicsContext.saveGraphicsState()

        // Draw hover glow background
        if isHovered {
            // Draw outer glow
            let glowPath = NSBezierPath(roundedRect: bounds.insetBy(dx: -2, dy: -2), xRadius: 7, yRadius: 7)
            NSColor.white.withAlphaComponent(0.15).setFill()
            glowPath.fill()

            // Draw inner background
            let bgPath = NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5)
            NSColor.white.withAlphaComponent(0.2).setFill()
            bgPath.fill()

            // Set shadow for icon
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.white.withAlphaComponent(0.5)
            shadow.shadowBlurRadius = 6
            shadow.shadowOffset = NSSize(width: 0, height: 0)
            shadow.set()
        }

        // Draw icon with full opacity when hovered
        icon.draw(
            in: bounds,
            from: .zero,
            operation: .sourceOver,
            fraction: isHovered ? 1.0 : 0.85
        )

        NSGraphicsContext.restoreGraphicsState()
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

// MARK: - Helper: String width measurement

private extension String {
    func width(using font: NSFont) -> CGFloat {
        let attributes = [NSAttributedString.Key.font: font]
        return (self as NSString).size(withAttributes: attributes).width
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

