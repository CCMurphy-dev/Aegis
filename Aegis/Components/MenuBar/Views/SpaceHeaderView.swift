import SwiftUI

// MARK: - Space Header View
// Displays space number and handles space click

struct SpaceHeaderView: View {
    let spaceIndex: Int
    let isActive: Bool
    let onSpaceClick: () -> Void

    var body: some View {
        Text("\(spaceIndex)")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white.opacity(isActive ? 1.0 : 0.6))
            .frame(width: 16)
            .onTapGesture {
                onSpaceClick()
            }
    }
}
