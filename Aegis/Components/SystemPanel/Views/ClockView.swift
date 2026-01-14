import SwiftUI
import Combine

struct ClockView: View {
    @State private var currentTime = Date()
    
    // Timer updates every second
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        Text(timeString)
            .onReceive(timer) { _ in
                currentTime = Date()
            }
    }
    
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm" // 24-hour format, e.g., "14:45"
        return formatter.string(from: currentTime)
    }
}
