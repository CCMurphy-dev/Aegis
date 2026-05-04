import Cocoa
import SwiftUI

// MARK: - MenuBarCoordinator
// Main coordinator that manages all menu bar components

class MenuBarCoordinator {
    private let windowManager: WindowManagerProtocol
    private let eventRouter: EventRouter
    private let floatingAppController: FloatingAppController

    private let windowController: MenuBarWindowController
    private let interactionMonitor: MenuBarInteractionMonitor
    private var viewModel: MenuBarViewModel?

    /// Display index this coordinator is associated with (nil = primary only)
    private let displayIndex: Int?

    /// Screen to display the menu bar on (nil = NSScreen.main)
    private let targetScreen: NSScreen?

    /// Space filter mode for this coordinator
    private let spaceFilterMode: MenuBarViewModel.SpaceFilterMode

    /// Suppress window reorder after drag-initiated space moves (prevents flash from orderFront)
    private var suppressReorderUntil: Date = .distantPast


    init(windowManager: WindowManagerProtocol,
         eventRouter: EventRouter,
         displayIndex: Int? = nil,
         targetScreen: NSScreen? = nil,
         spaceFilterMode: MenuBarViewModel.SpaceFilterMode = .all) {
        self.windowManager = windowManager
        self.eventRouter = eventRouter
        self.displayIndex = displayIndex
        self.targetScreen = targetScreen
        self.spaceFilterMode = spaceFilterMode
        self.floatingAppController = FloatingAppController(windowManager: windowManager)
        self.windowController = MenuBarWindowController()
        self.interactionMonitor = MenuBarInteractionMonitor()
    }

    // MARK: - Show/Hide

    func show() {
        // Create ViewModel with display-specific settings
        let vm = MenuBarViewModel(windowManager: windowManager, targetScreen: targetScreen)
        vm.displayIndex = displayIndex
        vm.spaceFilterMode = spaceFilterMode
        viewModel = vm

        // SwiftUI content with action handlers
        let contentView = MenuBarView(
            viewModel: vm,
            onSpaceClick: { [weak self] index in
                self?.windowManager.focusSpace(index)
            },
            onWindowClick: { [weak self] windowId in
                self?.windowManager.focusWindow(windowId)
            },
            onSpaceDestroy: { [weak self] index in
                self?.windowManager.destroySpace(index)
            },
            onSpaceCreate: { [weak self] in
                self?.windowManager.createSpace()
            },
            onWindowDrop: { [weak self] windowId, targetSpaceIndex, insertBeforeWindowId, shouldStack in
                guard let self = self else { return }

                // Get the current space of the window before moving
                let sourceSpaceIndex = self.windowManager.getWindowSpace(windowId)

                self.windowManager.moveWindowToSpace(windowId, spaceIndex: targetSpaceIndex, insertBeforeWindowId: insertBeforeWindowId, shouldStack: shouldStack)

                // If moving to a different space, follow the window
                if let sourceSpace = sourceSpaceIndex, sourceSpace != targetSpaceIndex {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self.windowManager.focusSpace(targetSpaceIndex)
                    }
                }
            },
            onSpaceMove: { [weak self] fromIndex, toIndex in
                guard let self = self else { return }
                guard self.windowManager.capabilities.contains(.reorderSpaces) else { return }
                // Optimistically reorder spaceIds + update display indices
                // (caller wraps in animation-disabled transaction)
                self.viewModel?.spaceStore.reorderSpace(fromDisplayIndex: fromIndex, toDisplayIndex: toIndex)
                // Suppress orderFront during the WM-triggered space refresh
                self.suppressReorderUntil = Date().addingTimeInterval(1.0)
                // Then tell the WM to actually move the space
                self.windowManager.moveSpace(from: fromIndex, to: toIndex)
            },
            onRotateLayout: { [weak self] degrees in
                self?.windowManager.rotateLayout(degrees)
            },
            onFlipLayout: { [weak self] axis in
                self?.windowManager.flipLayout(axis: axis)
            },
            onBalanceLayout: { [weak self] in
                self?.windowManager.balanceLayout()
            },
            onToggleLayout: { [weak self] in
                self?.windowManager.toggleLayout()
            },
            onStackAllWindows: { [weak self] in
                self?.windowManager.toggleStackAllWindows()
            },
            onToggleApp: { [weak self] app in
                self?.floatingAppController.toggle(app)
            }
        )

        // Create window with content on the target screen
        windowController.createWindow(with: contentView, for: targetScreen)

        // Wire up fullscreen state callback (fires after performUpdate completes)
        vm.onFullscreenStateChanged = { [weak self] isFullscreen in
            self?.windowController.updateVisibilityForSpace(isFullscreen: isFullscreen)
        }

        // Trigger initial update to compute fullscreen state
        updateSpaces()

        // Start monitoring native menu bar only (not mouse position)
        interactionMonitor.startMonitoring { [weak self] nativeMenuActive in
            self?.windowController.setVisibilityForNativeMenu(nativeMenuActive)
        }
    }

    func hide() {
        interactionMonitor.stopMonitoring()
        windowController.hide()
        viewModel = nil
    }

    // MARK: - Public update methods

    func updateSpaces() {
        viewModel?.updateSpaces()

        // Re-order window to ensure visibility during space transitions
        // Skip during drag-initiated space moves (orderFront causes white flash)
        if Date() >= suppressReorderUntil {
            windowController.reorderWindowForSpaceTransition()
        }
    }

    func updateWindows() {
        viewModel?.refreshWindowIcons()
    }

    // MARK: - Fullscreen State

    /// Current fullscreen state of this coordinator's display (for snapshot before rebuild)
    var isCurrentlyFullscreen: Bool { windowController.isInFullscreenSpace }

    /// Immediately apply a known fullscreen state to the window and seed the VM
    /// so the next yabai poll correctly diffs from this baseline.
    func seedFullscreenState(_ isFullscreen: Bool) {
        viewModel?.seedFullscreenState(isFullscreen)
        windowController.updateVisibilityForSpace(isFullscreen: isFullscreen)
    }

    // MARK: - Notch HUD Integration

    func connectHUDVisibility(from hudController: NotchHUDController) {
        viewModel?.observeHUDVisibility(from: hudController)

        // Also connect the HUD controller to the view model for layout coordination
        if let viewModel = viewModel {
            hudController.connectMenuBarViewModel(viewModel)
        }

        // Connect fullscreen state observation so media HUD hides with menu bar
        hudController.observeFullscreenState(from: windowController)
    }
}
