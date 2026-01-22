//
//  NotchHUDViewModel.swift
//  Aegis
//
//  Created by Claude on 13/01/2026.
//

import Foundation
import SwiftUI
import Combine

/// ViewModel to hold persistent state for overlay HUD
class OverlayHUDViewModel: ObservableObject {
    @Published var isVisible: Bool = false
    @Published var level: Float = 0.0
    @Published var isMuted: Bool = false
    @Published var iconName: String = "speaker.fill"

    // Progress bar animator - hoisted to view model so it survives view rebuilds
    // Not @Published - views observe this directly via @ObservedObject
    let progressAnimator: ProgressBarAnimator

    init() {
        self.progressAnimator = ProgressBarAnimator()
    }
}

/// ViewModel to hold persistent state for media HUD
class MediaHUDViewModel: ObservableObject {
    @Published var isVisible: Bool = false
    @Published var info: MediaInfo = .placeholder

    /// Count of active overlays (volume, brightness, device, focus, notification)
    /// Using a counter instead of boolean prevents race conditions when multiple HUDs overlap
    private var overlayCount: Int = 0

    /// Whether any overlay HUD is currently showing
    /// When true, the right panel of the media HUD should hide to avoid overlap
    /// NOTE: Must be @Published for SwiftUI animations to properly observe changes
    @Published private(set) var isOverlayActive: Bool = false

    /// Increment overlay count (call when showing an overlay HUD)
    func overlayDidShow() {
        overlayCount += 1
        isOverlayActive = overlayCount > 0
        print("🔢 overlayDidShow: count=\(overlayCount), isOverlayActive=\(isOverlayActive)")
    }

    /// Decrement overlay count (call when hiding an overlay HUD)
    func overlayDidHide() {
        overlayCount = max(0, overlayCount - 1)
        isOverlayActive = overlayCount > 0
        print("🔢 overlayDidHide: count=\(overlayCount), isOverlayActive=\(isOverlayActive)")
    }

    /// Reset overlay counter to 0 (safety valve for stuck state)
    func resetOverlayState() {
        if overlayCount != 0 {
            #if DEBUG
            print("⚠️ Resetting stuck overlay counter from \(overlayCount) to 0")
            #endif
            overlayCount = 0
            isOverlayActive = false
        }
    }

    /// Current right panel width (for overlay HUD to match when covering media content)
    @Published var currentRightPanelWidth: CGFloat = 0

    /// Whether the HUD has been dismissed by the user (resets on track change)
    @Published var isDismissed: Bool = false

    /// Track identifier when dismissed - used to reset isDismissed on track change
    private var dismissedTrackId: String?

    func updateInfo(_ newInfo: MediaInfo) {
        // Reset dismissed state if track changed
        if isDismissed && newInfo.trackIdentifier != dismissedTrackId {
            isDismissed = false
            dismissedTrackId = nil
        }

        self.info = newInfo
    }

    /// Dismiss the HUD until the next track starts
    func dismiss() {
        isDismissed = true
        dismissedTrackId = info.trackIdentifier
    }
}

/// ViewModel for notification HUD
class NotificationHUDViewModel: ObservableObject {
    @Published var isVisible: Bool = false
    @Published var appName: String = ""
    @Published var title: String = ""
    @Published var body: String = ""
    @Published var appIcon: NSImage?

    var bundleIdentifier: String = ""

    func show(appName: String, title: String, body: String, bundleIdentifier: String) {
        self.appName = appName
        self.title = title
        self.body = body
        self.bundleIdentifier = bundleIdentifier

        // Get app icon from bundle identifier or app name
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            self.appIcon = NSWorkspace.shared.icon(forFile: appURL.path)
        } else if let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName }),
                  let url = app.bundleURL {
            self.appIcon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            self.appIcon = NSImage(systemSymbolName: "app.fill", accessibilityDescription: "App")
        }

        self.isVisible = true
    }

    /// Callback for opening/focusing the source app (set by controller to integrate with Yabai)
    var openAppHandler: ((String, String) -> Void)?

    func openSourceApp() {
        // Use handler if set (allows Yabai integration from controller)
        if let handler = openAppHandler {
            handler(appName, bundleIdentifier)
            isVisible = false
            return
        }

        // Fallback: use NSWorkspace to launch/activate
        guard !bundleIdentifier.isEmpty else {
            // Try to activate by app name if no bundle identifier
            if !appName.isEmpty,
               let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName }) {
                app.activate()
            }
            isVisible = false
            return
        }

        NSWorkspace.shared.launchApplication(
            withBundleIdentifier: bundleIdentifier,
            options: [],
            additionalEventParamDescriptor: nil,
            launchIdentifier: nil
        )
        isVisible = false
    }
}
