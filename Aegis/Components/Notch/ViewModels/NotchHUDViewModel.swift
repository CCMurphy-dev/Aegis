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
    @Published var isVisible: Bool = false {
        didSet {
            print("🎼 MediaHUDViewModel: isVisible changed from \(oldValue) to \(isVisible)")
        }
    }
    @Published var info: MediaInfo = .placeholder

    /// Whether the overlay HUD (volume/brightness) is currently showing
    /// When true, the right panel of the media HUD should hide to avoid overlap
    @Published var isOverlayActive: Bool = false

    /// Current right panel width (for overlay HUD to match when covering media content)
    @Published var currentRightPanelWidth: CGFloat = 0

    /// Whether the HUD has been dismissed by the user (resets on track change)
    @Published var isDismissed: Bool = false

    /// Track identifier when dismissed - used to reset isDismissed on track change
    private var dismissedTrackId: String?

    func updateInfo(_ newInfo: MediaInfo) {
        print("🎼 MediaHUDViewModel: Updating info - \(newInfo.title) by \(newInfo.artist), hasAlbumArt: \(newInfo.albumArt != nil), isPlaying: \(newInfo.isPlaying)")

        // Reset dismissed state if track changed
        if isDismissed && newInfo.trackIdentifier != dismissedTrackId {
            print("🎼 MediaHUDViewModel: New track detected, resetting dismissed state")
            isDismissed = false
            dismissedTrackId = nil
        }

        self.info = newInfo
    }

    /// Dismiss the HUD until the next track starts
    func dismiss() {
        print("🎼 MediaHUDViewModel: User dismissed HUD")
        isDismissed = true
        dismissedTrackId = info.trackIdentifier
    }
}
