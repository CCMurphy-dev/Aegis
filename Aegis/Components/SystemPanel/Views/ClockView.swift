import SwiftUI
import Combine

struct ClockView: View {
    @State private var currentTime = Date()
    @State private var timer: AnyCancellable?

    var body: some View {
        Text(timeString)
            .monospacedDigit()
            .onAppear {
                startMinuteSyncedTimer()
            }
            .onDisappear {
                timer?.cancel()
            }
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm" // 24-hour format, e.g., "14:45"
        return formatter.string(from: currentTime)
    }

    /// Start a timer that syncs to the minute boundary, then fires every 60s
    private func startMinuteSyncedTimer() {
        // Calculate seconds until next minute
        let now = Date()
        let calendar = Calendar.current
        let seconds = calendar.component(.second, from: now)
        let delayUntilNextMinute = Double(60 - seconds)

        // First update: wait until next minute boundary
        DispatchQueue.main.asyncAfter(deadline: .now() + delayUntilNextMinute) {
            currentTime = Date()

            // Then update every 60 seconds
            timer = Timer.publish(every: 60, on: .main, in: .common)
                .autoconnect()
                .sink { _ in
                    currentTime = Date()
                }
        }
    }
}
