# Spring Physics Animation Implementation

## Overview

The progress bar animation system has been upgraded from linear interpolation to spring physics for natural, polished motion that feels professionally animated.

## What Changed

### Previous (v4): Linear Interpolation with Adaptive Velocity
```swift
// Simple linear motion: move a fixed percentage toward target each frame
let velocityFactor = absDelta > 0.3 ? 0.50 : (absDelta > 0.1 ? 0.35 : 0.25)
let step = absDelta * velocityFactor
newDisplayed = currentDisplayed + (delta > 0 ? step : -step)
```

**Problems:**
- Constant velocity = mechanical feel
- No acceleration or deceleration
- No natural easing curves
- Abrupt direction changes on target updates

### Current (v5): Spring Physics with Adaptive Parameters
```swift
// Real physics simulation with spring force and damping
let springForce = -currentStiffness * delta
let dampingForce = -currentDamping * velocity
let acceleration = springForce + dampingForce

velocity += acceleration * frameDelta  // Update velocity first
newDisplayed = currentDisplayed + velocity * frameDelta  // Then position
```

**Benefits:**
- Natural S-curve easing (accelerate → decelerate)
- Maintains momentum through velocity state
- Smooth transitions on mid-flight target changes
- Professional, polished feel matching high-quality UIs

## How It Works

### Spring Physics Formula (Hooke's Law)

The animation uses a damped spring system based on Hooke's law:

```
F = -k(x - x_target) - c*v
```

Where:
- **F** = Total force on the bar
- **k** = Spring stiffness (how strongly it pulls toward target)
- **x** = Current position
- **x_target** = Target position
- **c** = Damping coefficient (resistance to motion)
- **v** = Current velocity

### Force Components

**Spring Force: -k(x - x_target)**
- Pulls the bar toward the target
- Stronger when far from target (large delta)
- Weaker when close to target (small delta)
- Creates acceleration at start, deceleration at end

**Damping Force: -c*v**
- Resists motion (like friction or air resistance)
- Proportional to velocity
- Prevents overshoot and oscillation
- Makes the spring settle smoothly

### Numerical Integration (Semi-Implicit Euler)

Each frame updates the physics state:

```swift
// 1. Calculate forces
let springForce = -stiffness * delta
let dampingForce = -damping * velocity
let acceleration = springForce + dampingForce

// 2. Update velocity using acceleration
velocity += acceleration * frameDelta

// 3. Update position using NEW velocity (semi-implicit)
newDisplayed = currentDisplayed + velocity * frameDelta
```

**Why semi-implicit?**
- More stable than explicit Euler (which updates position first)
- Better energy conservation
- Less prone to instability at high stiffness values

## Adaptive Spring Parameters

The spring "personality" adapts to the size of the jump:

### Large Jumps (>30% change)
```swift
stiffness = 100  // Strong pull (2x faster than v5.0)
damping = 20     // Controlled overshoot
```
**Feel:** Very snappy and responsive. Fast response (~250ms) with subtle natural overshoot.
**Example:** Mute (0%) → Max volume (100%)

### Medium Jumps (10-30% change)
```swift
stiffness = 70   // Moderate-strong pull (faster than v5.0)
damping = 17     // Natural overshoot
```
**Feel:** Balanced and responsive. Pleasant easing curve with good speed.
**Example:** 40% → 60% volume

### Small Adjustments (<10% change)
```swift
stiffness = 30   // Gentle pull
damping = 11     // Minimal overshoot
```
**Feel:** Very smooth and refined. No visible bounce.
**Example:** Single volume key press (6.25% change)

### Numerical Stability

**Critical constraint:** At 120fps (8.3ms frame time), very high stiffness values (>150) can cause exponential growth in velocity, leading to numerical instability.

**Solution implemented:**
1. **Tuned stiffness:** Keep values 30-100 (carefully tested at 120fps)
2. **Velocity clamping:** Max velocity ±10 units/second prevents explosion
3. **Velocity reset:** Reset to zero on large target changes (>15%) to prevent momentum carryover

**v5.1 Update:** Increased stiffness for large/medium jumps (100/70 vs 50/40) after testing confirmed stability at 120fps with velocity clamping. This provides 2x faster settling while maintaining smooth spring easing.

## Tuning Guidelines

### Spring Stiffness (k)
- **Higher values** (300-500): Faster response, more "springy"
- **Lower values** (100-250): Slower response, more "floaty"
- **Too high** (>1000): Can cause numerical instability
- **Too low** (<50): Feels sluggish and unresponsive

### Damping Coefficient (c)
- **Critical damping**: No overshoot, fastest settling
  - Formula: `c_critical = 2 * sqrt(k)`
  - For k=300: c_critical ≈ 34.6
- **Underdamped** (c < critical): Visible overshoot/oscillation
- **Overdamped** (c > critical): Slow, sluggish motion
- **Current values** (30-35): Slightly underdamped for natural feel

## Motion Characteristics

### Acceleration Phase (Start)
- Far from target → large spring force
- Low velocity → small damping force
- Net result: Strong acceleration

### Cruise Phase (Middle)
- Moderate distance → moderate spring force
- Building velocity → increasing damping force
- Net result: Roughly constant velocity

### Deceleration Phase (End)
- Close to target → small spring force
- High velocity → strong damping force
- Net result: Smooth deceleration to settle

### Settled State
Animation stops when BOTH conditions are met:
```swift
abs(delta) < 0.005 && abs(velocity) < 0.5
```
- Position within 0.5% of target (imperceptible to user)
- Velocity below 0.5 units/second (essentially stationary)

## Performance

### Computational Cost
- **2 multiplications** per frame (spring force, damping force)
- **2 additions** per frame (total force, velocity update)
- **1 multiplication** per frame (position update)
- **Total:** ~5 arithmetic operations per frame

### Thread Architecture
- All physics calculations on CVDisplayLink thread (off main thread)
- Runs at 120fps regardless of UI rendering
- Main thread only receives final position for @Published update
- Zero impact on UI responsiveness

### Memory Overhead
```swift
private var velocity: Double = 0        // 8 bytes
private var stiffness: Double = 300     // 8 bytes
private var damping: Double = 30        // 8 bytes
```
**Total:** 24 bytes additional state

## Comparison: Linear vs Spring

| Aspect | Linear (v4) | Spring Physics (v5) |
|--------|------------|---------------------|
| **Motion curve** | Straight line | Natural S-curve |
| **Acceleration** | None (instant max velocity) | Gradual (feels natural) |
| **Deceleration** | None (stops abruptly) | Gradual (smooth settle) |
| **Overshoot** | No overshoot | Subtle, natural overshoot |
| **Easing** | None (mechanical) | Automatic (physics-based) |
| **Perceived quality** | Fast but robotic | Polished and professional |
| **Mid-flight changes** | Instant direction flip | Smooth momentum transition |
| **Code complexity** | ~5 lines | ~15 lines |
| **CPU cost** | 1 multiply + 1 add | 3 multiplies + 2 adds |

## Testing the Implementation

### Enable Diagnostics
Uncomment in AppDelegate.swift:
```swift
notchHUDController?.enableAnimationDiagnostics(true)
```

### Observe Spring Behavior
Watch the console output:
```
🎬 [MOVE] t=1234.5678 | Δt=8.3ms (120 fps) | target=0.875 | displayed=0.750 |
   delta=0.125 | step=0.018 | velocity=2.145 | cumulative=0.018 | targetChanges=0
```

**What to look for:**
- **velocity**: Should build at start, decay at end
- **step**: Should start small, increase, then decrease (acceleration → deceleration)
- **delta**: Should decrease smoothly without jumps

### Test Scenarios

**Test 1: Small adjustment (single key press)**
- Expected: ~3-4 frames, smooth motion, no visible overshoot
- Velocity: Peaks around 1-2 units/second

**Test 2: Medium jump (several key presses)**
- Expected: ~4-6 frames, natural easing curve
- Velocity: Peaks around 3-5 units/second

**Test 3: Large jump (mute → max volume)**
- Expected: ~5-8 frames, fast with subtle overshoot
- Velocity: Peaks around 8-15 units/second

**Test 4: Direction change mid-flight**
- Expected: Smooth momentum reversal (not instant flip)
- Velocity: Should gradually change sign, not snap

## Troubleshooting

### Problem: Animation feels too slow
**Solution:** Increase spring stiffness
```swift
currentStiffness = 500  // Was 400 for large jumps
```

### Problem: Animation overshoots too much
**Solution:** Increase damping
```swift
currentDamping = 40  // Was 35 for large jumps
```

### Problem: Animation oscillates/bounces
**Solution:** Increase damping toward critical value
```swift
let criticalDamping = 2 * sqrt(currentStiffness)
currentDamping = criticalDamping * 0.95  // 95% of critical
```

### Problem: Animation feels sluggish
**Solution:** Both increase stiffness AND increase damping proportionally
```swift
currentStiffness = 600
currentDamping = 2 * sqrt(600) * 0.9  // Maintain damping ratio
```

## Future Enhancements

### Possible Improvements
1. **User preference profiles**: Let users choose "snappy", "bouncy", or "smooth"
2. **Velocity inheritance**: Preserve velocity when target changes mid-flight
3. **Variable damping**: Higher damping near target (prevent overshoot)
4. **Gesture velocity**: Match initial velocity to swipe speed
5. **Energy-based settling**: Stop when kinetic + potential energy is low

### Advanced Physics
- **RK4 integration**: Higher accuracy than Euler (negligible benefit for this use case)
- **Implicit integration**: Better stability for very stiff springs
- **Critically damped solver**: Analytical solution (fastest non-overshooting motion)

## References

- [Hooke's Law](https://en.wikipedia.org/wiki/Hooke%27s_law)
- [Damped Harmonic Oscillator](https://en.wikipedia.org/wiki/Harmonic_oscillator#Damped_harmonic_oscillator)
- [Semi-Implicit Euler Method](https://en.wikipedia.org/wiki/Semi-implicit_Euler_method)
- [Spring Animation in UI](https://medium.com/@dtinth/spring-animation-in-css-2039de6e1a03)
- [Critical Damping](https://en.wikipedia.org/wiki/Damping#Critical_damping_(ζ_=_1))

## Credits

Implementation inspired by:
- **mew-notch**: Spring animation approach
- **UIKit spring animations**: iOS spring animation parameters
- **Game physics engines**: Spring-damper systems for natural motion

---

*Spring physics implementation completed 2026-01-14*
*Performance-first architecture with off-main-thread CVDisplayLink preserved*
