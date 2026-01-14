import Foundation
import CoreAudio
import IOKit.ps
import AppKit

// Model for system state
struct SystemState {
    var volume: Float
    var brightness: Float
    var batteryLevel: Float
    var isCharging: Bool
    var isMuted: Bool
}

// Service to monitor system volume, brightness, battery
class SystemInfoService {
    private let eventRouter: EventRouter
    private var currentState = SystemState(volume: 0, brightness: 0, batteryLevel: 0, isCharging: false, isMuted: false)

    // Audio device ID for volume monitoring
    private var audioDeviceID: AudioDeviceID = 0

    // Track previous non-zero volume to detect mute via volume = 0
    private var previousNonZeroVolume: Float = 0.5
    
    init(eventRouter: EventRouter) {
        self.eventRouter = eventRouter

        // Suppress native macOS volume/brightness HUD
        suppressNativeHUD()

        // Start monitoring
        setupVolumeMonitoring()
        setupBrightnessMonitoring()
        setupBatteryMonitoring()
        setupKeyEventMonitoring()
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
    
    private func setupVolumeMonitoring() {
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
            return
        }

        audioDeviceID = deviceID

        // Register for volume change notifications
        address.mSelector = kAudioDevicePropertyVolumeScalar
        address.mScope = kAudioDevicePropertyScopeOutput

        AudioObjectAddPropertyListenerBlock(
            audioDeviceID,
            &address,
            DispatchQueue.main
        ) { [weak self] _, _ in
            self?.volumeDidChange()
        }

        // Register for mute change notifications
        address.mSelector = kAudioDevicePropertyMute

        // Try to register on main element first
        if AudioObjectHasProperty(audioDeviceID, &address) {
            AudioObjectAddPropertyListenerBlock(
                audioDeviceID,
                &address,
                DispatchQueue.main
            ) { [weak self] _, _ in
                self?.volumeDidChange()
            }
        }

        // Also try master channel (element 0)
        address.mElement = 0
        if AudioObjectHasProperty(audioDeviceID, &address) {
            AudioObjectAddPropertyListenerBlock(
                audioDeviceID,
                &address,
                DispatchQueue.main
            ) { [weak self] _, _ in
                self?.volumeDidChange()
            }
        }

        // Get initial volume
        volumeDidChange()
    }

    private func volumeDidChange() {
        guard let volume = getCurrentVolume() else { return }

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
    
    // MARK: - Battery Monitoring
    
    private func setupBatteryMonitoring() {
        // Poll battery every 5 seconds
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkBattery()
        }
        
        // Get initial battery state
        checkBattery()
    }
    
    private func checkBattery() {
        let powerInfo = IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
        let powerSources = IOPSCopyPowerSourcesList(powerInfo)?.takeRetainedValue() as? [CFTypeRef]
        
        guard let sources = powerSources, let source = sources.first else { return }
        
        let description = IOPSGetPowerSourceDescription(powerInfo, source)?.takeUnretainedValue() as? [String: Any]
        
        if let capacity = description?[kIOPSCurrentCapacityKey] as? Int,
           let maxCapacity = description?[kIOPSMaxCapacityKey] as? Int {
            let level = Float(capacity) / Float(maxCapacity)
            
            let isCharging = description?[kIOPSIsChargingKey] as? Bool ?? false
            
            if abs(level - currentState.batteryLevel) > 0.01 || isCharging != currentState.isCharging {
                currentState.batteryLevel = level
                currentState.isCharging = isCharging
                eventRouter.publish(.systemStateChanged, data: [
                    "battery": level,
                    "charging": isCharging
                ])
            }
        }
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

        // Only respond to key press (not release) and not repeats
        guard keyPressed && !keyRepeat else {
            return
        }

        // Key codes: 0 = vol up, 1 = vol down, 2 = brightness up, 3 = brightness down
        switch keyCode {
        case 0, 1:  // Volume up/down
            // Trigger volumeDidChange which will read current volume and publish event
            // This ensures HUD shows even if volume didn't change (at max/min)
            DispatchQueue.main.async {
                self.volumeDidChange()
            }
        case 2, 3:  // Brightness up/down
            // Trigger brightnessDidChange which will read current brightness and publish event
            DispatchQueue.main.async {
                self.brightnessDidChange()
            }
        default:
            break
        }
    }

    // Public getters
    func getCurrentState() -> SystemState {
        return currentState
    }
}
