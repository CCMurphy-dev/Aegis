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

/// ViewModel to hold persistent state for music HUD
class MusicHUDViewModel: ObservableObject {
    @Published var isVisible: Bool = false {
        didSet {
            print("🎼 MusicHUDViewModel: isVisible changed from \(oldValue) to \(isVisible)")
        }
    }
    @Published var info: MusicInfo = .placeholder

    func updateInfo(_ newInfo: MusicInfo) {
        print("🎼 MusicHUDViewModel: Updating info - \(newInfo.title) by \(newInfo.artist), hasAlbumArt: \(newInfo.albumArt != nil), isPlaying: \(newInfo.isPlaying)")
        self.info = newInfo
    }
}
