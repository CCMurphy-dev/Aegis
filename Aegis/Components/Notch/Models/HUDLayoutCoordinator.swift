//
//  HUDLayoutCoordinator.swift
//  Aegis
//
//  Created by Claude on 14/01/2026.
//

import SwiftUI
import Combine

/// Represents a single HUD module that can be displayed
struct HUDModule: Identifiable {
    let id: String
    let type: HUDModuleType
    var width: CGFloat
    var isVisible: Bool

    enum HUDModuleType: String {
        case music
        case volume
        case brightness
    }
}

/// Coordinates the layout of multiple HUD modules and manages their interaction with the menu bar
class HUDLayoutCoordinator: ObservableObject {
    // MARK: - Published Properties

    /// Active HUD modules currently displayed
    @Published var activeModules: [HUDModule] = []

    /// Total width occupied by all HUD modules (including notch)
    @Published var totalHUDWidth: CGFloat = 0

    /// Offset to apply to space indicators (push effect)
    @Published var spaceIndicatorOffset: CGFloat = 0

    /// Whether the HUD is currently occluding the notch area
    @Published var isOccludingNotch: Bool = false

    /// Version counter to force view updates
    @Published var layoutVersion: Int = 0

    // MARK: - Public Properties (for external access)

    /// The actual notch width from screen measurements
    var notchWidth: CGFloat {
        return notchDimensions.width
    }

    // MARK: - Private Properties

    private let notchDimensions: NotchDimensions
    private let screenWidth: CGFloat

    // Constants
    private let moduleSpacing: CGFloat = 12  // Space between adjacent modules
    private let minSpaceToNotch: CGFloat = 8  // Minimum gap to leave before notch

    // MARK: - Initialization

    init(notchDimensions: NotchDimensions, screenWidth: CGFloat) {
        self.notchDimensions = notchDimensions
        self.screenWidth = screenWidth
        self.updateLayout()
    }

    // MARK: - Public Methods

    /// Register or update a HUD module
    func setModule(type: HUDModule.HUDModuleType, isVisible: Bool, width: CGFloat) {
        let moduleId = type.rawValue

        print("🎨 HUDLayoutCoordinator: setModule(\(type.rawValue), isVisible: \(isVisible), width: \(width))")

        if let index = activeModules.firstIndex(where: { $0.id == moduleId }) {
            // Update existing module
            activeModules[index].isVisible = isVisible
            activeModules[index].width = width

            // Remove if not visible
            if !isVisible {
                activeModules.remove(at: index)
                print("🎨 HUDLayoutCoordinator: Removed module \(type.rawValue), active count: \(activeModules.count)")
            }
        } else if isVisible {
            // Add new module
            let module = HUDModule(
                id: moduleId,
                type: type,
                width: width,
                isVisible: isVisible
            )
            activeModules.append(module)
            print("🎨 HUDLayoutCoordinator: Added module \(type.rawValue), active count: \(activeModules.count)")
        }

        updateLayout()
    }

    /// Calculate the layout positions for all modules
    func calculateModulePositions() -> [String: CGFloat] {
        var positions: [String: CGFloat] = [:]

        guard !activeModules.isEmpty else {
            return positions
        }

        // Sort modules by priority (music always in center, others on sides)
        let musicModules = activeModules.filter { $0.type == .music }
        let volumeModules = activeModules.filter { $0.type == .volume }
        let brightnessModules = activeModules.filter { $0.type == .brightness }

        let screenCenter = screenWidth / 2

        // Music always centered on screen
        if let music = musicModules.first {
            positions[music.id] = screenCenter - (music.width / 2)
        }

        // Volume appears to the left of music (or center if no music)
        if let volume = volumeModules.first {
            if let music = musicModules.first {
                // Left of music
                let musicLeftEdge = screenCenter - (music.width / 2)
                positions[volume.id] = musicLeftEdge - volume.width - moduleSpacing
            } else {
                // Center if no music
                positions[volume.id] = screenCenter - (volume.width / 2)
            }
        }

        // Brightness appears to the right of music (or center if no music)
        if let brightness = brightnessModules.first {
            if let music = musicModules.first {
                // Right of music
                let musicRightEdge = screenCenter + (music.width / 2)
                positions[brightness.id] = musicRightEdge + moduleSpacing
            } else {
                // Center if no music
                positions[brightness.id] = screenCenter - (brightness.width / 2)
            }
        }

        return positions
    }

    /// Get the total occupied width of the HUD (for menu bar collision detection)
    func getOccupiedWidth() -> CGFloat {
        guard !activeModules.isEmpty else { return 0 }

        let positions = calculateModulePositions()

        // Find leftmost and rightmost edges
        var minX: CGFloat = .infinity
        var maxX: CGFloat = -.infinity

        for module in activeModules {
            guard let position = positions[module.id] else { continue }

            let leftEdge = position
            let rightEdge = position + module.width

            minX = min(minX, leftEdge)
            maxX = max(maxX, rightEdge)
        }

        return minX == .infinity ? 0 : (maxX - minX)
    }

    /// Get the leftmost edge of visible HUD content
    /// This returns where space indicators should stop (with small gap)
    func getLeftEdge() -> CGFloat {
        guard !activeModules.isEmpty else {
            return screenWidth / 2 - notchDimensions.width / 2
        }

        let screenCenter = screenWidth / 2
        let notchLeftEdge = screenCenter - notchDimensions.width / 2

        // Find the leftmost module and calculate its visible left edge
        // For music HUD: album art is notchDimensions.height wide, positioned next to notch
        var leftmostVisibleEdge = notchLeftEdge

        for module in activeModules {
            if module.type == .music {
                // Music HUD: album art sits to the left of the notch
                // Album art width = notchDimensions.height (square)
                // With padding of notchDimensions.padding / 2 on the outside
                let albumArtWidth = notchDimensions.height
                let outerPadding = notchDimensions.padding / 2
                leftmostVisibleEdge = notchLeftEdge - albumArtWidth - outerPadding
            } else if module.type == .volume || module.type == .brightness {
                // Volume/brightness: similar structure
                let indicatorWidth = notchDimensions.height
                let outerPadding = notchDimensions.padding / 2
                leftmostVisibleEdge = min(leftmostVisibleEdge, notchLeftEdge - indicatorWidth - outerPadding)
            }
        }

        print("🎨 getLeftEdge: notchLeftEdge=\(notchLeftEdge), leftmostVisibleEdge=\(leftmostVisibleEdge)")
        return leftmostVisibleEdge
    }

    /// Get the rightmost edge of visible HUD content
    func getRightEdge() -> CGFloat {
        guard !activeModules.isEmpty else {
            return screenWidth / 2 + notchDimensions.width / 2
        }

        let screenCenter = screenWidth / 2
        let notchRightEdge = screenCenter + notchDimensions.width / 2

        // Find the rightmost module and calculate its visible right edge
        var rightmostVisibleEdge = notchRightEdge

        for module in activeModules {
            if module.type == .music {
                // Music HUD: visualizer/track info sits to the right of the notch
                // For now use compact size (visualizer = notchDimensions.height)
                let visualizerWidth = notchDimensions.height
                let outerPadding = notchDimensions.padding / 2
                rightmostVisibleEdge = notchRightEdge + visualizerWidth + outerPadding
            } else if module.type == .volume || module.type == .brightness {
                // Volume/brightness: on the right side
                let indicatorWidth = notchDimensions.height
                let outerPadding = notchDimensions.padding / 2
                rightmostVisibleEdge = max(rightmostVisibleEdge, notchRightEdge + indicatorWidth + outerPadding)
            }
        }

        return rightmostVisibleEdge
    }

    // MARK: - Private Methods

    private func updateLayout() {
        // Calculate total width
        totalHUDWidth = getOccupiedWidth()

        // Determine if occluding notch
        isOccludingNotch = !activeModules.isEmpty

        // Calculate space indicator offset (push effect)
        if !activeModules.isEmpty {
            // Space indicators should be pushed away from HUD edges
            let leftEdge = getLeftEdge()
            let screenCenter = screenWidth / 2

            // Calculate how far the HUD extends left of center
            let extensionLeftOfCenter = screenCenter - leftEdge

            // Push space indicators left by this amount plus some padding
            spaceIndicatorOffset = -(extensionLeftOfCenter + minSpaceToNotch)
        } else {
            spaceIndicatorOffset = 0
        }

        // Increment version to force view update
        layoutVersion += 1
    }
}
