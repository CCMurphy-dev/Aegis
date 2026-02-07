//
//  WindowTitleObserver.swift
//  Aegis
//
//  Observes window title changes using macOS Accessibility API.
//  Used to update expanded window labels when browser tabs change, etc.
//

import Foundation
import AppKit

/// Observes a single window for title changes using AXObserver
final class WindowTitleObserver {
    private var observer: AXObserver?
    private var observedElement: AXUIElement?
    private var observedWindowId: Int?
    private var onTitleChanged: ((Int, String) -> Void)?

    deinit {
        stopObserving()
    }

    /// Start observing a window for title changes
    /// - Parameters:
    ///   - windowId: The yabai window ID to observe
    ///   - pid: The process ID of the window's application
    ///   - onTitleChanged: Callback when title changes (windowId, newTitle)
    func startObserving(windowId: Int, pid: pid_t, onTitleChanged: @escaping (Int, String) -> Void) {
        // Stop any existing observation
        stopObserving()

        self.observedWindowId = windowId
        self.onTitleChanged = onTitleChanged

        // Create observer for the app's process
        let callback: AXObserverCallback = { observer, element, notification, refcon in
            guard let refcon = refcon else { return }
            let observer = Unmanaged<WindowTitleObserver>.fromOpaque(refcon).takeUnretainedValue()
            observer.handleTitleChange(element: element)
        }

        var newObserver: AXObserver?
        guard AXObserverCreate(pid, callback, &newObserver) == .success,
              let observer = newObserver else {
            return
        }

        self.observer = observer

        // Get the focused window element for the app
        let appElement = AXUIElementCreateApplication(pid)
        var focusedWindowRef: CFTypeRef?

        // Try to get the focused window
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowRef) == .success,
           let windowElement = focusedWindowRef {
            self.observedElement = (windowElement as! AXUIElement)

            // Register for title changes on this window
            let refcon = Unmanaged.passUnretained(self).toOpaque()
            AXObserverAddNotification(observer, self.observedElement!, kAXTitleChangedNotification as CFString, refcon)

            // Add observer to run loop
            let source = AXObserverGetRunLoopSource(observer)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    /// Stop observing the current window
    func stopObserving() {
        if let observer = observer, let element = observedElement {
            AXObserverRemoveNotification(observer, element, kAXTitleChangedNotification as CFString)
            if let source = AXObserverGetRunLoopSource(observer) as CFRunLoopSource? {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
        }
        observer = nil
        observedElement = nil
        observedWindowId = nil
        onTitleChanged = nil
    }

    /// Handle title change notification
    private func handleTitleChange(element: AXUIElement) {
        guard let windowId = observedWindowId,
              let callback = onTitleChanged else { return }

        // Get the new title
        var titleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success,
           let title = titleRef as? String {
            DispatchQueue.main.async {
                callback(windowId, title)
            }
        }
    }

    /// Currently observed window ID
    var currentWindowId: Int? {
        return observedWindowId
    }
}
