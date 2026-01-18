//
//  ProgressBarAnimator.swift
//  Aegis
//
//  Created by Claude on 13/01/2026.
//

import Foundation
import Combine
import CoreVideo
import QuartzCore

/// Frame-locked animator for smooth progress bar updates
/// Uses CVDisplayLink for vsync-driven updates (cannot be starved by runloop)
final class ProgressBarAnimator: ObservableObject {
    /// The displayed level (what the UI actually shows)
    @Published private(set) var displayed: Double = 0

    /// The target level (what we're interpolating toward)
    private var target: Double = 0

    /// Internal displayed value (updated off main thread, then synced to @Published)
    private var internalDisplayed: Double = 0

    /// Last value synced to @Published (for interpolation when frames are skipped)
    private var lastPublishedValue: Double = 0

    /// Timestamp of last @Published update (for throttling)
    private var lastPublishedTime: CFTimeInterval = 0

    // MARK: - Spring Animation State

    /// Current velocity (units per second)
    private var velocity: Double = 0

    /// Spring stiffness (higher = faster oscillation)
    private var stiffness: Double = 300

    /// Spring damping (higher = less overshoot)
    private var damping: Double = 30

    /// Display link synchronized to screen refresh rate (macOS)
    private var displayLink: CVDisplayLink?

    /// Flag to prevent flooding main queue with display updates
    private var updatePending = false

    /// Lock for thread-safe access to all mutable state
    private let lock = NSLock()

    // MARK: - Performance Diagnostics

    /// Enable detailed frame logging for debugging
    private var enableDiagnostics = false

    /// Timestamp of last frame for delta calculation
    private var lastFrameTime: CFTimeInterval = 0

    /// Cumulative distance traveled (for catch-up tracking)
    private var cumulativeDistance: Double = 0

    /// Number of target changes since last frame
    private var targetChangesPerFrame: Int = 0

    /// Last target value (to detect mid-flight changes)
    private var previousTarget: Double = 0

    init() {
        // Create display link for vsync updates
        let result = CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)

        guard result == kCVReturnSuccess, let displayLink = displayLink else {
            print("❌ ProgressBarAnimator: Failed to create display link")
            return
        }

        // Set output callback - runs on display link thread (NOT main thread)
        CVDisplayLinkSetOutputCallback(displayLink, { (_, _, _, _, _, userInfo) -> CVReturn in
            guard let userInfo = userInfo else { return kCVReturnSuccess }
            let animator = Unmanaged<ProgressBarAnimator>.fromOpaque(userInfo).takeUnretainedValue()

            // CRITICAL FIX: Do animation calculations OFF main thread
            // This prevents being blocked by SwiftUI re-renders
            animator.tickOffMainThread()

            return kCVReturnSuccess
        }, Unmanaged.passUnretained(self).toOpaque())

        // Start the display link
        CVDisplayLinkStart(displayLink)
    }

    deinit {
        if let displayLink = displayLink {
            CVDisplayLinkStop(displayLink)
            // Note: CVDisplayLink is automatically released when the Swift reference is dropped
            // (it's a CFTypeRef bridged type), but we nil it explicitly for clarity
        }
        self.displayLink = nil
    }

    /// Called every frame (vsync) - runs OFF main thread for maximum performance
    private func tickOffMainThread() {
        let frameTime = CACurrentMediaTime()

        // Thread-safe read of target and internal displayed
        lock.lock()
        let currentTarget = target
        let currentDisplayed = internalDisplayed
        let frameDelta = lastFrameTime > 0 ? frameTime - lastFrameTime : 0
        lastFrameTime = frameTime

        // Detect target change mid-flight (catch-up scenario)
        if currentTarget != previousTarget {
            targetChangesPerFrame += 1
            previousTarget = currentTarget
        }
        lock.unlock()

        let delta = currentTarget - currentDisplayed

        // Snap to target if close enough to avoid jitter (0.5% of range = imperceptible)
        guard abs(delta) > 0.005 else {
            if currentDisplayed != currentTarget {
                lock.lock()
                internalDisplayed = currentTarget
                let finalDisplayed = internalDisplayed
                lock.unlock()

                logFrame(
                    frameTime: frameTime,
                    frameDelta: frameDelta,
                    delta: delta,
                    step: abs(currentTarget - currentDisplayed),
                    snapped: true,
                    internalDisplayed: finalDisplayed
                )

                // Sync to @Published on main thread (non-blocking)
                syncToPublished(finalDisplayed)
            }

            lock.lock()
            targetChangesPerFrame = 0
            lock.unlock()
            return
        }

        // Spring physics animation - natural easing with adaptive parameters
        // Uses Hooke's law: F = -kx - cv (spring force + damping force)
        //
        // Strategy: Adapt spring parameters based on jump size
        // - Small changes: Smooth spring (lower stiffness, more damping)
        // - Medium changes: Balanced spring (medium stiffness and damping)
        // - Large changes: Snappy spring (higher stiffness, controlled damping)

        let absDelta = abs(delta)

        // Adaptive spring parameters based on jump size
        // CRITICAL: Keep stiffness low to prevent numerical instability at 120fps
        // At 8.3ms frame time, high stiffness causes exponential growth
        let currentStiffness: Double
        let currentDamping: Double

        if absDelta > 0.3 {
            // Large jump: snappy spring (fast, minimal overshoot)
            // Increased from 50 to 100 for faster response
            currentStiffness = 100
            currentDamping = 20
        } else if absDelta > 0.1 {
            // Medium jump: balanced spring (natural feel)
            // Increased from 40 to 70 for snappier mid-range
            currentStiffness = 70
            currentDamping = 17
        } else {
            // Small adjustment: smooth spring (gentle, no overshoot)
            currentStiffness = 30
            currentDamping = 11
        }

        // Read current velocity from state
        lock.lock()
        var currentVelocity = velocity
        lock.unlock()

        // Spring physics calculation (semi-implicit Euler integration)
        // F = k * delta - c*v
        // delta = (target - current), so positive delta means we need positive force (pull right)
        let springForce = currentStiffness * delta
        let dampingForce = -currentDamping * currentVelocity
        let acceleration = springForce + dampingForce

        // Update velocity: v += a * dt
        currentVelocity += acceleration * frameDelta

        // CRITICAL: Clamp velocity to prevent numerical explosion
        // Max velocity: 10 units/second (100% in 0.1 seconds)
        let maxVelocity = 10.0
        currentVelocity = max(-maxVelocity, min(maxVelocity, currentVelocity))

        // Update position: x += v * dt
        let newDisplayed = currentDisplayed + currentVelocity * frameDelta

        // CRITICAL: Clamp position to valid range [0.0, 1.0]
        // Zero velocity ONLY if we're at boundary AND moving away from target
        // This allows spring to pull back from boundaries toward target
        let clampedDisplayed: Double
        let finalVelocity: Double

        if newDisplayed < 0.0 {
            // Hit lower bound - clamp position
            clampedDisplayed = 0.0
            // Only zero velocity if target is also below/at boundary (prevents oscillation)
            // If target is above boundary, let spring pull us back up
            finalVelocity = (currentTarget <= 0.0) ? 0.0 : currentVelocity
        } else if newDisplayed > 1.0 {
            // Hit upper bound - clamp position
            clampedDisplayed = 1.0
            // Only zero velocity if target is also above/at boundary (prevents oscillation)
            // If target is below boundary, let spring pull us back down
            finalVelocity = (currentTarget >= 1.0) ? 0.0 : currentVelocity
        } else {
            // Within valid range - no clamping needed
            clampedDisplayed = newDisplayed
            finalVelocity = currentVelocity
        }

        let actualStep = abs(clampedDisplayed - currentDisplayed)

        // Determine if we've essentially reached the target (within 0.5% and low velocity)
        let isSettled = abs(delta) < 0.005 && abs(finalVelocity) < 0.5
        let snapped = isSettled

        // Update internal state (thread-safe)
        lock.lock()
        internalDisplayed = clampedDisplayed
        velocity = finalVelocity  // Store updated velocity for next frame
        cumulativeDistance += actualStep
        let finalDisplayed = internalDisplayed
        targetChangesPerFrame = 0
        lock.unlock()

        logFrame(
            frameTime: frameTime,
            frameDelta: frameDelta,
            delta: delta,
            step: actualStep,
            snapped: snapped,
            internalDisplayed: clampedDisplayed
        )

        // Sync to @Published on main thread (non-blocking)
        syncToPublished(finalDisplayed)
    }

    /// Sync internal value to @Published property on main thread (non-blocking, interpolated)
    private func syncToPublished(_ value: Double) {
        let now = CACurrentMediaTime()

        // Check if an update is already pending
        lock.lock()
        let shouldUpdate = !updatePending
        let timeSinceLastPublish = now - lastPublishedTime
        if shouldUpdate {
            updatePending = true
        }
        lock.unlock()

        // Only dispatch if not already pending
        guard shouldUpdate else {
            return
        }

        // Use async to avoid blocking if main thread is busy
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let publishTime = CACurrentMediaTime()

            self.lock.lock()
            let lastValue = self.lastPublishedValue
            let targetValue = self.internalDisplayed
            let timeDelta = publishTime - self.lastPublishedTime
            self.lock.unlock()

            // Calculate interpolated value to smooth over skipped frames
            // If main thread was busy and we skipped frames, interpolate instead of snapping
            var newValue: Double

            if timeDelta > 0.020 {  // If more than ~16ms (missed frames)
                // Aggressive interpolation: move up to 50% of the remaining distance
                // This makes the UI catch up faster when main thread is delayed
                let delta = targetValue - lastValue
                let maxStep = abs(delta) * 0.50  // Increased from 0.25 to 0.50

                if abs(delta) <= maxStep {
                    newValue = targetValue
                } else {
                    newValue = lastValue + (delta > 0 ? maxStep : -maxStep)
                }
            } else {
                // Normal case: use the target value directly
                newValue = targetValue
            }

            // CRITICAL: Clamp to valid range [0.0, 1.0] before updating UI
            newValue = max(0.0, min(1.0, newValue))

            // Update the @Published property
            self.displayed = newValue

            // Store for next interpolation
            self.lock.lock()
            self.lastPublishedValue = newValue
            self.lastPublishedTime = publishTime
            self.updatePending = false
            self.lock.unlock()
        }
    }

    /// Log frame diagnostics with minimal performance impact
    private func logFrame(
        frameTime: CFTimeInterval,
        frameDelta: CFTimeInterval,
        delta: Double,
        step: Double,
        snapped: Bool,
        internalDisplayed: Double
    ) {
        guard enableDiagnostics else { return }

        let fps = frameDelta > 0 ? 1.0 / frameDelta : 0
        let status = snapped ? "SNAP" : "MOVE"

        lock.lock()
        let currentVelocity = velocity
        lock.unlock()

        print(String(format: """
            🎬 [%@] t=%.4f | Δt=%.1fms (%.0f fps) | target=%.3f | internal=%.3f | displayed=%.3f | \
            delta=%.3f | step=%.3f | velocity=%.3f
            """,
            status,
            frameTime,
            frameDelta * 1000,
            fps,
            target,
            internalDisplayed,
            displayed,
            delta,
            step,
            currentVelocity
        ))
    }

    /// Update the target level (called from showVolume/showBrightness)
    func setTarget(_ value: Double) {
        lock.lock()
        let oldTarget = target
        let oldInternal = internalDisplayed
        target = value

        if enableDiagnostics {
            print(String(format: "🎯 setTarget(%.3f) | oldTarget=%.3f | internalDisplayed=%.3f | velocity=%.3f",
                         value, oldTarget, oldInternal, velocity))
        }

        // Reset velocity on large target changes to prevent momentum carryover
        // This prevents spring from overshooting wildly when direction changes
        if abs(value - oldTarget) > 0.15 {
            velocity = 0
            if enableDiagnostics {
                print("   → Velocity reset (large target change)")
            }
        }

        // If this is the first target (displayed is still 0), snap internal value immediately
        if internalDisplayed == 0 && value > 0 {
            internalDisplayed = value
            lastPublishedValue = value
            lastPublishedTime = CACurrentMediaTime()
            velocity = 0  // Start with zero velocity
            lock.unlock()
            if enableDiagnostics {
                print("   → First show: snapping to target")
            }
            // Sync to UI immediately for first show
            DispatchQueue.main.async { [weak self] in
                self?.displayed = value
            }
        } else {
            lock.unlock()
        }
    }

    // MARK: - Diagnostics Control

    /// Enable frame-by-frame diagnostic logging
    func enableDiagnosticLogging(_ enabled: Bool = true) {
        enableDiagnostics = enabled
        if enabled {
            print("🎬 ProgressBarAnimator: Diagnostics ENABLED (Spring Physics v5)")
            print("🎬 Logging format: [STATUS] t=time | Δt=frameDelta | target | displayed | delta | step | velocity | cumulative | targetChanges")
            resetDiagnostics()
        } else {
            print("🎬 ProgressBarAnimator: Diagnostics DISABLED")
        }
    }

    /// Reset diagnostic counters (useful for starting a new test)
    func resetDiagnostics() {
        lastFrameTime = 0
        cumulativeDistance = 0
        targetChangesPerFrame = 0
        previousTarget = target
        print("🎬 ProgressBarAnimator: Diagnostics RESET")
    }
}
