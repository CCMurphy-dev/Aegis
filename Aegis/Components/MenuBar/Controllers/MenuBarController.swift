import Cocoa
import SwiftUI
import Combine

// MARK: - MenuBarController
// Simplified controller that delegates to MenuBarCoordinator
// This maintains backward compatibility with existing code

class MenuBarController {
    private let coordinator: MenuBarCoordinator

    init(yabaiService: YabaiService, eventRouter: EventRouter) {
        self.coordinator = MenuBarCoordinator(
            yabaiService: yabaiService,
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

struct MenuBarView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    let onSpaceClick: (Int) -> Void
    let onWindowClick: (Int) -> Void
    let onSpaceDestroy: (Int) -> Void
    let onSpaceCreate: () -> Void
    let onWindowDrop: (Int, Int, Int?, Bool) -> Void
    let onRotateLayout: (Int) -> Void
    let onFlipLayout: (String) -> Void
    let onBalanceLayout: () -> Void
    let onToggleLayout: () -> Void
    let onStackAllWindows: () -> Void

    private let config = AegisConfig.shared
    @State private var scrollOffset: CGFloat = 0
    @State private var isScrolled: Bool = false
    @State private var draggedWindowId: Int?
    @State private var buttonLabelShowing: Bool = false
    @State private var previousSpaceCount: Int = 0

    init(
        viewModel: MenuBarViewModel,
        onSpaceClick: @escaping (Int) -> Void,
        onWindowClick: @escaping (Int) -> Void,
        onSpaceDestroy: @escaping (Int) -> Void,
        onSpaceCreate: @escaping () -> Void,
        onWindowDrop: @escaping (Int, Int, Int?, Bool) -> Void,
        onRotateLayout: @escaping (Int) -> Void,
        onFlipLayout: @escaping (String) -> Void,
        onBalanceLayout: @escaping () -> Void,
        onToggleLayout: @escaping () -> Void,
        onStackAllWindows: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onSpaceClick = onSpaceClick
        self.onWindowClick = onWindowClick
        self.onSpaceDestroy = onSpaceDestroy
        self.onSpaceCreate = onSpaceCreate
        self.onWindowDrop = onWindowDrop
        self.onRotateLayout = onRotateLayout
        self.onFlipLayout = onFlipLayout
        self.onBalanceLayout = onBalanceLayout
        self.onToggleLayout = onToggleLayout
        self.onStackAllWindows = onStackAllWindows
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Background blur with gradient fade - full blur at top, transparent at bottom
            // Blends smoothly into the desktop wallpaper
            GradientBlurView(material: .hudWindow, blendingMode: .behindWindow)
                .frame(height: config.menuBarHeight)

            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    HStack(alignment: .top, spacing: 0) {
                        // Dynamic spacer that grows when button label is shown
                        Spacer()
                            .frame(width: config.menuBarEdgePadding + 32 + config.spaceIndicatorSpacing + (buttonLabelShowing ? 95 : 0))
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: buttonLabelShowing)

                        // Spaces (with scrolling if needed)
                        ZStack(alignment: .topLeading) {
                        // Scrollable spaces area (full width)
                        ScrollViewReader { scrollProxy in
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: config.spaceIndicatorSpacing) {
                                    ForEach(viewModel.spaces) { space in
                                        // Use the windowIconsBySpace dictionary directly (it's @Published)
                                        let windowIcons = viewModel.windowIconsBySpace[space.index] ?? []
                                        let allWindowIcons = viewModel.getAllWindowIcons(for: space)

                                        // Derive isActive from window focus state (same source as the focus dot)
                                        // This keeps the space highlight in sync with the focus indicator
                                        let hasWindowFocus = windowIcons.contains(where: { $0.hasFocus })

                                        SpaceIndicatorView(
                                            space: space,
                                            isActive: hasWindowFocus,
                                            windowIcons: windowIcons,
                                            allWindowIcons: allWindowIcons,
                                            onWindowClick: onWindowClick,
                                            onSpaceClick: {
                                                onSpaceClick(space.index)
                                            },
                                            onSpaceDestroy: onSpaceDestroy,
                                            onWindowDrop: onWindowDrop,
                                            draggedWindowId: $draggedWindowId,
                                            expandedWindowId: $viewModel.expandedWindowId
                                        )
                                        .id("\(space.id)-\(viewModel.windowIconsVersion)")
                                        .transition(.asymmetric(
                                            insertion: .move(edge: .leading).combined(with: .opacity),
                                            removal: .move(edge: .top).combined(with: .opacity)
                                        ))
                                    }
                                }
                                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.spaces.count)
                                .animation(.easeInOut(duration: 0.2), value: viewModel.windowIconsBySpace)  // Animate when dictionary changes
                                .padding(.leading, config.menuBarEdgePadding + config.spaceIndicatorSpacing + 32)  // Start after button
                                // Extra trailing padding allows scrolling content past the notch area
                                // This creates scrollable space so user can scroll left to reveal spaces hidden behind notch/HUD
                                .padding(.trailing, geometry.size.width / 2 + 50)
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: ScrollOffsetPreferenceKey.self,
                                        value: geo.frame(in: .named("scroll")).minX
                                    )
                                }
                            )
                        }
                        .coordinateSpace(name: "scroll")
                        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                            // Content is scrolled if minX is less than 0
                            isScrolled = value < -5
                        }
                        .onChange(of: viewModel.spaces) { newSpaces in
                            // Only auto-scroll when spaces are added/removed (count changes)
                            // Don't auto-scroll when just switching focus - preserve user's scroll position
                            let newCount = newSpaces.count
                            if newCount != previousSpaceCount {
                                previousSpaceCount = newCount
                                // Scroll to newly focused space when spaces change
                                if let focusedSpace = newSpaces.first(where: { $0.focused }) {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        scrollProxy.scrollTo("\(focusedSpace.id)-\(viewModel.windowIconsVersion)", anchor: .center)
                                    }
                                }
                            }
                        }
                        .onAppear {
                            // Initialize the previous space count
                            previousSpaceCount = viewModel.spaces.count
                        }
                    }
                    .offset(x: -(config.menuBarEdgePadding + config.spaceIndicatorSpacing + 32))  // Extend under button
                    .mask(
                        GeometryReader { maskGeometry in
                            ZStack {
                                // Base white (shows content)
                                Rectangle()
                                    .fill(Color.white)

                                // Left fade - hide content as it scrolls under the button
                                LinearGradient(
                                    gradient: Gradient(stops: [
                                        .init(color: .clear, location: 0.0),
                                        .init(color: .black, location: 0.3),
                                        .init(color: .black, location: 1.0)
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: config.menuBarEdgePadding + config.spaceIndicatorSpacing + 32 + 20)  // Button area + fade
                                .blendMode(.destinationOut)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .opacity(isScrolled ? 1.0 : 0.0)

                                // Right fade - smooth fade before notch/HUD
                                // With destinationOut: clear = keep content, black = cut out content
                                LinearGradient(
                                    gradient: Gradient(stops: [
                                        .init(color: .clear, location: 0.0),   // Keep content at start
                                        .init(color: .clear, location: 0.4),   // Still keep content
                                        .init(color: .black, location: 1.0)    // Cut out at right edge
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: 60)  // Width of the fade zone
                                .blendMode(.destinationOut)  // Cut out content where gradient is black
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            .animation(.easeInOut(duration: 0.2), value: isScrolled)
                            .compositingGroup()
                            .drawingGroup()
                        }
                    )
                        }

                        Spacer()
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 4)  // Small top padding to align with notch HUD elements

                    // Right: System status - positioned on its own layer for proper vertical centering
                    HStack {
                        Spacer()
                        SystemStatusView()
                            .padding(.trailing, config.menuBarEdgePadding)
                    }
                    .frame(height: config.menuBarHeight, alignment: .center)

                    // Button on top layer to ensure it's interactive
                    HStack {
                        LayoutActionsButton(
                            viewModel: viewModel,
                            onRotate: onRotateLayout,
                            onFlip: onFlipLayout,
                            onBalance: onBalanceLayout,
                            onToggleLayout: onToggleLayout,
                            onStackAllWindows: onStackAllWindows,
                            onSpaceCreate: onSpaceCreate,
                            onSpaceDestroy: onSpaceDestroy,
                            labelShowing: $buttonLabelShowing
                        )
                        .padding(.leading, config.menuBarEdgePadding)
                        .padding(.trailing, config.spaceIndicatorSpacing)

                        Spacer()
                    }
                    .frame(height: config.menuBarHeight, alignment: .center)
                }
            }
            .frame(height: config.menuBarHeight)
        }
        .frame(height: config.menuBarHeight)
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
                    .foregroundColor(.white.opacity(isHovered ? 1.0 : 0.6))
                    .frame(width: 16, height: 16)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.white.opacity(0.18) : Color.white.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                    .opacity(isHovered ? 1.0 : 0.0)
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
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

    // Define all available actions
    let actions: [(label: String, icon: String, execute: (LayoutActionsButton) -> Void)] = [
        ("Rotate 90°", "↻", { $0.onRotate(90) }),
        ("Rotate 180°", "↻↻", { $0.onRotate(180) }),
        ("Rotate 270°", "↺", { $0.onRotate(270) }),
        ("Flip Horizontal", "↔", { $0.onFlip("x") }),
        ("Flip Vertical", "↕", { $0.onFlip("y") }),
        ("Balance", "⚖", { $0.onBalance() }),
        ("Toggle Layout", "⇄", { $0.onToggleLayout() }),
        ("Stack/Unstack", "⧉", { $0.onStackAllWindows() }),
        ("New Space", "+", { $0.onSpaceCreate() })
    ]

    var body: some View {
        // Main button - label expands to the right
        HStack(spacing: 0) {
            Text(actions[selectedActionIndex].icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(isHovered ? 1.0 : 0.6))
                .frame(width: 16, height: 16)

            if showActionLabel {
                Text(actions[selectedActionIndex].label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 95, alignment: .leading)
                    .padding(.leading, 6)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            ZStack {
                // Backdrop blur effect when label is showing to cover spaces behind
                if showActionLabel {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.4))
                        .blur(radius: 8)
                        .padding(-8)
                }

                // Main button background matching space indicators
                RoundedRectangle(cornerRadius: 8)
                    .fill(showActionLabel ? Color.white.opacity(0.2) : (isHovered ? Color.white.opacity(0.15) : Color.white.opacity(0.12)))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                .opacity((isHovered || showActionLabel) ? 1.0 : 0.0)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showActionLabel)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: selectedActionIndex)
        .background(
            // Use GeometryReader to capture frame for menu positioning
            GeometryReader { geo in
                Color.clear.preference(key: ButtonFramePreferenceKey.self, value: geo.frame(in: .global))
            }
        )
        .onPreferenceChange(ButtonFramePreferenceKey.self) { frame in
            self.buttonFrame = frame
        }
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
        print("🎯 Executing action: \(actions[selectedActionIndex].label)")
        actions[selectedActionIndex].execute(self)
    }

    private func showContextMenu() {
        print("🖱️ showContextMenu called, buttonFrame: \(buttonFrame)")

        let menu = NSMenu()
        menu.autoenablesItems = false

        let yabaiService = viewModel.yabaiService
        // Get all spaces from cache
        let spaces = yabaiService.getCurrentSpaces()

        // Query yabai synchronously for the actual focused space (more accurate than cache)
        let focusedSpaceIndex = yabaiService.getFocusedSpaceIndexSync()
        let focusedSpace = spaces.first(where: { $0.index == focusedSpaceIndex })

        print("🔍 Menu: focused space = \(focusedSpaceIndex), total spaces = \(spaces.count)")

        // Get window count for current space
        let windowCount = focusedSpace.map { yabaiService.getWindowIconsForSpace($0.index).count } ?? 0

        // Create a menu target with captured callbacks
        let menuTarget = LayoutActionsMenuTarget(
            yabaiService: yabaiService,
            onRotate: onRotate,
            onFlip: onFlip,
            onBalance: onBalance,
            onToggleLayout: onToggleLayout,
            onStackAllWindows: onStackAllWindows,
            onSpaceCreate: onSpaceCreate,
            onSpaceDestroy: onSpaceDestroy
        )

        // MARK: - Layout Actions Section
        let currentLayoutType = focusedSpace?.type ?? "bsp"

        for (index, action) in actions.enumerated() {
            // Skip "Toggle Layout" - we'll add a submenu instead
            if index == 6 {
                continue
            }

            let menuItem = NSMenuItem(title: "\(action.icon)  \(action.label)", action: #selector(LayoutActionsMenuTarget.executeAction(_:)), keyEquivalent: "")
            menuItem.target = menuTarget
            menuItem.tag = index

            // Disable Stack/Unstack if only 0-1 windows
            if index == 7 { // Stack/Unstack action
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

        let layoutTypes = [
            ("BSP", "bsp", "Binary space partitioning - tiles windows automatically"),
            ("Float", "float", "Floating windows - manual positioning"),
            ("Stack", "stack", "All windows stacked on top of each other")
        ]

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

        moveWindowItem.submenu = moveSubmenu
        menu.addItem(moveWindowItem)

        // MARK: - Send to Space Submenu
        let sendToSpaceItem = NSMenuItem(title: "Send to Space", action: nil, keyEquivalent: "")
        let spaceSubmenu = NSMenu()
        spaceSubmenu.autoenablesItems = false

        // Show all spaces in the menu (including current space for convenience)
        for space in spaces {
            let spaceItem = NSMenuItem(title: "Space \(space.index)", action: #selector(LayoutActionsMenuTarget.sendToSpace(_:)), keyEquivalent: "")
            spaceItem.target = menuTarget
            spaceItem.representedObject = space.index
            spaceItem.isEnabled = windowCount > 0
            // Dim the current space to indicate it's where you already are
            if space.index == focusedSpaceIndex {
                spaceItem.attributedTitle = NSAttributedString(
                    string: "Space \(space.index) (current)",
                    attributes: [.foregroundColor: NSColor.gray]
                )
            }
            spaceSubmenu.addItem(spaceItem)
        }

        sendToSpaceItem.submenu = spaceSubmenu
        menu.addItem(sendToSpaceItem)

        // MARK: - Stack Windows Submenu
        let stackWindowsItem = NSMenuItem(title: "Stack Windows", action: nil, keyEquivalent: "")
        let stackSubmenu = NSMenu()
        stackSubmenu.autoenablesItems = false

        // Get windows in current space for stacking selection
        let spaceWindows = focusedSpace.map { yabaiService.getWindowIconsForSpace($0.index) } ?? []

        if spaceWindows.count >= 2 {
            // Create a submenu item for each window that can be the stack target
            for targetWindow in spaceWindows {
                let targetTitle = targetWindow.title.isEmpty ? targetWindow.appName : String(targetWindow.title.prefix(30))
                let targetItem = NSMenuItem(title: targetTitle, action: nil, keyEquivalent: "")
                // Set scaled icon for target window
                if let icon = targetWindow.icon {
                    let scaledIcon = NSImage(size: NSSize(width: 16, height: 16))
                    scaledIcon.lockFocus()
                    icon.draw(in: NSRect(x: 0, y: 0, width: 16, height: 16))
                    scaledIcon.unlockFocus()
                    targetItem.image = scaledIcon
                }
                let windowsToStackSubmenu = NSMenu()
                windowsToStackSubmenu.autoenablesItems = false

                // Add other windows that can be stacked onto this target
                for sourceWindow in spaceWindows where sourceWindow.id != targetWindow.id {
                    let sourceTitle = sourceWindow.title.isEmpty ? sourceWindow.appName : String(sourceWindow.title.prefix(40))
                    let sourceItem = NSMenuItem(
                        title: sourceTitle,
                        action: #selector(LayoutActionsMenuTarget.stackWindowOnto(_:)),
                        keyEquivalent: ""
                    )
                    sourceItem.target = menuTarget
                    // Set scaled icon for source window
                    if let icon = sourceWindow.icon {
                        let scaledIcon = NSImage(size: NSSize(width: 16, height: 16))
                        scaledIcon.lockFocus()
                        icon.draw(in: NSRect(x: 0, y: 0, width: 16, height: 16))
                        scaledIcon.unlockFocus()
                        sourceItem.image = scaledIcon
                    }
                    // Store both window IDs: source to stack onto target
                    sourceItem.representedObject = ["source": sourceWindow.id, "target": targetWindow.id]
                    windowsToStackSubmenu.addItem(sourceItem)
                }

                // Add "Stack All Others" option
                if spaceWindows.count > 2 {
                    windowsToStackSubmenu.addItem(NSMenuItem.separator())
                    let stackAllItem = NSMenuItem(
                        title: "Stack All Others Here",
                        action: #selector(LayoutActionsMenuTarget.stackAllOnto(_:)),
                        keyEquivalent: ""
                    )
                    stackAllItem.target = menuTarget
                    stackAllItem.representedObject = targetWindow.id
                    windowsToStackSubmenu.addItem(stackAllItem)
                }

                targetItem.submenu = windowsToStackSubmenu
                stackSubmenu.addItem(targetItem)
            }
        } else {
            let noWindowsItem = NSMenuItem(title: "Need 2+ windows to stack", action: nil, keyEquivalent: "")
            noWindowsItem.isEnabled = false
            stackSubmenu.addItem(noWindowsItem)
        }

        stackWindowsItem.submenu = stackSubmenu
        menu.addItem(stackWindowsItem)

        menu.addItem(NSMenuItem.separator())

        // MARK: - Space Management Section
        menu.addItem(NSMenuItem(title: "Destroy Space", action: #selector(LayoutActionsMenuTarget.destroyCurrentSpace(_:)), keyEquivalent: ""))
        menu.items.last?.target = menuTarget
        menu.items.last?.representedObject = focusedSpaceIndex
        menu.items.last?.isEnabled = spaces.count > 1

        menu.addItem(NSMenuItem.separator())

        // MARK: - Status Section
        let statusItem = NSMenuItem(title: "Status", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        // Yabai Version
        let yabaiVersion = yabaiService.getYabaiVersion()
        let yabaiVersionItem = NSMenuItem(title: "  Yabai: v\(yabaiVersion)", action: nil, keyEquivalent: "")
        yabaiVersionItem.isEnabled = false
        menu.addItem(yabaiVersionItem)

        // SA Status - check if scripting addition is loaded
        let saStatus = YabaiSetupChecker.checkSA()
        let saStatusItem: NSMenuItem
        switch saStatus {
        case .loaded:
            saStatusItem = NSMenuItem(title: "  SA: Loaded", action: nil, keyEquivalent: "")
            saStatusItem.isEnabled = false
        case .notLoaded:
            saStatusItem = NSMenuItem(title: "  SA: Not loaded (click to load)", action: #selector(LayoutActionsMenuTarget.loadSA), keyEquivalent: "")
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

        // Aegis Version
        let aegisVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let aegisVersionItem = NSMenuItem(title: "  Aegis: v\(aegisVersion)", action: nil, keyEquivalent: "")
        aegisVersionItem.isEnabled = false
        menu.addItem(aegisVersionItem)

        // Link Status - check yabai-aegis integration
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

        menu.addItem(NSMenuItem.separator())

        // MARK: - Display Options
        let showMusicHUDItem = NSMenuItem(
            title: "Show Now Playing",
            action: #selector(LayoutActionsMenuTarget.toggleShowMusicHUD(_:)),
            keyEquivalent: ""
        )
        showMusicHUDItem.target = menuTarget
        showMusicHUDItem.state = AegisConfig.shared.showMusicHUD ? .on : .off
        menu.addItem(showMusicHUDItem)

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
        visualizerItem.state = AegisConfig.shared.musicHUDRightPanelMode == .visualizer ? .on : .off
        rightPanelSubmenu.addItem(visualizerItem)

        let trackInfoItem = NSMenuItem(
            title: "Track Info",
            action: #selector(LayoutActionsMenuTarget.setRightPanelModeTrackInfo(_:)),
            keyEquivalent: ""
        )
        trackInfoItem.target = menuTarget
        trackInfoItem.state = AegisConfig.shared.musicHUDRightPanelMode == .trackInfo ? .on : .off
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
        menu.addItem(NSMenuItem(title: "Reload yabai", action: #selector(LayoutActionsMenuTarget.restartYabai), keyEquivalent: ""))
        menu.items.last?.target = menuTarget
        menu.items.last?.isEnabled = true

        menu.addItem(NSMenuItem(title: "Restart Aegis", action: #selector(LayoutActionsMenuTarget.restartAegis), keyEquivalent: ""))
        menu.items.last?.target = menuTarget
        menu.items.last?.isEnabled = true

        menu.addItem(NSMenuItem(title: "Restart skhd", action: #selector(LayoutActionsMenuTarget.restartSkhd), keyEquivalent: ""))
        menu.items.last?.target = menuTarget
        menu.items.last?.isEnabled = true

        menu.addItem(NSMenuItem.separator())

        // MARK: - Quit
        menu.addItem(NSMenuItem(title: "Quit Aegis", action: #selector(LayoutActionsMenuTarget.quitAegis), keyEquivalent: "q"))
        menu.items.last?.target = menuTarget
        menu.items.last?.isEnabled = true

        // Show menu aligned with the button
        if let event = NSApp.currentEvent, let window = event.window {
            let locationInWindow = event.locationInWindow
            print("📍 Menu location in window: \(locationInWindow)")
            menu.popUp(positioning: nil, at: locationInWindow, in: window.contentView)
        } else if let window = NSApp.keyWindow, let contentView = window.contentView {
            // Fallback: use button frame if no event
            let windowPoint = NSPoint(x: buttonFrame.minX, y: window.frame.height - buttonFrame.minY)
            print("📍 Fallback menu location: \(windowPoint)")
            menu.popUp(positioning: nil, at: windowPoint, in: contentView)
        }

    }

    private func checkYabaiStatus() -> String {
        // Check if yabai is running
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["yabai", "-m", "query", "--spaces"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                // Check SA status
                let saTask = Process()
                saTask.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                saTask.arguments = ["yabai", "-m", "query", "--windows"]
                let saPipe = Pipe()
                saTask.standardOutput = saPipe
                saTask.standardError = saPipe

                try? saTask.run()
                saTask.waitUntilExit()

                let hasSA = saTask.terminationStatus == 0
                return hasSA ? "✓ Yabai running, SA loaded" : "⚠ Yabai running, SA not loaded"
            } else {
                return "✗ Yabai not responding"
            }
        } catch {
            return "✗ Yabai not running"
        }
    }
}

// MARK: - Menu Handler

class LayoutActionsMenuTarget: NSObject {
    static let shared = LayoutActionsMenuTarget()

    private let yabaiService: YabaiService?
    private let onRotate: ((Int) -> Void)?
    private let onFlip: ((String) -> Void)?
    private let onBalance: (() -> Void)?
    private let onToggleLayout: (() -> Void)?
    private let onStackAllWindows: (() -> Void)?
    private let onSpaceCreate: (() -> Void)?
    private let onSpaceDestroy: ((Int) -> Void)?

    init(yabaiService: YabaiService? = nil,
         onRotate: ((Int) -> Void)? = nil,
         onFlip: ((String) -> Void)? = nil,
         onBalance: (() -> Void)? = nil,
         onToggleLayout: (() -> Void)? = nil,
         onStackAllWindows: (() -> Void)? = nil,
         onSpaceCreate: (() -> Void)? = nil,
         onSpaceDestroy: ((Int) -> Void)? = nil) {
        self.yabaiService = yabaiService
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
        print("📋 Menu action at index: \(index)")

        // Execute based on index
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
            print("❌ Unknown action index: \(index)")
        }
    }

    @objc func openSettings() {
        print("⚙️ Opening Settings Panel...")
        SettingsPanelController.shared.showSettings()
    }

    @objc func toggleShowMusicHUD(_ sender: NSMenuItem) {
        let config = AegisConfig.shared
        config.showMusicHUD.toggle()
        config.savePreferences()
        print("🎵 Show Music HUD: \(config.showMusicHUD ? "ON" : "OFF")")
    }

    @objc func setRightPanelModeVisualizer(_ sender: NSMenuItem) {
        let config = AegisConfig.shared
        config.musicHUDRightPanelMode = .visualizer
        config.savePreferences()
        print("🎵 Music HUD Right Panel: Visualizer")
    }

    @objc func setRightPanelModeTrackInfo(_ sender: NSMenuItem) {
        let config = AegisConfig.shared
        config.musicHUDRightPanelMode = .trackInfo
        config.savePreferences()
        print("🎵 Music HUD Right Panel: Track Info")
    }

    @objc func restartYabai() {
        print("🔄 Restarting yabai...")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/yabai")
        task.arguments = ["--restart-service"]
        do {
            try task.run()
            print("✅ Yabai restart command sent")
        } catch {
            print("❌ Failed to restart yabai: \(error)")
        }
    }

    @objc func restartAegis() {
        print("🔄 Restarting Aegis...")
        // Use NSWorkspace to relaunch
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true

        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error = error {
                print("❌ Failed to relaunch: \(error)")
            } else {
                NSApp.terminate(nil)
            }
        }
    }

    @objc func restartSkhd() {
        print("🔄 Restarting skhd...")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/skhd")
        task.arguments = ["--restart-service"]
        do {
            try task.run()
            print("✅ skhd restart command sent")
        } catch {
            print("❌ Failed to restart skhd: \(error)")
        }
    }

    @objc func quitAegis() {
        print("👋 Quitting Aegis...")
        NSApp.terminate(nil)
    }

    @objc func createNewSpace() {
        print("➕ Creating new space...")
        onSpaceCreate?()
    }

    @objc func destroyCurrentSpace(_ sender: NSMenuItem) {
        guard let spaceIndex = sender.representedObject as? Int else { return }
        print("🗑️ Destroying space \(spaceIndex)...")
        onSpaceDestroy?(spaceIndex)
    }

    // MARK: - Window Navigation Actions

    @objc func focusNext() {
        print("➡️ Focusing next window...")
        yabaiService?.executeYabai(args: ["-m", "window", "--focus", "next"]) { _ in }
    }

    @objc func focusPrevious() {
        print("⬅️ Focusing previous window...")
        yabaiService?.executeYabai(args: ["-m", "window", "--focus", "prev"]) { _ in }
    }

    @objc func swapLeft() {
        print("⬅️ Swapping window left...")
        yabaiService?.executeYabai(args: ["-m", "window", "--swap", "west"]) { _ in }
    }

    @objc func swapRight() {
        print("➡️ Swapping window right...")
        yabaiService?.executeYabai(args: ["-m", "window", "--swap", "east"]) { _ in }
    }

    @objc func toggleFloat() {
        print("🎈 Toggling float...")
        yabaiService?.executeYabai(args: ["-m", "window", "--toggle", "float"]) { _ in }
    }

    @objc func toggleFullscreen() {
        print("🖥️ Toggling fullscreen...")
        yabaiService?.executeYabai(args: ["-m", "window", "--toggle", "zoom-fullscreen"]) { _ in }
    }

    // MARK: - Move Window Actions

    @objc func moveNorth() {
        print("⬆️ Moving window north...")
        yabaiService?.executeYabai(args: ["-m", "window", "--warp", "north"]) { _ in }
    }

    @objc func moveSouth() {
        print("⬇️ Moving window south...")
        yabaiService?.executeYabai(args: ["-m", "window", "--warp", "south"]) { _ in }
    }

    @objc func moveEast() {
        print("➡️ Moving window east...")
        yabaiService?.executeYabai(args: ["-m", "window", "--warp", "east"]) { _ in }
    }

    @objc func moveWest() {
        print("⬅️ Moving window west...")
        yabaiService?.executeYabai(args: ["-m", "window", "--warp", "west"]) { _ in }
    }

    @objc func sendToSpace(_ sender: NSMenuItem) {
        guard let spaceIndex = sender.representedObject as? Int else { return }
        print("📦 Sending window to space \(spaceIndex)...")
        yabaiService?.executeYabai(args: ["-m", "window", "--space", "\(spaceIndex)"]) { [weak self] result in
            // Follow focus to the new space after moving the window
            if case .success = result {
                self?.yabaiService?.executeYabai(args: ["-m", "space", "--focus", "\(spaceIndex)"]) { _ in }
            }
        }
    }

    @objc func setLayout(_ sender: NSMenuItem) {
        guard let layoutType = sender.representedObject as? String else { return }
        print("📐 Setting layout to \(layoutType)...")
        yabaiService?.executeYabai(args: ["-m", "space", "--layout", layoutType]) { _ in }
    }

    @objc func loadSA() {
        logInfo("User requested SA load")

        // Use AppleScript to run sudo command with admin privileges prompt
        let script = """
        do shell script "/opt/homebrew/bin/yabai --load-sa" with administrator privileges
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            if let error = error {
                logError("Failed to load SA: \(error)")
            } else {
                logInfo("SA loaded successfully via user action")
            }
        }
    }

    // MARK: - Stack Window Actions

    @objc func stackWindowOnto(_ sender: NSMenuItem) {
        guard let windowIds = sender.representedObject as? [String: Int],
              let sourceId = windowIds["source"],
              let targetId = windowIds["target"] else { return }
        print("📚 Stacking window \(sourceId) onto \(targetId)...")
        yabaiService?.stackWindow(sourceId, onto: targetId)
    }

    @objc func stackAllOnto(_ sender: NSMenuItem) {
        guard let targetId = sender.representedObject as? Int else { return }
        print("📚 Stacking all windows onto \(targetId)...")
        yabaiService?.stackAllWindowsOnto(targetId)
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
        var lastHapticIndex: Int = 0
        var hideTask: DispatchWorkItem?

        // Adjust sensitivity: higher = less sensitive (need more scroll)
        // Using 3 for vertical scroll - trackpad deltas are typically 0.5-1.0 per event
        let scrollThreshold: CGFloat = 3

        private let config = AegisConfig.shared

        init(selectedIndex: Binding<Int>, actionCount: Int, showLabel: Binding<Bool>) {
            self.selectedIndex = selectedIndex
            self.actionCount = actionCount
            self.showLabel = showLabel
            self.lastHapticIndex = selectedIndex.wrappedValue
        }

        func handleScroll(delta: CGFloat) {
            // Cancel previous hide task
            hideTask?.cancel()

            // Show label while scrolling
            showLabel.wrappedValue = true

            // Accumulate scroll delta (negative = scroll up, positive = scroll down)
            scrollAccumulator += delta

            // Calculate how many actions to move
            // Negative delta (scroll up) should move to previous action (decrease index)
            // Positive delta (scroll down) should move to next action (increase index)
            let actionSteps = Int(scrollAccumulator / scrollThreshold)

            if actionSteps != 0 {
                // Calculate new index with wrapping (loop around)
                var newIndex = selectedIndex.wrappedValue + actionSteps

                // Wrap around using modulo
                if newIndex < 0 {
                    newIndex = actionCount + (newIndex % actionCount)
                } else if newIndex >= actionCount {
                    newIndex = newIndex % actionCount
                }

                if newIndex != selectedIndex.wrappedValue {
                    selectedIndex.wrappedValue = newIndex

                    // Trigger haptic feedback on action boundary (if enabled)
                    if config.enableLayoutActionHaptics {
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    }

                    print("🔄 Selected action index: \(newIndex) (action: \(["Rotate 90°", "Rotate 180°", "Rotate 270°", "Flip Horizontal", "Flip Vertical", "Balance", "Toggle Layout", "Stack/Unstack", "New Space"][newIndex]))")
                }

                // Reset accumulator
                scrollAccumulator = 0
            }

            // Hide label after a delay
            let task = DispatchWorkItem { [weak self] in
                self?.showLabel.wrappedValue = false
            }
            hideTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: task)
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
        // Use deltaY for vertical scrolling (two-finger up/down)
        // This button captures scroll-up for menu selection
        // Space indicators will still capture scroll-up for destruction

        // Ignore momentum phase for notched feeling - only respond to actual gestures
        guard event.phase == .began || event.phase == .changed || event.phase == [] else {
            return
        }

        let delta = event.deltaY

        print("📜 ScrollActionView scrollWheel - phase: \(event.phase.rawValue), deltaY: \(delta)")

        // Only respond to vertical scroll
        if abs(delta) > 0.1 {
            print("   ✅ Passing to handler")
            onScrollChange?(delta)
        }
    }

    override func mouseDown(with event: NSEvent) {
        print("👆 ScrollActionView mouseDown called")
        onTap?()
    }

    override func rightMouseDown(with event: NSEvent) {
        print("🖱️ ScrollActionView rightMouseDown called")
        onRightClick?()
    }
}

// MARK: - Int Extension for Clamping

extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
