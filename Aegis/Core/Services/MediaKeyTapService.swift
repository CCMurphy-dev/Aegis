import Foundation
import CoreAudio
import AudioToolbox
import CoreGraphics
import ApplicationServices
import AppKit

/// Intercepts volume/brightness media keys at the CGEventTap level to suppress
/// the native macOS BezelServices HUD. The tap swallows the events so BezelServices
/// never sees them, while manually adjusting volume/brightness so the existing
/// CoreAudio/brightness listeners fire and show the Aegis notch HUD instead.
final class MediaKeyTapService {

    enum KeyAction {
        case volumeUp
        case volumeDown
        case mute
    }

    static let shared = MediaKeyTapService()

    /// Called on the CGEventTap thread after volume/mute is adjusted.
    /// SystemInfoService sets this to update the HUD directly.
    var onVolumeKeyAction: ((KeyAction) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private let NX_KEYTYPE_SOUND_UP: Int32 = 0
    private let NX_KEYTYPE_SOUND_DOWN: Int32 = 1
    private let NX_KEYTYPE_BRIGHTNESS_UP: Int32 = 2
    private let NX_KEYTYPE_BRIGHTNESS_DOWN: Int32 = 3
    private let NX_KEYTYPE_MUTE: Int32 = 7

    private let kCGEventSystemDefinedType = CGEventType(rawValue: 14)!

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard AXIsProcessTrusted(), eventTap == nil else { return }

        let eventMask = (1 << kCGEventSystemDefinedType.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (_, type, event, _) -> Unmanaged<CGEvent>? in
                return MediaKeyTapService.shared.handle(type: type, event: event)
            },
            userInfo: nil
        ) else {
            print("🔊 MediaKeyTapService: failed to create event tap (check Accessibility permission)")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }

        print("🔊 MediaKeyTapService: started")
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
                runLoopSource = nil
            }
            eventTap = nil
        }
        print("🔊 MediaKeyTapService: stopped")
    }

    // MARK: - Event Handling

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable tap if macOS disabled it due to timeout
        if type == .tapDisabledByTimeout {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // Pass through regular keyboard events
        if type == .keyDown || type == .keyUp {
            return Unmanaged.passUnretained(event)
        }

        guard type.rawValue == 14 else {
            return Unmanaged.passUnretained(event)
        }

        let subtypeField = CGEventField(rawValue: 160)!
        let data1Field = CGEventField(rawValue: 161)!

        var subtype = event.getIntegerValueField(subtypeField)
        var data1 = event.getIntegerValueField(data1Field)

        // Fallback: some events have subtype=0 in CGEvent fields but correct values in NSEvent
        if subtype == 0, let nsEvent = NSEvent(cgEvent: event) {
            if nsEvent.type == .systemDefined {
                let nsSubtype = Int64(nsEvent.subtype.rawValue)
                let nsData1 = Int64(nsEvent.data1)
                if nsSubtype != 0 {
                    subtype = nsSubtype
                    data1 = nsData1
                }
            }
        }

        guard subtype == 8 else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = Int32((data1 >> 16) & 0xFFFF)
        let keyFlags = data1 & 0xFFFF
        let isKeyDown = ((keyFlags & 0xFF00) >> 8) == 0xA
        let isKeyUp   = ((keyFlags & 0xFF00) >> 8) == 0xB

        if isKeyDown {
            switch keyCode {
            case NX_KEYTYPE_SOUND_UP:
                adjustVolume(by: 1.0 / 16.0)
                DispatchQueue.main.async { self.onVolumeKeyAction?(.volumeUp) }
                return nil
            case NX_KEYTYPE_SOUND_DOWN:
                adjustVolume(by: -1.0 / 16.0)
                DispatchQueue.main.async { self.onVolumeKeyAction?(.volumeDown) }
                return nil
            case NX_KEYTYPE_MUTE:
                toggleMute()
                DispatchQueue.main.async { self.onVolumeKeyAction?(.mute) }
                return nil
            case NX_KEYTYPE_BRIGHTNESS_UP:
                adjustBrightness(by: 1.0 / 16.0)
                return nil
            case NX_KEYTYPE_BRIGHTNESS_DOWN:
                adjustBrightness(by: -1.0 / 16.0)
                return nil
            default:
                break
            }
        } else if isKeyUp {
            // Swallow key-up events too so BezelServices doesn't re-trigger on release
            switch keyCode {
            case NX_KEYTYPE_SOUND_UP, NX_KEYTYPE_SOUND_DOWN, NX_KEYTYPE_MUTE,
                 NX_KEYTYPE_BRIGHTNESS_UP, NX_KEYTYPE_BRIGHTNESS_DOWN:
                return nil
            default:
                break
            }
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Volume

    private func defaultOutputDevice() -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return deviceID
    }

    private func adjustVolume(by delta: Float) {
        let deviceID = defaultOutputDevice()

        // Use VirtualMainVolume — works for all device types including Bluetooth
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var current: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &current)

        var newVol = max(0.0, min(1.0, current + delta))
        AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &newVol)

        // Unmute when adjusting volume (matches macOS behaviour)
        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var muted: UInt32 = 0
        AudioObjectSetPropertyData(deviceID, &muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &muted)
    }

    private func toggleMute() {
        let deviceID = defaultOutputDevice()

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted)
        var newMuted: UInt32 = muted == 0 ? 1 : 0
        AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &newMuted)
    }

    // MARK: - Brightness

    private func adjustBrightness(by delta: Float) {
        let current = BrightnessHelper.shared().getBrightness()
        let newBrightness = max(0.0, min(1.0, current + delta))
        BrightnessHelper.shared().setBrightness(newBrightness)
    }
}
