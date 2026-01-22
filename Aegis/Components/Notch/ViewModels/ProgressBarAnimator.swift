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

    /// Current timer interval in milliseconds (adaptive frame rate)
    private var currentInterval: Int = 16

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
        currentInterval = 16  // Start at 60fps

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(currentInterval))

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

        // Adaptive frame rate based on delta magnitude
        // Large delta = 60fps for smooth animation
        // Small delta = lower fps to reduce CPU during settling
        let newInterval: Int
        switch abs(delta) {
        case let d where d > 0.2:  newInterval = 16  // 60fps - large movement
        case let d where d > 0.05: newInterval = 33  // 30fps - moderate
        default:                   newInterval = 66  // 15fps - settling
        }

        // Reschedule timer if interval changed
        if newInterval != currentInterval {
            currentInterval = newInterval
            timer?.schedule(deadline: .now() + .milliseconds(newInterval),
                           repeating: .milliseconds(newInterval))
        }

        // Exponential ease-out interpolation
        let step = delta * interpolationSpeed
        displayed = current + step
    }

    // MARK: - Diagnostics (no-op for compatibility)

    func enableDiagnosticLogging(_ enabled: Bool = true) {}
    func resetDiagnostics() {}
}
