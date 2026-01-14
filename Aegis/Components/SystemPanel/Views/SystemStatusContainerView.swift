import SwiftUI

struct SystemStatusContainerView: View {
    var body: some View {
        HStack(spacing: 6) { // inner spacing like MenuBar blocks
            SystemStatusView() // your indicators: wifi, battery, date/time
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.85))
        )
        .shadow(color: Color.black.opacity(0.3), radius: 1, x: 0, y: 1)
        .fixedSize()
    }
}
