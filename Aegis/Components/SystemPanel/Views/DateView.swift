import SwiftUI
import Combine

enum DateFormatOption {
    case short    // "DD/MM/YY"
    case long     // "E MMM d"
}

struct DateView: View {
    @State private var currentDate = Date()
    
    // Allow the format to be set externally
    var format: DateFormatOption = .long
    
    // Timer updates every minute
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    var body: some View {
        Text(dateString)
            .monospacedDigit()
            .onReceive(timer) { _ in
                currentDate = Date()
            }
    }
    
    private var dateString: String {
        let formatter = DateFormatter()
        switch format {
        case .long:
            formatter.dateFormat = "E MMM d" // e.g., "Mon Jan 13"
        case .short:
            formatter.dateFormat = "dd/MM/yy" // e.g., "13/01/26"
        }
        return formatter.string(from: currentDate)
    }
}
