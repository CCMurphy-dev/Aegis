import SwiftUI
import Combine

struct DateView: View {
    @State private var currentDate = Date()
    @ObservedObject private var config = AegisConfig.shared

    // Timer updates every minute
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    // Cached formatters - created once, reused on every render
    private static let longFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "E MMM d" // e.g., "Mon Jan 13"
        return formatter
    }()

    private static let shortFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yy" // e.g., "13/01/26"
        return formatter
    }()

    var body: some View {
        Text(dateString)
            .monospacedDigit()
            .onReceive(timer) { _ in
                currentDate = Date()
            }
    }

    private var dateString: String {
        switch config.dateFormat {
        case .long:
            return Self.longFormatter.string(from: currentDate)
        case .short:
            return Self.shortFormatter.string(from: currentDate)
        }
    }
}
