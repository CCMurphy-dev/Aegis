//
//  ProgressBarAnimator.swift
//  Aegis
//
//  Created by Claude on 13/01/2026.
//

import Foundation
import Combine
import QuartzCore

/// Lightweight animator for smooth progress bar updates
/// Uses a simple timer-based approach for minimal CPU overhead
final class ProgressBarAnimator: ObservableObject {
    /// The displayed level (what the UI actually shows)
    @Published private(set) var displayed: Double = 0

    /// The target level (what we're interpolating toward)
    private var target: Double = 0

    /// Animation timer (60fps max)
    private var timer: DispatchSourceTimer?

    /// Lock for thread-safe access
    private let lock = NSLock()

    /// Whether animation is currently active
    private var isAnimating = false

    /// Flag to snap to target on next setTarget (after stop/start cycle)
    private var needsImmediateSnap: Bool = true

    /// Interpolation speed (fraction of remaining distance per frame)
    /// 0.25 = smooth, 0.4 = snappy
    private let interpolationSpeed: Double = 0.35

    /// Threshold for snapping to target (avoid infinite approach)
    private let snapThreshold: Double = 0.005

    init() {
        // Timer created on-demand when animation starts
    }

    deinit {
        timer?.cancel()
        timer = nil
    }

    /// Start the animator (called when HUD becomes visible)
    func start() {
        // No-op - animation starts automatically when setTarget is called
    }

    /// Stop the animator (called when HUD is hidden)
    func stop() {
        lock.lock()
        stopTimer()
        needsImmediateSnap = true
        lock.unlock()
    }

    /// Update the target level (called from showVolume/showBrightness)
    func setTarget(_ value: Double) {
        lock.lock()

        let shouldSnap = needsImmediateSnap
        target = value

        if shouldSnap {
            // First call after stop - snap immediately
            needsImmediateSnap = false
            lock.unlock()

            DispatchQueue.main.async { [weak self] in
                self?.displayed = value
            }
            return
        }

        // Check if we need to animate
        let currentDisplayed = displayed
        let needsAnimation = abs(value - currentDisplayed) > snapThreshold

        if needsAnimation && !isAnimating {
            startTimer()
        }

        lock.unlock()
    }

    // MARK: - Private

    private func startTimer() {
        guard timer == nil else { return }

        isAnimating = true

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(16)) // ~60fps

        timer.setEventHandler { [weak self] in
            self?.tick()
        }

        self.timer = timer
        timer.resume()
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
        isAnimating = false
    }

    private func tick() {
        lock.lock()
        let currentTarget = target
        lock.unlock()

        let current = displayed
        let delta = currentTarget - current

        // Snap if close enough
        if abs(delta) <= snapThreshold {
            displayed = currentTarget

            lock.lock()
            stopTimer()
            lock.unlock()
            return
        }

        // Exponential ease-out interpolation
        let step = delta * interpolationSpeed
        displayed = current + step
    }

    // MARK: - Diagnostics (no-op for compatibility)

    func enableDiagnosticLogging(_ enabled: Bool = true) {}
    func resetDiagnostics() {}
}
