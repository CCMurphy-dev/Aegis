import Foundation
import Combine

enum NetworkStatus: Equatable {
    case wifi(strength: Double)
    case ethernet
    case disconnected
}

class NetworkStatusMonitor: ObservableObject {
    @Published var status: NetworkStatus = .disconnected

    private var timer: Timer?

    init() {
        startMonitoring()
    }

    deinit { timer?.invalidate() }

    private func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateStatus()
        }
        updateStatus()
    }

    private func updateStatus() {
        // Your network check logic
    }
}
