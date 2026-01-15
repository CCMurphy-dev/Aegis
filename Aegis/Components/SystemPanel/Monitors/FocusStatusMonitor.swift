import Foundation
import Combine

/// Model representing Focus mode state and type
struct FocusStatus: Equatable {
    let isEnabled: Bool
    let focusName: String?
    let symbolName: String?

    static let disabled = FocusStatus(isEnabled: false, focusName: nil, symbolName: nil)
}

/// Monitors macOS Focus mode status using directory monitoring
/// Watches the DoNotDisturb DB directory for any file changes
class FocusStatusMonitor: ObservableObject {
    @Published var focusStatus: FocusStatus = .disabled

    private var directoryMonitorSource: DispatchSourceFileSystemObject?
    private var directoryDescriptor: Int32 = -1

    private let dndDirectory = NSHomeDirectory() + "/Library/DoNotDisturb/DB"
    private let assertionsPath = NSHomeDirectory() + "/Library/DoNotDisturb/DB/Assertions.json"
    private let modeConfigPath = NSHomeDirectory() + "/Library/DoNotDisturb/DB/ModeConfigurations.json"

    init() {
        // Initial check
        updateFocusStatus()

        // Monitor the DoNotDisturb/DB directory for any changes
        // This is more reliable than monitoring individual files
        setupDirectoryMonitoring()
    }

    deinit {
        stopDirectoryMonitoring()
    }

    // MARK: - Directory Monitoring

    private func setupDirectoryMonitoring() {
        directoryDescriptor = open(dndDirectory, O_EVTONLY)
        guard directoryDescriptor != -1 else {
            logWarning("Could not open DoNotDisturb/DB directory for monitoring")
            return
        }

        directoryMonitorSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryDescriptor,
            eventMask: [.write, .extend, .attrib, .link, .rename, .revoke],
            queue: DispatchQueue.main
        )

        directoryMonitorSource?.setEventHandler { [weak self] in
            // Small delay to ensure file writes are complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self?.updateFocusStatus()
            }
        }

        directoryMonitorSource?.setCancelHandler { [weak self] in
            if let fd = self?.directoryDescriptor, fd != -1 {
                close(fd)
                self?.directoryDescriptor = -1
            }
        }

        directoryMonitorSource?.resume()
        logInfo("Focus directory monitoring started")
    }

    private func stopDirectoryMonitoring() {
        directoryMonitorSource?.cancel()
        directoryMonitorSource = nil
    }

    // MARK: - Status Updates

    private func updateFocusStatus() {
        var isEnabled = false
        var focusName: String?
        var symbolName: String?

        // Check if any Focus assertions are active
        if let assertionsData = FileManager.default.contents(atPath: assertionsPath),
           let assertions = try? JSONSerialization.jsonObject(with: assertionsData) as? [String: Any],
           let data = assertions["data"] as? [[String: Any]] {

            // Look for active assertions (storeAssertionRecords key only exists when Focus is active)
            for item in data {
                if let storeAssertionRecords = item["storeAssertionRecords"] as? [[String: Any]],
                   let firstRecord = storeAssertionRecords.first,
                   let assertionDetails = firstRecord["assertionDetails"] as? [String: Any],
                   let modeIdentifier = assertionDetails["assertionDetailsModeIdentifier"] as? String {

                    isEnabled = true
                    // Get the mode details (name and symbol) from ModeConfigurations
                    let modeDetails = getModeDetails(for: modeIdentifier)
                    focusName = modeDetails.name
                    symbolName = modeDetails.symbol
                    break
                }
            }
        }

        let newStatus = FocusStatus(isEnabled: isEnabled, focusName: focusName, symbolName: symbolName)
        if focusStatus != newStatus {
            focusStatus = newStatus
            if isEnabled {
                logInfo("Focus enabled: \(focusName ?? "Unknown") (symbol: \(symbolName ?? "none"))")
            } else {
                logInfo("Focus disabled")
            }
        }
    }

    // MARK: - Mode Configuration Lookup

    private func getModeDetails(for identifier: String) -> (name: String?, symbol: String?) {
        // Read ModeConfigurations.json to get the actual name and symbol
        guard let configData = FileManager.default.contents(atPath: modeConfigPath),
              let config = try? JSONSerialization.jsonObject(with: configData) as? [String: Any],
              let data = config["data"] as? [[String: Any]] else {
            return getBuiltInModeDetails(for: identifier)
        }

        // Search through mode configurations
        for item in data {
            if let modeConfigurations = item["modeConfigurations"] as? [String: Any] {
                // Check if this identifier exists in the configurations
                if let modeConfig = modeConfigurations[identifier] as? [String: Any],
                   let mode = modeConfig["mode"] as? [String: Any] {
                    let name = mode["name"] as? String
                    let symbol = mode["symbolImageName"] as? String
                    return (name, symbol)
                }
            }
        }

        // Fallback for built-in modes that might not be in user's config
        return getBuiltInModeDetails(for: identifier)
    }

    private func getBuiltInModeDetails(for identifier: String) -> (name: String?, symbol: String?) {
        // Built-in Focus modes with their default symbols
        let builtInModes: [String: (name: String, symbol: String)] = [
            "com.apple.donotdisturb.mode.default": ("Do Not Disturb", "moon.fill"),
            "com.apple.focus.personal-time": ("Personal", "person.fill"),
            "com.apple.focus.work": ("Work", "briefcase.fill"),
            "com.apple.focus.sleep": ("Sleep", "bed.double.fill"),
            "com.apple.focus.driving": ("Driving", "car.fill"),
            "com.apple.focus.fitness": ("Fitness", "figure.run"),
            "com.apple.focus.gaming": ("Gaming", "gamecontroller.fill"),
            "com.apple.focus.mindfulness": ("Mindfulness", "brain.head.profile"),
            "com.apple.focus.reading": ("Reading", "book.fill")
        ]

        if let details = builtInModes[identifier] {
            return (details.name, details.symbol)
        }

        // For custom modes with identifier pattern like "com.apple.donotdisturb.mode.stethoscope"
        // The symbol is often embedded in the identifier
        if identifier.hasPrefix("com.apple.donotdisturb.mode.") {
            let symbolPart = identifier.replacingOccurrences(of: "com.apple.donotdisturb.mode.", with: "")
            if symbolPart != "default" {
                return (nil, symbolPart)
            }
        }

        return (nil, "moon.fill") // Default fallback
    }
}
