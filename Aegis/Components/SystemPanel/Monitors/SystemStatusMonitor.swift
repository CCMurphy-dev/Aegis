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
    private let networkMonitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "SystemStatusMonitorQueue")

    /// Shared instance that subscribes to the app's EventRouter
    /// This avoids duplicate file system watchers for Focus status
    static let shared = SystemStatusMonitor()

    private init() {
        // Bind battery monitor
        batteryMonitor.$level.assign(to: &$batteryLevel)
        batteryMonitor.$isCharging.assign(to: &$isCharging)

        // Setup network monitoring
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.updateNetworkStatus(path: path)
            }
        }
        networkMonitor.start(queue: queue)
    }

    /// Subscribe to EventRouter for focus changes
    /// Called once from AppDelegate after EventRouter is set up
    func subscribeToFocusEvents(eventRouter: EventRouter) {
        eventRouter.subscribe(to: .focusChanged) { [weak self] data in
            let isEnabled = data["isEnabled"] as? Bool ?? false
            let focusName = data["focusName"] as? String
            let symbolName = data["symbolName"] as? String
            self?.focusStatus = FocusStatus(isEnabled: isEnabled, focusName: focusName, symbolName: symbolName)
        }
    }

    /// Set initial focus status (called once at startup, before events start flowing)
    func setInitialFocusStatus(_ status: FocusStatus) {
        self.focusStatus = status
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
