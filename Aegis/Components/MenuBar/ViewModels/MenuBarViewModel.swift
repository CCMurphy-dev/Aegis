import SwiftUI
import AppKit
import Combine

// MARK: - Menu Bar ViewModel
// State-only view model for menu bar data

class MenuBarViewModel: ObservableObject {
    @Published var spaces: [Space] = []
    @Published var windowIconsBySpace: [Int: [WindowIcon]] = [:]  // Window icons keyed by space index
    @Published var windowIconsVersion: Int = 0  // Increment to force UI refresh
    @Published var isHUDVisible: Bool = false  // Tracks notch HUD visibility
    @Published var hudLayoutCoordinator: HUDLayoutCoordinator?  // Manages HUD module layout

    let yabaiService: YabaiService  // Made public for context menu
    private var updateTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(yabaiService: YabaiService) {
        self.yabaiService = yabaiService

        // Initial load
        updateSpaces()

        // Initialize HUD layout coordinator with screen dimensions
        if let screen = NSScreen.main {
            let notchDimensions = NotchDimensions.calculate(for: screen)
            self.hudLayoutCoordinator = HUDLayoutCoordinator(
                notchDimensions: notchDimensions,
                screenWidth: screen.frame.width
            )
        }

        // Backup polling every 10 seconds
        updateTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.updateSpaces()
        }
    }

    deinit {
        updateTimer?.invalidate()
    }

    // MARK: - Update methods

    func updateSpaces() {
        spaces = yabaiService.getCurrentSpaces()

        // Also update window icons when spaces change
        var newIconsBySpace: [Int: [WindowIcon]] = [:]
        for space in spaces {
            newIconsBySpace[space.index] = yabaiService.getWindowIconsForSpace(space.index)
        }
        windowIconsBySpace = newIconsBySpace
    }

    func refreshWindowIcons() {
        // Ensure we're on main thread for @Published updates
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            print("🔄 ViewModel refreshWindowIcons() - about to update")

            // Trigger SwiftUI update for app icons
            self.spaces = self.yabaiService.getCurrentSpaces()

            // Rebuild window icons dictionary for all spaces
            var newIconsBySpace: [Int: [WindowIcon]] = [:]
            for space in self.spaces {
                let icons = self.yabaiService.getWindowIconsForSpace(space.index)
                newIconsBySpace[space.index] = icons
                let windowIds = icons.map { String($0.id) }.joined(separator: ", ")
                print("   - Space \(space.index): \(icons.count) icons in order: [\(windowIds)]")
            }

            // Update @Published property with animation
            withAnimation(.easeInOut(duration: 0.3)) {
                self.windowIconsBySpace = newIconsBySpace
                self.windowIconsVersion += 1
            }

            print("🔄 ViewModel refreshed window icons (version \(self.windowIconsVersion))")
            print("✅ ViewModel update complete")
        }
    }

    func getWindowIcons(for space: Space) -> [WindowIcon] {
        // Return from @Published dictionary
        let icons = windowIconsBySpace[space.index] ?? []
        let windowIds = icons.map { String($0.id) }.joined(separator: ", ")
        print("🎨 getWindowIcons called for space \(space.index), returning \(icons.count) icons in order: [\(windowIds)]")
        return icons
    }

    func getAllWindowIcons(for space: Space) -> [WindowIcon] {
        return yabaiService.getWindowIconsForSpace(space.index)
    }

    func getAppIcons(for space: Space) -> [NSImage] {
        return yabaiService.getAppIconsForSpace(space.index)
    }

    // MARK: - Notch HUD Integration

    /// Connect to NotchHUDController to observe HUD visibility
    func observeHUDVisibility(from hudController: NotchHUDController) {
        // Observe both music and overlay HUD visibility
        // HUD is visible if either music OR overlay is visible
        Publishers.CombineLatest(
            hudController.$isMusicHUDVisible,
            hudController.$isOverlayHUDVisible
        )
        .map { musicVisible, overlayVisible in
            musicVisible || overlayVisible
        }
        .receive(on: DispatchQueue.main)
        .assign(to: &$isHUDVisible)
    }
}
