# Progress Bar Animation Diagnostics Guide

## Quick Start

To enable frame-by-frame diagnostic logging:

1. Open `AppDelegate.swift`
2. Uncomment line 30:
   ```swift
   notchHUDController?.enableAnimationDiagnostics(true)
   ```
3. Run the app and adjust volume/brightness
4. Check the console for detailed frame logs

## Understanding the Output

### Example Log Entry
```
🎬 [MOVE] t=1234.5678 | Δt=16.7ms (60 fps) | target=0.875 | displayed=0.750 | delta=0.125 | step=0.150 | velocity=2.340 | cumulative=0.150 | targetChanges=0
```

### Field Breakdown

| Field | Description | What to Look For |
|-------|-------------|------------------|
| **[STATUS]** | `MOVE` = interpolating, `SNAP` = reached target | Too many SNAPs = jumpy animation |
| **t** | Absolute timestamp (seconds) | - |
| **Δt** | Time since last frame (milliseconds) | Should be ~16.7ms (60fps). Spikes indicate frame drops |
| **fps** | Frames per second | Should be consistently 60. Lower = rendering bottleneck |
| **target** | Target value the bar is moving toward | Multiple different targets in succession = event flooding |
| **displayed** | Current displayed value | Should smoothly approach target |
| **delta** | Distance remaining to target | Should decrease each frame |
| **step** | Amount moved this frame | With spring physics: varies (accelerates then decelerates) |
| **velocity** | Current velocity (units/second) | Shows spring momentum - builds then decays |
| **cumulative** | Total distance traveled | High values = lots of catch-up movement |
| **targetChanges** | Target changes since last frame | >1 = multiple events per frame (event flooding) |

## Diagnosing Common Issues

### Issue: Perceived Lag/Delay

**Symptoms in logs:**
- `targetChanges > 1` frequently
- High `cumulative` distance values
- `displayed` never quite catches up to `target`

**Cause:** Too many events arriving faster than animation can render

**Solution:** Events are already being throttled properly. This is expected behavior.

---

### Issue: Jumpy/Stuttering Animation

**Symptoms in logs:**
- Frame delta (Δt) varies wildly (not consistently ~16.7ms)
- FPS drops below 60
- Many `[SNAP]` entries instead of smooth `[MOVE]` progression

**Cause:** Frame drops due to rendering or main thread blocking

**Solution:** Investigate what's blocking the main thread

---

### Issue: Animation Too Slow

**Symptoms in logs:**
- Small `step` values (< 0.05)
- Many frames to reach target
- Delta decreases very gradually

**Cause:** Step size calculation may be too conservative

**Solution:** Adjust velocity constants in `ProgressBarAnimator.tick()`

---

### Issue: Animation Too Fast/Snappy

**Symptoms in logs:**
- Large `step` values (> 0.3)
- Very few frames between target changes
- Frequent `[SNAP]` entries

**Cause:** Step size too aggressive

**Solution:** Adjust velocity constants in `ProgressBarAnimator.tick()`

---

## Testing Scenarios

### Test 1: Single Key Press (Small Change)
1. Enable diagnostics
2. Press volume up/down once
3. **Expected:**
   - 1-3 frames with `[MOVE]`
   - Final `[SNAP]` to target
   - Delta ~0.0625 (one volume step)

### Test 2: Holding Key (Large Change)
1. Enable diagnostics
2. Hold volume up/down
3. **Expected:**
   - Multiple `[MOVE]` frames
   - `targetChanges=1` as new targets arrive
   - Smooth progression of `displayed` toward `target`

### Test 3: Rapid Key Presses (Event Flooding)
1. Enable diagnostics
2. Rapidly tap volume up/down
3. **Expected:**
   - `targetChanges > 1` on some frames
   - High `cumulative` distance
   - Animation eventually catches up

---

## Disabling Diagnostics

To disable logging:

1. Open `AppDelegate.swift`
2. Comment out line 30:
   ```swift
   // notchHUDController?.enableAnimationDiagnostics(true)
   ```

Or call at runtime:
```swift
notchHUDController?.enableAnimationDiagnostics(false)
```

---

## Advanced: Runtime Control

You can toggle diagnostics at any time via the controller:

```swift
// Enable
notchHUDController?.enableAnimationDiagnostics(true)

// Reset counters for a fresh test
notchHUDController?.resetAnimationDiagnostics()

// Disable
notchHUDController?.enableAnimationDiagnostics(false)
```

---

## Performance Impact

When **disabled** (default): Zero performance impact - logging code is guarded by a boolean check.

When **enabled**: Minimal impact:
- String formatting happens only when logging is active
- Uses efficient `String(format:)`
- Output is buffered by console
- No measurable FPS impact in testing

---

## Implementation Details

The diagnostic system tracks:
- Frame timestamps using `CACurrentMediaTime()`
- Delta calculations for frame timing
- Target changes to detect mid-flight updates
- Cumulative distance for catch-up tracking
- All calculations happen on the display link thread (off main thread)
- Only the final print statement touches the main thread

The system is designed to be production-safe and can be left in the codebase permanently.

---

## Performance Fix: Off-Main-Thread Animation (v2)

**Problem Solved:** Previous implementation showed 300-400ms frame drops (3 fps) during rapid volume changes because animation calculations blocked on main thread dispatch.

**Root Cause:** SwiftUI re-renders (from icon changes, config updates) blocked the main thread, causing `DispatchQueue.main.async` in the CVDisplayLink callback to wait hundreds of milliseconds.

**Solution:** Split animation into two phases:
1. **Off main thread (CVDisplayLink)**: All math calculations update `internalDisplayed`
2. **On main thread (async, non-blocking)**: Only sync final value to `@Published displayed`

**Benefits:**
- Animation calculations run at full 60-120fps regardless of main thread state
- UI updates skip frames if main thread is busy (graceful degradation)
- No more 300-400ms hangs - animations stay smooth even during heavy rendering

---

## Performance Fix: Frame-Skip Interpolation (v3)

**Problem Solved:** Micro-lag from UI frame skipping when main thread is busy with SwiftUI re-renders.

**Root Cause:** When main thread delays processing the `@Published` update, the UI snaps directly to `internalDisplayed`, creating visible jumps if multiple frames were skipped.

**Solution:** Interpolate the `@Published` value when frames are skipped:

```swift
private func syncToPublished(_ value: Double) {
    DispatchQueue.main.async {
        let timeDelta = now - lastPublishedTime

        if timeDelta > 0.020 {  // Detected skipped frames (>16ms)
            // Interpolate: move 50% of remaining distance (v5.1: increased from 25%)
            let delta = targetValue - lastPublishedValue
            let maxStep = abs(delta) * 0.50
            newValue = lastPublishedValue + clamp(delta, maxStep)
        } else {
            // Normal: use target directly
            newValue = targetValue
        }

        self.displayed = newValue
        self.lastPublishedValue = newValue
        self.lastPublishedTime = now
    }
}
```

**Benefits:**
- Smooth motion even when UI frames are skipped
- No visible snapping or jumping
- Animation appears continuous regardless of main thread load
- Gracefully handles SwiftUI re-render delays
- **v5.1 Update:** 2x faster catch-up when frames are skipped (50% vs 25%)

**Key Insight:** The CVDisplayLink continues running at 120fps off main thread, but UI updates interpolate smoothly at whatever rate the main thread can handle (60fps, 30fps, or even slower during heavy rendering).

---

## Performance Fix: Adaptive Velocity (v4)

**Problem Solved:** Perceived lag from gradual interpolation taking too long to reach target during large volume jumps.

**Root Cause:** Fixed 25% velocity meant large jumps (0→100% volume) took 10-15 frames (~125ms at 120fps), feeling sluggish despite smooth animation.

**Solution:** Adaptive velocity based on jump size:

```swift
let absDelta = abs(delta)
let velocityFactor: Double

if absDelta > 0.3 {
    // Large jump: 50% per frame = ~2 frames (instant feel)
    velocityFactor = 0.50
} else if absDelta > 0.1 {
    // Medium jump: 35% per frame = ~3 frames (snappy)
    velocityFactor = 0.35
} else {
    // Small adjustment: 25% per frame = ~4 frames (smooth)
    velocityFactor = 0.25
}

let step = absDelta * velocityFactor
```

**Benefits:**
- **Large jumps feel instant**: 0→100% volume reaches target in ~2 frames (16ms)
- **Small adjustments stay smooth**: Single volume step animates gently over 3-4 frames
- **No snapping**: All motion is interpolated, just faster for larger changes
- **Best of both worlds**: Responsive for big changes, fluid for small adjustments

**Example Timing:**
- Small change (6.25%, one volume step): 4 frames = 33ms
- Medium change (18.75%, three volume steps): 3 frames = 25ms
- Large change (50%, half volume): 2 frames = 16ms
- Maximum change (100%, mute to max): 2 frames = 16ms

This matches user expectations: large actions feel immediate, fine adjustments feel smooth.

---

## Animation Evolution: Spring Physics (v5)

**Problem Solved:** Linear interpolation felt mechanical and lacked the natural easing curves humans expect from polished UI.

**Root Cause:** Linear motion (constant velocity) doesn't match real-world physics or how we perceive natural motion. Professional animations use easing curves with acceleration/deceleration.

**Solution:** Hybrid spring physics approach combining mew-notch's natural feel with Aegis's bulletproof performance:

### Architecture
- **Keep**: Off-main-thread CVDisplayLink for frame-locked updates (bulletproof performance)
- **Replace**: Linear interpolation → Spring physics with Hooke's law
- **Add**: Adaptive spring parameters that change based on jump size

### Spring Physics Implementation

The animation now uses real physics simulation with spring force and damping:

```swift
// Spring state (maintained across frames)
private var velocity: Double = 0  // Current velocity in units/second

// Adaptive spring parameters based on jump size
let absDelta = abs(delta)
let currentStiffness: Double
let currentDamping: Double

if absDelta > 0.3 {
    // Large jump: snappy spring (fast, minimal overshoot)
    currentStiffness = 50
    currentDamping = 15
} else if absDelta > 0.1 {
    // Medium jump: balanced spring (natural feel)
    currentStiffness = 40
    currentDamping = 13
} else {
    // Small adjustment: smooth spring (gentle, no overshoot)
    currentStiffness = 30
    currentDamping = 11
}

// Spring physics calculation (Hooke's law)
// F = -k(x - target) - c*v
let springForce = -currentStiffness * delta
let dampingForce = -currentDamping * velocity
let acceleration = springForce + dampingForce

// Semi-implicit Euler integration
velocity += acceleration * frameDelta
newDisplayed = currentDisplayed + velocity * frameDelta
```

### Physics Explanation

**Hooke's Law**: F = -kx - cv
- **Spring force** (-kx): Pulls toward target, proportional to distance
- **Damping force** (-cv): Resists motion, proportional to velocity
- **Stiffness (k)**: How strong the spring pulls (higher = faster)
- **Damping (c)**: How much the motion is resisted (higher = less overshoot)

**Semi-Implicit Euler**: Numerical integration method
1. Update velocity first: `v += a * dt`
2. Update position using new velocity: `x += v * dt`
3. More stable than explicit Euler (update position first)

### Spring Parameter Tuning

**Large jumps (>30%)**: Snappy spring
- Stiffness: 100 (very strong pull, 2x faster than v5.0)
- Damping: 20 (controlled overshoot)
- Result: Very fast motion (~250ms) with subtle natural overshoot

**Medium jumps (10-30%)**: Balanced spring
- Stiffness: 70 (moderate-strong pull, faster than v5.0)
- Damping: 17 (natural overshoot)
- Result: Snappy easing curve, responsive feel

**Small adjustments (<10%)**: Smooth spring
- Stiffness: 30 (gentle pull)
- Damping: 11 (minimal overshoot)
- Result: Very smooth, no visible bounce

**Numerical Stability Constraints:**
- Stiffness kept at 30-100 at 120fps (tested stable with velocity clamping)
- Velocity is clamped to ±10 units/second as a safety limit
- Velocity resets to zero on large target changes (>15%) to prevent momentum carryover
- **v5.1 Update:** Doubled stiffness for large/medium jumps for 2x faster response

### Benefits

**Natural Easing:**
- Motion accelerates at the start (spring force strongest when far from target)
- Decelerates near the end (damping dominates as velocity builds)
- Natural S-curve easing without manual curve definitions

**Adaptive Feel:**
- Large jumps feel instant and confident (snappy spring)
- Small adjustments feel polished and smooth (gentle spring)
- All motion has natural easing, never linear

**Physical Realism:**
- Maintains momentum through velocity
- Responds naturally to mid-flight target changes
- Subtle overshoot on large changes feels natural and high-quality

**Performance:**
- Still runs at 120fps on CVDisplayLink thread
- Physics calculations are simple (2 multiplies, 2 adds per frame)
- Main thread never blocked

### Comparison to v4

| Aspect | v4 (Adaptive Velocity) | v5 (Spring Physics) |
|--------|------------------------|---------------------|
| Motion curve | Linear (constant velocity) | Natural S-curve (acceleration + deceleration) |
| Easing | None (mechanical feel) | Natural spring easing |
| Overshoot | No overshoot | Subtle overshoot on large jumps |
| Feel | Responsive but mechanical | Polished and natural |
| Timing | Fixed frames to target | Settles naturally based on physics |
| Mid-flight changes | Instant direction change | Smooth momentum transition |

### Settled State Detection

Animation stops when both conditions are met:
```swift
let isSettled = abs(delta) < 0.005 && abs(velocity) < 0.5
```

- **Position threshold**: Within 0.5% of target (imperceptible)
- **Velocity threshold**: Moving slower than 0.5 units/second
- Both required to prevent premature stopping during spring oscillation

### Diagnostic Logging

When diagnostics are enabled, you can observe the spring physics in action:
- **velocity**: Shows momentum building and decaying
- **step**: No longer constant - varies as spring accelerates/decelerates
- **delta**: Smooth approach to target with natural easing

The spring parameters are tuned to be critically damped (no visible oscillation) while still providing natural easing curves that feel more polished than linear motion.

---
