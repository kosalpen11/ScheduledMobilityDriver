//
//  NationalIDCaptureStability.swift
//  ScheduledMobilityDriver
//

import CoreGraphics
import Foundation

enum NIDTrackingConfig {
    static let sampleWidth = 256
    static let sampleHeight = 162

    static let requiredFrames = 5
    static let requiredHoldDuration: TimeInterval = 0.350

    /// Hard motion threshold: hold blocked if smoothedMotion exceeds this.
    /// Slightly raised to 10 to tolerate natural handheld variation.
    static let maximumMotion: CGFloat = 10.0
    /// Soft motion tolerance: rawMotion spikes up to this are acceptable if smoothedMotion ≤ maximumMotion.
    /// Raised to 16 to allow larger instant jitter without blocking hold progress.
    static let maximumSoftMotion: CGFloat = 16.0

    /// Only freeze the geometry lock / wipe hold above this. Raised to 26 to allow
    /// mild camera shake (up to 25 rawMotion) without freezing during capture.
    static let freezeReferenceMotion: CGFloat = 26.0

    static let maximumCornerStep: CGFloat = 0.018
    static let maximumSoftCornerStep: CGFloat = 0.030
    /// After this many consistent Vision proposals away from the lock, adopt the
    /// alternative (recovers from a bad early bootstrap).
    static let lockRecoveryConsistentFrames = 3
    /// Max distance between successive alternative proposals to count as the same lock target.
    static let lockRecoveryClusterDistance: CGFloat = 0.040

    static let cornerDriftAcquire: CGFloat = 0.025
    static let cornerDriftRetain: CGFloat = 0.030
    static let cornerDriftHard: CGFloat = 0.040
    static let maximumCornerDrift: CGFloat = cornerDriftAcquire

    static let maximumLumaDrift: CGFloat = 16.0

    static let blurrySharpness: CGFloat = 200.0
    // Lowered to reduce long "blurry" lockout on mid-tier devices while
    // still preserving blur rejection via blurrySharpness and post-capture QA.
    static let focusAcquireThreshold: CGFloat = 320.0
    static let focusRetainThreshold: CGFloat = 260.0
    static let readySharpness: CGFloat = focusAcquireThreshold

    static let emaAlpha: CGFloat = 0.35

    static let maximumFrameGap: TimeInterval = 0.500
    /// Motion median filter samples older than this are discarded. Must stay
    /// above the slowest expected processing interval (~5 fps) or every frame
    /// will reset the filter.
    static let motionFilterTimeout: TimeInterval = 0.200

    static let ocrInterval: TimeInterval = 0.400
    static let ocrAcquisitionInterval: TimeInterval = 0.180
    static let ocrEvidenceLifetime: TimeInterval = 1.500

    static let immediateResetMotion: CGFloat = 22.0
}

enum NIDMotionState: Equatable {
    case stable
    case softFail
    case hardFail
}

enum NIDCornerState: Equatable {
    case stable
    case softStep
    case stepFail
    case softDrift
    case hardDrift
    case unavailable
}

enum NIDStabilityBlocker: String, Equatable {
    case frameGap
    case ocrMissing
    case ocrExpired
    case cardCutOff
    case textOutside
    case quality
    case focus
    case missingBoundary
    case cornerStep
    case cornerDrift
    case lumaDrift
    case rawMotion
    case smoothedMotion
}

enum NIDMotionMetrics {
    static func documentMotion(_ previous: [UInt8], _ current: [UInt8]) -> CGFloat {
        guard previous.count == current.count, previous.isEmpty == false else {
            return .infinity
        }
        var deltaSum: Int = 0
        for index in previous.indices {
            deltaSum += Int(current[index]) - Int(previous[index])
        }
        let offset = CGFloat(deltaSum) / CGFloat(previous.count)
        var motion: CGFloat = 0
        for index in previous.indices {
            let delta = CGFloat(Int(current[index]) - Int(previous[index]))
            motion += abs(delta - offset)
        }
        return motion / CGFloat(previous.count)
    }

    static func median3(_ current: CGFloat, _ previous0: CGFloat?, _ previous1: CGFloat?) -> CGFloat {
        // True median: sort 3 samples (or fewer if some are nil) and return middle value
        var values = [current]
        if let p0 = previous0 { values.append(p0) }
        if let p1 = previous1 { values.append(p1) }
        
        values.sort()
        return values[values.count / 2]  // Returns middle element: more stable than asymmetric max(min(...))
    }
}

final class NationalIDCaptureStability {
    private(set) var frames = 0
    private(set) var holdDuration: TimeInterval = 0
    private(set) var blocker: NIDStabilityBlocker?

    private(set) var lastTimestamp: CFTimeInterval?
    private(set) var motion0: CGFloat?
    private(set) var motion1: CGFloat?
    private(set) var smoothedMotion: CGFloat = .infinity

    private(set) var motionState: NIDMotionState = .hardFail
    private(set) var motionFailCount = 0
    private(set) var cornerState: NIDCornerState = .unavailable
    private(set) var cornerStep: CGFloat = .infinity
    private(set) var cornerDrift: CGFloat = .infinity

    private(set) var cleanFrames = 0
    private var previousSampleStable = false
    /// Stable hold anchor: the first clean boundary of the current hold window.
    /// Prefer this over the latest Vision detection when deciding crop.
    private(set) var anchorQuad: NationalIDQuad?
    private var anchorPixels: [UInt8]?

    var progress: CGFloat {
        let frameProgress = CGFloat(frames) / CGFloat(NIDTrackingConfig.requiredFrames)
        let holdProgress = CGFloat(holdDuration / NIDTrackingConfig.requiredHoldDuration)
        return min(frameProgress, holdProgress).clamped(to: 0...1)
    }

    var ready: Bool {
        blocker == nil
            && cleanFrames >= 2
            && frames >= NIDTrackingConfig.requiredFrames
            && holdDuration >= NIDTrackingConfig.requiredHoldDuration
    }

    @discardableResult
    func add(
        now: CFTimeInterval,
        eligibilityBlocker: NIDStabilityBlocker?,
        motion: CGFloat,
        cornerStep: CGFloat,
        boundary: NationalIDQuad?,
        pixels: [UInt8],
        tolerateMotionSpike: Bool = false,
        enforceMotion: Bool = true
    ) -> Bool {
        let interval = lastTimestamp.map { now - $0 } ?? 0
        let gap = lastTimestamp != nil && (interval > NIDTrackingConfig.maximumFrameGap || interval <= 0)
        
        // Motion filter timeout: reset if more than 200ms since last valid frame
        let motionFilterTimeout = lastTimestamp != nil && (interval > NIDTrackingConfig.motionFilterTimeout)
        
        lastTimestamp = now

        if gap || motionFilterTimeout {
            // Hard reset: discard stale motion samples
            motion0 = nil
            motion1 = nil
            smoothedMotion = motion
            motionState = .hardFail
            if motionFilterTimeout {
                NIDLog.debug(
                    NIDLog.motion,
                    "[NID][MOTION] Filter timeout: resetting stale motion data after \(String(format: "%.0f", interval * 1000))ms"
                )
            }
        } else {
            // Apply motion filtering with stability
            if !tolerateMotionSpike || !motion.isFinite {
                smoothedMotion = motion
            } else {
                // Improved median3: use true median instead of asymmetric bias
                smoothedMotion = NIDMotionMetrics.median3(motion, motion0, motion1)
            }
            
            motion1 = motion0
            motion0 = motion.isFinite ? motion : nil
            
            if !motion.isFinite
                || !smoothedMotion.isFinite
                || motion > NIDTrackingConfig.immediateResetMotion
                || smoothedMotion > NIDTrackingConfig.maximumSoftMotion {
                motionState = .hardFail
            } else if smoothedMotion > NIDTrackingConfig.maximumMotion {
                motionState = .softFail
            } else {
                motionState = .stable
            }
        }

        self.cornerStep = cornerStep
        let wasCornerStable = cornerState == .stable
        if !cornerStep.isFinite || boundary == nil {
            cornerState = .unavailable
            cornerDrift = .infinity
        } else if cornerStep > NIDTrackingConfig.maximumSoftCornerStep {
            cornerState = .stepFail
            cornerDrift = anchorQuad.map { boundary?.maxDistance(to: $0) ?? .infinity } ?? 0
        } else if cornerStep > NIDTrackingConfig.maximumCornerStep {
            cornerState = .softStep
            cornerDrift = anchorQuad.map { boundary?.maxDistance(to: $0) ?? .infinity } ?? 0
        } else if let anchorQuad, let boundary {
            cornerDrift = boundary.maxDistance(to: anchorQuad)
            let stableThreshold = wasCornerStable
                ? NIDTrackingConfig.cornerDriftRetain
                : NIDTrackingConfig.cornerDriftAcquire
            if cornerDrift > NIDTrackingConfig.cornerDriftHard {
                cornerState = .hardDrift
            } else if cornerDrift > stableThreshold {
                cornerState = .softDrift
            } else {
                cornerState = .stable
            }
        } else {
            cornerDrift = 0
            cornerState = .stable
        }

        blocker = gap
            ? .frameGap
            : eligibilityBlocker
            ?? (boundary == nil
                ? .missingBoundary
                : (cornerState == .stepFail || cornerState == .unavailable)
                ? .cornerStep
                : cornerState == .hardDrift
                ? .cornerDrift
                : enforceMotion && anchorPixels.map { NIDMotionMetrics.documentMotion($0, pixels) > NIDTrackingConfig.maximumLumaDrift } == true
                ? .lumaDrift
                : nil)

        if blocker != nil {
            clearHold()
            motionFailCount = 0
            return false
        }

        let failed = enforceMotion && (!motion.isFinite
            || motion > NIDTrackingConfig.maximumMotion
            || !smoothedMotion.isFinite
            || smoothedMotion > NIDTrackingConfig.maximumMotion)
        if failed {
            motionFailCount += 1
            blocker = motion > NIDTrackingConfig.maximumMotion || !motion.isFinite ? .rawMotion : .smoothedMotion
            let soft = tolerateMotionSpike
                && motion.isFinite
                && motion > NIDTrackingConfig.maximumMotion
                && motion <= NIDTrackingConfig.maximumSoftMotion
                && smoothedMotion <= NIDTrackingConfig.maximumMotion
                && motionFailCount == 1
            motionState = soft ? .softFail : .hardFail
            if soft {
                frames = max(0, frames - 1)
                cleanFrames = 0
                previousSampleStable = false
            } else {
                clearHold()
                motion0 = nil
                motion1 = nil
            }
            return false
        }

        if cornerState == .softStep || cornerState == .softDrift {
            motionFailCount = 0
            previousSampleStable = false
            return false
        }

        motionFailCount = 0
        if anchorQuad == nil { anchorQuad = boundary }
        if anchorPixels == nil { anchorPixels = pixels }
        frames = min(NIDTrackingConfig.requiredFrames, frames + 1)
        if previousSampleStable {
            holdDuration = min(NIDTrackingConfig.requiredHoldDuration, holdDuration + interval)
        }
        previousSampleStable = true
        cleanFrames += 1
        return true
    }

    func reset() {
        clearHold()
        lastTimestamp = nil
        motion0 = nil
        motion1 = nil
        smoothedMotion = .infinity
        motionState = .hardFail
        cornerState = .unavailable
        cornerStep = .infinity
        cornerDrift = .infinity
        motionFailCount = 0
        blocker = nil
    }

    func preserveHoldForMissingBoundary(now: CFTimeInterval) {
        lastTimestamp = now
        blocker = .missingBoundary
        cornerState = .unavailable
        cornerStep = .infinity
        cornerDrift = .infinity
    }

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

    private func clearHold() {
        frames = 0
        holdDuration = 0
        cleanFrames = 0
        previousSampleStable = false
        anchorQuad = nil
        anchorPixels = nil
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
