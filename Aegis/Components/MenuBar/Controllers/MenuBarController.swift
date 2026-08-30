import Cocoa
import SwiftUI
import Combine

// MARK: - MenuBarController
// Simplified controller that delegates to MenuBarCoordinator
// This maintains backward compatibility with existing code

class MenuBarController {
    private let coordinator: MenuBarCoordinator

    init(windowManager: WindowManagerProtocol, eventRouter: EventRouter) {
        self.coordinator = MenuBarCoordinator(
            windowManager: windowManager,
            eventRouter: eventRouter
        )
    }

    // Show the menu bar
    func show() {
        coordinator.show()
    }

    // Hide the menu bar
    func hide() {
        coordinator.hide()
    }

    // MARK: - Public update methods

    // Refresh spaces (called on spaceChanged)
    func updateSpaces() {
        coordinator.updateSpaces()
    }

    // Refresh window icons (called on windowsChanged)
    func updateWindows() {
        coordinator.updateWindows()
    }

    // MARK: - Notch HUD Integration

    // Connect to NotchHUDController to observe HUD visibility
    func connectHUDVisibility(from hudController: NotchHUDController) {
        coordinator.connectHUDVisibility(from: hudController)
    }
}

// MARK: - SwiftUI Menu Bar View (kept in this file for compatibility)

// PreferenceKey used to report the active space pill's frame in the scroll viewport.
// Fires reactively on every layout pass (including during expansion animation).
struct ActiveSpaceFrameValue: Equatable {
    let spaceId: Int
    let frame: CGRect
}

struct ActiveSpaceFrameKey: PreferenceKey {
    static var defaultValue: ActiveSpaceFrameValue? = nil
    static func reduce(value: inout ActiveSpaceFrameValue?, nextValue: () -> ActiveSpaceFrameValue?) {
        value = nextValue() ?? value
    }
}

// Reference type: tracks last seen focused space ID and frame without triggering SwiftUI re-renders.
// Used to detect focus changes and pill expansion in onPreferenceChange without causing layout passes.
private final class ScrollState {
    var previousSpaceId: Int? = nil
    var previousFrame: CGRect? = nil
}

struct MenuBarView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @ObservedObject var spaceStore: SpaceViewModelStore
    let sharedState: SharedMenuBarState
    let onSpaceClick: (Int) -> Void
    let onWindowClick: (Int) -> Void
    let onSpaceDestroy: (Int) -> Void
    let onSpaceCreate: () -> Void
    let onWindowDrop: (Int, Int, Int?, Bool) -> Void
    let onSpaceMove: (Int, Int) -> Void
    let onRotateLayout: (Int) -> Void
    let onFlipLayout: (String) -> Void
    let onBalanceLayout: () -> Void
    let onToggleLayout: () -> Void
    let onStackAllWindows: () -> Void
    let onToggleApp: (FloatingApp) -> Void

    @ObservedObject private var config = AegisConfig.shared
    @State private var launcherAppFocused: Bool = false
    @State private var scrollOffset: CGFloat = 0
    @State private var isScrolled: Bool = false
    @State private var previousSpaceCount: Int = 0
    @State private var isContextButtonExpanded: Bool = false
    @State private var scrollState = ScrollState()
    @State private var isMediaHUDActive: Bool = false

    // Dynamic context button width based on expansion state and visibility
    private var contextButtonWidth: CGFloat {
        guard config.showContextButton else { return 0 }
        return isContextButtonExpanded
            ? AppKitLayoutActionsButton.expandedWidth
            : AppKitLayoutActionsButton.collapsedWidth
    }

    // Calculate left button area width for spacer
    private var leftButtonsWidth: CGFloat {
        var width: CGFloat = config.menuBarEdgePadding

        if config.showContextButton {
            width += contextButtonWidth
        }

        if config.showContextButton && config.showAppLauncher {
            width += 6 // spacing between buttons
        }

        if config.showAppLauncher {
            width += 32 // launcher button width
        }

        if config.showSpaceIndicators {
            width += config.spaceIndicatorSpacing
        }

        return width
    }

    /// Calculate available width for space indicators (stops before the notch HUD area on MacBook)
    private func availableSpaceWidth(screenWidth: CGFloat) -> CGFloat {
        guard let screen = viewModel.targetScreen ?? NSScreen.main,
              screen.safeAreaInsets.top > 0 else {
            // No notch - use generous width (leave room for system status on right)
            return screenWidth - leftButtonsWidth - 150
        }

        let notchDimensions = NotchDimensions.calculate(for: screen)
        let notchLeftEdge = screenWidth / 2 - notchDimensions.width / 2
        // The scroll container is visually offset left (to extend under buttons), so its
        // visual right edge = scrollViewExtraLeft + maxWidth, not just maxWidth.
        // Subtract the extra to align the visual edge with the desired screen position.
        let scrollViewExtraLeft = leftButtonsWidth
            - (config.menuBarEdgePadding + config.spaceIndicatorSpacing + contextButtonWidth)
        if isMediaHUDActive {
            // HUD active: visual right edge stops at album art's left edge
            return notchLeftEdge - notchDimensions.height - scrollViewExtraLeft
        } else {
            // HUD inactive: visual right edge stops at notch left edge
            return notchLeftEdge - scrollViewExtraLeft
        }
    }

    init(
        viewModel: MenuBarViewModel,
        onSpaceClick: @escaping (Int) -> Void,
        onWindowClick: @escaping (Int) -> Void,
        onSpaceDestroy: @escaping (Int) -> Void,
        onSpaceCreate: @escaping () -> Void,
        onWindowDrop: @escaping (Int, Int, Int?, Bool) -> Void,
        onSpaceMove: @escaping (Int, Int) -> Void,
        onRotateLayout: @escaping (Int) -> Void,
        onFlipLayout: @escaping (String) -> Void,
        onBalanceLayout: @escaping () -> Void,
        onToggleLayout: @escaping () -> Void,
        onStackAllWindows: @escaping () -> Void,
        onToggleApp: @escaping (FloatingApp) -> Void
    ) {
        self.viewModel = viewModel
        self.spaceStore = viewModel.spaceStore
        self.sharedState = viewModel.sharedState
        self.onSpaceClick = onSpaceClick
        self.onWindowClick = onWindowClick
        self.onSpaceDestroy = onSpaceDestroy
        self.onSpaceCreate = onSpaceCreate
        self.onWindowDrop = onWindowDrop
        self.onSpaceMove = onSpaceMove
        self.onRotateLayout = onRotateLayout
        self.onFlipLayout = onFlipLayout
        self.onBalanceLayout = onBalanceLayout
        self.onToggleLayout = onToggleLayout
        self.onStackAllWindows = onStackAllWindows
        self.onToggleApp = onToggleApp
    }

    var body: some View {
        AegisMenuBarSurface {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    HStack(alignment: .center, spacing: 0) {
                        // Dynamic spacer - accounts for visible buttons (context, launcher)
                        Spacer()
                            .frame(width: leftButtonsWidth)

                        // Spaces (with scrolling if needed)
                        ZStack(alignment: .leading) {
                        // Scrollable spaces area - only show if space indicators enabled
                        if config.showSpaceIndicators {
                            let maxWidth = availableSpaceWidth(screenWidth: geometry.size.width)

                            ZStack(alignment: .trailing) {
                                ScrollViewReader { scrollProxy in
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(alignment: .center, spacing: config.spaceIndicatorSpacing) {
                                            // Sentinel at scroll-content-x=0 (before any pill).
                                            // scrollTo("space-row-start", .leading) → contentOffset=0
                                            // → scrollOffset=0 → isScrolled=false → left fade disappears.
                                            Color.clear
                                                .frame(width: config.menuBarEdgePadding + contextButtonWidth, height: 0)
                                                .id("space-row-start")

                                            // Split State Architecture: ForEach over space IDs
                                            // Each SpaceIndicatorViewContainer observes only its own SpaceViewModel
                                            // This prevents re-renders of all spaces when only one changes
                                            let spaceDisplayIndices = spaceStore.spaceIds.compactMap { spaceStore.viewModel(for: $0)?.space.index }
                                            ForEach(spaceStore.spaceIds, id: \.self) { spaceId in
                                                if let spaceVM = spaceStore.viewModel(for: spaceId) {
                                                    SpaceIndicatorViewContainer(
                                                        spaceViewModel: spaceVM,
                                                        sharedState: sharedState,
                                                        onWindowClick: onWindowClick,
                                                        onSpaceClick: {
                                                            onSpaceClick(spaceVM.space.index)
                                                        },
                                                        onSpaceDestroy: onSpaceDestroy,
                                                        onWindowDrop: onWindowDrop,
                                                        onSpaceMove: onSpaceMove,
                                                        spaceIds: spaceStore.spaceIds,
                                                        spaceDisplayIndices: spaceDisplayIndices
                                                    )
                                                    // Insertion: slide in from left
                                                    // Removal: handled by SwipeableSpaceContainer's own animation (fade + move up)
                                                    // Using .identity for removal to avoid double-animation and vertical jiggle
                                                    .transition(.asymmetric(
                                                        insertion: .move(edge: .leading).combined(with: .opacity),
                                                        removal: .identity
                                                    ))
                                                }
                                            }
                                        }
                                        .padding(.trailing, 20)  // Small trailing padding
                                        .background(
                                            GeometryReader { geo in
                                                Color.clear
                                                    .preference(
                                                        key: ScrollOffsetPreferenceKey.self,
                                                        value: geo.frame(in: .named("scroll")).minX
                                                    )
                                            }
                                        )
                                    }
                                    .coordinateSpace(name: "scroll")
                                    .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                                        scrollOffset = value
                                        // Content is scrolled left (under button) if minX is less than 0
                                        isScrolled = value < -5
                                    }
                                    .onChange(of: spaceStore.spaceIds) { newSpaceIds in
                                        // Only auto-scroll when spaces are ADDED (not removed or focus changed)
                                        // This ensures newly created spaces behind the notch become visible
                                        // For removal, SwiftUI handles scroll position automatically
                                        let newCount = newSpaceIds.count
                                        if newCount > previousSpaceCount {
                                            previousSpaceCount = newCount
                                            // Find the focused space from the store
                                            if let focusedSpaceId = newSpaceIds.first(where: { spaceId in
                                                spaceStore.viewModel(for: spaceId)?.space.isFocused ?? false
                                            }) {
                                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                                    scrollProxy.scrollTo(focusedSpaceId, anchor: .leading)
                                                }
                                            }
                                        } else {
                                            previousSpaceCount = newCount
                                        }
                                    }
                                    .onPreferenceChange(ActiveSpaceFrameKey.self) { value in
                                        guard let value else {
                                            scrollState.previousSpaceId = nil
                                            scrollState.previousFrame = nil
                                            return
                                        }
                                        let isNewFocus = value.spaceId != scrollState.previousSpaceId
                                        let previousFrame = scrollState.previousFrame
                                        scrollState.previousSpaceId = value.spaceId
                                        scrollState.previousFrame = value.frame

                                        if value.frame.maxX > maxWidth + 2 {
                                            let shouldScroll: Bool
                                            if isNewFocus {
                                                shouldScroll = true
                                            } else if let prev = previousFrame {
                                                // Expansion: maxX grows significantly more than minX shifts.
                                                // Manual scroll: both edges shift by roughly the same delta.
                                                let maxXGrowth = value.frame.maxX - prev.maxX
                                                let minXShift = value.frame.minX - prev.minX
                                                shouldScroll = maxXGrowth > minXShift + 5
                                            } else {
                                                shouldScroll = false
                                            }
                                            if shouldScroll {
                                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                                    scrollProxy.scrollTo(value.spaceId, anchor: .trailing)
                                                }
                                            }
                                        } else if value.frame.minX < -2 && isNewFocus {
                                            // Only snap left on focus change, not during manual scroll.
                                            // Scrolling to sentinel (x=0) sets contentOffset=0
                                            // so isScrolled=false and the left fade clears.
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                                scrollProxy.scrollTo("space-row-start", anchor: .leading)
                                            }
                                        }
                                    }
                                    .onReceive(sharedState.isHUDVisibleSubject) { isActive in
                                        // Only update state here — @State mutations are queued, so
                                        // availableSpaceWidth would still read the old value if called here.
                                        isMediaHUDActive = isActive
                                    }
                                    .onChange(of: isMediaHUDActive) { isActive in
                                        // Fires after state is committed → availableSpaceWidth is correct.
                                        // If HUD just became active (maxWidth narrowed), scroll active pill into new boundary.
                                        guard isActive,
                                              let frame = scrollState.previousFrame,
                                              let spaceId = scrollState.previousSpaceId else { return }
                                        let newMaxWidth = availableSpaceWidth(screenWidth: geometry.size.width)
                                        if frame.maxX > newMaxWidth + 2 {
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                                scrollProxy.scrollTo(spaceId, anchor: .trailing)
                                            }
                                        }
                                    }
                                    .onAppear {
                                        previousSpaceCount = spaceStore.spaceIds.count
                                        if let index = sharedState.currentFocusedSpaceIndex,
                                           let spaceId = spaceStore.spaceIds.first(where: {
                                               spaceStore.viewModel(for: $0)?.space.index == index
                                           }) {
                                            DispatchQueue.main.async {
                                                scrollProxy.scrollTo(spaceId, anchor: .trailing)
                                            }
                                        }
                                    }
                                }
                                .frame(maxWidth: maxWidth, alignment: .leading)  // Constrain width to stop before notch
                                .clipped()  // Hard clip at boundary
                                .offset(x: -(config.menuBarEdgePadding + config.spaceIndicatorSpacing + contextButtonWidth))  // Extend under button
                                .mask(
                                    // Simplified mask using HStack of gradients - avoids expensive blend modes
                                    HStack(spacing: 0) {
                                        // Left fade - hide content as it scrolls under the button
                                        LinearGradient(
                                            colors: [.clear, .white],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                        .frame(width: isScrolled ? (config.menuBarEdgePadding + config.spaceIndicatorSpacing + contextButtonWidth + 20) : 0)

                                        // Middle - full visibility
                                        Rectangle()
                                            .fill(Color.white)

                                        // Right fade - smooth fade before edge (kept narrow so active pill isn't faded)
                                        LinearGradient(
                                            colors: [.white, .clear],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                        .frame(width: 16)
                                    }
                                    .animation(.easeInOut(duration: 0.2), value: isScrolled)
                                )

                            }
                        } // end if showSpaceIndicators
                        }

                        Spacer()
                    }
                    .frame(height: config.menuBarHeight, alignment: .center)
                    .animation(.easeOut(duration: 0.2), value: isContextButtonExpanded)

                    // Right: System status - positioned on its own layer for proper vertical centering
                    HStack {
                        Spacer()
                        // AeroSpace mode badge — only shown when in a non-default mode
                        if config.activeWindowManagerName == "AeroSpace" && config.aeroSpaceCurrentMode != "main" {
                            AeroSpaceModeBadge(mode: config.aeroSpaceCurrentMode)
                                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        }
                        if config.showSystemStatus {
                            SystemStatusView()
                                .padding(.trailing, config.menuBarEdgePadding)
                        }
                    }
                    .animation(.easeInOut(duration: 0.15), value: config.aeroSpaceCurrentMode)
                    .frame(height: config.menuBarHeight, alignment: .center)

                    // Buttons on top layer to ensure they're interactive
                    // Using pure AppKit buttons to bypass SwiftUI during scroll for minimal CPU
                    HStack(spacing: 6) {
                        if config.showContextButton {
                            AppKitLayoutActionsButtonWrapper(
                                viewModel: viewModel,
                                isExpanded: $isContextButtonExpanded,
                                onRotate: onRotateLayout,
                                onFlip: onFlipLayout,
                                onBalance: onBalanceLayout,
                                onToggleLayout: onToggleLayout,
                                onStackAllWindows: onStackAllWindows,
                                onSpaceCreate: onSpaceCreate,
                                onSpaceDestroy: onSpaceDestroy
                            )
                            // Animate frame width when context button expands/collapses
                            .frame(
                                width: isContextButtonExpanded
                                    ? AppKitLayoutActionsButton.expandedWidth
                                    : AppKitLayoutActionsButton.collapsedWidth,
                                height: 26
                            )
                        }

                        if config.showAppLauncher {
                            AppKitAppLauncherButtonWrapper(apps: FloatingApp.appsFromConfig(), onToggleApp: onToggleApp, isAppFocused: launcherAppFocused)
                                .frame(width: 32, height: 26)
                        }

                        Spacer()
                    }
                    .padding(.leading, config.menuBarEdgePadding)
                    .frame(height: config.menuBarHeight, alignment: .center)
                    .animation(.easeOut(duration: 0.2), value: isContextButtonExpanded)
                }
            }
            .frame(height: config.menuBarHeight)
        }
        .frame(height: config.menuBarHeight)
        .onReceive(sharedState.launcherAppFocusedSubject.removeDuplicates()) { focused in
            launcherAppFocused = focused
        }
    }
}

// MARK: - Preference Key for Scroll Offset

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ButtonFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

// MARK: - Visual Effect Wrapper

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active

        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Gradient Blur View

/// A blur view with a gradient mask that fades from full blur at top to transparent at bottom
struct GradientBlurView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSView {
        let containerView = NSView()
        containerView.wantsLayer = true

        // Create visual effect view for blur
        let blurView = NSVisualEffectView()
        blurView.material = material
        blurView.blendingMode = blendingMode
        blurView.state = .active
        blurView.wantsLayer = true
        blurView.autoresizingMask = [.width, .height]
        containerView.addSubview(blurView)

        // Create gradient mask - fades from opaque at top to transparent at bottom
        // More gradual fade to keep blur visible longer
        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = [
            NSColor.white.cgColor,                         // Full opacity at top
            NSColor.white.cgColor,                         // Maintain full opacity
            NSColor.white.withAlphaComponent(0.8).cgColor,
            NSColor.white.withAlphaComponent(0.4).cgColor,
            NSColor.clear.cgColor                          // Transparent at bottom
        ]
        gradientLayer.locations = [0.0, 0.5, 0.7, 0.85, 1.0]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 1.0)  // Top (layer coords: y=1 is top)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 0.0)    // Bottom

        blurView.layer?.mask = gradientLayer

        // Store gradient layer for updates
        context.coordinator.gradientLayer = gradientLayer
        context.coordinator.blurView = blurView

        return containerView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Update gradient frame when view size changes
        context.coordinator.gradientLayer?.frame = nsView.bounds
        context.coordinator.blurView?.frame = nsView.bounds
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var gradientLayer: CAGradientLayer?
        var blurView: NSVisualEffectView?
    }
}

// MARK: - New Space Button

struct NewSpaceButton: View {
    let onSpaceCreate: () -> Void
    @State private var isHovered = false
    private let config = AegisConfig.shared

    var body: some View {
        Button {
            onSpaceCreate()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ThemeColors.foreground.opacity(isHovered ? 1.0 : 0.6))
                    .frame(width: 16, height: 16)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(ThemeColors.background.opacity(isHovered ? config.hoveredSpaceBgOpacity : config.inactiveSpaceBgOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(ThemeColors.border(opacity: config.activeBorderOpacity), lineWidth: 1)
                    .opacity(isHovered ? 1.0 : 0.0)
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - App Launcher Button

struct AppLauncherButton: View {
    let onToggleApp: (FloatingApp) -> Void
    let apps: [FloatingApp]

    private let config = AegisConfig.shared
    @State private var isHovered = false
    @State private var selectedAppIndex: Int = 0

    private var selectedApp: FloatingApp {
        apps[selectedAppIndex]
    }

    var body: some View {
        Image(nsImage: selectedApp.icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 18, height: 18)
            .opacity(isHovered ? 1.0 : 0.7)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(ThemeColors.background.opacity(isHovered ? config.hoveredSpaceBgOpacity : config.inactiveSpaceBgOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(ThemeColors.border(opacity: config.activeBorderOpacity), lineWidth: 1)
                    .opacity(isHovered ? 1.0 : 0.0)
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.1), value: isHovered)
            .overlay(
                AppLauncherScrollSelector(
                    selectedIndex: $selectedAppIndex,
                    appCount: apps.count,
                    onTap: {
                        onToggleApp(selectedApp)
                    }
                )
                .allowsHitTesting(true)
            )
            .onHover { isHovered = $0 }
            .help("Toggle \(selectedApp.name) (scroll to change)")
    }
}

// MARK: - App Launcher Scroll Selector

struct AppLauncherScrollSelector: NSViewRepresentable {
    @Binding var selectedIndex: Int
    let appCount: Int
    let onTap: () -> Void

    func makeNSView(context: Context) -> AppLauncherScrollView {
        let view = AppLauncherScrollView()
        view.onScrollChange = { delta in
            context.coordinator.handleScroll(delta: delta)
        }
        view.onTap = onTap
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }

    func updateNSView(_ nsView: AppLauncherScrollView, context: Context) {
        context.coordinator.selectedIndex = $selectedIndex
        context.coordinator.appCount = appCount
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedIndex: $selectedIndex, appCount: appCount)
    }

    class Coordinator {
        var selectedIndex: Binding<Int>
        var appCount: Int
        var scrollAccumulator: CGFloat = 0

        // Debounce: batch rapid scroll events
        var pendingIndex: Int?
        var updateWorkItem: DispatchWorkItem?

        // Higher threshold = less sensitive, fewer SwiftUI updates
        let scrollThreshold: CGFloat = 8  // Increased from 5

        private let config = AegisConfig.shared

        init(selectedIndex: Binding<Int>, appCount: Int) {
            self.selectedIndex = selectedIndex
            self.appCount = appCount
            self.pendingIndex = selectedIndex.wrappedValue
        }

        func handleScroll(delta: CGFloat) {
            scrollAccumulator += delta

            let actionSteps = Int(scrollAccumulator / scrollThreshold)

            if actionSteps != 0 {
                let currentIndex = pendingIndex ?? selectedIndex.wrappedValue
                var newIndex = currentIndex + actionSteps

                // Wrap around
                if newIndex < 0 {
                    newIndex = appCount + (newIndex % appCount)
                } else if newIndex >= appCount {
                    newIndex = newIndex % appCount
                }

                if newIndex != pendingIndex {
                    pendingIndex = newIndex

                    // Debounce: cancel previous, schedule batched update
                    updateWorkItem?.cancel()
                    let workItem = DispatchWorkItem { [weak self] in
                        guard let self = self, let index = self.pendingIndex else { return }
                        if index != self.selectedIndex.wrappedValue {
                            self.selectedIndex.wrappedValue = index
                            if self.config.enableLayoutActionHaptics {
                                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                            }
                        }
                    }
                    updateWorkItem = workItem
                    // 33ms debounce (30fps max) batches rapid scroll events
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.033, execute: workItem)
                }

                scrollAccumulator = 0
            }
        }
    }
}

class AppLauncherScrollView: NSView {
    var onScrollChange: ((CGFloat) -> Void)?
    var onTap: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for trackingArea in trackingAreas {
            removeTrackingArea(trackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    override func scrollWheel(with event: NSEvent) {
        // Ignore momentum phase for notched feeling - only respond to actual gestures
        guard event.phase == .began || event.phase == .changed || event.phase == [] else {
            return
        }

        let delta = event.deltaY
        // Higher threshold reduces callback frequency - filters tiny scroll movements
        if abs(delta) > 0.5 {
            onScrollChange?(delta)
        }
    }

    override func mouseDown(with event: NSEvent) {
        onTap?()
    }
}

// MARK: - Action Icon View (extracted for performance)
// Separate struct to minimize re-renders when only icon changes
private struct ActionIconView: View {
    let icon: String
    let isHovered: Bool

    var body: some View {
        Text(icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(ThemeColors.foreground.opacity(isHovered ? 1.0 : 0.6))
            .frame(width: 16, height: 16)
    }
}

// MARK: - Layout Actions Button

struct LayoutActionsButton: View {
    @ObservedObject var viewModel: MenuBarViewModel
    let onRotate: (Int) -> Void
    let onFlip: (String) -> Void
    let onBalance: () -> Void
    let onToggleLayout: () -> Void
    let onStackAllWindows: () -> Void
    let onSpaceCreate: () -> Void
    let onSpaceDestroy: (Int) -> Void
    @Binding var labelShowing: Bool

    @State private var isHovered = false
    @State private var selectedActionIndex: Int = 0
    @State private var showActionLabel = false
    @State private var buttonFrame: CGRect = .zero

    private let config = AegisConfig.shared

    // Define available actions — filtered by window manager capabilities
    typealias ActionTuple = (label: String, icon: String, execute: (LayoutActionsButton) -> Void)

    var actions: [ActionTuple] {
        var result: [ActionTuple] = []
        if viewModel.windowManager.name == "Yabai" {
            result.append(contentsOf: [
                ("Rotate 90°", "↻", { (b: LayoutActionsButton) in b.onRotate(90) }),
                ("Rotate 180°", "↻↻", { (b: LayoutActionsButton) in b.onRotate(180) }),
                ("Rotate 270°", "↺", { (b: LayoutActionsButton) in b.onRotate(270) }),
                ("Flip Horizontal", "↔", { (b: LayoutActionsButton) in b.onFlip("x") }),
                ("Flip Vertical", "↕", { (b: LayoutActionsButton) in b.onFlip("y") }),
                ("Balance", "⚖", { (b: LayoutActionsButton) in b.onBalance() }),
            ] as [ActionTuple])
        } else if viewModel.windowManager.name == "AeroSpace" {
            result.append(("Balance", "⚖", { (b: LayoutActionsButton) in b.onBalance() }))
        }
        result.append(("Toggle Layout", "⇄", { (b: LayoutActionsButton) in b.onToggleLayout() }))
        if viewModel.windowManager.capabilities.contains(.stackWindows) {
            result.append(("Stack/Unstack", "⧉", { (b: LayoutActionsButton) in b.onStackAllWindows() }))
        }
        result.append(("New Space", "+", { (b: LayoutActionsButton) in b.onSpaceCreate() }))
        return result
    }

    // Computed properties to avoid array access in body
    private var currentIcon: String { actions[selectedActionIndex].icon }
    private var currentLabel: String { actions[selectedActionIndex].label }

    var body: some View {
        // Main button - label expands to the right
        HStack(spacing: 0) {
            // Icon view - only updates when selectedActionIndex changes
            ActionIconView(icon: currentIcon, isHovered: isHovered)

            if showActionLabel {
                Text(currentLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(ThemeColors.secondaryText())
                    .frame(width: 95, alignment: .leading)
                    .padding(.leading, 6)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            // Simplified background - no conditional blur that forces re-render
            RoundedRectangle(cornerRadius: 8)
                .fill(ThemeColors.background.opacity(showActionLabel ? config.activeSpaceBgOpacity : (isHovered ? config.hoveredSpaceBgOpacity : config.inactiveSpaceBgOpacity)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(ThemeColors.border(opacity: 0.18), lineWidth: 1)
                .opacity((isHovered || showActionLabel) ? 1.0 : 0.0)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        // Consolidated animation - simpler easeOut for both hover and label expansion
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .animation(.easeOut(duration: 0.2), value: showActionLabel)
        // GeometryReader only runs once on appear, not on every update
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        self.buttonFrame = geo.frame(in: .global)
                    }
            }
        )
        .overlay(
            // Scroll detector overlay on top to capture events
            ScrollableActionSelector(
                selectedIndex: $selectedActionIndex,
                actionCount: actions.count,
                showLabel: $showActionLabel,
                onTap: {
                    executeSelectedAction()
                },
                onRightClick: {
                    showContextMenu()
                }
            )
            .allowsHitTesting(true)
        )
        .onHover { isHovered = $0 }
        .onChange(of: showActionLabel) { newValue in
            labelShowing = newValue
        }
    }

    private func executeSelectedAction() {
        actions[selectedActionIndex].execute(self)
    }

    private func showContextMenu() {

        let menu = NSMenu()
        menu.autoenablesItems = false

        let windowManager = viewModel.windowManager
        // Get all spaces from cache
        let spaces = windowManager.getCurrentSpaces()

        // Query WM directly for accurate focused space
        let focusedSpaceIndex = windowManager.getFocusedSpaceIndex()
        let focusedSpace = spaces.first(where: { $0.index == focusedSpaceIndex })

        // Get window count for current space
        let windowCount = focusedSpace.map { windowManager.getAppIconsForSpace($0.index).count } ?? 0

        // Create a menu target with captured callbacks
        let menuTarget = LayoutActionsMenuTarget(
            windowManager: windowManager,
            onRotate: onRotate,
            onFlip: onFlip,
            onBalance: onBalance,
            onToggleLayout: onToggleLayout,
            onStackAllWindows: onStackAllWindows,
            onSpaceCreate: onSpaceCreate,
            onSpaceDestroy: onSpaceDestroy
        )

        // MARK: - Layout Actions Section
        let currentLayoutType = focusedSpace?.layoutType.rawValue ?? "bsp"

        for action in actions {
            // Skip "Toggle Layout" - we'll add a submenu instead
            if action.label == "Toggle Layout" {
                continue
            }

            let menuItem = NSMenuItem(title: "\(action.icon)  \(action.label)", action: #selector(LayoutActionsMenuTarget.executeActionByLabel(_:)), keyEquivalent: "")
            menuItem.target = menuTarget
            menuItem.representedObject = action.label

            // Disable Stack/Unstack if only 0-1 windows
            if action.label == "Stack/Unstack" {
                menuItem.isEnabled = windowCount > 1
            } else {
                menuItem.isEnabled = true
            }

            menu.addItem(menuItem)
        }

        // MARK: - Layout Type Submenu (replaces Toggle Layout)
        let layoutItem = NSMenuItem(title: "⇄  Layout", action: nil, keyEquivalent: "")
        let layoutSubmenu = NSMenu()
        layoutSubmenu.autoenablesItems = false

        let layoutTypes: [(String, String, String)]
        if windowManager.name == "Rift" {
            layoutTypes = [
                ("Traditional", "traditional", "Standard macOS window management"),
                ("BSP", "bsp", "Binary space partitioning - tiles windows automatically"),
                ("Stack", "stack", "All windows stacked on top of each other"),
                ("Master-Stack", "master_stack", "One master window with stack on the side"),
                ("Scrolling", "scrolling", "Horizontally scrolling strip of windows")
            ]
        } else if windowManager.name == "AeroSpace" {
            layoutTypes = [
                ("Tiling", "tiling", "Tile windows using h/v splits"),
                ("Accordion", "accordion", "Stack windows in accordion layout"),
                ("Floating", "floating", "Floating windows - manual positioning")
            ]
        } else {
            layoutTypes = [
                ("BSP", "bsp", "Binary space partitioning - tiles windows automatically"),
                ("Float", "float", "Floating windows - manual positioning"),
                ("Stack", "stack", "All windows stacked on top of each other")
            ]
        }

        for (label, value, _) in layoutTypes {
            let item = NSMenuItem(title: label, action: #selector(LayoutActionsMenuTarget.setLayout(_:)), keyEquivalent: "")
            item.target = menuTarget
            item.representedObject = value
            item.state = currentLayoutType == value ? .on : .off
            layoutSubmenu.addItem(item)
        }

        layoutItem.submenu = layoutSubmenu
        menu.addItem(layoutItem)

        // Keep the target alive for the menu's lifetime
        objc_setAssociatedObject(menu, "menuTarget", menuTarget, .OBJC_ASSOCIATION_RETAIN)

        menu.addItem(NSMenuItem.separator())

        // MARK: - Window Navigation Section
        menu.addItem(NSMenuItem(title: "Focus Next", action: #selector(LayoutActionsMenuTarget.focusNext), keyEquivalent: ""))
        menu.items.last?.target = menuTarget
        menu.items.last?.isEnabled = windowCount > 1

        menu.addItem(NSMenuItem(title: "Focus Previous", action: #selector(LayoutActionsMenuTarget.focusPrevious), keyEquivalent: ""))
        menu.items.last?.target = menuTarget
        menu.items.last?.isEnabled = windowCount > 1

        if windowManager.name == "AeroSpace" {
            menu.addItem(NSMenuItem(title: "Focus Monitor Next", action: #selector(LayoutActionsMenuTarget.focusMonitorNext), keyEquivalent: ""))
            menu.items.last?.target = menuTarget

            menu.addItem(NSMenuItem(title: "Focus Monitor Prev", action: #selector(LayoutActionsMenuTarget.focusMonitorPrev), keyEquivalent: ""))
            menu.items.last?.target = menuTarget
        }

        menu.addItem(NSMenuItem(title: "Swap Left", action: #selector(LayoutActionsMenuTarget.swapLeft), keyEquivalent: ""))
        menu.items.last?.target = menuTarget
        menu.items.last?.isEnabled = windowCount > 1

        menu.addItem(NSMenuItem(title: "Swap Right", action: #selector(LayoutActionsMenuTarget.swapRight), keyEquivalent: ""))
        menu.items.last?.target = menuTarget
        menu.items.last?.isEnabled = windowCount > 1

        menu.addItem(NSMenuItem(title: "Toggle Float", action: #selector(LayoutActionsMenuTarget.toggleFloat), keyEquivalent: ""))
        menu.items.last?.target = menuTarget
        menu.items.last?.isEnabled = windowCount > 0

        menu.addItem(NSMenuItem(title: "Toggle Fullscreen", action: #selector(LayoutActionsMenuTarget.toggleFullscreen), keyEquivalent: ""))
        menu.items.last?.target = menuTarget
        menu.items.last?.isEnabled = windowCount > 0

        if windowManager.name == "AeroSpace" {
            menu.addItem(NSMenuItem(title: "Native Fullscreen", action: #selector(LayoutActionsMenuTarget.macosNativeFullscreen), keyEquivalent: ""))
            menu.items.last?.target = menuTarget
            menu.items.last?.isEnabled = windowCount > 0

            menu.addItem(NSMenuItem(title: "Minimize", action: #selector(LayoutActionsMenuTarget.minimizeWindow), keyEquivalent: ""))
            menu.items.last?.target = menuTarget
            menu.items.last?.isEnabled = windowCount > 0

            menu.addItem(NSMenuItem(title: "Close Window", action: #selector(LayoutActionsMenuTarget.closeWindow), keyEquivalent: ""))
            menu.items.last?.target = menuTarget
            menu.items.last?.isEnabled = windowCount > 0

            menu.addItem(NSMenuItem(title: "Close All But Current", action: #selector(LayoutActionsMenuTarget.closeAllButCurrent), keyEquivalent: ""))
            menu.items.last?.target = menuTarget
            menu.items.last?.isEnabled = windowCount > 0

            menu.addItem(NSMenuItem(title: "Toggle Orientation", action: #selector(LayoutActionsMenuTarget.toggleOrientation), keyEquivalent: ""))
            menu.items.last?.target = menuTarget
            menu.items.last?.isEnabled = windowCount > 0

            menu.addItem(NSMenuItem(title: "Last Workspace", action: #selector(LayoutActionsMenuTarget.workspaceBackAndForth), keyEquivalent: ""))
            menu.items.last?.target = menuTarget
        }

        menu.addItem(NSMenuItem.separator())

        // MARK: - Move Window Submenu
        let moveWindowItem = NSMenuItem(title: "Move Window", action: nil, keyEquivalent: "")
        let moveSubmenu = NSMenu()
        moveSubmenu.autoenablesItems = false

        moveSubmenu.addItem(NSMenuItem(title: "North", action: #selector(LayoutActionsMenuTarget.moveNorth), keyEquivalent: ""))
        moveSubmenu.items.last?.target = menuTarget
        moveSubmenu.items.last?.isEnabled = windowCount > 0

        moveSubmenu.addItem(NSMenuItem(title: "South", action: #selector(LayoutActionsMenuTarget.moveSouth), keyEquivalent: ""))
        moveSubmenu.items.last?.target = menuTarget
        moveSubmenu.items.last?.isEnabled = windowCount > 0

        moveSubmenu.addItem(NSMenuItem(title: "East", action: #selector(LayoutActionsMenuTarget.moveEast), keyEquivalent: ""))
        moveSubmenu.items.last?.target = menuTarget
        moveSubmenu.items.last?.isEnabled = windowCount > 0

        moveSubmenu.addItem(NSMenuItem(title: "West", action: #selector(LayoutActionsMenuTarget.moveWest), keyEquivalent: ""))
        moveSubmenu.items.last?.target = menuTarget
        moveSubmenu.items.last?.isEnabled = windowCount > 0

        if windowManager.name == "AeroSpace" {
            moveSubmenu.addItem(NSMenuItem.separator())

            // Join With submenu
            let joinItem = NSMenuItem(title: "Join With", action: nil, keyEquivalent: "")
            let joinSubmenu = NSMenu()
            joinSubmenu.autoenablesItems = false
            for (label, dir) in [("Left", "left"), ("Down", "down"), ("Up", "up"), ("Right", "right")] {
                let item = NSMenuItem(title: label, action: #selector(LayoutActionsMenuTarget.joinWith(_:)), keyEquivalent: "")
                item.target = menuTarget
                item.representedObject = dir
                item.isEnabled = windowCount > 1
                joinSubmenu.addItem(item)
            }
            joinItem.submenu = joinSubmenu
            moveSubmenu.addItem(joinItem)

            moveSubmenu.addItem(NSMenuItem.separator())

            // Resize
            let resizeItem = NSMenuItem(title: "Resize", action: nil, keyEquivalent: "")
            let resizeSubmenu = NSMenu()
            resizeSubmenu.autoenablesItems = false
            for (label, amount) in [("Grow", "+50"), ("Shrink", "-50")] {
                let item = NSMenuItem(title: label, action: #selector(LayoutActionsMenuTarget.resizeSmart(_:)), keyEquivalent: "")
                item.target = menuTarget
                item.representedObject = amount
                item.isEnabled = windowCount > 0
                resizeSubmenu.addItem(item)
            }
            resizeItem.submenu = resizeSubmenu
            moveSubmenu.addItem(resizeItem)

            moveSubmenu.addItem(NSMenuItem.separator())

            // Monitor actions
            moveSubmenu.addItem(NSMenuItem(title: "To Monitor Next", action: #selector(LayoutActionsMenuTarget.moveToMonitorNext), keyEquivalent: ""))
            moveSubmenu.items.last?.target = menuTarget
            moveSubmenu.items.last?.isEnabled = windowCount > 0

            moveSubmenu.addItem(NSMenuItem(title: "To Monitor Prev", action: #selector(LayoutActionsMenuTarget.moveToMonitorPrev), keyEquivalent: ""))
            moveSubmenu.items.last?.target = menuTarget
            moveSubmenu.items.last?.isEnabled = windowCount > 0
        }

        moveWindowItem.submenu = moveSubmenu
        menu.addItem(moveWindowItem)

        // MARK: - Send to Space Submenu
        let sendToSpaceItem = NSMenuItem(title: "Send to Space", action: nil, keyEquivalent: "")
        let spaceSubmenu = NSMenu()
        spaceSubmenu.autoenablesItems = false

        if windowManager.name == "AeroSpace" {
            // AeroSpace: show all workspaces 1-9, use workspace name as identifier
            let focusedLabel = spaces.first(where: { $0.index == focusedSpaceIndex })?.label
            for i in 1...9 {
                let wsName = "\(i)"
                let spaceItem = NSMenuItem(title: "Space \(wsName)", action: #selector(LayoutActionsMenuTarget.sendToSpace(_:)), keyEquivalent: "")
                spaceItem.target = menuTarget
                spaceItem.representedObject = wsName  // Pass workspace name string
                spaceItem.isEnabled = windowCount > 0
                if wsName == focusedLabel {
                    spaceItem.attributedTitle = NSAttributedString(
                        string: "Space \(wsName) (current)",
                        attributes: [.foregroundColor: NSColor.gray]
                    )
                }
                spaceSubmenu.addItem(spaceItem)
            }
        } else {
            // Yabai/Rift: show existing spaces with indices
            for space in spaces {
                let spaceLabel = space.label ?? "\(space.index)"
                let spaceItem = NSMenuItem(title: "Space \(spaceLabel)", action: #selector(LayoutActionsMenuTarget.sendToSpace(_:)), keyEquivalent: "")
                spaceItem.target = menuTarget
                spaceItem.representedObject = space.index
                spaceItem.isEnabled = windowCount > 0
                if space.index == focusedSpaceIndex {
                    spaceItem.attributedTitle = NSAttributedString(
                        string: "Space \(spaceLabel) (current)",
                        attributes: [.foregroundColor: NSColor.gray]
                    )
                }
                spaceSubmenu.addItem(spaceItem)
            }
        }

        sendToSpaceItem.submenu = spaceSubmenu
        menu.addItem(sendToSpaceItem)

        // MARK: - Stack Windows Submenu (only for WMs with stack capability)
      if windowManager.capabilities.contains(.stackWindows) {
        let stackWindowsItem = NSMenuItem(title: "Stack Windows", action: nil, keyEquivalent: "")
        let stackSubmenu = NSMenu()
        stackSubmenu.autoenablesItems = false

        // Query WM fresh for accurate stack-index values
        let freshWindows = windowManager.getWindowsForSpace(focusedSpaceIndex)
        logDebug("📋 Stack menu: focusedSpace=\(focusedSpaceIndex), freshWindows=\(freshWindows.count)")

        if freshWindows.count >= 2 {
            // Pre-scale icons once
            let iconSize = NSSize(width: 16, height: 16)
            var scaledIcons: [Int: NSImage] = [:]
            for window in freshWindows {
                if let icon = windowManager.getAppIcon(for: window.app) {
                    let scaled = NSImage(size: iconSize)
                    scaled.lockFocus()
                    icon.draw(in: NSRect(origin: .zero, size: iconSize))
                    scaled.unlockFocus()
                    scaledIcons[window.id] = scaled
                }
            }

            // Group windows by stack using exact frame match
            // Stacked windows in yabai share the identical frame (x, y, w, h)
            var stackGroups: [[WMWindow]] = []
            var unstackedWindows: [WMWindow] = []

            let stacked = freshWindows.filter { $0.stackIndex > 0 }
            let notStacked = freshWindows.filter { $0.stackIndex == 0 }

            // Group stacked windows by their exact frame (rounded to avoid float precision issues)
            let frameKey: (WMWindow) -> String = { w in
                guard let f = w.frame else { return "nil-\(w.id)" }
                return "\(Int(f.origin.x)),\(Int(f.origin.y)),\(Int(f.width)),\(Int(f.height))"
            }
            var frameGroups: [String: [WMWindow]] = [:]
            for window in stacked {
                let key = frameKey(window)
                frameGroups[key, default: []].append(window)
            }
            stackGroups = frameGroups.values.map { $0.sorted { $0.stackIndex < $1.stackIndex } }

            unstackedWindows = notStacked
            logDebug("📋 Stack grouping: \(stackGroups.count) stacks, \(unstackedWindows.count) unstacked (stacked windows: \(stacked.count))")

            // Helper to get display title for a window
            func windowTitle(_ w: WMWindow) -> String {
                w.title.isEmpty ? w.app : String(w.title.prefix(30))
            }

            // -- Show stack groups --
            for (groupIndex, group) in stackGroups.enumerated() {
                let stackItem = NSMenuItem(title: "Stack \(groupIndex + 1)", action: nil, keyEquivalent: "")
                let stackGroupMenu = NSMenu()
                stackGroupMenu.autoenablesItems = false

                for (windowIndex, window) in group.enumerated() {
                    let label = windowIndex == 0
                        ? "\(windowTitle(window)) (base)"
                        : windowTitle(window)
                    let item = NSMenuItem(title: label, action: nil, keyEquivalent: "")
                    item.image = scaledIcons[window.id]
                    item.isEnabled = false
                    stackGroupMenu.addItem(item)
                }

                stackGroupMenu.addItem(NSMenuItem.separator())

                let unstackItem = NSMenuItem(
                    title: "Unstack This Stack",
                    action: #selector(LayoutActionsMenuTarget.unstackStack(_:)),
                    keyEquivalent: ""
                )
                unstackItem.target = menuTarget
                unstackItem.representedObject = group.map { $0.id }
                stackGroupMenu.addItem(unstackItem)

                stackItem.submenu = stackGroupMenu
                stackSubmenu.addItem(stackItem)
            }

            // -- Separator between stacks and unstacked --
            if !stackGroups.isEmpty && !unstackedWindows.isEmpty {
                stackSubmenu.addItem(NSMenuItem.separator())
            }

            // -- Show unstacked windows with stack-to options --
            for window in unstackedWindows {
                let windowItem = NSMenuItem(title: windowTitle(window), action: nil, keyEquivalent: "")
                windowItem.image = scaledIcons[window.id]

                let windowSubmenu = NSMenu()
                windowSubmenu.autoenablesItems = false

                // "Stack onto Stack N" options
                for (groupIndex, group) in stackGroups.enumerated() {
                    guard let baseWindow = group.first else { continue }
                    let item = NSMenuItem(
                        title: "Stack onto Stack \(groupIndex + 1)",
                        action: #selector(LayoutActionsMenuTarget.stackWindowOnto(_:)),
                        keyEquivalent: ""
                    )
                    item.target = menuTarget
                    item.representedObject = ["source": window.id, "target": baseWindow.id]
                    windowSubmenu.addItem(item)
                }

                if !stackGroups.isEmpty && unstackedWindows.count > 1 {
                    windowSubmenu.addItem(NSMenuItem.separator())
                }

                // "Stack with [other unstacked window]" options
                for otherWindow in unstackedWindows where otherWindow.id != window.id {
                    let item = NSMenuItem(
                        title: "Stack with \(windowTitle(otherWindow))",
                        action: #selector(LayoutActionsMenuTarget.stackWindowOnto(_:)),
                        keyEquivalent: ""
                    )
                    item.target = menuTarget
                    item.image = scaledIcons[otherWindow.id]
                    item.representedObject = ["source": window.id, "target": otherWindow.id]
                    windowSubmenu.addItem(item)
                }

                windowItem.submenu = windowSubmenu
                stackSubmenu.addItem(windowItem)
            }

            // -- Stack All option --
            if freshWindows.count > 2 {
                stackSubmenu.addItem(NSMenuItem.separator())
                let stackAllItem = NSMenuItem(
                    title: "Stack All Windows",
                    action: #selector(LayoutActionsMenuTarget.stackAllOnto(_:)),
                    keyEquivalent: ""
                )
                stackAllItem.target = menuTarget
                stackAllItem.representedObject = freshWindows.first!.id
                stackSubmenu.addItem(stackAllItem)
            }
        } else {
            let noWindowsItem = NSMenuItem(title: "Need 2+ windows to stack", action: nil, keyEquivalent: "")
            noWindowsItem.isEnabled = false
            stackSubmenu.addItem(noWindowsItem)
        }

        stackWindowsItem.submenu = stackSubmenu
        menu.addItem(stackWindowsItem)
      }

        menu.addItem(NSMenuItem.separator())

        // MARK: - Space Management Section (Yabai only — Rift/AeroSpace use fixed/virtual workspaces)
        if windowManager.name == "Yabai" {
            menu.addItem(NSMenuItem(title: "Destroy Space", action: #selector(LayoutActionsMenuTarget.destroyCurrentSpace(_:)), keyEquivalent: ""))
            menu.items.last?.target = menuTarget
            menu.items.last?.representedObject = focusedSpaceIndex
            menu.items.last?.isEnabled = spaces.count > 1
        }

        menu.addItem(NSMenuItem.separator())

        // MARK: - Status Section
        let statusItem = NSMenuItem(title: "Status", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        // WM Version
        let wmVersion = windowManager.getVersion()
        let wmVersionItem = NSMenuItem(title: "  \(windowManager.name): v\(wmVersion)", action: nil, keyEquivalent: "")
        wmVersionItem.isEnabled = false
        menu.addItem(wmVersionItem)

        // Yabai-specific: SA status
        if windowManager.name == "Yabai" {
            let saStatus = YabaiSetupChecker.checkSA()
            let saStatusItem: NSMenuItem
            switch saStatus {
            case .loaded:
                saStatusItem = NSMenuItem(title: "  SA: Loaded", action: nil, keyEquivalent: "")
                saStatusItem.isEnabled = false
            case .notLoaded:
                saStatusItem = NSMenuItem(title: "  SA: Not loaded (click to copy cmd)", action: #selector(LayoutActionsMenuTarget.loadSA), keyEquivalent: "")
                saStatusItem.target = menuTarget
                saStatusItem.isEnabled = true
            case .notInstalled:
                saStatusItem = NSMenuItem(title: "  SA: Not installed", action: nil, keyEquivalent: "")
                saStatusItem.isEnabled = false
            case .unknown:
                saStatusItem = NSMenuItem(title: "  SA: Unknown", action: nil, keyEquivalent: "")
                saStatusItem.isEnabled = false
            }
            menu.addItem(saStatusItem)
        }

        // Aegis Version
        let aegisVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let aegisVersionItem = NSMenuItem(title: "  Aegis: v\(aegisVersion)", action: nil, keyEquivalent: "")
        aegisVersionItem.isEnabled = false
        menu.addItem(aegisVersionItem)

        // Yabai-specific: Link status
        if windowManager.name == "Yabai" {
            let linkStatus = YabaiSetupChecker.check()
            let linkStatusText: String
            switch linkStatus {
            case .ready:
                linkStatusText = "Active"
            case .yabaiNotInstalled:
                linkStatusText = "Inactive (Yabai not installed)"
            case .signalsNotConfigured:
                linkStatusText = "Not configured"
            case .notifyScriptMissing:
                linkStatusText = "Script missing"
            }
            let linkStatusItem = NSMenuItem(title: "  Link: \(linkStatusText)", action: nil, keyEquivalent: "")
            linkStatusItem.isEnabled = false
            menu.addItem(linkStatusItem)
        }

        menu.addItem(NSMenuItem.separator())

        // MARK: - Display Options
        let showMediaHUDItem = NSMenuItem(
            title: "Show Now Playing",
            action: #selector(LayoutActionsMenuTarget.toggleShowMediaHUD(_:)),
            keyEquivalent: ""
        )
        showMediaHUDItem.target = menuTarget
        showMediaHUDItem.state = AegisConfig.shared.showMediaHUD ? .on : .off
        menu.addItem(showMediaHUDItem)

        // Now Playing right panel mode submenu
        let rightPanelItem = NSMenuItem(title: "Now Playing Display", action: nil, keyEquivalent: "")
        let rightPanelSubmenu = NSMenu()
        rightPanelSubmenu.autoenablesItems = false

        let visualizerItem = NSMenuItem(
            title: "Visualizer",
            action: #selector(LayoutActionsMenuTarget.setRightPanelModeVisualizer(_:)),
            keyEquivalent: ""
        )
        visualizerItem.target = menuTarget
        visualizerItem.state = AegisConfig.shared.mediaHUDRightPanelMode == .visualizer ? .on : .off
        rightPanelSubmenu.addItem(visualizerItem)

        let trackInfoItem = NSMenuItem(
            title: "Track Info",
            action: #selector(LayoutActionsMenuTarget.setRightPanelModeTrackInfo(_:)),
            keyEquivalent: ""
        )
        trackInfoItem.target = menuTarget
        trackInfoItem.state = AegisConfig.shared.mediaHUDRightPanelMode == .trackInfo ? .on : .off
        rightPanelSubmenu.addItem(trackInfoItem)

        rightPanelItem.submenu = rightPanelSubmenu
        menu.addItem(rightPanelItem)

        menu.addItem(NSMenuItem.separator())

        // MARK: - Settings Section
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(LayoutActionsMenuTarget.openSettings), keyEquivalent: ""))
        menu.items.last?.target = menuTarget
        menu.items.last?.isEnabled = true

        menu.addItem(NSMenuItem.separator())

        // MARK: - System Actions Section
        menu.addItem(NSMenuItem(title: "Reload Config", action: #selector(LayoutActionsMenuTarget.reloadConfig), keyEquivalent: ""))
        menu.items.last?.target = menuTarget
        menu.items.last?.isEnabled = true

        if windowManager.name == "Yabai" {
            menu.addItem(NSMenuItem(title: "Reload yabai", action: #selector(LayoutActionsMenuTarget.restartYabai), keyEquivalent: ""))
            menu.items.last?.target = menuTarget
            menu.items.last?.isEnabled = true
        } else if windowManager.name == "Rift" {
            menu.addItem(NSMenuItem(title: "Restart Rift", action: #selector(LayoutActionsMenuTarget.restartRift), keyEquivalent: ""))
            menu.items.last?.target = menuTarget
            menu.items.last?.isEnabled = true
        } else if windowManager.name == "AeroSpace" {
            menu.addItem(NSMenuItem(title: "Reload AeroSpace", action: #selector(LayoutActionsMenuTarget.reloadAeroSpace), keyEquivalent: ""))
            menu.items.last?.target = menuTarget
            menu.items.last?.isEnabled = true
        }

        menu.addItem(NSMenuItem(title: "Restart Aegis", action: #selector(LayoutActionsMenuTarget.restartAegis), keyEquivalent: ""))
        menu.items.last?.target = menuTarget
        menu.items.last?.isEnabled = true

        if windowManager.name == "Yabai" {
            menu.addItem(NSMenuItem(title: "Restart skhd", action: #selector(LayoutActionsMenuTarget.restartSkhd), keyEquivalent: ""))
            menu.items.last?.target = menuTarget
            menu.items.last?.isEnabled = true
        }

        menu.addItem(NSMenuItem.separator())

        // MARK: - Quit
        menu.addItem(NSMenuItem(title: "Quit Aegis", action: #selector(LayoutActionsMenuTarget.quitAegis), keyEquivalent: "q"))
        menu.items.last?.target = menuTarget
        menu.items.last?.isEnabled = true

        // Show menu aligned with the button
        if let event = NSApp.currentEvent, let window = event.window {
            let locationInWindow = event.locationInWindow
            menu.popUp(positioning: nil, at: locationInWindow, in: window.contentView)
        } else if let window = NSApp.keyWindow, let contentView = window.contentView {
            // Fallback: use button frame if no event
            let windowPoint = NSPoint(x: buttonFrame.minX, y: window.frame.height - buttonFrame.minY)
            menu.popUp(positioning: nil, at: windowPoint, in: contentView)
        }

    }
}

// MARK: - Menu Handler

class LayoutActionsMenuTarget: NSObject {
    static let shared = LayoutActionsMenuTarget()

    private let windowManager: WindowManagerProtocol?
    private let onRotate: ((Int) -> Void)?
    private let onFlip: ((String) -> Void)?
    private let onBalance: (() -> Void)?
    private let onToggleLayout: (() -> Void)?
    private let onStackAllWindows: (() -> Void)?
    private let onSpaceCreate: (() -> Void)?
    private let onSpaceDestroy: ((Int) -> Void)?

    init(windowManager: WindowManagerProtocol? = nil,
         onRotate: ((Int) -> Void)? = nil,
         onFlip: ((String) -> Void)? = nil,
         onBalance: (() -> Void)? = nil,
         onToggleLayout: (() -> Void)? = nil,
         onStackAllWindows: (() -> Void)? = nil,
         onSpaceCreate: (() -> Void)? = nil,
         onSpaceDestroy: ((Int) -> Void)? = nil) {
        self.windowManager = windowManager
        self.onRotate = onRotate
        self.onFlip = onFlip
        self.onBalance = onBalance
        self.onToggleLayout = onToggleLayout
        self.onStackAllWindows = onStackAllWindows
        self.onSpaceCreate = onSpaceCreate
        self.onSpaceDestroy = onSpaceDestroy
        super.init()
    }

    @objc func executeAction(_ sender: NSMenuItem) {
        let index = sender.tag
        logDebug("📋 Menu action at index: \(index)")

        // Execute based on index (used by AppKitActionButton's hardcoded tag values)
        switch index {
        case 0: onRotate?(90)
        case 1: onRotate?(180)
        case 2: onRotate?(270)
        case 3: onFlip?("x")
        case 4: onFlip?("y")
        case 5: onBalance?()
        case 6: onToggleLayout?()
        case 7: onStackAllWindows?()
        case 8: onSpaceCreate?()
        default:
            logDebug("❌ Unknown action index: \(index)")
        }
    }

    @objc func executeActionByLabel(_ sender: NSMenuItem) {
        guard let label = sender.representedObject as? String else { return }
        logDebug("📋 Menu action: \(label)")

        switch label {
        case "Rotate 90°": onRotate?(90)
        case "Rotate 180°": onRotate?(180)
        case "Rotate 270°": onRotate?(270)
        case "Flip Horizontal": onFlip?("x")
        case "Flip Vertical": onFlip?("y")
        case "Balance": onBalance?()
        case "Toggle Layout": onToggleLayout?()
        case "Stack/Unstack": onStackAllWindows?()
        case "New Space": onSpaceCreate?()
        default:
            logDebug("❌ Unknown action: \(label)")
        }
    }

    @objc func openSettings() {
        logDebug("⚙️ Opening Settings Panel...")
        SettingsPanelController.shared.showSettings()
    }

    @objc func toggleShowMediaHUD(_ sender: NSMenuItem) {
        let config = AegisConfig.shared
        config.showMediaHUD.toggle()
        config.savePreferences()
        logDebug("🎵 Show Media HUD: \(config.showMediaHUD ? "ON" : "OFF")")
    }

    @objc func setRightPanelModeVisualizer(_ sender: NSMenuItem) {
        let config = AegisConfig.shared
        config.mediaHUDRightPanelMode = .visualizer
        config.savePreferences()
        logDebug("🎵 Media HUD Right Panel: Visualizer")
    }

    @objc func setRightPanelModeTrackInfo(_ sender: NSMenuItem) {
        let config = AegisConfig.shared
        config.mediaHUDRightPanelMode = .trackInfo
        config.savePreferences()
        logDebug("🎵 Media HUD Right Panel: Track Info")
    }

    @objc func reloadConfig() {
        AegisConfig.shared.reloadConfig()
    }

    @objc func restartYabai() {
        logDebug("🔄 Restarting yabai...")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/yabai")
        task.arguments = ["--restart-service"]
        do {
            try task.run()
            logDebug("✅ Yabai restart command sent")
        } catch {
            logDebug("❌ Failed to restart yabai: \(error)")
        }
    }

    @objc func restartRift() {
        logDebug("🔄 Restarting Rift...")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/rift-cli")
        task.arguments = ["service", "restart"]
        do {
            try task.run()
            logDebug("✅ Rift restart command sent")
        } catch {
            logDebug("❌ Failed to restart Rift: \(error)")
        }
    }

    @objc func reloadAeroSpace() {
        logDebug("🔄 Reloading AeroSpace config...")
        windowManager?.executeRawCommand(args: ["reload-config"]) { result in
            switch result {
            case .success: logDebug("✅ AeroSpace config reloaded")
            case .failure(let error): logDebug("❌ Failed to reload AeroSpace: \(error)")
            }
        }
    }

    @objc func restartAegis() {
        logDebug("🔄 Restarting Aegis...")
        // Use NSWorkspace to relaunch
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true

        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error = error {
                logDebug("❌ Failed to relaunch: \(error)")
            } else {
                NSApp.terminate(nil)
            }
        }
    }

    @objc func restartSkhd() {
        logDebug("🔄 Restarting skhd...")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/skhd")
        task.arguments = ["--restart-service"]
        do {
            try task.run()
            logDebug("✅ skhd restart command sent")
        } catch {
            logDebug("❌ Failed to restart skhd: \(error)")
        }
    }

    @objc func quitAegis() {
        logDebug("👋 Quitting Aegis...")
        NSApp.terminate(nil)
    }

    @objc func createNewSpace() {
        logDebug("➕ Creating new space...")
        onSpaceCreate?()
    }

    @objc func destroyCurrentSpace(_ sender: NSMenuItem) {
        guard let spaceIndex = sender.representedObject as? Int else { return }
        logDebug("🗑️ Destroying space \(spaceIndex)...")
        onSpaceDestroy?(spaceIndex)
    }

    // MARK: - Window Navigation Actions

    private var isRift: Bool { windowManager?.name == "Rift" }
    private var isAeroSpace: Bool { windowManager?.name == "AeroSpace" }

    @objc func focusNext() {
        logDebug("➡️ Focusing next window...")
        if isRift {
            windowManager?.executeRawCommand(args: ["execute", "window", "next"]) { _ in }
        } else if isAeroSpace {
            windowManager?.executeRawCommand(args: ["focus", "right"]) { _ in }
        } else {
            windowManager?.executeRawCommand(args: ["-m", "window", "--focus", "next"]) { _ in }
        }
    }

    @objc func focusPrevious() {
        logDebug("⬅️ Focusing previous window...")
        if isRift {
            windowManager?.executeRawCommand(args: ["execute", "window", "prev"]) { _ in }
        } else if isAeroSpace {
            windowManager?.executeRawCommand(args: ["focus", "left"]) { _ in }
        } else {
            windowManager?.executeRawCommand(args: ["-m", "window", "--focus", "prev"]) { _ in }
        }
    }

    @objc func swapLeft() {
        logDebug("⬅️ Swapping window left...")
        if isRift {
            windowManager?.executeRawCommand(args: ["execute", "layout", "move-node", "left"]) { _ in }
        } else if isAeroSpace {
            windowManager?.executeRawCommand(args: ["move", "left"]) { _ in }
        } else {
            windowManager?.executeRawCommand(args: ["-m", "window", "--swap", "west"]) { _ in }
        }
    }

    @objc func swapRight() {
        logDebug("➡️ Swapping window right...")
        if isRift {
            windowManager?.executeRawCommand(args: ["execute", "layout", "move-node", "right"]) { _ in }
        } else if isAeroSpace {
            windowManager?.executeRawCommand(args: ["move", "right"]) { _ in }
        } else {
            windowManager?.executeRawCommand(args: ["-m", "window", "--swap", "east"]) { _ in }
        }
    }

    @objc func toggleFloat() {
        logDebug("🎈 Toggling float...")
        if isRift {
            windowManager?.executeRawCommand(args: ["execute", "window", "toggle-float"]) { _ in }
        } else if isAeroSpace {
            windowManager?.executeRawCommand(args: ["layout", "floating", "tiling"]) { _ in }
        } else {
            windowManager?.executeRawCommand(args: ["-m", "window", "--toggle", "float"]) { _ in }
        }
    }

    @objc func toggleFullscreen() {
        logDebug("🖥️ Toggling fullscreen...")
        if isRift {
            windowManager?.executeRawCommand(args: ["execute", "window", "toggle-fullscreen"]) { _ in }
        } else if isAeroSpace {
            windowManager?.executeRawCommand(args: ["fullscreen"]) { _ in }
        } else {
            windowManager?.executeRawCommand(args: ["-m", "window", "--toggle", "zoom-fullscreen"]) { _ in }
        }
    }

    // MARK: - Move Window Actions

    @objc func moveNorth() {
        logDebug("⬆️ Moving window north...")
        if isRift {
            windowManager?.executeRawCommand(args: ["execute", "layout", "move-node", "up"]) { _ in }
        } else if isAeroSpace {
            windowManager?.executeRawCommand(args: ["move", "up"]) { _ in }
        } else {
            windowManager?.executeRawCommand(args: ["-m", "window", "--warp", "north"]) { _ in }
        }
    }

    @objc func moveSouth() {
        logDebug("⬇️ Moving window south...")
        if isRift {
            windowManager?.executeRawCommand(args: ["execute", "layout", "move-node", "down"]) { _ in }
        } else if isAeroSpace {
            windowManager?.executeRawCommand(args: ["move", "down"]) { _ in }
        } else {
            windowManager?.executeRawCommand(args: ["-m", "window", "--warp", "south"]) { _ in }
        }
    }

    @objc func moveEast() {
        logDebug("➡️ Moving window east...")
        if isRift {
            windowManager?.executeRawCommand(args: ["execute", "layout", "move-node", "right"]) { _ in }
        } else if isAeroSpace {
            windowManager?.executeRawCommand(args: ["move", "right"]) { _ in }
        } else {
            windowManager?.executeRawCommand(args: ["-m", "window", "--warp", "east"]) { _ in }
        }
    }

    @objc func moveWest() {
        logDebug("⬅️ Moving window west...")
        if isRift {
            windowManager?.executeRawCommand(args: ["execute", "layout", "move-node", "left"]) { _ in }
        } else if isAeroSpace {
            windowManager?.executeRawCommand(args: ["move", "left"]) { _ in }
        } else {
            windowManager?.executeRawCommand(args: ["-m", "window", "--warp", "west"]) { _ in }
        }
    }

    @objc func sendToSpace(_ sender: NSMenuItem) {
        if isAeroSpace {
            // AeroSpace: representedObject is workspace name string
            guard let wsName = sender.representedObject as? String else { return }
            logDebug("📦 Sending window to AeroSpace workspace \(wsName)...")
            windowManager?.executeRawCommand(args: ["move-node-to-workspace", "--focus-follows-window", wsName]) { _ in }
            return
        }
        guard let spaceIndex = sender.representedObject as? Int else { return }
        logDebug("📦 Sending window to space \(spaceIndex)...")
        if isRift {
            // Rift uses 0-based workspace indices, spaceIndex is 1-based
            let riftIndex = spaceIndex - 1
            windowManager?.executeRawCommand(args: ["execute", "workspace", "move-window", "\(riftIndex)"]) { [weak self] result in
                if case .success = result {
                    self?.windowManager?.executeRawCommand(args: ["execute", "workspace", "switch", "\(riftIndex)"]) { _ in }
                }
            }
        } else {
            windowManager?.executeRawCommand(args: ["-m", "window", "--space", "\(spaceIndex)"]) { [weak self] result in
                if case .success = result {
                    self?.windowManager?.executeRawCommand(args: ["-m", "space", "--focus", "\(spaceIndex)"]) { _ in }
                }
            }
        }
    }

    @objc func setLayout(_ sender: NSMenuItem) {
        guard let layoutType = sender.representedObject as? String else { return }
        logDebug("📐 Setting layout to \(layoutType)...")
        if isRift {
            windowManager?.executeRawCommand(args: ["execute", "workspace", "set-layout", layoutType]) { _ in }
        } else if isAeroSpace {
            windowManager?.executeRawCommand(args: ["layout", layoutType]) { _ in }
        } else {
            windowManager?.executeRawCommand(args: ["-m", "space", "--layout", layoutType]) { _ in }
        }
    }

    @objc func loadSA() {
        logInfo("User requested SA load - copying command to clipboard")

        // Copy the command to clipboard for user to run in Terminal
        let command = "sudo yabai --load-sa"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)

        // Show notification with instructions
        let notification = NSUserNotification()
        notification.title = "Load Yabai SA"
        notification.informativeText = "Command copied! Paste in Terminal and enter your password."
        notification.soundName = nil
        NSUserNotificationCenter.default.deliver(notification)
    }

    // MARK: - Stack Window Actions

    @objc func stackWindowOnto(_ sender: NSMenuItem) {
        guard let windowIds = sender.representedObject as? [String: Int],
              let sourceId = windowIds["source"],
              let targetId = windowIds["target"] else { return }
        windowManager?.stackWindow(sourceId, onto: targetId)
    }

    @objc func stackAllOnto(_ sender: NSMenuItem) {
        guard let targetId = sender.representedObject as? Int else { return }
        windowManager?.stackAllWindowsOnto(targetId)
    }

    @objc func unstackStack(_ sender: NSMenuItem) {
        guard let windowIds = sender.representedObject as? [Int] else { return }
        windowManager?.unstackWindows(windowIds)
    }

    // MARK: - AeroSpace-specific Actions

    @objc func closeWindow() {
        if isAeroSpace {
            windowManager?.executeRawCommand(args: ["close"]) { _ in }
        }
    }

    @objc func closeAllButCurrent() {
        if isAeroSpace {
            windowManager?.executeRawCommand(args: ["close-all-windows-but-current"]) { _ in }
        }
    }

    @objc func minimizeWindow() {
        if isAeroSpace {
            windowManager?.executeRawCommand(args: ["macos-native-minimize"]) { _ in }
        }
    }

    @objc func macosNativeFullscreen() {
        if isAeroSpace {
            windowManager?.executeRawCommand(args: ["macos-native-fullscreen"]) { _ in }
        }
    }

    @objc func workspaceBackAndForth() {
        if isAeroSpace {
            windowManager?.executeRawCommand(args: ["workspace-back-and-forth"]) { _ in }
        }
    }

    @objc func focusMonitorNext() {
        if isAeroSpace {
            windowManager?.executeRawCommand(args: ["focus-monitor", "next"]) { _ in }
        }
    }

    @objc func focusMonitorPrev() {
        if isAeroSpace {
            windowManager?.executeRawCommand(args: ["focus-monitor", "prev"]) { _ in }
        }
    }

    @objc func moveToMonitorNext() {
        if isAeroSpace {
            windowManager?.executeRawCommand(args: ["move-node-to-monitor", "--focus-follows-window", "next"]) { _ in }
        }
    }

    @objc func moveToMonitorPrev() {
        if isAeroSpace {
            windowManager?.executeRawCommand(args: ["move-node-to-monitor", "--focus-follows-window", "prev"]) { _ in }
        }
    }

    @objc func joinWith(_ sender: NSMenuItem) {
        guard let direction = sender.representedObject as? String else { return }
        if isAeroSpace {
            windowManager?.executeRawCommand(args: ["join-with", direction]) { _ in }
        }
    }

    @objc func resizeSmart(_ sender: NSMenuItem) {
        guard let amount = sender.representedObject as? String else { return }
        if isAeroSpace {
            windowManager?.executeRawCommand(args: ["resize", "smart", amount]) { _ in }
        }
    }

    @objc func toggleOrientation() {
        if isAeroSpace {
            windowManager?.executeRawCommand(args: ["layout", "horizontal", "vertical"]) { _ in }
        }
    }
}

// MARK: - Scrollable Action Selector

struct ScrollableActionSelector: NSViewRepresentable {
    @Binding var selectedIndex: Int
    let actionCount: Int
    @Binding var showLabel: Bool
    let onTap: () -> Void
    let onRightClick: () -> Void

    func makeNSView(context: Context) -> ScrollActionView {
        let view = ScrollActionView()
        view.onScrollChange = { delta in
            context.coordinator.handleScroll(delta: delta)
        }
        view.onTap = onTap
        view.onRightClick = onRightClick

        // Make sure view is visible and interactive
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

        return view
    }

    func updateNSView(_ nsView: ScrollActionView, context: Context) {
        // Update coordinator bindings
        context.coordinator.selectedIndex = $selectedIndex
        context.coordinator.actionCount = actionCount
        context.coordinator.showLabel = $showLabel
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedIndex: $selectedIndex, actionCount: actionCount, showLabel: $showLabel)
    }

    class Coordinator {
        var selectedIndex: Binding<Int>
        var actionCount: Int
        var showLabel: Binding<Bool>
        var scrollAccumulator: CGFloat = 0
        var isLabelShowing: Bool = false
        var hideWorkItem: DispatchWorkItem?

        // Debounce: track pending index to batch rapid scroll updates
        var pendingIndex: Int?
        var updateWorkItem: DispatchWorkItem?

        // Debounce label show to avoid rapid SwiftUI updates
        var labelShowWorkItem: DispatchWorkItem?
        var labelShowPending: Bool = false

        // Higher threshold = less sensitive, fewer SwiftUI updates
        let scrollThreshold: CGFloat = 10  // Increased from 8

        private let config = AegisConfig.shared

        init(selectedIndex: Binding<Int>, actionCount: Int, showLabel: Binding<Bool>) {
            self.selectedIndex = selectedIndex
            self.actionCount = actionCount
            self.showLabel = showLabel
            self.isLabelShowing = showLabel.wrappedValue
            self.pendingIndex = selectedIndex.wrappedValue
        }

        func handleScroll(delta: CGFloat) {
            // Show label while scrolling (if enabled) - debounced to prevent rapid updates
            if config.expandContextButtonOnScroll && !isLabelShowing && !labelShowPending {
                labelShowPending = true
                labelShowWorkItem?.cancel()
                let workItem = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    if !self.isLabelShowing {
                        self.isLabelShowing = true
                        self.showLabel.wrappedValue = true
                    }
                    self.labelShowPending = false
                }
                labelShowWorkItem = workItem
                // Show label after brief delay to avoid showing during quick single scroll
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
            }

            // Cancel pending hide while actively scrolling
            hideWorkItem?.cancel()

            // Accumulate scroll delta
            scrollAccumulator += delta

            let actionSteps = Int(scrollAccumulator / scrollThreshold)

            if actionSteps != 0 {
                let currentIndex = pendingIndex ?? selectedIndex.wrappedValue
                var newIndex = currentIndex + actionSteps

                // Wrap around
                if newIndex < 0 {
                    newIndex = actionCount + (newIndex % actionCount)
                } else if newIndex >= actionCount {
                    newIndex = newIndex % actionCount
                }

                if newIndex != pendingIndex {
                    pendingIndex = newIndex

                    // Debounce: cancel previous, schedule batched update
                    updateWorkItem?.cancel()
                    let workItem = DispatchWorkItem { [weak self] in
                        guard let self = self, let index = self.pendingIndex else { return }
                        if index != self.selectedIndex.wrappedValue {
                            self.selectedIndex.wrappedValue = index
                            if self.config.enableLayoutActionHaptics {
                                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                            }
                        }
                    }
                    updateWorkItem = workItem
                    // 33ms debounce (30fps max) batches rapid scroll events
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.033, execute: workItem)
                }

                scrollAccumulator = 0
            }

            // Schedule label hide after delay
            if config.expandContextButtonOnScroll && isLabelShowing {
                let workItem = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    self.isLabelShowing = false
                    self.showLabel.wrappedValue = false
                }
                hideWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
            }
        }
    }
}

class ScrollActionView: NSView {
    var onScrollChange: ((CGFloat) -> Void)?
    var onTap: (() -> Void)?
    var onRightClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        // Accept first responder to receive events
        self.wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        return true
    }

    // Accept all mouse events
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Always return self if point is in bounds
        if bounds.contains(point) {
            return self
        }
        return nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        // Remove old tracking areas
        for trackingArea in trackingAreas {
            removeTrackingArea(trackingArea)
        }

        // Add new tracking area
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    override func scrollWheel(with event: NSEvent) {
        // Ignore momentum phase for notched feeling - only respond to actual gestures
        guard event.phase == .began || event.phase == .changed || event.phase == [] else {
            return
        }

        let delta = event.deltaY

        // Higher threshold reduces callback frequency - filters tiny scroll movements
        if abs(delta) > 0.5 {
            onScrollChange?(delta)
        }
    }

    override func mouseDown(with event: NSEvent) {
        onTap?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }
}

// MARK: - Int Extension for Clamping

extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
