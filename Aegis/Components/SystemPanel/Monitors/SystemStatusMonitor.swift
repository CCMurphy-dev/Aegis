import Foundation
import Combine
import Network

class SystemStatusMonitor: ObservableObject {
    // MARK: - Published status
    @Published var batteryLevel: Float = 1.0
    @Published var isCharging: Bool = false
    @Published var networkStatus: NetworkStatus = .disconnected
    @Published var focusStatus: FocusStatus = .disabled

    private let batteryMonitor = BatteryStatusMonitor()
    private let focusMonitor = FocusStatusMonitor()
    private let networkMonitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "SystemStatusMonitorQueue")

    init() {
        // Bind battery monitor
        batteryMonitor.$level.assign(to: &$batteryLevel)
        batteryMonitor.$isCharging.assign(to: &$isCharging)

        // Bind focus monitor
        focusMonitor.$focusStatus.assign(to: &$focusStatus)

        // Setup network monitoring
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.updateNetworkStatus(path: path)
            }
        }
        networkMonitor.start(queue: queue)
    }

    private func updateNetworkStatus(path: NWPath) {
        if path.status == .satisfied {
            if path.usesInterfaceType(.wifi) {
                // Map WiFi strength approximately if needed, or just connected
                networkStatus = .wifi(strength: 1.0)
            } else if path.usesInterfaceType(.wiredEthernet) {
                networkStatus = .ethernet
            } else {
                networkStatus = .disconnected
            }
        } else {
            networkStatus = .disconnected
        }
    }
}
