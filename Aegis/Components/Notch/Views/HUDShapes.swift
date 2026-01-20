//
//  HUDShapes.swift
//  Aegis
//
//  Shared panel shapes for all HUD views (volume, brightness, media, device, focus, notification).
//  These shapes create the curved panels that appear to extend from the notch.
//

import SwiftUI

/// Shape for LEFT panel - curved outer edges, inner edge curves outward to connect with notch
struct HUDLeftPanelShape: Shape {
    let cornerRadius: CGFloat
    let topCornerRadius: CGFloat
    let innerCornerRadius: CGFloat  // Curves outward to match notch's bottom corner

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Top-left: outward curve (curves away from center)
        path.move(to: CGPoint(x: topCornerRadius, y: 0))
        path.addQuadCurve(
            to: CGPoint(x: 0, y: topCornerRadius),
            control: CGPoint(x: 0, y: 0)
        )

        // Left edge down to bottom corner
        path.addLine(to: CGPoint(x: 0, y: rect.height - cornerRadius))

        // Bottom-left rounded corner (inward curve)
        path.addQuadCurve(
            to: CGPoint(x: cornerRadius, y: rect.height),
            control: CGPoint(x: 0, y: rect.height)
        )

        // Bottom edge to inner corner
        path.addLine(to: CGPoint(x: rect.width - innerCornerRadius, y: rect.height))

        // Bottom-right: outward curve (concave - matches notch's corner)
        path.addQuadCurve(
            to: CGPoint(x: rect.width, y: rect.height - innerCornerRadius),
            control: CGPoint(x: rect.width, y: rect.height)
        )

        // Right edge straight up to top
        path.addLine(to: CGPoint(x: rect.width, y: 0))

        // Top edge back to start
        path.addLine(to: CGPoint(x: topCornerRadius, y: 0))

        return path
    }
}

/// Shape for RIGHT panel - curved outer edges, inner edge curves outward to connect with notch
struct HUDRightPanelShape: Shape {
    let cornerRadius: CGFloat
    let topCornerRadius: CGFloat
    let innerCornerRadius: CGFloat  // Curves outward to match notch's bottom corner

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Start at top-left (connects to notch)
        path.move(to: CGPoint(x: 0, y: 0))

        // Left edge straight down to inner corner
        path.addLine(to: CGPoint(x: 0, y: rect.height - innerCornerRadius))

        // Bottom-left: outward curve (concave - matches notch's corner)
        path.addQuadCurve(
            to: CGPoint(x: innerCornerRadius, y: rect.height),
            control: CGPoint(x: 0, y: rect.height)
        )

        // Bottom edge to outer corner
        path.addLine(to: CGPoint(x: rect.width - cornerRadius, y: rect.height))

        // Bottom-right rounded corner (inward curve)
        path.addQuadCurve(
            to: CGPoint(x: rect.width, y: rect.height - cornerRadius),
            control: CGPoint(x: rect.width, y: rect.height)
        )

        // Right edge up to top corner
        path.addLine(to: CGPoint(x: rect.width, y: topCornerRadius))

        // Top-right: outward curve (curves away from center)
        path.addQuadCurve(
            to: CGPoint(x: rect.width - topCornerRadius, y: 0),
            control: CGPoint(x: rect.width, y: 0)
        )

        // Top edge back to start
        path.addLine(to: CGPoint(x: 0, y: 0))

        return path
    }
}
