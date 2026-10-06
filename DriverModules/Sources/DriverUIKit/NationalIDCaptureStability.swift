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
    static let requiredHoldDuration: TimeInterval = 0.450

    static let maximumMotion: CGFloat = 8.0
    static let maximumSoftMotion: CGFloat = 10.0

    static let maximumCornerStep: CGFloat = 0.018
    static let maximumCornerDrift: CGFloat = 0.025

    static let maximumLumaDrift: CGFloat = 12.0

    static let blurrySharpness: CGFloat = 1200.0
    static let focusAcquireThreshold: CGFloat = 2500.0
    static let focusRetainThreshold: CGFloat = 2200.0
    static let readySharpness: CGFloat = focusAcquireThreshold

    static let emaAlpha: CGFloat = 0.35

    static let maximumFrameGap: TimeInterval = 0.500

    static let ocrInterval: TimeInterval = 0.400
    static let ocrEvidenceLifetime: TimeInterval = 1.500

    static let immediateResetMotion: CGFloat = 18.0
}

enum NIDMotionState: Equatable {
    case stable
    case softFail
    case hardFail
}

enum NIDCornerState: Equatable {
    case stable
    case stepFail
    case drift
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
        guard let previous0 else { return current }
        guard let previous1 else { return max(current, previous0) }
        return max(min(current, previous0), min(max(current, previous0), previous1))
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

    private(set) var cleanFrames = 0
    private var previousSampleStable = false
    private var anchorQuad: NationalIDQuad?
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
        tolerateMotionSpike: Bool = false
    ) -> Bool {
        let interval = lastTimestamp.map { now - $0 } ?? 0
        let gap = lastTimestamp != nil && (interval > NIDTrackingConfig.maximumFrameGap || interval <= 0)
        lastTimestamp = now

        if gap {
            motion0 = nil
            motion1 = nil
            smoothedMotion = motion
            motionState = .hardFail
        } else {
            smoothedMotion = (!tolerateMotionSpike || !motion.isFinite)
                ? motion
                : NIDMotionMetrics.median3(motion, motion0, motion1)
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

        if !cornerStep.isFinite || boundary == nil {
            cornerState = .unavailable
        } else if cornerStep > NIDTrackingConfig.maximumCornerStep {
            cornerState = .stepFail
        } else if let anchorQuad, let boundary, boundary.maxDistance(to: anchorQuad) > NIDTrackingConfig.maximumCornerDrift {
            cornerState = .drift
        } else {
            cornerState = .stable
        }

        blocker = gap
            ? .frameGap
            : eligibilityBlocker
            ?? (boundary == nil
                ? .missingBoundary
                : (cornerState == .stepFail || cornerState == .unavailable)
                ? .cornerStep
                : cornerState == .drift
                ? .cornerDrift
                : anchorPixels.map { NIDMotionMetrics.documentMotion($0, pixels) > NIDTrackingConfig.maximumLumaDrift } == true
                ? .lumaDrift
                : nil)

        if blocker != nil {
            clearHold()
            motionFailCount = 0
            return false
        }

        let failed = !motion.isFinite
            || motion > NIDTrackingConfig.maximumMotion
            || !smoothedMotion.isFinite
            || smoothedMotion > NIDTrackingConfig.maximumMotion
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
        motionFailCount = 0
        blocker = nil
    }

    func preserveHoldForMissingBoundary(now: CFTimeInterval) {
        lastTimestamp = now
        blocker = .missingBoundary
        cornerState = .unavailable
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
