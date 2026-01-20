//
//  NotificationService.swift
//  Aegis
//
//  Event-driven notification watcher using Accessibility API
//  Zero CPU when idle - only wakes on notification events
//

import Cocoa
import ApplicationServices

class NotificationService {
    private var observer: AXObserver?
    private let eventRouter: EventRouter
    private var backgroundRunLoop: CFRunLoop?
    private var isMonitoring = false

    init(eventRouter: EventRouter) {
        self.eventRouter = eventRouter
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        // Run on background queue - CFRunLoop blocks but uses zero CPU when idle
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.setupObserver()
            self?.backgroundRunLoop = CFRunLoopGetCurrent()
            CFRunLoopRun()  // Blocks here, wakes only on notification events
        }
    }

    private func setupObserver() {
        // Find Notification Center process
        guard let ncApp = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == "com.apple.notificationcenterui" })
        else {
            print("⚠️ NotificationService: notificationcenterui not found")
            return
        }

        // C callback - minimal overhead, called only on window creation
        let callback: AXObserverCallback = { _, element, _, refcon in
            guard let refcon = refcon else { return }
            let service = Unmanaged<NotificationService>.fromOpaque(refcon).takeUnretainedValue()
            service.handleNotificationWindow(element)
        }

        var observer: AXObserver?
        guard AXObserverCreate(ncApp.processIdentifier, callback, &observer) == .success,
              let observer = observer else {
            print("⚠️ NotificationService: Failed to create AXObserver (check Accessibility permissions)")
            return
        }

        self.observer = observer

        // Register for window creation only (not all AX events)
        let ncElement = AXUIElementCreateApplication(ncApp.processIdentifier)
        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        AXObserverAddNotification(observer, ncElement, kAXWindowCreatedNotification as CFString, refcon)

        // Add to run loop - this is efficient kernel-level event waiting
        let source = AXObserverGetRunLoopSource(observer)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)

        print("✅ NotificationService: Monitoring active (event-driven, zero idle CPU)")
    }

    private func handleNotificationWindow(_ element: AXUIElement) {
        // OPTIMIZATION: Dismiss FIRST to minimize visible flash (~20-50ms savings)
        // The AXUIElement remains valid for reading even after dismiss action starts
        dismissNativeBanner(element)

        // Then extract content (banner is already animating out)
        let notificationData = extractNotificationContent(element)

        // Skip if we couldn't extract meaningful content
        guard !notificationData.title.isEmpty || !notificationData.body.isEmpty || !notificationData.appName.isEmpty else {
            return
        }

        // Publish to main thread (single async dispatch)
        DispatchQueue.main.async { [weak self] in
            self?.eventRouter.publish(.notificationReceived, data: [
                "appName": notificationData.appName,
                "title": notificationData.title,
                "body": notificationData.body,
                "bundleIdentifier": notificationData.bundleId
            ])
        }
    }

    // MARK: - Debug AX Hierarchy Dump

    #if DEBUG
    private func dumpAXHierarchy(_ element: AXUIElement, indent: Int = 0) {
        let prefix = String(repeating: "  ", count: indent)

        // Get role
        var roleRef: CFTypeRef?
        let role: String
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
           let r = roleRef as? String {
            role = r
        } else {
            role = "unknown"
        }

        // Get value
        var valueRef: CFTypeRef?
        let value: String
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success {
            if let v = valueRef as? String {
                let truncated = v.count > 50 ? String(v.prefix(50)) + "..." : v
                value = truncated
            } else {
                value = String(describing: valueRef)
            }
        } else {
            value = "(no value)"
        }

        // Get description
        var descRef: CFTypeRef?
        let desc: String
        if AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef) == .success,
           let d = descRef as? String, !d.isEmpty {
            desc = " desc='\(d)'"
        } else {
            desc = ""
        }

        // Get title
        var titleRef: CFTypeRef?
        let title: String
        if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success,
           let t = titleRef as? String, !t.isEmpty {
            title = " title='\(t)'"
        } else {
            title = ""
        }

        // Get subrole
        var subroleRef: CFTypeRef?
        let subrole: String
        if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef) == .success,
           let s = subroleRef as? String, !s.isEmpty {
            subrole = " subrole='\(s)'"
        } else {
            subrole = ""
        }

        print("\(prefix)[\(role)\(subrole)] value='\(value)'\(desc)\(title)")

        // Recurse into children
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                dumpAXHierarchy(child, indent: indent + 1)
            }
        }
    }
    #endif

    // MARK: - Content Extraction

    private func extractNotificationContent(_ element: AXUIElement) -> (appName: String, title: String, body: String, bundleId: String) {
        var appName = ""
        var title = ""
        var body = ""
        var bundleId = ""

        // Find the first AXNotificationCenterBanner in the hierarchy
        if let bannerData = findFirstNotificationBanner(element) {
            appName = bannerData.appName
            title = bannerData.title
            body = bannerData.body
        }

        // Get bundle identifier from the app name
        if !appName.isEmpty {
            bundleId = bundleIdentifierForAppName(appName)
        }

        // Debug logging
        print("🔔 Extracted: appName='\(appName)' title='\(title)' body='\(body)' bundleId='\(bundleId)'")

        return (appName, title, body, bundleId)
    }

    /// Find the first AXNotificationCenterBanner and extract its content
    /// The desc attribute format is: "AppName, Title/Sender, Body"
    private func findFirstNotificationBanner(_ element: AXUIElement) -> (appName: String, title: String, body: String)? {
        // Check if this element is a notification banner
        var subroleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef) == .success,
           let subrole = subroleRef as? String, subrole == "AXNotificationCenterBanner" {

            // Get the description which contains: "AppName, Title, Body"
            var descRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef) == .success,
               let desc = descRef as? String {

                // Parse the comma-separated description
                let parts = desc.components(separatedBy: ", ")
                if parts.count >= 2 {
                    let appName = parts[0]
                    let title = parts[1]
                    // Body is everything after the second comma (may contain commas itself)
                    let body = parts.count >= 3 ? parts.dropFirst(2).joined(separator: ", ") : ""

                    return (appName, title, body)
                }
            }
        }

        // Recurse into children
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                if let result = findFirstNotificationBanner(child) {
                    return result
                }
            }
        }

        return nil
    }

    // Hardcoded bundle IDs for common apps (fallback when app isn't running)
    private static let knownAppBundleIds: [String: String] = [
        "messages": "com.apple.MobileSMS",
        "whatsapp": "net.whatsapp.WhatsApp",
        "slack": "com.tinyspeck.slackmacgap",
        "telegram": "ru.keepcoder.Telegram",
        "discord": "com.hnc.Discord",
        "mail": "com.apple.mail",
        "calendar": "com.apple.iCal",
        "reminders": "com.apple.reminders",
        "facetime": "com.apple.FaceTime",
        "finder": "com.apple.finder",
        "safari": "com.apple.Safari",
        "music": "com.apple.Music",
        "photos": "com.apple.Photos",
        "notes": "com.apple.Notes"
    ]

    private func bundleIdentifierForAppName(_ appName: String) -> String {
        let normalized = appName.lowercased()

        // Check hardcoded list first (handles apps that may not be running)
        if let bundleId = Self.knownAppBundleIds[normalized] {
            return bundleId
        }

        // Case-insensitive match against running apps
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName?.localizedCaseInsensitiveCompare(appName) == .orderedSame
        }) {
            return app.bundleIdentifier ?? ""
        }

        // Fallback: partial match (for "Messages" vs "Messages.app" or locale differences)
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName?.lowercased().contains(normalized) == true ||
            normalized.contains($0.localizedName?.lowercased() ?? "")
        }) {
            return app.bundleIdentifier ?? ""
        }

        return ""
    }

    private func dismissNativeBanner(_ element: AXUIElement) {
        // First, find the actual banner element (might be the element itself or a child)
        if let bannerElement = findBannerElement(element) {
            // Log available actions on the banner using AXUIElementCopyActionNames
            var actionsRef: CFArray?
            if AXUIElementCopyActionNames(bannerElement, &actionsRef) == .success,
               let actions = actionsRef as? [String] {
                print("🔔 Banner available actions: \(actions)")

                // First, look for the "Close" action specifically (it has a weird format)
                for action in actions {
                    if action.contains("Close") {
                        let result = AXUIElementPerformAction(bannerElement, action as CFString)
                        print("🔔 Tried Close action '\(action)': \(result == .success ? "SUCCESS" : "failed (\(result.rawValue))")")
                        if result == .success {
                            return
                        }
                    }
                }

                // If no Close action worked, try others (but skip AXPress as it just opens the app)
                for action in actions where !action.contains("AXPress") && !action.contains("Show Details") {
                    let result = AXUIElementPerformAction(bannerElement, action as CFString)
                    print("🔔 Tried action '\(action)': \(result == .success ? "SUCCESS" : "failed (\(result.rawValue))")")
                    if result == .success {
                        return
                    }
                }
            } else {
                print("🔔 Banner has no actions")
            }

            // Strategy 1: Try AXDismissAction (if available)
            let dismissResult = AXUIElementPerformAction(bannerElement, "AXDismiss" as CFString)
            if dismissResult == .success {
                print("🔔 Dismissed banner via AXDismiss action")
                return
            }

            // Strategy 2: Try AXPress on the banner itself
            let pressResult = AXUIElementPerformAction(bannerElement, kAXPressAction as CFString)
            if pressResult == .success {
                print("🔔 Dismissed banner via AXPress action")
                return
            }

            // Strategy 3: Try AXCancel (common dismiss action)
            let cancelResult = AXUIElementPerformAction(bannerElement, "AXCancel" as CFString)
            if cancelResult == .success {
                print("🔔 Dismissed banner via AXCancel action")
                return
            }

            // Strategy 4: Look for close button in children
            var childrenRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(bannerElement, kAXChildrenAttribute as CFString, &childrenRef) == .success,
               let children = childrenRef as? [AXUIElement] {
                if dismissButtonRecursively(in: children) {
                    return
                }
            }
        }

        // Fallback: Try on the original element's children
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            _ = dismissButtonRecursively(in: children)
        }

        print("🔔 Warning: Could not dismiss native banner")
    }

    /// Find the AXNotificationCenterBanner element in the hierarchy
    private func findBannerElement(_ element: AXUIElement) -> AXUIElement? {
        // Check if this element is the banner
        var subroleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef) == .success,
           let subrole = subroleRef as? String, subrole == "AXNotificationCenterBanner" {
            return element
        }

        // Recurse into children
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                if let banner = findBannerElement(child) {
                    return banner
                }
            }
        }

        return nil
    }

    @discardableResult
    private func dismissButtonRecursively(in elements: [AXUIElement]) -> Bool {
        for element in elements {
            var roleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
               let role = roleRef as? String, role == "AXButton" {
                // Found a button - check if it's the close button
                var subroleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef) == .success,
                   let subrole = subroleRef as? String, subrole == "AXCloseButton" {
                    let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
                    if result == .success {
                        print("🔔 Dismissed via AXCloseButton")
                        return true
                    }
                }

                // Check for close button by description
                var descRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef) == .success,
                   let desc = descRef as? String, desc.lowercased().contains("close") {
                    let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
                    if result == .success {
                        print("🔔 Dismissed via close button (by description)")
                        return true
                    }
                }

                // Check for "X" or dismiss button by title
                var titleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success,
                   let title = titleRef as? String, title == "X" || title.lowercased().contains("dismiss") {
                    let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
                    if result == .success {
                        print("🔔 Dismissed via X/dismiss button")
                        return true
                    }
                }
            }

            // Recurse into children
            var childrenRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
               let children = childrenRef as? [AXUIElement] {
                if dismissButtonRecursively(in: children) {
                    return true
                }
            }
        }
        return false
    }

    func stopMonitoring() {
        isMonitoring = false
        if let runLoop = backgroundRunLoop {
            CFRunLoopStop(runLoop)
        }
        observer = nil
        backgroundRunLoop = nil
    }

    deinit {
        stopMonitoring()
    }
}
