import Foundation
import IOBluetooth

/// Model for a Bluetooth device connection event
struct BluetoothDeviceInfo {
    let name: String
    let address: String
    let deviceType: DeviceType
    let isConnected: Bool
    let batteryLevel: Int?  // 0-100, nil if unknown

    enum DeviceType {
        case airpods
        case airpodsPro
        case airpodsMax
        case beats
        case headphones
        case speaker
        case keyboard
        case mouse
        case trackpad
        case other

        var iconName: String {
            switch self {
            case .airpods, .airpodsPro: return "airpodspro"
            case .airpodsMax: return "airpodsmax"
            case .beats, .headphones: return "headphones"
            case .speaker: return "hifispeaker.fill"
            case .keyboard: return "keyboard.fill"
            case .mouse: return "magicmouse.fill"
            case .trackpad: return "rectangle.and.hand.point.up.left.fill"
            case .other: return "wave.3.right.circle.fill"
            }
        }

        var displayName: String {
            switch self {
            case .airpods: return "AirPods"
            case .airpodsPro: return "AirPods Pro"
            case .airpodsMax: return "AirPods Max"
            case .beats: return "Beats"
            case .headphones: return "Headphones"
            case .speaker: return "Speaker"
            case .keyboard: return "Keyboard"
            case .mouse: return "Mouse"
            case .trackpad: return "Trackpad"
            case .other: return "Device"
            }
        }
    }
}

/// Service that monitors Bluetooth device connections and disconnections
class BluetoothDeviceService: NSObject {
    private let eventRouter: EventRouter
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    private var connectedDevices: Set<String> = []  // Track by address to avoid duplicates

    // Debounce rapid connect/disconnect events
    private var pendingEvents: [String: DispatchWorkItem] = [:]
    private let debounceDelay: TimeInterval = 0.5

    // Track recently disconnected devices to ignore spurious reconnect notifications
    private var recentlyDisconnected: [String: Date] = [:]
    private let reconnectIgnoreWindow: TimeInterval = 2.0  // Ignore reconnects within 2 seconds of disconnect

    init(eventRouter: EventRouter) {
        self.eventRouter = eventRouter
        super.init()
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        logInfo("🎧 BluetoothDeviceService: Starting Bluetooth monitoring")

        // Register for any device connection
        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))

        // Subscribe to audio output changes to detect Bluetooth disconnects faster
        // (IOBluetooth disconnect notifications can be delayed)
        eventRouter.subscribe(to: .audioOutputDeviceChanged) { [weak self] _ in
            self?.checkForDisconnectedDevices()
        }

        // Also check currently connected devices on startup
        checkCurrentlyConnectedDevices()
    }

    private func stopMonitoring() {
        connectNotification?.unregister()
        connectNotification = nil

        for (_, notification) in disconnectNotifications {
            notification.unregister()
        }
        disconnectNotifications.removeAll()
    }

    private func checkCurrentlyConnectedDevices() {
        guard let devices = IOBluetoothDevice.pairedDevices() else {
            logInfo("🎧 BluetoothDeviceService: No paired devices found")
            return
        }

        for item in devices {
            guard let device = item as? IOBluetoothDevice else { continue }
            if device.isConnected() {
                let address = device.addressString ?? "unknown"
                connectedDevices.insert(address)
                registerDisconnectNotification(for: device)
                logInfo("🎧 BluetoothDeviceService: Found connected device: \(device.name ?? "Unknown")")
            }
        }
    }

    /// Called when audio output device changes - check if any tracked Bluetooth devices disconnected
    /// This catches disconnects faster than IOBluetooth notifications (which can be delayed)
    func checkForDisconnectedDevices() {
        guard let devices = IOBluetoothDevice.pairedDevices() else { return }

        // Build a set of currently connected device addresses
        var stillConnected: Set<String> = []
        for item in devices {
            guard let device = item as? IOBluetoothDevice else { continue }
            if device.isConnected() {
                stillConnected.insert(device.addressString ?? "unknown")
            }
        }

        // Find devices we were tracking that are no longer connected
        // BUT skip any that have pending events (connect in progress - race condition during audio switch)
        let disconnectedAddresses = connectedDevices.subtracting(stillConnected).filter { address in
            pendingEvents[address] == nil
        }

        for address in disconnectedAddresses {
            // Find the device to trigger disconnect
            for item in devices {
                guard let device = item as? IOBluetoothDevice else { continue }
                if device.addressString == address {
                    logInfo("🎧 BluetoothDeviceService: Detected disconnect via audio change: \(device.name ?? "Unknown")")
                    deviceDisconnected(nil, device: device)
                    break
                }
            }
        }
    }

    // MARK: - Connection Callbacks

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification?, device: IOBluetoothDevice?) {
        guard let device = device else { return }

        let address = device.addressString ?? "unknown"
        let name = device.name ?? "Unknown Device"

        // Skip if we already know about this device
        guard !connectedDevices.contains(address) else {
            logInfo("🎧 BluetoothDeviceService: Device already tracked: \(name)")
            return
        }

        // Skip if this device was recently disconnected (spurious reconnect notification)
        if let disconnectTime = recentlyDisconnected[address],
           Date().timeIntervalSince(disconnectTime) < reconnectIgnoreWindow {
            logInfo("🎧 BluetoothDeviceService: Ignoring spurious reconnect for recently disconnected device: \(name)")
            return
        }

        // Clear from recently disconnected if it's been long enough
        recentlyDisconnected.removeValue(forKey: address)

        // Mark as tracked immediately to prevent duplicate events from rapid notifications
        connectedDevices.insert(address)

        // Cancel any pending disconnect event for this device
        pendingEvents[address]?.cancel()
        pendingEvents[address] = nil

        logInfo("🎧 BluetoothDeviceService: Device connected: \(name) (\(address))")

        // Debounce the connect event (but we've already marked it as tracked)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            // Verify device is still connected
            guard device.isConnected() else {
                logInfo("🎧 BluetoothDeviceService: Device disconnected before event fired: \(name)")
                self.connectedDevices.remove(address)  // Remove since it didn't actually connect
                return
            }

            self.registerDisconnectNotification(for: device)

            let deviceInfo = self.createDeviceInfo(from: device, isConnected: true)
            self.eventRouter.publish(.bluetoothDeviceConnected, data: ["device": deviceInfo])
        }

        pendingEvents[address] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceDelay, execute: workItem)
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification?, device: IOBluetoothDevice?) {
        guard let device = device else { return }

        let address = device.addressString ?? "unknown"
        let name = device.name ?? "Unknown Device"

        // Skip if we don't know about this device (already processed or never tracked)
        guard connectedDevices.contains(address) else {
            logInfo("🎧 BluetoothDeviceService: Device already removed or not tracked: \(name)")
            return
        }

        // Remove from tracking immediately to prevent duplicate events
        connectedDevices.remove(address)

        // Mark as recently disconnected to ignore spurious reconnect notifications
        recentlyDisconnected[address] = Date()

        // Cancel any pending connect event for this device
        pendingEvents[address]?.cancel()
        pendingEvents[address] = nil

        logInfo("🎧 BluetoothDeviceService: Device disconnected: \(name) (\(address))")

        // Debounce the disconnect event (but we've already marked it as removed)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            self.disconnectNotifications[address]?.unregister()
            self.disconnectNotifications.removeValue(forKey: address)

            let deviceInfo = self.createDeviceInfo(from: device, isConnected: false)
            self.eventRouter.publish(.bluetoothDeviceDisconnected, data: ["device": deviceInfo])
        }

        pendingEvents[address] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceDelay, execute: workItem)
    }

    private func registerDisconnectNotification(for device: IOBluetoothDevice) {
        let address = device.addressString ?? "unknown"

        // Don't register twice
        guard disconnectNotifications[address] == nil else { return }

        let notification = device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
        disconnectNotifications[address] = notification
    }

    // MARK: - Device Info Creation

    private func createDeviceInfo(from device: IOBluetoothDevice, isConnected: Bool) -> BluetoothDeviceInfo {
        let name = device.name ?? "Unknown Device"
        let address = device.addressString ?? "unknown"
        let deviceType = determineDeviceType(from: device)
        let batteryLevel = fetchBatteryLevel(for: device)

        return BluetoothDeviceInfo(
            name: name,
            address: address,
            deviceType: deviceType,
            isConnected: isConnected,
            batteryLevel: batteryLevel
        )
    }

    private func determineDeviceType(from device: IOBluetoothDevice) -> BluetoothDeviceInfo.DeviceType {
        let name = (device.name ?? "").lowercased()

        // Check for Apple devices first
        if name.contains("airpods pro") {
            return .airpodsPro
        } else if name.contains("airpods max") {
            return .airpodsMax
        } else if name.contains("airpods") {
            return .airpods
        } else if name.contains("beats") {
            return .beats
        } else if name.contains("magic keyboard") || name.contains("keyboard") {
            return .keyboard
        } else if name.contains("magic mouse") || name.contains("mouse") {
            return .mouse
        } else if name.contains("magic trackpad") || name.contains("trackpad") {
            return .trackpad
        } else if name.contains("headphone") || name.contains("wh-") || name.contains("wf-") {
            // Sony WH/WF series, generic headphones
            return .headphones
        } else if name.contains("speaker") || name.contains("soundbar") || name.contains("bose") {
            return .speaker
        }

        // Check device class for audio devices
        let deviceClass = device.classOfDevice
        let majorClass = (deviceClass >> 8) & 0x1F
        let minorClass = (deviceClass >> 2) & 0x3F

        // Major class 4 = Audio/Video
        if majorClass == 4 {
            // Minor classes for audio
            if minorClass == 1 || minorClass == 2 { // Wearable headset / Hands-free
                return .headphones
            } else if minorClass == 4 { // Microphone
                return .headphones
            } else if minorClass == 5 { // Loudspeaker
                return .speaker
            } else if minorClass == 6 { // Headphones
                return .headphones
            }
        }

        // Major class 5 = Peripheral (keyboard, mouse, etc.)
        if majorClass == 5 {
            if minorClass & 0x10 != 0 { // Keyboard
                return .keyboard
            }
            if minorClass & 0x20 != 0 { // Pointing device
                return .mouse
            }
        }

        return .other
    }

    private func fetchBatteryLevel(for device: IOBluetoothDevice) -> Int? {
        // Try to get battery level from system_profiler
        // This is a fallback since IOBluetooth doesn't expose battery directly
        let address = device.addressString ?? ""
        return fetchBatteryFromSystemProfiler(deviceAddress: address)
    }

    private func fetchBatteryFromSystemProfiler(deviceAddress: String) -> Int? {
        // Run system_profiler to get Bluetooth data
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()

            // Parse JSON to find battery level
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let bluetooth = json["SPBluetoothDataType"] as? [[String: Any]] {

                for controller in bluetooth {
                    if let devices = controller["device_connected"] as? [[String: Any]] {
                        for deviceDict in devices {
                            // Each device is a dictionary with the device name as key
                            for (deviceName, value) in deviceDict {
                                if let deviceInfo = value as? [String: Any],
                                   let address = deviceInfo["device_address"] as? String,
                                   normalizeAddress(address) == normalizeAddress(deviceAddress) {

                                    logInfo("🎧 BluetoothDeviceService: Found device '\(deviceName)' in system_profiler, checking battery keys...")

                                    // Battery key priority: Left/Right earbuds first (average), then Main, then Case, then generic
                                    // AirPods report: device_batteryLevelLeft, device_batteryLevelRight, device_batteryLevelCase
                                    // Other devices may use: device_batteryLevel, device_batteryLevelMain

                                    // Try left/right earbud levels first (for AirPods)
                                    let leftLevel = parseBatteryString(deviceInfo["device_batteryLevelLeft"] as? String)
                                    let rightLevel = parseBatteryString(deviceInfo["device_batteryLevelRight"] as? String)

                                    if let left = leftLevel, let right = rightLevel {
                                        let avg = (left + right) / 2
                                        logInfo("🎧 BluetoothDeviceService: Battery (L/R avg): \(avg)% (L:\(left)%, R:\(right)%)")
                                        return avg
                                    } else if let left = leftLevel {
                                        logInfo("🎧 BluetoothDeviceService: Battery (Left only): \(left)%")
                                        return left
                                    } else if let right = rightLevel {
                                        logInfo("🎧 BluetoothDeviceService: Battery (Right only): \(right)%")
                                        return right
                                    }

                                    // Try main level
                                    if let main = parseBatteryString(deviceInfo["device_batteryLevelMain"] as? String) {
                                        logInfo("🎧 BluetoothDeviceService: Battery (Main): \(main)%")
                                        return main
                                    }

                                    // Try case level (for AirPods when earbuds are in case)
                                    if let caseLevel = parseBatteryString(deviceInfo["device_batteryLevelCase"] as? String) {
                                        logInfo("🎧 BluetoothDeviceService: Battery (Case): \(caseLevel)%")
                                        return caseLevel
                                    }

                                    // Try generic battery level
                                    if let generic = parseBatteryString(deviceInfo["device_batteryLevel"] as? String) {
                                        logInfo("🎧 BluetoothDeviceService: Battery (Generic): \(generic)%")
                                        return generic
                                    }

                                    logInfo("🎧 BluetoothDeviceService: No battery keys found for device. Available keys: \(deviceInfo.keys.sorted())")
                                }
                            }
                        }
                    }
                }

                logInfo("🎧 BluetoothDeviceService: Device address \(deviceAddress) not found in device_connected list")
            }
        } catch {
            logInfo("🎧 BluetoothDeviceService: Failed to fetch battery level: \(error)")
        }

        return nil
    }

    /// Parse battery string like "85%" to Int
    private func parseBatteryString(_ str: String?) -> Int? {
        guard let str = str else { return nil }
        let cleaned = str.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
        return Int(cleaned)
    }

    /// Normalize Bluetooth address to lowercase without separators for comparison
    /// IOBluetooth uses hyphens (04-99-b9-56-c4-50), system_profiler uses colons (04:99:B9:56:C4:50)
    private func normalizeAddress(_ address: String) -> String {
        return address.lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")
    }
}
