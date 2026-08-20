//
//  VirtualNotchView.swift
//  Aegis
//
//  Renders a black notch-shaped pill at the top center of an external display.
//

import SwiftUI

/// Shape for the virtual notch: flat top edge (flush with screen bezel), rounded bottom corners
struct VirtualNotchShape: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Top-left corner (flat, flush with screen edge)
        path.move(to: CGPoint(x: 0, y: 0))

        // Top edge
        path.addLine(to: CGPoint(x: rect.width, y: 0))

        // Right edge down to bottom-right corner
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - cornerRadius))

        // Bottom-right rounded corner
        path.addQuadCurve(
            to: CGPoint(x: rect.width - cornerRadius, y: rect.height),
            control: CGPoint(x: rect.width, y: rect.height)
        )

        // Bottom edge
        path.addLine(to: CGPoint(x: cornerRadius, y: rect.height))

        // Bottom-left rounded corner
        path.addQuadCurve(
            to: CGPoint(x: 0, y: rect.height - cornerRadius),
            control: CGPoint(x: 0, y: rect.height)
        )

        path.closeSubpath()
        return path
    }
}

struct VirtualNotchView: View {
    let dimensions: NotchDimensions

    var body: some View {
        VStack(spacing: 0) {
            VirtualNotchShape(cornerRadius: 8)
                .fill(.black)
                .frame(width: dimensions.width, height: dimensions.height)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
