//
//  AppKitActionButton.swift
//  Aegis
//
//  Pure AppKit implementation of the Layout Actions button.
//  Bypasses SwiftUI entirely for scroll interactions to minimize CPU usage.
//

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

// MARK: - AppKit Layout Actions Button

/// Pure AppKit button with scroll-to-select functionality
/// No SwiftUI involvement during scroll = minimal CPU overhead
final class AppKitLayoutActionsButton: NSView {

    // MARK: - Actions Configuration

    struct Action {
        let label: String
        let icon: String
        let execute: () -> Void
    }

    // MARK: - Properties

    private var actions: [Action] = []
    private var selectedIndex: Int = 0
    private var isHovered: Bool = false
    private var showLabel: Bool = false

    // Callbacks
    var onRightClick: (() -> Void)?
    var onExpandedChange: ((Bool) -> Void)?

    // Scroll handling
    private var scrollAccumulator: CGFloat = 0
    private let scrollThreshold: CGFloat = 15  // Higher threshold = fewer updates
    private var hideWorkItem: DispatchWorkItem?
    private var lastScrollTime: CFTimeInterval = 0
    private let scrollThrottleInterval: CFTimeInterval = 0.05  // ~20fps max - aggressive throttle

    // Layers for GPU-accelerated rendering
    private var backgroundLayer: CALayer!
    private var borderLayer: CAShapeLayer!
    private var iconLayer: CATextLayer!
    private var labelLayer: CATextLayer!

    // Layout constants
    private let cornerRadius: CGFloat = 8
    private let horizontalPadding: CGFloat = 8
    private let verticalPadding: CGFloat = 5
    private let iconSize: CGFloat = 16
    private let labelWidth: CGFloat = 95
    private let labelSpacing: CGFloat = 6

    private let config = AegisConfig.shared
    private var themeObserver: NSObjectProtocol?
    private var configCancellable: AnyCancellable?

    // Computed widths for SwiftUI layout coordination
    static let collapsedWidth: CGFloat = 8 * 2 + 16  // horizontalPadding * 2 + iconSize = 32
    static let expandedWidth: CGFloat = 8 * 2 + 16 + 6 + 95  // + labelSpacing + labelWidth = 133

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
        setupTrackingArea()
        setupThemeObserver()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
        setupTrackingArea()
        setupThemeObserver()
    }

    deinit {
        if let observer = themeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupThemeObserver() {
        themeObserver = NotificationCenter.default.addObserver(
            forName: .themeDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateColors()
        }
        configCancellable = config.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateColors()
            }
    }

    private func updateColors() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backgroundLayer.backgroundColor = ThemeColors.backgroundNSColor(alpha: config.inactiveSpaceBgOpacity).cgColor
        borderLayer.strokeColor = ThemeColors.foregroundNSColor(alpha: config.activeBorderOpacity).cgColor
        iconLayer.foregroundColor = ThemeColors.foregroundNSColor(alpha: config.tertiaryTextOpacity).cgColor
        labelLayer.foregroundColor = ThemeColors.foregroundNSColor(alpha: config.secondaryTextOpacity).cgColor
        CATransaction.commit()
    }

    func configure(actions: [Action]) {
        self.actions = actions
        updateIcon()
    }

    // MARK: - Layer Setup

    private func setupLayers() {
        wantsLayer = true
        layer?.masksToBounds = false

        // Background layer
        backgroundLayer = CALayer()
        backgroundLayer.cornerRadius = cornerRadius
        backgroundLayer.backgroundColor = ThemeColors.backgroundNSColor(alpha: config.inactiveSpaceBgOpacity).cgColor
        layer?.addSublayer(backgroundLayer)

        // Border layer
        borderLayer = CAShapeLayer()
        borderLayer.fillColor = nil
        borderLayer.strokeColor = ThemeColors.foregroundNSColor(alpha: config.activeBorderOpacity).cgColor
        borderLayer.lineWidth = 1
        borderLayer.opacity = 0
        layer?.addSublayer(borderLayer)

        // Icon layer
        iconLayer = CATextLayer()
        iconLayer.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        iconLayer.fontSize = 14
        iconLayer.foregroundColor = ThemeColors.foregroundNSColor(alpha: config.tertiaryTextOpacity).cgColor
        iconLayer.alignmentMode = .center
        iconLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        layer?.addSublayer(iconLayer)

        // Label layer (initially hidden)
        labelLayer = CATextLayer()
        labelLayer.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        labelLayer.fontSize = 11
        labelLayer.foregroundColor = ThemeColors.foregroundNSColor(alpha: config.secondaryTextOpacity).cgColor
        labelLayer.alignmentMode = .left
        labelLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        labelLayer.opacity = 0
        layer?.addSublayer(labelLayer)

        setupInitialLayout()
    }

    private func setupTrackingArea() {
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        // Only update layout on initial setup - don't reset during scroll
        if backgroundLayer.frame.isEmpty {
            setupInitialLayout()
        }
    }

    private func setupInitialLayout() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Use fixed collapsed dimensions for initial layout
        let collapsedWidth = horizontalPadding * 2 + iconSize
        let height = verticalPadding * 2 + iconSize

        // Background - starts collapsed
        backgroundLayer.frame = CGRect(x: 0, y: 0, width: collapsedWidth, height: height)

        // Border - matches collapsed size
        let borderPath = CGPath(roundedRect: CGRect(x: 0.5, y: 0.5, width: collapsedWidth - 1, height: height - 1),
                                cornerWidth: cornerRadius, cornerHeight: cornerRadius,
                                transform: nil)
        borderLayer.path = borderPath
        borderLayer.frame = CGRect(x: 0, y: 0, width: collapsedWidth, height: height)

        // Icon - centered in collapsed button area
        // Use full collapsed width for the text layer so multi-character icons (like "↻↻") center properly
        let iconY = (height - iconSize) / 2
        iconLayer.frame = CGRect(x: 0, y: iconY, width: collapsedWidth, height: iconSize)

        // Label - positioned for when visible (frame doesn't change, only opacity)
        let labelX = horizontalPadding + iconSize + labelSpacing
        let labelY = (height - 14) / 2
        labelLayer.frame = CGRect(x: labelX, y: labelY, width: labelWidth, height: 14)

        CATransaction.commit()
    }

    // MARK: - State Updates

    private func updateIcon() {
        guard selectedIndex < actions.count else { return }
        // Disable animations for instant icon swap during scroll
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        iconLayer.string = actions[selectedIndex].icon
        labelLayer.string = actions[selectedIndex].label
        CATransaction.commit()
    }

    private func updateHoverState(animated: Bool = true) {
        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.15)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
        }

        // Background opacity
        let bgOpacity: CGFloat = showLabel ? config.activeSpaceBgOpacity : (isHovered ? config.hoveredSpaceBgOpacity : config.inactiveSpaceBgOpacity)
        backgroundLayer.backgroundColor = ThemeColors.backgroundNSColor(alpha: bgOpacity).cgColor

        // Border visibility
        borderLayer.opacity = (isHovered || showLabel) ? 1.0 : 0.0

        // Icon brightness
        iconLayer.foregroundColor = ThemeColors.foregroundNSColor(alpha: isHovered ? config.primaryTextOpacity : config.tertiaryTextOpacity).cgColor

        // Scale effect
        let scale: CGFloat = isHovered ? 1.02 : 1.0
        layer?.transform = CATransform3DMakeScale(scale, scale, 1.0)

        CATransaction.commit()
    }

    private func setLabelVisible(_ visible: Bool, animated: Bool = true) {
        guard showLabel != visible else { return }
        showLabel = visible

        // Single transaction for all visibility changes
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.2)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }

        // Label opacity
        labelLayer.opacity = visible ? 1.0 : 0.0

        // Background expansion (only change background frame, not NSView)
        let contentWidth = visible
            ? horizontalPadding * 2 + iconSize + labelSpacing + labelWidth
            : horizontalPadding * 2 + iconSize
        let height = verticalPadding * 2 + iconSize
        backgroundLayer.frame = CGRect(x: 0, y: 0, width: contentWidth, height: height)

        // Update hover-related styling
        let bgOpacity: CGFloat = visible ? config.activeSpaceBgOpacity : (isHovered ? config.hoveredSpaceBgOpacity : config.inactiveSpaceBgOpacity)
        backgroundLayer.backgroundColor = ThemeColors.backgroundNSColor(alpha: bgOpacity).cgColor
        borderLayer.opacity = (isHovered || visible) ? 1.0 : 0.0

        CATransaction.commit()

        // Notify SwiftUI of expansion change so it can animate the layout
        onExpandedChange?(visible)
    }

    // MARK: - Mouse Events

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateHoverState()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateHoverState()
    }

    override func mouseDown(with event: NSEvent) {
        // Execute current action
        guard selectedIndex < actions.count else { return }
        actions[selectedIndex].execute()
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }

    // MARK: - Scroll Handling

    override func scrollWheel(with event: NSEvent) {
        // Ignore momentum phase - only respond to direct user input
        guard event.phase == .began || event.phase == .changed || event.phase == [] else {
            return
        }

        let delta = event.deltaY
        guard abs(delta) > 0.5 else { return }

        // Throttle scroll events to reduce CPU
        let now = CACurrentMediaTime()
        guard now - lastScrollTime >= scrollThrottleInterval else {
            scrollAccumulator += delta  // Still accumulate even if throttled
            return
        }
        lastScrollTime = now

        // Show label while scrolling (only set once)
        if config.expandContextButtonOnScroll && !showLabel {
            setLabelVisible(true)
        }

        // Cancel pending hide (reuse existing work item pattern)
        hideWorkItem?.cancel()

        // Accumulate scroll
        scrollAccumulator += delta

        let steps = Int(scrollAccumulator / scrollThreshold)
        if steps != 0 {
            var newIndex = selectedIndex + steps

            // Wrap around
            if newIndex < 0 {
                newIndex = actions.count + (newIndex % actions.count)
            } else if newIndex >= actions.count {
                newIndex = newIndex % actions.count
            }

            if newIndex != selectedIndex {
                selectedIndex = newIndex
                updateIcon()

                // Haptic feedback
                if config.enableLayoutActionHaptics {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
            }

            scrollAccumulator = 0
        }

        // Schedule label hide - only create new work item if needed
        if config.expandContextButtonOnScroll && showLabel {
            hideWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.setLabelVisible(false)
            }
            hideWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
        }
    }

    // MARK: - Hit Testing

    override func hitTest(_ point: NSPoint) -> NSView? {
        return bounds.contains(point) ? self : nil
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - SwiftUI Wrapper

struct AppKitLayoutActionsButtonWrapper: NSViewRepresentable {
    let viewModel: MenuBarViewModel
    @Binding var isExpanded: Bool
    let onRotate: (Int) -> Void
    let onFlip: (String) -> Void
    let onBalance: () -> Void
    let onToggleLayout: () -> Void
    let onStackAllWindows: () -> Void
    let onSpaceCreate: () -> Void
    let onSpaceDestroy: (Int) -> Void

    func makeNSView(context: Context) -> AppKitLayoutActionsButton {
        let button = AppKitLayoutActionsButton()

        // Configure actions — filter based on window manager capabilities
        var actions: [AppKitLayoutActionsButton.Action] = []
        if viewModel.windowManager.name == "Yabai" {
            // Yabai tree operations
            actions.append(contentsOf: [
                .init(label: "Rotate 90°", icon: "↻", execute: { onRotate(90) }),
                .init(label: "Rotate 180°", icon: "↻↻", execute: { onRotate(180) }),
                .init(label: "Rotate 270°", icon: "↺", execute: { onRotate(270) }),
                .init(label: "Flip Horizontal", icon: "↔", execute: { onFlip("x") }),
                .init(label: "Flip Vertical", icon: "↕", execute: { onFlip("y") }),
                .init(label: "Balance", icon: "⚖", execute: { onBalance() }),
            ])
        } else if viewModel.windowManager.name == "AeroSpace" {
            // AeroSpace supports balance but not rotate/flip
            actions.append(.init(label: "Balance", icon: "⚖", execute: { onBalance() }))
        }
        actions.append(.init(label: "Toggle Layout", icon: "⇄", execute: { onToggleLayout() }))
        if viewModel.windowManager.capabilities.contains(.stackWindows) {
            actions.append(.init(label: "Stack/Unstack", icon: "⧉", execute: { onStackAllWindows() }))
        }
        actions.append(.init(label: "New Space", icon: "+", execute: { onSpaceCreate() }))
        button.configure(actions: actions)

        button.onRightClick = {
            context.coordinator.showContextMenu(button: button)
        }

        // Notify SwiftUI when expansion state changes
        button.onExpandedChange = { expanded in
            DispatchQueue.main.async {
                context.coordinator.parent.isExpanded = expanded
            }
        }

        return button
    }

    func updateNSView(_ nsView: AppKitLayoutActionsButton, context: Context) {
        // No updates needed - AppKit handles everything internally
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator {
        let parent: AppKitLayoutActionsButtonWrapper

        init(parent: AppKitLayoutActionsButtonWrapper) {
            self.parent = parent
        }

        func showContextMenu(button: AppKitLayoutActionsButton) {
            let menu = NSMenu()
            menu.autoenablesItems = false

            let windowManager = parent.viewModel.windowManager
            let spaces = windowManager.getCurrentSpaces()
            let focusedSpaceIndex = windowManager.getFocusedSpaceIndex()
            let focusedSpace = spaces.first(where: { $0.index == focusedSpaceIndex })
            let freshWindows = windowManager.getWindowsForSpace(focusedSpaceIndex)
            let windowCount = freshWindows.count
            let currentLayoutType = focusedSpace?.layoutType.rawValue ?? "bsp"

            // Create menu target
            let menuTarget = LayoutActionsMenuTarget(
                windowManager: windowManager,
                onRotate: parent.onRotate,
                onFlip: parent.onFlip,
                onBalance: parent.onBalance,
                onToggleLayout: parent.onToggleLayout,
                onStackAllWindows: parent.onStackAllWindows,
                onSpaceCreate: parent.onSpaceCreate,
                onSpaceDestroy: parent.onSpaceDestroy
            )

            // Store reference to prevent deallocation
            objc_setAssociatedObject(menu, "menuTarget", menuTarget, .OBJC_ASSOCIATION_RETAIN)

            // MARK: - Layout Actions Section
            var actions: [(String, String, Int)] = []
            if windowManager.name == "Yabai" {
                actions.append(contentsOf: [
                    ("↻", "Rotate 90°", 0),
                    ("↻↻", "Rotate 180°", 1),
                    ("↺", "Rotate 270°", 2),
                    ("↔", "Flip Horizontal", 3),
                    ("↕", "Flip Vertical", 4),
                    ("⚖", "Balance", 5),
                ])
            } else if windowManager.name == "AeroSpace" {
                actions.append(("⚖", "Balance", 5))
            }
            // Rift: no rotate/flip/balance
            if windowManager.capabilities.contains(.stackWindows) {
                actions.append(("⧉", "Stack/Unstack", 7))
            }
            actions.append(("+", "New Space", 8))

            for (icon, label, index) in actions {
                let menuItem = NSMenuItem(title: "\(icon)  \(label)", action: #selector(LayoutActionsMenuTarget.executeAction(_:)), keyEquivalent: "")
                menuItem.target = menuTarget
                menuItem.tag = index
                menuItem.isEnabled = (index != 7) || (windowCount > 1)
                menu.addItem(menuItem)
            }

            // Layout Type Submenu
            let layoutItem = NSMenuItem(title: "⇄  Layout", action: nil, keyEquivalent: "")
            let layoutSubmenu = NSMenu()
            let layoutTypes: [(String, String)]
            if windowManager.name == "Rift" {
                layoutTypes = [("Traditional", "traditional"), ("BSP", "bsp"), ("Stack", "stack"), ("Master-Stack", "master_stack"), ("Scrolling", "scrolling")]
            } else if windowManager.name == "AeroSpace" {
                layoutTypes = [("Tiling", "tiling"), ("Accordion", "accordion"), ("Floating", "floating")]
            } else {
                layoutTypes = [("BSP", "bsp"), ("Float", "float"), ("Stack", "stack")]
            }
            for (label, value) in layoutTypes {
                let item = NSMenuItem(title: label, action: #selector(LayoutActionsMenuTarget.setLayout(_:)), keyEquivalent: "")
                item.target = menuTarget
                item.representedObject = value
                item.state = currentLayoutType == value ? .on : .off
                layoutSubmenu.addItem(item)
            }
            layoutItem.submenu = layoutSubmenu
            menu.addItem(layoutItem)

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
                    spaceItem.representedObject = wsName
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
                for space in spaces {
                    let label = space.label ?? ""
                    let spaceLabel = label.isEmpty ? "\(space.index)" : label
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

            if freshWindows.count >= 2 {
                // Build scaled icons for each window (dimmed for minimized/hidden)
                let iconSize = NSSize(width: 16, height: 16)
                var scaledIcons: [Int: NSImage] = [:]
                for window in freshWindows {
                    if let icon = windowManager.getAppIcon(for: window.app) {
                        let stateOpacity: CGFloat = (window.isMinimized || window.isHidden) ? 0.5 : 1.0
                        let scaled = NSImage(size: iconSize)
                        scaled.lockFocus()
                        icon.draw(in: NSRect(origin: .zero, size: iconSize), from: .zero, operation: .sourceOver, fraction: stateOpacity)
                        if window.isMinimized {
                            if let badge = NSImage(systemSymbolName: "minus.circle.fill", accessibilityDescription: nil) {
                                let config = NSImage.SymbolConfiguration(paletteColors: [.systemYellow])
                                    .applying(.init(pointSize: 7, weight: .bold))
                                let tinted = badge.withSymbolConfiguration(config) ?? badge
                                tinted.draw(in: NSRect(x: 9, y: 0, width: 8, height: 8))
                            }
                        }
                        scaled.unlockFocus()
                        scaledIcons[window.id] = scaled
                    }
                }

                // Helper for window display name
                let displayName: (WMWindow) -> String = { w in
                    w.title.isEmpty ? w.app.components(separatedBy: ".").last ?? w.app : String(w.title.prefix(30))
                }

                // Separate stacked vs unstacked windows
                let stacked = freshWindows.filter { $0.stackIndex > 0 }
                let unstacked = freshWindows.filter { $0.stackIndex == 0 }

                // Group stacked windows by frame proximity
                // Windows in the same stack share nearly identical origins but frames
                // can differ by 10-20+ pixels, so use proximity clustering (100px tolerance)
                var stackGroups: [[WMWindow]] = []
                if !stacked.isEmpty {
                    var remaining = stacked
                    while !remaining.isEmpty {
                        var group = [remaining.removeFirst()]
                        let anchor = group[0].frame ?? .zero
                        var i = 0
                        while i < remaining.count {
                            let f = remaining[i].frame ?? CGRect(x: -9999, y: -9999, width: 0, height: 0)
                            let dx = abs(f.origin.x - anchor.origin.x)
                            let dy = abs(f.origin.y - anchor.origin.y)
                            if dx < 100 && dy < 100 {
                                group.append(remaining.remove(at: i))
                            } else {
                                i += 1
                            }
                        }
                        stackGroups.append(group.sorted { $0.stackIndex < $1.stackIndex })
                    }
                }

                // Show each stack group
                for (groupIndex, group) in stackGroups.enumerated() {
                    let headerItem = NSMenuItem(title: "Stack \(groupIndex + 1)", action: nil, keyEquivalent: "")
                    headerItem.isEnabled = false
                    headerItem.attributedTitle = NSAttributedString(
                        string: "Stack \(groupIndex + 1) (\(group.count) windows)",
                        attributes: [.font: NSFont.boldSystemFont(ofSize: 12)]
                    )
                    stackSubmenu.addItem(headerItem)

                    for window in group {
                        let item = NSMenuItem(
                            title: "  \(displayName(window))",
                            action: #selector(LayoutActionsMenuTarget.unstackStack(_:)),
                            keyEquivalent: ""
                        )
                        item.target = menuTarget
                        item.image = scaledIcons[window.id]
                        item.representedObject = [window.id]
                        stackSubmenu.addItem(item)
                    }

                    // Unstack this group
                    let unstackItem = NSMenuItem(
                        title: "  Unstack This Stack",
                        action: #selector(LayoutActionsMenuTarget.unstackStack(_:)),
                        keyEquivalent: ""
                    )
                    unstackItem.target = menuTarget
                    unstackItem.representedObject = group.map { $0.id }
                    stackSubmenu.addItem(unstackItem)

                    stackSubmenu.addItem(NSMenuItem.separator())
                }

                // Show unstacked windows with stack-to options
                if !unstacked.isEmpty {
                    if !stackGroups.isEmpty {
                        let unHeader = NSMenuItem(title: "Unstacked", action: nil, keyEquivalent: "")
                        unHeader.isEnabled = false
                        unHeader.attributedTitle = NSAttributedString(
                            string: "Unstacked",
                            attributes: [.font: NSFont.boldSystemFont(ofSize: 12)]
                        )
                        stackSubmenu.addItem(unHeader)
                    }

                    for window in unstacked {
                        let windowItem = NSMenuItem(title: displayName(window), action: nil, keyEquivalent: "")
                        windowItem.image = scaledIcons[window.id]

                        // Submenu: stack onto existing stacks or other unstacked windows
                        let windowSubmenu = NSMenu()
                        windowSubmenu.autoenablesItems = false

                        // Stack onto existing stack groups
                        for (groupIndex, group) in stackGroups.enumerated() {
                            if let target = group.first {
                                let item = NSMenuItem(
                                    title: "Stack onto Stack \(groupIndex + 1)",
                                    action: #selector(LayoutActionsMenuTarget.stackWindowOnto(_:)),
                                    keyEquivalent: ""
                                )
                                item.target = menuTarget
                                item.representedObject = ["source": window.id, "target": target.id]
                                windowSubmenu.addItem(item)
                            }
                        }

                        if !stackGroups.isEmpty && unstacked.count > 1 {
                            windowSubmenu.addItem(NSMenuItem.separator())
                        }

                        // Stack with another unstacked window
                        for other in unstacked where other.id != window.id {
                            let item = NSMenuItem(
                                title: "Stack with \(displayName(other))",
                                action: #selector(LayoutActionsMenuTarget.stackWindowOnto(_:)),
                                keyEquivalent: ""
                            )
                            item.target = menuTarget
                            item.image = scaledIcons[other.id]
                            item.representedObject = ["source": window.id, "target": other.id]
                            windowSubmenu.addItem(item)
                        }

                        windowItem.submenu = windowSubmenu
                        stackSubmenu.addItem(windowItem)
                    }
                }

                // Stack All Windows option at the bottom
                if freshWindows.count > 1 {
                    stackSubmenu.addItem(NSMenuItem.separator())
                    let stackAllItem = NSMenuItem(
                        title: "Stack All Windows",
                        action: #selector(LayoutActionsMenuTarget.executeAction(_:)),
                        keyEquivalent: ""
                    )
                    stackAllItem.target = menuTarget
                    stackAllItem.tag = 7
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

            // Show menu
            let location = NSPoint(x: button.bounds.minX, y: button.bounds.minY)
            menu.popUp(positioning: nil, at: location, in: button)
        }
    }
}

// MARK: - AppKit App Launcher Button

/// Pure AppKit button for app launcher with scroll-to-select
final class AppKitAppLauncherButton: NSView {

    // MARK: - Properties

    private var apps: [FloatingApp] = []
    private var selectedIndex: Int = 0
    private var isHovered: Bool = false

    // Callbacks
    var onToggleApp: ((FloatingApp) -> Void)?
    var onRightClick: (() -> Void)?

    // Scroll handling
    private var scrollAccumulator: CGFloat = 0
    private let scrollThreshold: CGFloat = 15  // Higher threshold = fewer updates
    private var lastScrollTime: CFTimeInterval = 0
    private let scrollThrottleInterval: CFTimeInterval = 0.05  // ~20fps max - aggressive throttle

    // Layers
    private var backgroundLayer: CALayer!
    private var borderLayer: CAShapeLayer!
    private var iconLayer: CALayer!
    private var dotLayer: CALayer!

    // Layout constants
    private let cornerRadius: CGFloat = 8
    private let horizontalPadding: CGFloat = 7
    private let verticalPadding: CGFloat = 4
    private let iconSize: CGFloat = 18

    private let config = AegisConfig.shared
    private var themeObserver: NSObjectProtocol?
    private var configCancellable: AnyCancellable?

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
        setupTrackingArea()
        setupThemeObserver()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
        setupTrackingArea()
        setupThemeObserver()
    }

    deinit {
        if let observer = themeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupThemeObserver() {
        themeObserver = NotificationCenter.default.addObserver(
            forName: .themeDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateColors()
        }
        configCancellable = config.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateColors()
            }
    }

    private func updateColors() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backgroundLayer.backgroundColor = ThemeColors.backgroundNSColor(alpha: config.inactiveSpaceBgOpacity).cgColor
        borderLayer.strokeColor = ThemeColors.foregroundNSColor(alpha: config.activeBorderOpacity).cgColor
        dotLayer.backgroundColor = ThemeColors.foregroundNSColor(alpha: 1.0).cgColor
        CATransaction.commit()
    }

    func configure(apps: [FloatingApp]) {
        self.apps = apps
        updateIcon()
    }

    func setFocused(_ focused: Bool) {
        let targetOpacity: Float = focused ? 1.0 : 0.0
        guard dotLayer.opacity != targetOpacity else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        dotLayer.opacity = targetOpacity
        CATransaction.commit()
    }

    // MARK: - Layer Setup

    private func setupLayers() {
        wantsLayer = true
        layer?.masksToBounds = false

        let width = horizontalPadding * 2 + iconSize
        let height = verticalPadding * 2 + iconSize
        frame.size = NSSize(width: width, height: height)

        // Background layer
        backgroundLayer = CALayer()
        backgroundLayer.cornerRadius = cornerRadius
        backgroundLayer.backgroundColor = ThemeColors.backgroundNSColor(alpha: config.inactiveSpaceBgOpacity).cgColor
        backgroundLayer.frame = bounds
        layer?.addSublayer(backgroundLayer)

        // Border layer
        borderLayer = CAShapeLayer()
        borderLayer.fillColor = nil
        borderLayer.strokeColor = ThemeColors.foregroundNSColor(alpha: config.activeBorderOpacity).cgColor
        borderLayer.lineWidth = 1
        borderLayer.opacity = 0
        let borderPath = CGPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                cornerWidth: cornerRadius, cornerHeight: cornerRadius,
                                transform: nil)
        borderLayer.path = borderPath
        borderLayer.frame = bounds
        layer?.addSublayer(borderLayer)

        // Icon layer
        iconLayer = CALayer()
        iconLayer.contentsGravity = .resizeAspect
        iconLayer.frame = CGRect(x: horizontalPadding, y: verticalPadding, width: iconSize, height: iconSize)
        layer?.addSublayer(iconLayer)

        // Initial opacity
        iconLayer.opacity = 0.7

        // Focus dot layer (matches space indicator dot style)
        dotLayer = CALayer()
        dotLayer.backgroundColor = ThemeColors.foregroundNSColor(alpha: 1.0).cgColor
        dotLayer.cornerRadius = 1.5
        dotLayer.frame = CGRect(x: (bounds.width - 3) / 2, y: -1.5, width: 3, height: 3)
        dotLayer.opacity = 0
        layer?.addSublayer(dotLayer)
    }

    private func setupTrackingArea() {
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    // MARK: - State Updates

    private func updateIcon() {
        guard selectedIndex < apps.count else { return }
        // Disable animations for instant icon swap during scroll
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        iconLayer.contents = apps[selectedIndex].icon
        CATransaction.commit()
    }

    /// Select app by index and update icon (used by context menu)
    func selectApp(at index: Int) {
        guard index >= 0 && index < apps.count else { return }
        selectedIndex = index
        updateIcon()
    }

    private func updateHoverState() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.1)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))

        // Background
        backgroundLayer.backgroundColor = ThemeColors.backgroundNSColor(alpha: isHovered ? config.hoveredSpaceBgOpacity : config.inactiveSpaceBgOpacity).cgColor

        // Border
        borderLayer.opacity = isHovered ? 1.0 : 0.0

        // Icon opacity
        iconLayer.opacity = isHovered ? 1.0 : 0.7

        // Scale
        let scale: CGFloat = isHovered ? 1.02 : 1.0
        layer?.transform = CATransform3DMakeScale(scale, scale, 1.0)

        CATransaction.commit()
    }

    // MARK: - Mouse Events

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateHoverState()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateHoverState()
    }

    override func mouseDown(with event: NSEvent) {
        guard selectedIndex < apps.count else { return }
        onToggleApp?(apps[selectedIndex])
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }

    // MARK: - Scroll Handling

    override func scrollWheel(with event: NSEvent) {
        guard event.phase == .began || event.phase == .changed || event.phase == [] else {
            return
        }

        let delta = event.deltaY
        guard abs(delta) > 0.5 else { return }

        // Throttle scroll events to reduce CPU
        let now = CACurrentMediaTime()
        guard now - lastScrollTime >= scrollThrottleInterval else {
            scrollAccumulator += delta  // Still accumulate even if throttled
            return
        }
        lastScrollTime = now

        scrollAccumulator += delta

        let steps = Int(scrollAccumulator / scrollThreshold)
        if steps != 0 {
            var newIndex = selectedIndex + steps

            // Wrap around
            if newIndex < 0 {
                newIndex = apps.count + (newIndex % apps.count)
            } else if newIndex >= apps.count {
                newIndex = newIndex % apps.count
            }

            if newIndex != selectedIndex {
                selectedIndex = newIndex
                updateIcon()

                if config.enableLayoutActionHaptics {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
            }

            scrollAccumulator = 0
        }
    }

    // MARK: - Hit Testing

    override func hitTest(_ point: NSPoint) -> NSView? {
        return bounds.contains(point) ? self : nil
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - Tooltip

    override var toolTip: String? {
        get {
            guard selectedIndex < apps.count else { return nil }
            return "Toggle \(apps[selectedIndex].name) (scroll to change)"
        }
        set { }
    }
}

// MARK: - SwiftUI Wrapper

struct AppKitAppLauncherButtonWrapper: NSViewRepresentable {
    let apps: [FloatingApp]
    let onToggleApp: (FloatingApp) -> Void
    var isAppFocused: Bool = false

    func makeNSView(context: Context) -> AppKitAppLauncherButton {
        let button = AppKitAppLauncherButton()
        button.configure(apps: apps)
        button.onToggleApp = onToggleApp
        button.onRightClick = {
            context.coordinator.showContextMenu(button: button)
        }
        return button
    }

    func updateNSView(_ nsView: AppKitAppLauncherButton, context: Context) {
        // Reconfigure if apps list changes
        nsView.configure(apps: apps)
        nsView.setFocused(isAppFocused)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator {
        let parent: AppKitAppLauncherButtonWrapper

        init(parent: AppKitAppLauncherButtonWrapper) {
            self.parent = parent
        }

        func showContextMenu(button: AppKitAppLauncherButton) {
            // Get fresh apps list from config (not cached parent.apps)
            let apps = FloatingApp.appsFromConfig()

            let menu = NSMenu()
            menu.autoenablesItems = false

            let menuTarget = LauncherMenuTarget(
                apps: apps,
                onToggleApp: parent.onToggleApp,
                button: button
            )

            // Store reference to prevent deallocation
            objc_setAssociatedObject(menu, "menuTarget", menuTarget, .OBJC_ASSOCIATION_RETAIN)

            // Add each configured app with its icon
            for (index, app) in apps.enumerated() {
                let menuItem = NSMenuItem(
                    title: app.name,
                    action: #selector(LauncherMenuTarget.launchApp(_:)),
                    keyEquivalent: ""
                )
                menuItem.target = menuTarget
                menuItem.tag = index
                menuItem.image = app.icon
                menuItem.image?.size = NSSize(width: 16, height: 16)
                menu.addItem(menuItem)
            }

            menu.addItem(NSMenuItem.separator())

            // Add App option
            let addItem = NSMenuItem(
                title: "Add App...",
                action: #selector(LauncherMenuTarget.addApp),
                keyEquivalent: ""
            )
            addItem.target = menuTarget
            menu.addItem(addItem)

            // Remove App submenu (only if there are apps to remove)
            if !apps.isEmpty {
                let removeItem = NSMenuItem(title: "Remove App", action: nil, keyEquivalent: "")
                let removeSubmenu = NSMenu()
                for (index, app) in apps.enumerated() {
                    let item = NSMenuItem(
                        title: app.name,
                        action: #selector(LauncherMenuTarget.removeApp(_:)),
                        keyEquivalent: ""
                    )
                    item.target = menuTarget
                    item.tag = index
                    item.image = app.icon
                    item.image?.size = NSSize(width: 16, height: 16)
                    removeSubmenu.addItem(item)
                }
                removeItem.submenu = removeSubmenu
                menu.addItem(removeItem)
            }

            // Show the menu
            let location = NSPoint(x: 0, y: button.bounds.height + 4)
            menu.popUp(positioning: nil, at: location, in: button)
        }
    }
}

// MARK: - Launcher Menu Target

/// Target for app launcher context menu actions
private class LauncherMenuTarget: NSObject {
    let apps: [FloatingApp]
    let onToggleApp: (FloatingApp) -> Void
    weak var button: AppKitAppLauncherButton?

    init(apps: [FloatingApp], onToggleApp: @escaping (FloatingApp) -> Void, button: AppKitAppLauncherButton) {
        self.apps = apps
        self.onToggleApp = onToggleApp
        self.button = button
        super.init()
    }

    @objc func launchApp(_ sender: NSMenuItem) {
        guard sender.tag < apps.count else { return }
        // Update the button's displayed icon to match the launched app
        button?.selectApp(at: sender.tag)
        onToggleApp(apps[sender.tag])
    }

    @objc func addApp() {
        // Open file picker to select an app
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Select an application to add to the launcher"
        panel.prompt = "Add"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            // Get bundle identifier from the app
            guard let bundle = Bundle(url: url),
                  let bundleId = bundle.bundleIdentifier else {
                // Show error alert
                let alert = NSAlert()
                alert.messageText = "Invalid Application"
                alert.informativeText = "Could not read bundle identifier from the selected application."
                alert.alertStyle = .warning
                alert.runModal()
                return
            }

            // Check if already in list
            let config = AegisConfig.shared
            if config.launcherApps.contains(bundleId) {
                let alert = NSAlert()
                alert.messageText = "Already Added"
                alert.informativeText = "\(url.deletingPathExtension().lastPathComponent) is already in the launcher."
                alert.alertStyle = .informational
                alert.runModal()
                return
            }

            // Add to config
            config.launcherApps.append(bundleId)
            config.savePreferences()
        }
    }

    @objc func removeApp(_ sender: NSMenuItem) {
        guard sender.tag < apps.count else { return }
        let app = apps[sender.tag]

        let config = AegisConfig.shared
        config.launcherApps.removeAll { $0 == app.bundleIdentifier }
        config.savePreferences()
    }
}
