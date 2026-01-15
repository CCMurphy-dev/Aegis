import Foundation

// MARK: - App Events

/// Event types that can occur in the app
enum AppEvent: CaseIterable {
    case spaceChanged
    case windowsChanged
    case volumeChanged
    case brightnessChanged
    case musicPlaybackChanged
    case musicTrackChanged
    case systemStateChanged
    case bluetoothDeviceConnected
    case bluetoothDeviceDisconnected
    case audioOutputDeviceChanged  // Fired when default audio output changes
}

// MARK: - Event Router

/// Simple publish/subscribe system for app events
class EventRouter {
    // Type alias for event handlers (callbacks)
    typealias EventHandler = ([String: Any]) -> Void
    
    // Dictionary mapping events to arrays of handlers
    private var subscribers: [AppEvent: [EventHandler]] = [:]
    
    // Thread-safe queue for event handling
    private let queue = DispatchQueue(label: "com.aegis.eventrouter")
    
    init() {
        // Initialize empty subscriber lists for each event type
        for event in AppEvent.allCases {
            subscribers[event] = []
        }
    }
    
    // Subscribe to an event
    // Usage: eventRouter.subscribe(to: .volumeChanged) { data in ... }
    func subscribe(to event: AppEvent, handler: @escaping EventHandler) {
        queue.async { [weak self] in
            self?.subscribers[event]?.append(handler)
        }
    }
    
    // Publish an event with optional data
    // Usage: eventRouter.publish(.volumeChanged, data: ["level": 0.5])
    func publish(_ event: AppEvent, data: [String: Any] = [:]) {
        queue.async { [weak self] in
            guard let self = self else { return }

            if let handlers = self.subscribers[event] {
                for handler in handlers {
                    // Ensure UI updates happen on main thread
                    DispatchQueue.main.async {
                        handler(data)
                    }
                }
            }
        }
    }
}
