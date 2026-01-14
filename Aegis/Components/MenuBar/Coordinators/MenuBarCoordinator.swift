import Cocoa
import SwiftUI

// MARK: - MenuBarCoordinator
// Main coordinator that manages all menu bar components

class MenuBarCoordinator {
    private let yabaiService: YabaiService
    private let eventRouter: EventRouter

    private let windowController: MenuBarWindowController
    private let interactionMonitor: MenuBarInteractionMonitor
    private var viewModel: MenuBarViewModel?

    init(yabaiService: YabaiService, eventRouter: EventRouter) {
        self.yabaiService = yabaiService
        self.eventRouter = eventRouter
        self.windowController = MenuBarWindowController()
        self.interactionMonitor = MenuBarInteractionMonitor()
    }

    // MARK: - Show/Hide

    func show() {
        // Create ViewModel
        viewModel = MenuBarViewModel(yabaiService: yabaiService)

        // SwiftUI content with action handlers
        let contentView = MenuBarView(
            viewModel: viewModel!,
            onSpaceClick: { [weak self] index in
                self?.yabaiService.focusSpace(index)
            },
            onWindowClick: { [weak self] windowId in
                print("📍 MenuBarCoordinator: Requesting focus for window \(windowId)")
                self?.yabaiService.focusWindow(windowId)
            },
            onSpaceDestroy: { [weak self] index in
                self?.yabaiService.destroySpace(index)
            },
            onSpaceCreate: { [weak self] in
                self?.yabaiService.createSpace()
            },
            onWindowDrop: { [weak self] windowId, targetSpaceIndex, insertBeforeWindowId, shouldStack in
                guard let self = self else { return }

                // Get the current space of the window before moving
                let sourceSpaceIndex = self.yabaiService.getWindowSpace(windowId)

                if shouldStack {
                    print("📦 Drop: Stacking window \(windowId) with \(insertBeforeWindowId?.description ?? "unknown") in space \(targetSpaceIndex)")
                } else {
                    print("📦 Drop: Moving window \(windowId) to space \(targetSpaceIndex), insertBefore: \(insertBeforeWindowId?.description ?? "end")")
                }

                self.yabaiService.moveWindowToSpace(windowId, spaceIndex: targetSpaceIndex, insertBeforeWindowId: insertBeforeWindowId, shouldStack: shouldStack)

                // If moving to a different space, follow the window
                if let sourceSpace = sourceSpaceIndex, sourceSpace != targetSpaceIndex {
                    print("🎯 Following window to space \(targetSpaceIndex)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self.yabaiService.focusSpace(targetSpaceIndex)
                    }
                }
            },
            onRotateLayout: { [weak self] degrees in
                self?.yabaiService.rotateLayout(degrees)
            },
            onFlipLayout: { [weak self] axis in
                self?.yabaiService.flipLayout(axis: axis)
            },
            onBalanceLayout: { [weak self] in
                self?.yabaiService.balanceLayout()
            },
            onToggleLayout: { [weak self] in
                self?.yabaiService.toggleLayout()
            },
            onStackAllWindows: { [weak self] in
                self?.yabaiService.toggleStackAllWindowsInCurrentSpace()
            }
        )

        // Create window with content
        windowController.createWindow(with: contentView)

        // Check initial space fullscreen status
        checkAndUpdateFullscreenStatus()

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

    // MARK: - Space Change Handling

    private func checkAndUpdateFullscreenStatus() {
        let spaces = yabaiService.getCurrentSpaces()
        if let focusedSpace = spaces.first(where: { $0.focused }) {
            // Check both yabai fullscreen and native macOS fullscreen
            let isYabaiFullscreen = focusedSpace.type == "fullscreen"

            // Check if any window in the current space is in native fullscreen
            let windowIcons = yabaiService.getWindowIconsForSpace(focusedSpace.index)
            let hasNativeFullscreen = windowIcons.contains { window in
                // Get the full WindowInfo to check isNativeFullscreen
                if let windowInfo = yabaiService.getWindow(window.id) {
                    return windowInfo.isNativeFullscreen
                }
                return false
            }

            let isFullscreen = isYabaiFullscreen || hasNativeFullscreen
            windowController.updateVisibilityForSpace(isFullscreen: isFullscreen)
        }
    }

    // MARK: - Public update methods

    func updateSpaces() {
        viewModel?.updateSpaces()

        // CRITICAL: Check fullscreen status whenever spaces change
        checkAndUpdateFullscreenStatus()
    }

    func updateWindows() {
        viewModel?.refreshWindowIcons()
    }

    // MARK: - Notch HUD Integration

    func connectHUDVisibility(from hudController: NotchHUDController) {
        viewModel?.observeHUDVisibility(from: hudController)

        // Also connect the HUD controller to the view model for layout coordination
        if let viewModel = viewModel {
            hudController.connectMenuBarViewModel(viewModel)
        }
    }
}
