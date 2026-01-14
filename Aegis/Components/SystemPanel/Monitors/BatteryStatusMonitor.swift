import Foundation
import Combine
import IOKit.ps

class BatteryStatusMonitor: ObservableObject {
    @Published var level: Float = 1.0
    @Published var isCharging: Bool = false

    private var runLoopSource: Unmanaged<CFRunLoopSource>?

    init() {
        startMonitoring()
        updateBattery()
    }

    deinit {
        if let source = runLoopSource?.takeRetainedValue() {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode)
        }
    }

    private func startMonitoring() {
        // Create a callback for battery changes
        let callback: IOPowerSourceCallbackType = { context in
            let monitor = Unmanaged<BatteryStatusMonitor>.fromOpaque(context!).takeUnretainedValue()
            monitor.updateBattery()
        }

        // Create the run loop source
        runLoopSource = IOPSNotificationCreateRunLoopSource(callback, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
        
        if let source = runLoopSource?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
        }
    }

    private func updateBattery() {
        guard let powerInfo = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let powerSources = IOPSCopyPowerSourcesList(powerInfo)?.takeRetainedValue() as? [CFTypeRef],
              let source = powerSources.first,
              let description = IOPSGetPowerSourceDescription(powerInfo, source)?.takeUnretainedValue() as? [String: Any]
        else { return }

        if let capacity = description[kIOPSCurrentCapacityKey] as? Int,
           let maxCapacity = description[kIOPSMaxCapacityKey] as? Int {
            DispatchQueue.main.async {
                self.level = Float(capacity) / Float(maxCapacity)
                self.isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            }
        }
    }
}
