import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

// MARK: - Space Indicator View

struct SpaceIndicatorView: View {
    let space: WMSpace
    let isActive: Bool
    let windowIcons: [WindowIcon]
    let allWindowIcons: [WindowIcon]
    let focusedIndex: Int?  // Pre-computed by ViewModel (avoids O(N) search per render)
    let dotEntryEdge: Edge  // Direction for focus dot entry animation
    let onWindowClick: ((Int) -> Void)?
    let onSpaceClick: (() -> Void)?
    let onSpaceDestroy: ((Int) -> Void)?
    let onWindowDrop: ((Int, Int, Int?, Bool) -> Void)?  // (windowId, targetSpaceIndex, insertBeforeWindowId, shouldStack)
    let onSpaceMove: ((Int, Int) -> Void)?  // (fromIndex, toIndex)
    let spaceIds: [Int]  // Ordered array of space IDs for position computation
    @Binding var draggedWindowId: Int?  // Shared: ID of window currently being dragged
    @Binding var expandedWindowId: Int?  // Shared: ID of currently expanded window icon (persists across updates)
    @Binding var draggedSpaceIndex: Int?  // Shared: space index being dragged for reorder
    @Binding var dropTargetSpaceIndex: Int?  // Shared: target position during space drag
    @Binding var draggedSpaceWidth: CGFloat  // Shared: width of dragged space for shift calculation
    let spaceWidths: [Int: CGFloat]  // Measured widths of all space indicators for drag computation
    let spaceDisplayIndices: [Int]  // Ordered global indices of spaces on this display

    @State private var isOverflowExpanded = false  // True when showing all icons (overflow expanded)
    @State private var autoCollapseTask: Task<Void, Never>?
    @State private var isDraggingOver = false  // True when actively dragging over this space
    @State private var spaceDragOffset: CGFloat = 0  // Horizontal offset during space drag

    // Non-reactive width storage for drag calculations only.
    // Using a class ref instead of @State avoids triggering body re-evaluations
    // when the width changes during expand/collapse animation (~42 times per animation).
    private final class WidthRef { var value: CGFloat = 50 }
    @State private var widthRef = WidthRef()

    @ObservedObject private var config = AegisConfig.shared

    // Icons to display - either limited or all based on expansion state
    private var displayedIcons: [WindowIcon] {
        isOverflowExpanded ? allWindowIcons : windowIcons
    }

    // Number of hidden icons (only shown when not expanded)
    private var hiddenCount: Int {
        allWindowIcons.count - windowIcons.count
    }

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
        Text(space.label?.isEmpty == false ? space.label! : "\(space.index)")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(ThemeColors.primaryText(opacity: isActive ? 1.0 : 0.6))
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
                    ForEach(Array(displayedIcons.enumerated()), id: \.element.id) { index, windowIcon in
                        ExpandableWindowIcon(
                            windowIcon: windowIcon,
                            isExpanded: expandedWindowId == windowIcon.id,
                            isDragged: draggedWindowId == windowIcon.id,
                            showAppName: config.showAppNameInExpansion,
                            onLeftClick: { onWindowClick?(windowIcon.id) },
                            onRightClick: { toggleExpansion(for: windowIcon) },
                            onDragStarted: { draggedWindowId = windowIcon.id },
                            onDragEnded: { draggedWindowId = nil }
                        )
                        .equatable()
                        .id(windowIcon.id)
                    }

            // Overflow toggle button - shows "+N" when collapsed, "-" when expanded
            if hiddenCount > 0 {
                overflowToggleButton
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isOverflowExpanded)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: draggedWindowId)
    }

    private var overflowToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isOverflowExpanded.toggle()
            }
        } label: {
            Group {
                if isOverflowExpanded {
                    // Collapse button when expanded
                    Image(systemName: "minus")
                        .font(.system(size: 9, weight: .bold))
                } else {
                    // Show count when collapsed
                    Text("+\(hiddenCount)")
                        .font(.system(size: 9, weight: .medium))
                }
            }
            .foregroundColor(ThemeColors.tertiaryText())
            .frame(width: 20, height: 20)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(ThemeColors.background.opacity(isOverflowExpanded ? 0.25 : 0.12))
            )
        }
        .buttonStyle(.plain)
    }

    // Pre-compute dot position to avoid recalculation in view body
    private var dotXPosition: CGFloat {
        guard let idx = focusedIndex else { return 0 }
        // Starting position: left padding + space number + spacing after space number
        var xPosition: CGFloat = 8 + 16 + 6

        // Add width of all icons before the focused one
        let iconsToCheck = displayedIcons
        for i in 0..<idx {
            xPosition += 22  // Icon width
            xPosition += 6   // Spacing in icon's HStack

            // If this icon is expanded, add the title width
            if i < iconsToCheck.count && expandedWindowId == iconsToCheck[i].id {
                xPosition += iconsToCheck[i].expandedWidth
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
                Group {
                    if config.isLiquidGlass {
                        SpacePillGlassBackground(isActive: isActive, cornerRadius: 8)
                    } else {
                        // Use AppKit-based hover background to avoid SwiftUI state churn
                        HoverableBackground(isActive: isActive, cornerRadius: 8)
                    }
                }
            )
            .overlay(
                Group {
                    if !config.isLiquidGlass {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isActive ? ThemeColors.border(opacity: 0.18) : .clear, lineWidth: 1)
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isDraggingOver && draggedWindowId != nil
                            ? ThemeColors.foreground.opacity(0.35)
                            : .clear,
                        lineWidth: 1.5
                    )
            )
            .animation(.easeInOut(duration: 0.15), value: isDraggingOver)
            .overlay(alignment: .bottomLeading) {
                // Focus indicator dot at bottom edge with directional entry
                if focusedIndex != nil {
                    Circle()
                        .fill(ThemeColors.foreground)
                        .frame(width: 3, height: 3)
                        .offset(x: dotXPosition - 1.5, y: 1.5)
                        .transition(.asymmetric(
                            insertion: .move(edge: dotEntryEdge).combined(with: .opacity),
                            removal: .opacity
                        ))
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: 0.2), value: focusedIndex != nil)
            .shadow(
                color: (!config.isLiquidGlass && isActive) ? ThemeColors.foreground.opacity(0.12) : .clear,
                radius: 6
            )
            .animation(.easeOut(duration: 0.12), value: isActive)
        // Measure width for drag calculations — writes to class ref (not @State)
        // so no SwiftUI re-renders are triggered during animation
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { widthRef.value = geo.size.width }
                    .onChange(of: geo.size.width) { widthRef.value = $0 }
            }
        )
        // Space drag-to-reorder: offset and visual feedback
        .offset(x: computeSpaceOffset())
        // Animate non-dragged spaces shifting; dragged space follows cursor (no animation)
        .animation(
            draggedSpaceIndex != nil && draggedSpaceIndex != space.index
                ? .spring(response: 0.3, dampingFraction: 0.8)
                : nil,
            value: dropTargetSpaceIndex
        )
        .opacity(draggedSpaceIndex == space.index ? 0.8 : 1.0)
        .scaleEffect(draggedSpaceIndex == space.index ? 1.03 : 1.0)
        .zIndex(draggedSpaceIndex == space.index ? 1 : 0)
        // Add invisible padding to expand drop zone
        // Use asymmetric padding: no top padding to maintain alignment, bottom padding for drop zone
        .padding(.horizontal, 4)
        .contentShape(Rectangle())  // Make the entire padded area droppable
        .gesture(
            DragGesture(minimumDistance: 5)
                .onChanged { value in
                    handleSpaceDragChanged(value)
                }
                .onEnded { _ in
                    handleSpaceDragEnded()
                }
        )
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

            // Always append to end (nil = insert at end)
            // Note: yabai's window --space command is idempotent, so same-space drops are harmless
            DispatchQueue.main.async {
                self.onWindowDrop?(windowId, self.space.index, nil, false)
            }
        }

        return true
    }

    // MARK: - Space Drag-to-Reorder

    private func computeSpaceOffset() -> CGFloat {
        // If this space is being dragged, use the drag offset
        if draggedSpaceIndex == space.index {
            return spaceDragOffset
        }

        // If no drag in progress, no offset
        guard let draggedPos = draggedSpaceIndex,
              let targetPos = dropTargetSpaceIndex else {
            return 0
        }

        // Use display positions directly (space.index is 1-based display position)
        let myPos = space.index
        let shiftAmount = draggedSpaceWidth + config.spaceIndicatorSpacing

        if draggedPos < targetPos {
            // Dragging right: spaces between dragged+1 and target shift left
            if myPos > draggedPos && myPos <= targetPos {
                return -shiftAmount
            }
        } else if draggedPos > targetPos {
            // Dragging left: spaces between target and dragged-1 shift right
            if myPos >= targetPos && myPos < draggedPos {
                return shiftAmount
            }
        }

        return 0
    }

    private func handleSpaceDragChanged(_ value: DragGesture.Value) {
        // Dragged space follows cursor directly (no animation)
        spaceDragOffset = value.translation.width

        // Set dragged space and store width on first drag event
        if draggedSpaceIndex == nil {
            draggedSpaceIndex = space.index
            draggedSpaceWidth = max(widthRef.value, 30)  // Floor to prevent zero-width shifts
        }

        // Compute target using actual space widths (center-to-center distances)
        // Uses spaceDisplayIndices (ordered global indices for this display) to iterate
        // over actual neighbors, avoiding global vs local index mismatch on multi-monitor
        let draggedPos = space.index  // global index
        let myWidth = spaceWidths[draggedPos] ?? widthRef.value
        let translation = value.translation.width

        guard let localPos = spaceDisplayIndices.firstIndex(of: draggedPos) else { return }

        var targetPos = draggedPos

        if translation > 0 {
            // Dragging right: accumulate center-to-center distances
            var cumulative: CGFloat = myWidth / 2
            for i in (localPos + 1)..<spaceDisplayIndices.count {
                let globalIdx = spaceDisplayIndices[i]
                let w = spaceWidths[globalIdx] ?? widthRef.value
                cumulative += config.spaceIndicatorSpacing + w / 2
                if translation >= cumulative {
                    targetPos = globalIdx
                    cumulative += w / 2  // Past center, advance to far edge
                } else {
                    break
                }
            }
        } else if translation < 0 {
            // Dragging left: same logic in reverse
            var cumulative: CGFloat = myWidth / 2
            for i in stride(from: localPos - 1, through: 0, by: -1) {
                let globalIdx = spaceDisplayIndices[i]
                let w = spaceWidths[globalIdx] ?? widthRef.value
                cumulative += config.spaceIndicatorSpacing + w / 2
                if abs(translation) >= cumulative {
                    targetPos = globalIdx
                    cumulative += w / 2
                } else {
                    break
                }
            }
        }

        if targetPos != dropTargetSpaceIndex {
            dropTargetSpaceIndex = targetPos
        }
    }

    private func handleSpaceDragEnded() {
        // Wrap everything in a single no-animation transaction to prevent flash
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if let targetIdx = dropTargetSpaceIndex, targetIdx != space.index {
                onSpaceMove?(space.index, targetIdx)
            }
            // Always reset drag state — optimistic reorder in coordinator prevents snap-back
            spaceDragOffset = 0
            draggedSpaceIndex = nil
            dropTargetSpaceIndex = nil
        }
    }

    // MARK: - Expansion Logic

    private func toggleExpansion(for icon: WindowIcon) {
        autoCollapseTask?.cancel()

        // If clicking the same icon → just collapse (toggle off)
        if expandedWindowId == icon.id {
            withAnimation(.easeOut(duration: 0.15)) {
                expandedWindowId = nil
            }
            return
        }

        // Direct swap: one collapses while other expands
        withAnimation(.easeOut(duration: 0.2)) {
            expandedWindowId = icon.id
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
            // Simple opacity change - implicit CALayer animation, no CATransaction overhead
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
        layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)  // Scale from center
        layer?.opacity = 0.85  // Default non-hovered opacity
        registerForDraggedTypes([.string])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
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

        // Render once to cache, then draw from cache
        let rendered = NSImage(size: bounds.size)
        rendered.lockFocus()
        icon.draw(in: NSRect(origin: .zero, size: bounds.size), from: .zero, operation: .sourceOver, fraction: stateOpacity)
        rendered.unlockFocus()

        cachedImage = rendered
        cachedBounds = bounds

        // Draw from the freshly cached image
        rendered.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0)
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

// MARK: - Hoverable Background (AppKit-based for CPU efficiency)

/// AppKit-based background that handles hover at the CALayer level
/// This avoids SwiftUI state changes and re-renders on every hover event
struct HoverableBackground: NSViewRepresentable {
    let isActive: Bool
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> HoverableBackgroundView {
        let view = HoverableBackgroundView()
        view.cornerRadius = cornerRadius
        view.isActiveSpace = isActive
        return view
    }

    func updateNSView(_ nsView: HoverableBackgroundView, context: Context) {
        nsView.isActiveSpace = isActive
    }
}

final class HoverableBackgroundView: NSView {
    var cornerRadius: CGFloat = 8 {
        didSet {
            backgroundLayer.cornerRadius = cornerRadius
        }
    }

    var isActiveSpace: Bool = false {
        didSet {
            guard isActiveSpace != oldValue else { return }
            updateBackgroundColor(animated: true)
        }
    }

    private var isHovered: Bool = false {
        didSet {
            guard isHovered != oldValue else { return }
            updateBackgroundColor(animated: true)
        }
    }

    private let backgroundLayer = CALayer()
    private var trackingArea: NSTrackingArea?
    private var themeObserver: NSObjectProtocol?
    private var configCancellable: AnyCancellable?
    private let config = AegisConfig.shared

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayer()
        setupThemeObserver()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
        setupThemeObserver()
    }

    deinit {
        if let observer = themeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupLayer() {
        wantsLayer = true
        layer?.addSublayer(backgroundLayer)
        backgroundLayer.cornerRadius = cornerRadius
        backgroundLayer.backgroundColor = colorForCurrentState()
    }

    private func setupThemeObserver() {
        themeObserver = NotificationCenter.default.addObserver(
            forName: .themeDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateBackgroundColor(animated: true)
        }
        configCancellable = config.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateBackgroundColor(animated: false)
            }
    }

    private func colorForCurrentState() -> CGColor {
        let opacity: CGFloat
        if isActiveSpace {
            opacity = config.activeSpaceBgOpacity
        } else if isHovered {
            opacity = config.hoveredSpaceBgOpacity
        } else {
            opacity = config.inactiveSpaceBgOpacity
        }
        return ThemeColors.backgroundCGColor(alpha: opacity)
    }

    override func layout() {
        super.layout()
        // Disable implicit animations during layout
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backgroundLayer.frame = bounds
        CATransaction.commit()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        trackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    private func updateBackgroundColor(animated: Bool) {
        let targetColor = colorForCurrentState()

        if animated {
            // Use Core Animation for smooth, GPU-accelerated transition
            let animation = CABasicAnimation(keyPath: "backgroundColor")
            animation.fromValue = backgroundLayer.backgroundColor
            animation.toValue = targetColor
            animation.duration = 0.08
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            backgroundLayer.add(animation, forKey: "backgroundColorAnimation")
        }

        // Disable implicit animation when setting the final value
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backgroundLayer.backgroundColor = targetColor
        CATransaction.commit()
    }
}

// MARK: - Glass Pill Background (Liquid Glass theme)

/// NSViewRepresentable wrapper around GlassPillBackgroundView.
/// Uses .glass material on macOS 26+, falling back to .ultraThinMaterial.
/// Hover tracking is handled at the AppKit level (same pattern as HoverableBackground).
struct GlassPillBackground: NSViewRepresentable {
    let isActive: Bool
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> GlassPillBackgroundView {
        let view = GlassPillBackgroundView()
        view.cornerRadius = cornerRadius
        view.isActiveSpace = isActive
        return view
    }

    func updateNSView(_ nsView: GlassPillBackgroundView, context: Context) {
        nsView.isActiveSpace = isActive
    }
}

final class GlassPillBackgroundView: NSView {
    var cornerRadius: CGFloat = 8 {
        didSet { applyCornerRadius() }
    }

    var isActiveSpace: Bool = false {
        didSet {
            guard isActiveSpace != oldValue else { return }
            updateAppearance(animated: true)
        }
    }

    private var isHovered: Bool = false {
        didSet {
            guard isHovered != oldValue else { return }
            updateAppearance(animated: true)
        }
    }

    private let effectView = NSVisualEffectView()
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.autoresizingMask = [.width, .height]
        addSubview(effectView)
        applyCornerRadius()
        updateAppearance(animated: false)
    }

    private func applyCornerRadius() {
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
        effectView.layer?.cornerRadius = cornerRadius
        effectView.layer?.masksToBounds = true
    }

    override func layout() {
        super.layout()
        effectView.frame = bounds
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        trackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent)  { isHovered = false }

    private func updateAppearance(animated: Bool) {
        let targetAlpha: CGFloat = isActiveSpace ? 1.0 : isHovered ? 0.75 : 0.45
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                effectView.animator().alphaValue = targetAlpha
            }
        } else {
            effectView.alphaValue = targetAlpha
        }
    }
}

/// SwiftUI wrapper that layers specular highlight, glass edge stroke, and shadow
/// over the NSVisualEffectView glass base for the Liquid Glass theme.
struct SpacePillGlassBackground: View {
    let isActive: Bool
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            // Layer 1: NSVisualEffectView glass blur (handles refraction/tinting)
            GlassPillBackground(isActive: isActive, cornerRadius: cornerRadius)

            // Layer 2: Active inner wet glow
            if isActive {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.white.opacity(0.08))
            }

            // Layer 3: Specular highlight — light hitting the top glass surface
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .white.opacity(0.35), location: 0.0),
                            .init(color: .white.opacity(0.0),  location: 0.42)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Layer 4: Glass edge — bright top-left, dim bottom-right (3D glass edge)
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .white.opacity(0.45), location: 0.0),
                            .init(color: .white.opacity(0.45), location: 0.25),
                            .init(color: .white.opacity(0.18), location: 0.5),
                            .init(color: .white.opacity(0.08), location: 0.75),
                            .init(color: .white.opacity(0.08), location: 1.0)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(
            color: .black.opacity(isActive ? 0.20 : 0.0),
            radius: isActive ? 9 : 0,
            x: 0,
            y: 2
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isActive)
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

    // Throttle scroll event processing to reduce CPU usage
    private var lastScrollEventTime: CFTimeInterval = 0
    private let scrollEventThrottle: CFTimeInterval = 0.05  // ~20fps max

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
            guard let self = self, let selfWindow = self.window else {
                print("🔴 SwipeDetector[\(ObjectIdentifier(self ?? SwipeDetectorView()))]: no window")
                return event
            }

            // Only process events from our own window
            if let eventWindow = event.window, eventWindow !== selfWindow {
                return event
            }

            // Throttle at monitor level to reduce CPU overhead
            let now = CACurrentMediaTime()
            guard now - self.lastScrollEventTime >= self.scrollEventThrottle else {
                return event
            }
            self.lastScrollEventTime = now

            // Use frame-based detection since SwipeDetectorView has allowsHitTesting(false)
            // Convert our bounds to window coordinates and check if event location is inside
            let locationInWindow = event.locationInWindow
            let boundsInWindow = self.convert(self.bounds, to: nil)
            let isInside = boundsInWindow.contains(locationInWindow)

            if isInside {
                self.handleScrollWheel(event)
            }

            return event
        }
    }

    private func handleScrollWheel(_ event: NSEvent) {
        let deltaY = event.scrollingDeltaY

        // Phase values: 1=began, 4=changed, 8=ended, 16=cancelled, 32=mayBegin, 0=momentum
        // Trackpad swipes quickly transition from changed to momentum, so we need to
        // include early momentum events in our accumulation

        switch event.phase {
        case .began, .mayBegin:
            // Start of a new gesture - reset accumulator and mark gesture as active
            scrollAccumulator = 0
            isGestureActive = true

        case .changed:
            // Gesture in progress - accumulate
            scrollAccumulator += deltaY

        case .ended:
            // Gesture ended - final accumulation
            scrollAccumulator += deltaY
            checkThresholdAndTrigger()
            scrollAccumulator = 0
            isGestureActive = false

        case .cancelled:
            scrollAccumulator = 0
            isGestureActive = false

        default:
            // Momentum phase (phase=0) - only count if gesture was recently active
            // This handles the case where trackpad quickly transitions to momentum
            if isGestureActive {
                scrollAccumulator += deltaY
                checkThresholdAndTrigger()
            }
        }
    }

    private var isGestureActive = false

    private func checkThresholdAndTrigger() {
        // Threshold for swipe-up gesture (negative = upward)
        if scrollAccumulator < -80 {
            DispatchQueue.main.async { [weak self] in
                self?.onSwipeUp?()
            }
            scrollAccumulator = 0
            isGestureActive = false  // Prevent re-triggering
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

// MARK: - Isolated Expandable Window Icon

/// Isolates per-icon re-renders during expansion animation.
/// Takes `isExpanded` and `isDragged` as plain Bool values so SwiftUI
/// only re-evaluates icons whose state actually changed — not all icons
/// on every animation frame.
private struct ExpandableWindowIcon: View, Equatable {
    let windowIcon: WindowIcon
    let isExpanded: Bool
    let isDragged: Bool
    let showAppName: Bool
    let onLeftClick: () -> Void
    let onRightClick: () -> Void
    let onDragStarted: () -> Void
    let onDragEnded: () -> Void

    static func == (lhs: ExpandableWindowIcon, rhs: ExpandableWindowIcon) -> Bool {
        lhs.windowIcon == rhs.windowIcon &&
        lhs.isExpanded == rhs.isExpanded &&
        lhs.isDragged == rhs.isDragged &&
        lhs.showAppName == rhs.showAppName
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                RightClickableIcon(
                    windowId: windowIcon.id,
                    icon: windowIcon.icon ?? NSImage(),
                    isMinimized: windowIcon.isMinimized,
                    isHidden: windowIcon.isHidden,
                    onLeftClick: onLeftClick,
                    onRightClick: onRightClick,
                    onDragStarted: onDragStarted,
                    onDragEnded: onDragEnded
                )

                WindowStatusBadge(
                    isMinimized: windowIcon.isMinimized,
                    isHidden: windowIcon.isHidden,
                    stackIndex: windowIcon.stackIndex
                )
            }
            .frame(width: isDragged ? 0 : 22, height: 22)
            .opacity(isDragged ? 0.0 : 1.0)
            .clipped()

            // Expandable title area (dynamic width)
            VStack(alignment: .leading, spacing: 2) {
                Text(windowIcon.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(ThemeColors.secondaryText())
                    .lineLimit(1)

                if showAppName {
                    Text(windowIcon.appName)
                        .font(.system(size: 9))
                        .foregroundColor(ThemeColors.tertiaryText())
                        .lineLimit(1)
                }
            }
            .frame(width: windowIcon.expandedWidth, alignment: .leading)
            .frame(
                width: isDragged ? 0 : (isExpanded ? windowIcon.expandedWidth : 0),
                alignment: .leading
            )
            .opacity(isDragged ? 0 : (isExpanded ? 1 : 0))
            .clipped()
        }
    }
}

