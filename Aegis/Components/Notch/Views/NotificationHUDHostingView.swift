//
//  NotificationHUDHostingView.swift
//  Aegis
//
//  Custom NSHostingView that passes through mouse events outside the visible HUD panels.
//  This allows the notification HUD to be clickable while not blocking the menu bar.
//

import AppKit
import SwiftUI

// MARK: - Custom Window Class

/// Custom window that can receive mouse events but never becomes key window.
/// This prevents the "makeKeyWindow called but canBecomeKey returned NO" warnings.
class NotificationHUDWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func makeKey() { /* Do nothing */ }
    override func becomeKey() { /* Do nothing */ }
}

/// Custom NSHostingView for the notification HUD that only responds to clicks
/// within the visible panel areas (left of notch and right of notch).
/// Clicks outside these areas pass through to windows below (e.g., menu bar).
class NotificationHUDHostingView<Content: View>: NSHostingView<Content> {

    /// The bounds of the left panel (relative to this view's coordinate system)
    var leftPanelBounds: NSRect = .zero

    /// The bounds of the right panel (relative to this view's coordinate system)
    var rightPanelBounds: NSRect = .zero

    /// Whether the HUD is currently visible (panels are shown)
    var isHUDVisible: Bool = false

    /// Callback when user clicks on the HUD panels
    var onPanelClick: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        // If HUD is not visible, pass through all clicks
        guard isHUDVisible else {
            return nil
        }

        // Check if point is within either panel bounds
        if leftPanelBounds.contains(point) || rightPanelBounds.contains(point) {
            // Return self to handle the click in mouseDown
            return self
        }

        // Point is outside panels - pass through to windows below
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        // Convert event location to view coordinates
        let point = convert(event.locationInWindow, from: nil)

        // Check if click is within panel bounds
        if isHUDVisible && (leftPanelBounds.contains(point) || rightPanelBounds.contains(point)) {
            // Trigger the callback to open the source app
            onPanelClick?()
        }
        // Don't call super - we've handled the event
    }

    /// Update the panel bounds based on notch dimensions and view size
    /// Call this after the view is laid out or when the HUD visibility changes
    func updatePanelBounds(notchDimensions: NotchDimensions, isVisible: Bool) {
        self.isHUDVisible = isVisible

        guard isVisible else {
            leftPanelBounds = .zero
            rightPanelBounds = .zero
            return
        }

        let notchGapFill: CGFloat = 18

        // Calculate panel widths (matching NotchHUDController calculations)
        let leftPanelWidth = notchDimensions.height  // Square for icon
        let rightPanelWidth = min(notchDimensions.height * 3, 150)  // Match controller

        // The window is now sized to exactly match the HUD width and centered on the notch,
        // so the HUD starts at x=0 in the view's coordinate system

        // Left panel: starts at x=0, width includes notchGapFill for the part that extends under notch
        leftPanelBounds = NSRect(
            x: 0,
            y: 0,
            width: leftPanelWidth + notchGapFill,
            height: notchDimensions.height
        )

        // Right panel: starts after left panel + notch, extends with notchGapFill
        let rightPanelStartX = leftPanelWidth + notchDimensions.width - notchGapFill
        rightPanelBounds = NSRect(
            x: rightPanelStartX,
            y: 0,
            width: rightPanelWidth + notchGapFill,
            height: notchDimensions.height
        )

        print("🔔 NotificationHUDHostingView: Updated panel bounds - left=\(leftPanelBounds), right=\(rightPanelBounds), viewBounds=\(bounds)")
    }
}
