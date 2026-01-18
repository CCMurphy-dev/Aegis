import Foundation
import CoreAudio
import AppKit

// Model for system state (volume and brightness only - battery handled by BatteryStatusMonitor)
struct SystemState {
    var volume: Float
    var brightness: Float
    var isMuted: Bool
}

// Service to monitor system volume, brightness, battery
class SystemInfoService {
    private let eventRouter: EventRouter
    private var currentState = SystemState(volume: 0, brightness: 0, isMuted: false)

    // Audio device ID for volume monitoring
    private var audioDeviceID: AudioDeviceID = 0

    // Track registered audio listener addresses to remove on device change
    // Stored as tuples of (deviceID, address) for cleanup
    private var registeredVolumeListenerAddresses: [(AudioDeviceID, AudioObjectPropertyAddress)] = []

    // Track previous non-zero volume to detect mute via volume = 0
    private var previousNonZeroVolume: Float = 0.5

    // For Bluetooth devices that don't expose volume - track estimated volume
    private var estimatedBluetoothVolume: Float = 0.5
    private var estimatedBluetoothMuted: Bool = false
    private var deviceSupportsVolumeProperty = true

    // Suppress volume events briefly after device switch to avoid spurious HUD displays
    private var suppressVolumeEventsUntil: Date = .distantPast

    init(eventRouter: EventRouter) {
        self.eventRouter = eventRouter

        // Suppress native macOS volume/brightness HUD
        suppressNativeHUD()

        // Start monitoring
        setupDefaultDeviceChangeMonitoring()
        setupVolumeMonitoring()
        setupBrightnessMonitoring()
        // Note: Battery monitoring is handled by BatteryStatusMonitor (event-based via IOPowerSource)
        // which is bound to SystemStatusMonitor.shared - no polling needed here
        setupKeyEventMonitoring()
    }

    // MARK: - Default Device Change Monitoring

    private func setupDefaultDeviceChangeMonitoring() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main
        ) { [weak self] _, _ in
            print("🔊 Default audio output device changed - re-registering volume listener")
            // Suppress volume events for 1 second to avoid spurious HUD (e.g., mute animation on disconnect)
            self?.suppressVolumeEventsUntil = Date().addingTimeInterval(1.0)
            self?.setupVolumeMonitoring()

            // Notify other services that audio output changed (used by BluetoothDeviceService to detect disconnects faster)
            self?.eventRouter.publish(.audioOutputDeviceChanged, data: [:])
        }
    }
    
    // Suppress the native macOS HUD overlays
    private func suppressNativeHUD() {
        // This uses a private API to disable the system HUD
        // Note: This may not work on all macOS versions
        let script = """
        launchctl unload -w /System/Library/LaunchAgents/com.apple.OSDUIHelper.plist 2>/dev/null
        """
        
        // Run with elevated privileges
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", script]
        
        do {
            try task.run()
        } catch {
            print("Could not suppress native HUD: \(error)")
            // Continue anyway - custom HUD will still work
        }
    }
    
    // MARK: - Volume Monitoring

    /// Clear the list of registered listeners when switching devices
    /// Note: CoreAudio's AudioObjectRemovePropertyListenerBlock requires the exact same block pointer,
    /// which isn't possible with Swift closures. The old listeners will become orphaned on the old device
    /// but won't fire since that device is no longer the default output. We track addresses to prevent
    /// duplicate registration on the same device.
    private func removeVolumeListeners() {
        registeredVolumeListenerAddresses.removeAll()
    }

    private func setupVolumeMonitoring() {
        // Remove listeners from previous device before setting up new ones
        removeVolumeListeners()

        // Get default audio output device
        var deviceID = AudioDeviceID(0)
        var deviceIDSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &deviceIDSize,
            &deviceID
        )

        guard status == noErr else {
            print("🔊 setupVolumeMonitoring: Failed to get default output device")
            return
        }

        audioDeviceID = deviceID
        print("🔊 setupVolumeMonitoring: Using audio device ID \(deviceID)")

        // Check what properties this device supports
        var volumeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let hasVolumeProperty = AudioObjectHasProperty(audioDeviceID, &volumeAddress)
        deviceSupportsVolumeProperty = hasVolumeProperty
        print("🔊 setupVolumeMonitoring: Device has volume property: \(hasVolumeProperty)")

        // If switching to a device without volume property, reset estimated volume
        if !hasVolumeProperty {
            estimatedBluetoothVolume = 0.5  // Start at 50%
            print("🔊 setupVolumeMonitoring: Using estimated volume for Bluetooth device")
        }

        // Register for volume change notifications
        var volumeListenerAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        if hasVolumeProperty {
            AudioObjectAddPropertyListenerBlock(
                audioDeviceID,
                &volumeListenerAddress,
                DispatchQueue.main
            ) { [weak self] _, _ in
                self?.volumeDidChange()
            }
            registeredVolumeListenerAddresses.append((audioDeviceID, volumeListenerAddress))
        }

        // Register for mute change notifications
        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        // Try to register on main element first
        if AudioObjectHasProperty(audioDeviceID, &muteAddress) {
            AudioObjectAddPropertyListenerBlock(
                audioDeviceID,
                &muteAddress,
                DispatchQueue.main
            ) { [weak self] _, _ in
                self?.volumeDidChange()
            }
            registeredVolumeListenerAddresses.append((audioDeviceID, muteAddress))
        }

        // Also try master channel (element 0)
        var muteAddressElement0 = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: 0
        )
        if AudioObjectHasProperty(audioDeviceID, &muteAddressElement0) {
            AudioObjectAddPropertyListenerBlock(
                audioDeviceID,
                &muteAddressElement0,
                DispatchQueue.main
            ) { [weak self] _, _ in
                self?.volumeDidChange()
            }
            registeredVolumeListenerAddresses.append((audioDeviceID, muteAddressElement0))
        }

        // For Bluetooth devices that don't expose volume property,
        // we need to rely on key event monitoring (handleMediaKeyEvent)
        // Get initial volume state (but don't publish event - avoid HUD on device switch)
        updateCurrentVolumeState()
    }

    /// Update internal volume state without publishing event (used during device setup)
    private func updateCurrentVolumeState() {
        guard let volume = getCurrentVolume() else {
            print("🔊 updateCurrentVolumeState: Failed to get volume for device \(audioDeviceID)")
            return
        }

        let isMuted = getIsMuted()
        currentState.volume = volume
        currentState.isMuted = isMuted

        if volume > 0.01 {
            previousNonZeroVolume = volume
        }

        print("🔊 updateCurrentVolumeState: volume=\(volume), muted=\(isMuted) (no HUD)")
    }

    private func volumeDidChange() {
        // Check if we're in suppression window (e.g., device just changed)
        if Date() < suppressVolumeEventsUntil {
            print("🔊 volumeDidChange: Suppressed (device switch in progress)")
            return
        }

        guard let volume = getCurrentVolume() else {
            print("🔊 volumeDidChange: Failed to get current volume for device \(audioDeviceID)")
            return
        }
        print("🔊 volumeDidChange: volume=\(volume) for device \(audioDeviceID)")

        // Check hardware mute first
        let isMuted = getIsMuted()

        // Save non-zero volume for potential unmute restoration
        if volume > 0.01 {
            previousNonZeroVolume = volume
        }

        // Fallback: If no hardware mute detected, treat volume at 0.0 as muted if previous volume was non-zero
        let effectivelyMuted = isMuted || (volume == 0.0 && previousNonZeroVolume > 0.01)

        // Always publish event to show HUD, even if value didn't change (e.g., pressing vol up at max)
        currentState.volume = volume
        currentState.isMuted = effectivelyMuted
        eventRouter.publish(.volumeChanged, data: ["level": effectivelyMuted ? 0.0 : volume, "isMuted": effectivelyMuted])
    }
    
    private func getCurrentVolume() -> Float? {
        var volume: Float32 = 0
        var volumeSize = UInt32(MemoryLayout<Float32>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            audioDeviceID,
            &address,
            0,
            nil,
            &volumeSize,
            &volume
        )

        return status == noErr ? volume : nil
    }

    private func getIsMuted() -> Bool {
        var muted: UInt32 = 0
        var mutedSize = UInt32(MemoryLayout<UInt32>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        // First check if the device supports mute property
        if AudioObjectHasProperty(audioDeviceID, &address) {
            let status = AudioObjectGetPropertyData(
                audioDeviceID,
                &address,
                0,
                nil,
                &mutedSize,
                &muted
            )

            if status == noErr {
                return muted != 0
            }
        }

        // Fallback: Check master volume mute on element 0 (master channel)
        address.mElement = 0
        if AudioObjectHasProperty(audioDeviceID, &address) {
            let status = AudioObjectGetPropertyData(
                audioDeviceID,
                &address,
                0,
                nil,
                &mutedSize,
                &muted
            )

            if status == noErr {
                return muted != 0
            }
        }

        return false
    }
    
    // MARK: - Brightness Monitoring

    private func setupBrightnessMonitoring() {
        // Start monitoring using the event-based BrightnessHelper (via Objective-C bridging)
        BrightnessHelper.shared().startMonitoring()

        // Listen for brightness change notifications
        // Use the string value directly - matches what's defined in BrightnessHelper.m
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(brightnessDidChange),
            name: NSNotification.Name("AegisBrightnessChanged"),
            object: nil
        )

        // Get initial brightness
        brightnessDidChange()
    }

    @objc private func brightnessDidChange() {
        // Get brightness using BrightnessHelper
        let brightness = BrightnessHelper.shared().getBrightness()

        // Always publish event to show HUD, even if value didn't change (e.g., pressing brightness up at max)
        currentState.brightness = brightness
        eventRouter.publish(.brightnessChanged, data: ["level": brightness])
    }
    
    // MARK: - Key Event Monitoring (for max/min edge cases)

    private func setupKeyEventMonitoring() {
        // Use local monitor to catch media key events
        // This WILL receive events even when volume doesn't change (at max/min)
        NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            self?.handleMediaKeyEvent(event)
            return event
        }
    }

    private func handleMediaKeyEvent(_ event: NSEvent) {
        // System-defined events include media keys (volume, brightness, etc.)
        // subtype 8 = AUX control key (volume, brightness, play/pause, etc.)
        guard event.subtype.rawValue == 8 else {
            return
        }

        let keyCode = ((event.data1 & 0xFFFF0000) >> 16)
        let keyFlags = (event.data1 & 0x0000FFFF)
        let keyPressed = ((keyFlags & 0xFF00) >> 8) == 0xA
        let keyRepeat = (keyFlags & 0x1) == 0x1

        print("🔊 handleMediaKeyEvent: keyCode=\(keyCode), keyPressed=\(keyPressed), keyRepeat=\(keyRepeat)")

        // Only respond to key press (not release) and not repeats
        guard keyPressed && !keyRepeat else {
            return
        }

        // Key codes: 0 = vol up, 1 = vol down, 2 = brightness up, 3 = brightness down, 7 = mute
        switch keyCode {
        case 0, 1:  // Volume up/down
            print("🔊 handleMediaKeyEvent: Volume key detected (deviceSupportsVolume: \(deviceSupportsVolumeProperty))")

            if deviceSupportsVolumeProperty {
                // Normal path - read actual volume from CoreAudio
                DispatchQueue.main.async {
                    self.volumeDidChange()
                }
            } else {
                // Bluetooth device without volume property - estimate volume
                DispatchQueue.main.async {
                    self.handleBluetoothVolumeKey(isVolumeUp: keyCode == 0)
                }
            }
        case 7:  // Mute toggle
            print("🔊 handleMediaKeyEvent: Mute key detected (deviceSupportsVolume: \(deviceSupportsVolumeProperty))")

            if deviceSupportsVolumeProperty {
                // Normal path - read actual mute state from CoreAudio
                DispatchQueue.main.async {
                    self.volumeDidChange()
                }
            } else {
                // Bluetooth device - toggle mute state
                DispatchQueue.main.async {
                    self.handleBluetoothMuteKey()
                }
            }
        case 2, 3:  // Brightness up/down
            print("🔊 handleMediaKeyEvent: Brightness key detected, triggering brightnessDidChange")
            // Trigger brightnessDidChange which will read current brightness and publish event
            DispatchQueue.main.async {
                self.brightnessDidChange()
            }
        default:
            break
        }
    }

    /// Handle volume key press for Bluetooth devices that don't expose volume property
    private func handleBluetoothVolumeKey(isVolumeUp: Bool) {
        // macOS typically changes volume by ~6.25% per key press (1/16th)
        let volumeStep: Float = 0.0625

        if isVolumeUp {
            estimatedBluetoothVolume = min(1.0, estimatedBluetoothVolume + volumeStep)
        } else {
            estimatedBluetoothVolume = max(0.0, estimatedBluetoothVolume - volumeStep)
        }

        print("🔊 handleBluetoothVolumeKey: \(isVolumeUp ? "UP" : "DOWN") -> estimated volume: \(estimatedBluetoothVolume)")

        // Unmute if adjusting volume while muted
        if estimatedBluetoothMuted {
            estimatedBluetoothMuted = false
        }

        // Publish volume event with estimated value
        currentState.volume = estimatedBluetoothVolume
        currentState.isMuted = false
        eventRouter.publish(.volumeChanged, data: ["level": estimatedBluetoothVolume, "isMuted": false])
    }

    /// Handle mute key press for Bluetooth devices
    private func handleBluetoothMuteKey() {
        estimatedBluetoothMuted.toggle()

        print("🔊 handleBluetoothMuteKey: muted = \(estimatedBluetoothMuted)")

        currentState.isMuted = estimatedBluetoothMuted
        // When muted, show level as 0; when unmuted, show the estimated volume
        let displayLevel: Float = estimatedBluetoothMuted ? 0.0 : estimatedBluetoothVolume
        eventRouter.publish(.volumeChanged, data: ["level": displayLevel, "isMuted": estimatedBluetoothMuted])
    }
}
