//
//  AppKitActionButton.swift
//  Aegis
//
//  Pure AppKit implementation of the Layout Actions button.
//  Bypasses SwiftUI entirely for scroll interactions to minimize CPU usage.
//

import AppKit
import SwiftUI

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

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
        setupTrackingArea()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
        setupTrackingArea()
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
        backgroundLayer.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        layer?.addSublayer(backgroundLayer)

        // Border layer
        borderLayer = CAShapeLayer()
        borderLayer.fillColor = nil
        borderLayer.strokeColor = NSColor.white.withAlphaComponent(0.18).cgColor
        borderLayer.lineWidth = 1
        borderLayer.opacity = 0
        layer?.addSublayer(borderLayer)

        // Icon layer
        iconLayer = CATextLayer()
        iconLayer.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        iconLayer.fontSize = 14
        iconLayer.foregroundColor = NSColor.white.withAlphaComponent(0.6).cgColor
        iconLayer.alignmentMode = .center
        iconLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        layer?.addSublayer(iconLayer)

        // Label layer (initially hidden)
        labelLayer = CATextLayer()
        labelLayer.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        labelLayer.fontSize = 11
        labelLayer.foregroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
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
        let bgOpacity: CGFloat = showLabel ? 0.2 : (isHovered ? 0.15 : 0.12)
        backgroundLayer.backgroundColor = NSColor.white.withAlphaComponent(bgOpacity).cgColor

        // Border visibility
        borderLayer.opacity = (isHovered || showLabel) ? 1.0 : 0.0

        // Icon brightness
        iconLayer.foregroundColor = NSColor.white.withAlphaComponent(isHovered ? 1.0 : 0.6).cgColor

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
        let bgOpacity: CGFloat = visible ? 0.2 : (isHovered ? 0.15 : 0.12)
        backgroundLayer.backgroundColor = NSColor.white.withAlphaComponent(bgOpacity).cgColor
        borderLayer.opacity = (isHovered || visible) ? 1.0 : 0.0

        CATransaction.commit()
        // No SwiftUI callback - expansion is handled purely in AppKit layers
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
    let onRotate: (Int) -> Void
    let onFlip: (String) -> Void
    let onBalance: () -> Void
    let onToggleLayout: () -> Void
    let onStackAllWindows: () -> Void
    let onSpaceCreate: () -> Void
    let onSpaceDestroy: (Int) -> Void

    func makeNSView(context: Context) -> AppKitLayoutActionsButton {
        let button = AppKitLayoutActionsButton()

        // Configure actions
        let actions: [AppKitLayoutActionsButton.Action] = [
            .init(label: "Rotate 90°", icon: "↻", execute: { onRotate(90) }),
            .init(label: "Rotate 180°", icon: "↻↻", execute: { onRotate(180) }),
            .init(label: "Rotate 270°", icon: "↺", execute: { onRotate(270) }),
            .init(label: "Flip Horizontal", icon: "↔", execute: { onFlip("x") }),
            .init(label: "Flip Vertical", icon: "↕", execute: { onFlip("y") }),
            .init(label: "Balance", icon: "⚖", execute: { onBalance() }),
            .init(label: "Toggle Layout", icon: "⇄", execute: { onToggleLayout() }),
            .init(label: "Stack/Unstack", icon: "⧉", execute: { onStackAllWindows() }),
            .init(label: "New Space", icon: "+", execute: { onSpaceCreate() })
        ]
        button.configure(actions: actions)

        button.onRightClick = {
            context.coordinator.showContextMenu(button: button)
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

            let yabaiService = parent.viewModel.yabaiService
            let spaces = yabaiService.getCurrentSpaces()
            let focusedSpaceIndex = yabaiService.getFocusedSpaceIndexSync()
            let focusedSpace = spaces.first(where: { $0.index == focusedSpaceIndex })
            let windowCount = focusedSpace.map { yabaiService.getWindowIconsForSpace($0.index).count } ?? 0
            let currentLayoutType = focusedSpace?.type ?? "bsp"

            // Create menu target
            let menuTarget = LayoutActionsMenuTarget(
                yabaiService: yabaiService,
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
            let actions: [(String, String, Int)] = [
                ("↻", "Rotate 90°", 0),
                ("↻↻", "Rotate 180°", 1),
                ("↺", "Rotate 270°", 2),
                ("↔", "Flip Horizontal", 3),
                ("↕", "Flip Vertical", 4),
                ("⚖", "Balance", 5),
                ("⧉", "Stack/Unstack", 7),
                ("+", "New Space", 8)
            ]

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
            let layoutTypes = [("BSP", "bsp"), ("Float", "float"), ("Stack", "stack")]
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

            for space in spaces {
                let spaceItem = NSMenuItem(title: "Space \(space.index)", action: #selector(LayoutActionsMenuTarget.sendToSpace(_:)), keyEquivalent: "")
                spaceItem.target = menuTarget
                spaceItem.representedObject = space.index
                spaceItem.isEnabled = windowCount > 0
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

            let spaceWindows = focusedSpace.map { yabaiService.getWindowIconsForSpace($0.index) } ?? []

            if spaceWindows.count >= 2 {
                let iconSize = NSSize(width: 16, height: 16)
                var scaledIcons: [Int: NSImage] = [:]
                for window in spaceWindows {
                    if let icon = window.icon {
                        let scaled = NSImage(size: iconSize)
                        scaled.lockFocus()
                        icon.draw(in: NSRect(origin: .zero, size: iconSize))
                        scaled.unlockFocus()
                        scaledIcons[window.id] = scaled
                    }
                }

                for targetWindow in spaceWindows {
                    let targetTitle = targetWindow.title.isEmpty ? targetWindow.appName : String(targetWindow.title.prefix(30))
                    let targetItem = NSMenuItem(title: targetTitle, action: nil, keyEquivalent: "")
                    targetItem.image = scaledIcons[targetWindow.id]

                    let windowsToStackSubmenu = NSMenu()
                    windowsToStackSubmenu.autoenablesItems = false

                    for sourceWindow in spaceWindows where sourceWindow.id != targetWindow.id {
                        let sourceTitle = sourceWindow.title.isEmpty ? sourceWindow.appName : String(sourceWindow.title.prefix(40))
                        let sourceItem = NSMenuItem(
                            title: sourceTitle,
                            action: #selector(LayoutActionsMenuTarget.stackWindowOnto(_:)),
                            keyEquivalent: ""
                        )
                        sourceItem.target = menuTarget
                        sourceItem.image = scaledIcons[sourceWindow.id]
                        sourceItem.representedObject = ["source": sourceWindow.id, "target": targetWindow.id]
                        windowsToStackSubmenu.addItem(sourceItem)
                    }

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

            let yabaiVersion = yabaiService.getYabaiVersion()
            let yabaiVersionItem = NSMenuItem(title: "  Yabai: v\(yabaiVersion)", action: nil, keyEquivalent: "")
            yabaiVersionItem.isEnabled = false
            menu.addItem(yabaiVersionItem)

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

            let aegisVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
            let aegisVersionItem = NSMenuItem(title: "  Aegis: v\(aegisVersion)", action: nil, keyEquivalent: "")
            aegisVersionItem.isEnabled = false
            menu.addItem(aegisVersionItem)

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

    // Callback
    var onToggleApp: ((FloatingApp) -> Void)?

    // Scroll handling
    private var scrollAccumulator: CGFloat = 0
    private let scrollThreshold: CGFloat = 15  // Higher threshold = fewer updates
    private var lastScrollTime: CFTimeInterval = 0
    private let scrollThrottleInterval: CFTimeInterval = 0.05  // ~20fps max - aggressive throttle

    // Layers
    private var backgroundLayer: CALayer!
    private var borderLayer: CAShapeLayer!
    private var iconLayer: CALayer!

    // Layout constants
    private let cornerRadius: CGFloat = 8
    private let horizontalPadding: CGFloat = 7
    private let verticalPadding: CGFloat = 4
    private let iconSize: CGFloat = 18

    private let config = AegisConfig.shared

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
        setupTrackingArea()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
        setupTrackingArea()
    }

    func configure(apps: [FloatingApp]) {
        self.apps = apps
        updateIcon()
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
        backgroundLayer.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        backgroundLayer.frame = bounds
        layer?.addSublayer(backgroundLayer)

        // Border layer
        borderLayer = CAShapeLayer()
        borderLayer.fillColor = nil
        borderLayer.strokeColor = NSColor.white.withAlphaComponent(0.2).cgColor
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

    private func updateHoverState() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.1)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))

        // Background
        backgroundLayer.backgroundColor = NSColor.white.withAlphaComponent(isHovered ? 0.18 : 0.12).cgColor

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

    func makeNSView(context: Context) -> AppKitAppLauncherButton {
        let button = AppKitAppLauncherButton()
        button.configure(apps: apps)
        button.onToggleApp = onToggleApp
        return button
    }

    func updateNSView(_ nsView: AppKitAppLauncherButton, context: Context) {
        // Apps list doesn't change at runtime
    }
}
