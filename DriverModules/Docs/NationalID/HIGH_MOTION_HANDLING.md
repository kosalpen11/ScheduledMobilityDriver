# High Motion Handling - NID Capture Flow

## Summary
Implemented robust high motion detection and recovery in the National ID capture stability tracking to prevent accumulation of false stability signals during large document movements.

## Changes Made

### 1. NationalIDFrameTracker.swift

#### cornerStep Calculation (Lines 172-187)
**Issue:** When high motion was detected, the code still calculated `cornerStep` by comparing the current boundary to the stale `previousBoundary`, poisoning the reference with a meaningless calculation.

**Fix:** 
- Check for `rawMotionHigh` first
- If high motion detected: set `cornerStep = .infinity` and reset `emaCornerStep = nil`
- Only calculate `cornerStep` normally when motion is stable
- Move `previousBoundary` update into the stable-motion path only

```swift
if rawMotionHigh {
    // High motion: don't poison cornerStep reference with stale boundary comparison
    cornerStep = .infinity
    emaCornerStep = nil
} else if let previousBoundary, let boundary {
    // Normal path: calculate and update cornerStep with fresh boundary
    let step = boundary.meanDistance(to: previousBoundary)
    emaCornerStep = NIDTrackingConfig.emaAlpha * step
        + (1 - NIDTrackingConfig.emaAlpha) * (emaCornerStep ?? step)
    cornerStep = emaCornerStep ?? step
    previousBoundary = boundary
} else {
    cornerStep = .infinity
}
```

#### Stability Hold Management (Lines 209-222)
**Issue:** During high motion, the hold timer was still accumulating, artificially inflating capture readiness.

**Fix:**
- Added explicit check for `rawMotionHigh` before stability accumulation
- Call new `stability.pauseHoldForHighMotion()` method to reset hold state
- Prevents hold accumulation during large document movements

```swift
if toleratedMissingBoundary {
    stability.preserveHoldForMissingBoundary(now: now)
    stabilityAdvanced = false
} else if rawMotionHigh {
    // High motion: pause hold and reset to prevent accumulating stability during large movements
    stability.pauseHoldForHighMotion(now: now)
    stabilityAdvanced = false
} else {
    stabilityAdvanced = stability.add(...)
}
```

### 2. NationalIDCaptureStability.swift

#### New pauseHoldForHighMotion() Method (Lines 289-301)
**Purpose:** Cleanly handle high motion by resetting the hold accumulation state.

**Behavior:**
- Updates `lastTimestamp` to maintain frame gap detection
- Calls `clearHold()` to reset: frames, holdDuration, cleanFrames, previousSampleStable, and anchors
- Sets `blocker = .rawMotion` for diagnostic logging
- Sets `motionState = .hardFail` to indicate motion instability
- Sets corner tracking to unavailable to prevent false corner stability claims

```swift
func pauseHoldForHighMotion(now: CFTimeInterval) {
    lastTimestamp = now
    // High motion indicates significant document movement; reset hold to restart accumulation
    clearHold()
    blocker = .rawMotion
    motionState = .hardFail
    cornerState = .unavailable
    cornerStep = .infinity
    cornerDrift = .infinity
}
```

## Benefits

1. **Prevents false stability signals:** No longer poisons cornerStep with stale boundary comparisons
2. **Resets accumulation on motion:** Hold timer resets when high motion detected, requiring fresh stable frames
3. **Clear semantic intent:** Explicit method for high-motion handling makes code flow clearer
4. **Diagnostic visibility:** Sets blocker to `.rawMotion` for debugging motion issues
5. **Proper boundary freeze:** `previousBoundary` only updated during stable motion, acting as true reference

## Flow

```
High Motion Detected (rawMotion > maximumMotion)
    ↓
cornerStep = .infinity (avoid stale comparison)
emaCornerStep = nil (reset EMA)
previousBoundary NOT updated (freeze reference)
    ↓
stability.pauseHoldForHighMotion(now)
    ↓
Hold reset (frames, holdDuration, cleanFrames → 0)
motionState = .hardFail
cornerState = .unavailable
    ↓
Requires fresh stable frames to resume accumulation
```
