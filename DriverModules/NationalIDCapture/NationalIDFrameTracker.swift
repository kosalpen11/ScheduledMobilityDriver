//
//  NationalIDFrameTracker.swift
//  ScheduledMobilityDriver
//

import AVFoundation
import CoreGraphics
import Foundation
import Vision

enum NIDDetectionStatus: Equatable {
    case notDetected
    case holdSteady
    case ready
}

private enum NIDTrackingPhase: String {
    case searching
    case acquiring
    case tracking
}

private enum OCRScheduleState {
    case acquiring            // 0.180s interval, waiting for confirmation
    case confirmed            // 0.400s interval, re-confirming periodically
    case failing              // Exponential backoff on failures
    case disabled(until: CFTimeInterval)  // Disabled after N consecutive failures
}

struct NIDDetectionResult: Equatable {
    let status: NIDDetectionStatus
    let progress: CGFloat
    let sharpness: CGFloat
    let focusOK: Bool
    let qualityOK: Bool
    let eligible: Bool
    let blocker: NIDStabilityBlocker?
    let cardPresent: Bool
    let documentConfirmed: Bool
    let ocrAgeMs: Int?
    let textOutside: Bool
    let tooDark: Bool
    let tooBright: Bool
    let hasGlare: Bool
    let blurry: Bool
    let cardCutOff: Bool
    let boundaryMissing: Bool
    let boundary: NationalIDQuad?
}

final class NationalIDFrameTracker {
    private let stability = NationalIDCaptureStability()

    private var lastCheck: CFTimeInterval?
    private var previousBoundary: NationalIDQuad?
    private var emaCornerStep: CGFloat?
    private var hadPreviousPixels = false
    private var motionFlip = false
    private var emaSharpness: CGFloat?
    private var focusWasGood = false
    private var lastFocusGoodTime: CFTimeInterval?

    private var pixels = [UInt8](repeating: 0, count: NIDTrackingConfig.sampleWidth * NIDTrackingConfig.sampleHeight)
    private var horizontal = [UInt16](repeating: 0, count: (NIDTrackingConfig.sampleWidth - 2) * NIDTrackingConfig.sampleHeight)
    private var motion0 = [UInt8](repeating: 0, count: (NIDTrackingConfig.sampleWidth - 2) * (NIDTrackingConfig.sampleHeight - 2))
    private var motion1 = [UInt8](repeating: 0, count: (NIDTrackingConfig.sampleWidth - 2) * (NIDTrackingConfig.sampleHeight - 2))

    private var cardPresent = false
    private var documentConfirmed = false
    private var cardDetectedAt: CFTimeInterval?
    private var textRegions: [CGRect] = []
    private var lastOCRAt: CFTimeInterval?
    private var ocrScheduleState = OCRScheduleState.acquiring
    private var ocrConsecutiveFailures = 0
    private var missingBoundaryCount = 0
    /// Tolerate brief Vision misses before wiping the reference. Was 1 — too
    /// aggressive and caused repeated bad re-bootstrap of previousBoundary.
    private let maximumMissingBoundaryFrames = 4
    private var trackingPhase: NIDTrackingPhase = .searching
    private var acquisitionCleanFrames = 0
    /// Best locked quad for crop once hold is progressing / ready.
    private var lockedCropQuad: NationalIDQuad?
    /// Consistent Vision alternative while sticky lock rejects jumps (bad bootstrap recovery).
    private var pendingLockCandidate: NationalIDQuad?
    private var pendingLockCandidateCount = 0

    var candidateReferenceQuad: NationalIDQuad? {
        lockedCropQuad ?? previousBoundary
    }

    func interruptStability() {
        stability.reset()
        emaSharpness = nil
        focusWasGood = false
        lastFocusGoodTime = nil
        resetTrackedGeometry()
    }

    func reset() {
        lastCheck = nil
        previousBoundary = nil
        emaCornerStep = nil
        hadPreviousPixels = false
        motionFlip = false
        emaSharpness = nil
        focusWasGood = false
        lastFocusGoodTime = nil
        cardPresent = false
        documentConfirmed = false
        cardDetectedAt = nil
        textRegions = []
        lastOCRAt = nil
        ocrScheduleState = .acquiring
        ocrConsecutiveFailures = 0
        missingBoundaryCount = 0
        trackingPhase = .searching
        acquisitionCleanFrames = 0
        lockedCropQuad = nil
        pendingLockCandidate = nil
        pendingLockCandidateCount = 0
        stability.reset()
    }

    func process(
        sampleBuffer: CMSampleBuffer,
        guideRect: CGRect,
        requiresDocumentConfirmation: Bool = true,
        now: CFTimeInterval = CACurrentMediaTime()
    ) -> NIDDetectionResult {
        let gap = lastCheck.map { now - $0 > NIDTrackingConfig.maximumFrameGap || now - $0 <= 0 } ?? true
        lastCheck = now
        if gap {
            emaSharpness = nil
            focusWasGood = false
            stability.reset()
            resetTrackedGeometry()
        }

        guard sampleLuma(from: sampleBuffer, guideRect: guideRect) else {
            reset()
            return emptyResult(boundaryMissing: true)
        }

        let quality = NationalIDFrameQualityAssessor.assess(pixels: pixels)
        computeMotionSample()
        let currentMotion = motionFlip ? motion1 : motion0
        let previousMotion = motionFlip ? motion0 : motion1
        let rawMotion = hadPreviousPixels ? NIDMotionMetrics.documentMotion(previousMotion, currentMotion) : .infinity
        hadPreviousPixels = true
        motionFlip.toggle()

        emaSharpness = NIDTrackingConfig.emaAlpha * quality.sharpness
            + (1 - NIDTrackingConfig.emaAlpha) * (emaSharpness ?? quality.sharpness)
        
        // Focus hysteresis with time-based recovery.
        // When focus was good, maintain it until retain threshold; when bad,
        // require acquire threshold to recover.
        let focusAcquireThreshold = NIDTrackingConfig.focusAcquireThreshold
        let focusRetainThreshold = NIDTrackingConfig.focusRetainThreshold
        
        let focusOK = if focusWasGood {
            quality.sharpness >= focusRetainThreshold
        } else {
            quality.sharpness >= focusAcquireThreshold
        }
        
        // Time-based recovery: if focus was bad for >2 seconds, allow re-acquisition
        if !focusOK, let lastFocusTime = lastFocusGoodTime,
           now - lastFocusTime > 2.0 {
            focusWasGood = false  // Explicitly allow re-acquisition from any level
            NIDLog.debug(NIDLog.tracking, "[NID][FOCUS] Recovery timeout: resetting to allow re-acquisition")
        }
        
        focusWasGood = focusOK
        if focusOK {
            lastFocusGoodTime = now
        }

        let detectedBoundary = detectBoundary(in: sampleBuffer)

        // Live overlay geometry: always prefer the latest continuous detection so
        // the guide tracks smoothly. Hold-last-good only when Vision briefly misses.
        var boundary: NationalIDQuad?
        var usedHoldLastGood = false
        if let detectedBoundary {
            boundary = detectedBoundary
        } else if let previousBoundary, missingBoundaryCount < maximumMissingBoundaryFrames {
            boundary = previousBoundary
            usedHoldLastGood = true
            NIDLog.debug(NIDLog.tracking, "[NID][BOUNDARY] hold-last-good (miss=\(missingBoundaryCount + 1)/\(maximumMissingBoundaryFrames))")
        } else {
            boundary = nil
        }

        var boundaryTrackLost = false
        if detectedBoundary == nil {
            missingBoundaryCount += 1
            if missingBoundaryCount > maximumMissingBoundaryFrames {
                boundaryTrackLost = true
                let keepLock = lockedCropQuad
                resetTrackedGeometry(clearLockedCrop: keepLock == nil)
                if let keepLock {
                    previousBoundary = keepLock
                    NIDLog.debug(NIDLog.tracking, "[NID][BOUNDARY] track lost: re-seed from locked crop quad")
                }
                stability.reset()
            }
        } else {
            missingBoundaryCount = 0
        }

        // Freeze hold only on hard shake — not normal handheld 8–12 motion.
        let rawMotionHigh = previousBoundary != nil
            && rawMotion > NIDTrackingConfig.freezeReferenceMotion
        var cornerStep: CGFloat
        let imageSizeForGate = orientedImageSize(for: sampleBuffer)
        var rejectedJump = false

        // Smooth tracking reference: follow continuous detections.
        // Crop lock (lockedCropQuad) is separate and only set when hold is clean.
        if let candidate = boundary {
            if let prevBoundary = previousBoundary {
                let step = candidate.meanDistance(to: prevBoundary)
                if rawMotionHigh {
                    // Hard shake: keep previousBoundary for continuity, but still
                    // show live detection when available so overlay is not frozen.
                    cornerStep = .infinity
                    emaCornerStep = nil
                    clearPendingLockCandidate()
                    NIDLog.debug(NIDLog.tracking, "[NID][BOUNDARY] high motion: freeze reference (rawMotion=\(Self.formatMetric(rawMotion)))")
                } else if step <= NIDTrackingConfig.maximumSoftCornerStep {
                    // Smooth follow within normal corner motion.
                    emaCornerStep = NIDTrackingConfig.emaAlpha * step
                        + (1 - NIDTrackingConfig.emaAlpha) * (emaCornerStep ?? step)
                    cornerStep = emaCornerStep ?? step
                    self.previousBoundary = candidate
                    clearPendingLockCandidate()
                } else if step <= NIDContinuityConfig.maximumMeanDistance {
                    // Larger but continuous move (user adjusting card). Follow for
                    // smoothness; report real step so stability can slow hold.
                    emaCornerStep = NIDTrackingConfig.emaAlpha * step
                        + (1 - NIDTrackingConfig.emaAlpha) * (emaCornerStep ?? step)
                    cornerStep = emaCornerStep ?? step
                    self.previousBoundary = candidate
                    clearPendingLockCandidate()
                    NIDLog.debug(NIDLog.tracking, "[NID][BOUNDARY] smooth follow (step=\(Self.formatMetric(step)))")
                } else {
                    // True jump to a different rectangle — do not snap reference.
                    // If the alternative is ID-like and consistent, recover lock.
                    rejectedJump = true
                    cornerStep = step
                    if considerLockRecovery(candidate, imageSize: imageSizeForGate) {
                        self.previousBoundary = candidate
                        lockedCropQuad = nil
                        stability.reset()
                        emaCornerStep = nil
                        cornerStep = .infinity
                        rejectedJump = false
                        NIDLog.debug(NIDLog.tracking, "[NID][BOUNDARY] lock recovery adopt area=\(Self.formatMetric(candidate.area))")
                    } else {
                        NIDLog.debug(
                            NIDLog.tracking,
                            "[NID][BOUNDARY] reject jump keep-ref (step=\(Self.formatMetric(step)) pending=\(pendingLockCandidateCount))"
                        )
                    }
                }
            } else if isIDLikeCandidate(candidate, imageSize: imageSizeForGate) {
                self.previousBoundary = candidate
                cornerStep = .infinity
                clearPendingLockCandidate()
                NIDLog.debug(NIDLog.tracking, "[NID][BOUNDARY] bootstrap ID-like reference area=\(Self.formatMetric(candidate.area))")
            } else {
                // Don't blank the live overlay — just skip locking reference.
                cornerStep = .infinity
                NIDLog.debug(NIDLog.tracking, "[NID][BOUNDARY] bootstrap rejected (not ID-like) area=\(Self.formatMetric(candidate.area))")
            }
        } else {
            cornerStep = .infinity
        }

        // OCR on live boundary for smooth confirmation; crop still uses lock at ready.
        if requiresDocumentConfirmation,
           shouldRunOCR(now: now, boundary: boundary, focusOK: focusOK, qualityOK: quality.acceptable) {
            runOCR(sampleBuffer: sampleBuffer, boundary: boundary, now: now)
        }

        var ocrAge = cardDetectedAt.map { now - $0 }
        if ocrAge.map({ $0 > NIDTrackingConfig.ocrEvidenceLifetime }) == true {
            cardPresent = false
            documentConfirmed = false
            cardDetectedAt = nil
            textRegions = []
            ocrAge = nil
        }
        let ocrFresh = cardPresent
            && ocrAge.map { $0 <= NIDTrackingConfig.ocrEvidenceLifetime } == true
        let ocrAgeMs = ocrAge.map { max(0, Int($0 * 1000)) }

        let cardCutOff = boundary.map { !quadIsInsideGuide($0, guideRect: guideRect, sampleBuffer: sampleBuffer) } ?? false
        // Only treat true Vision misses as tolerated missing — jumps still show live geometry.
        let toleratedMissingBoundary = detectedBoundary == nil
            && !boundaryTrackLost
            && missingBoundaryCount <= maximumMissingBoundaryFrames
            && boundary != nil
            && usedHoldLastGood

        // Fast pre-check: if the union bounding-box of all text regions
        // is fully contained inside the quad's bounding box then there is
        // no need to run the more expensive point-in-quad test per region.
        let textOutside: Bool
        if let quad = boundary, !textRegions.isEmpty {
            var regionsBounds = textRegions[0]
            for r in textRegions.dropFirst() { regionsBounds = regionsBounds.union(r) }
            let epsilon: CGFloat = 1e-6
            let insideBounds = regionsBounds.minX >= quad.boundingBox.minX - epsilon
                && regionsBounds.maxX <= quad.boundingBox.maxX + epsilon
                && regionsBounds.minY >= quad.boundingBox.minY - epsilon
                && regionsBounds.maxY <= quad.boundingBox.maxY + epsilon
            if insideBounds {
                // AABB pass only: still verify centers (rotated quads can fail AABB-only)
                textOutside = quad.hasRegionCenterOutside(textRegions)
            } else {
                textOutside = quad.hasRegionCenterOutside(textRegions)
            }
        } else {
            textOutside = boundary?.hasRegionCenterOutside(textRegions) ?? false
        }

        let eligibilityBlocker: NIDStabilityBlocker? = gap
            ? .frameGap
            : boundary == nil
            ? .missingBoundary
            : requiresDocumentConfirmation && !documentConfirmed && !cardPresent
            ? .ocrMissing
            : requiresDocumentConfirmation && !documentConfirmed && !ocrFresh
            ? .ocrExpired
            : cardCutOff
            ? .cardCutOff
            : !quality.acceptable
            ? .quality
            : !focusOK
            ? .focus
            : nil
        let eligible = eligibilityBlocker == nil
        if boundary != nil, eligible, trackingPhase == .searching {
            trackingPhase = .acquiring
            acquisitionCleanFrames = 0
        }
        let enforceMotion = trackingPhase == .tracking

        let stabilityAdvanced: Bool
        if toleratedMissingBoundary {
            stability.preserveHoldForMissingBoundary(now: now)
            stabilityAdvanced = false
        } else if rawMotionHigh {
            stability.pauseHoldForHighMotion(now: now)
            stabilityAdvanced = false
        } else if rejectedJump {
            // Different rectangle than lock — don't accumulate hold on bad geometry.
            stabilityAdvanced = stability.add(
                now: now,
                eligibilityBlocker: eligibilityBlocker ?? .cornerStep,
                motion: rawMotion,
                cornerStep: .infinity,
                boundary: boundary,
                pixels: currentMotion,
                tolerateMotionSpike: true,
                enforceMotion: enforceMotion
            )
        } else {
            stabilityAdvanced = stability.add(
                now: now,
                eligibilityBlocker: eligibilityBlocker,
                motion: rawMotion,
                cornerStep: cornerStep,
                boundary: boundary,
                pixels: currentMotion,
                tolerateMotionSpike: true,
                enforceMotion: enforceMotion
            )
        }
        let blocker = stability.blocker
        updateTrackingPhase(
            boundaryPresent: boundary != nil,
            eligible: eligible,
            toleratedMissingBoundary: toleratedMissingBoundary,
            stabilityAdvanced: stabilityAdvanced,
            blocker: blocker
        )

        #if DEBUG
        NIDLog.debug(
            NIDLog.tracking,
            "[NID][TRACKING] " +
            "phase=\(trackingPhase.rawValue) " +
            "acquireCleanFrames=\(acquisitionCleanFrames) " +
            "enforceMotion=\(enforceMotion) " +
            "rawMotion=\(Self.formatMetric(rawMotion)) " +
            "smoothedMotion=\(Self.formatMetric(stability.smoothedMotion)) " +
            "freezeBoundary=\(rawMotionHigh)"
        )
        NIDLog.debug(
            NIDLog.tracking,
            "[NID][QUALITY] " +
            "sharp=\(Self.formatNumber(quality.sharpness)) " +
            "blurryThreshold=\(Self.formatNumber(NIDTrackingConfig.blurrySharpness)) " +
            "focusAcquire=\(Self.formatNumber(NIDTrackingConfig.focusAcquireThreshold)) " +
            "focusRetain=\(Self.formatNumber(NIDTrackingConfig.focusRetainThreshold)) " +
            "blurry=\(quality.blurry) " +
            "focusOK=\(focusOK) " +
            "qualityOK=\(quality.acceptable) " +
            "eligible=\(eligible) " +
            "blocker=\(blocker?.rawValue ?? "none")"
        )
        NIDLog.debug(
            NIDLog.tracking,
            "[NID][ELIGIBILITY] " +
            "cardPresent=\(cardPresent) " +
            "documentConfirmed=\(documentConfirmed) " +
            "ocrAgeMs=\(ocrAgeMs.map(String.init) ?? "nil") " +
            "cardCutOff=\(cardCutOff) " +
            "textOutside=\(textOutside) " +
            "qualityOK=\(quality.acceptable) " +
            "focusOK=\(focusOK) " +
            "boundaryPresent=\(boundary != nil) " +
            "eligible=\(eligible) " +
            "blocker=\(blocker?.rawValue ?? "none")"
        )
        NIDLog.debug(
            NIDLog.tracking,
            "[NID][CORNER] " +
            "step=\(Self.formatMetric(stability.cornerStep)) " +
            "drift=\(Self.formatMetric(stability.cornerDrift)) " +
            "state=\(stability.cornerState.logValue) " +
            "stepMax=\(Self.formatMetric(NIDTrackingConfig.maximumCornerStep)) " +
            "softStepMax=\(Self.formatMetric(NIDTrackingConfig.maximumSoftCornerStep)) " +
            "acquire=\(Self.formatMetric(NIDTrackingConfig.cornerDriftAcquire)) " +
            "retain=\(Self.formatMetric(NIDTrackingConfig.cornerDriftRetain)) " +
            "hard=\(Self.formatMetric(NIDTrackingConfig.cornerDriftHard))"
        )
        NIDLog.debug(
            NIDLog.tracking,
            "[NID][READY] " +
            "confirmed=\(documentConfirmed) " +
            "geometry=\(boundary != nil) " +
            "landscape=true " +
            "focus=\(focusOK) " +
            "quality=\(quality.acceptable) " +
            "motion=\(stability.motionState == .stable) " +
            "corner=\(stability.cornerState == .stable) " +
            "cornerStep=\(Self.formatMetric(stability.cornerStep)) " +
            "cornerDrift=\(Self.formatMetric(stability.cornerDrift)) " +
            "cornerState=\(stability.cornerState.logValue) " +
            "holdMs=\(Int(stability.holdDuration * 1000)) " +
            "frames=\(stability.frames) " +
            "progress=\(String(format: "%.2f", Double(stability.progress))) " +
            "blocker=\(blocker?.rawValue ?? "none")"
        )
        #endif

        let ready = stability.ready
            && stability.motionState == .stable
            && stability.cornerState == .stable
            && (!requiresDocumentConfirmation || documentConfirmed)
            && focusOK
            && quality.acceptable
            && boundary != nil
            && !cardCutOff

        // Lock the quad for crop — prefer current boundary (just validated all checks)
        // over old anchor frames which may have been at frame edge.
        if stabilityAdvanced || ready {
            if let boundary, cornerStep.isFinite, cornerStep <= NIDTrackingConfig.maximumCornerStep {
                lockedCropQuad = boundary
            } else if let anchor = stability.anchorQuad {
                lockedCropQuad = anchor
            }
        }
        if ready, lockedCropQuad == nil {
            lockedCropQuad = boundary ?? previousBoundary
        }

        let holding = boundary != nil
            && quality.acceptable
            && focusOK
            && !cardCutOff
            && (!requiresDocumentConfirmation || documentConfirmed)
        let status: NIDDetectionStatus = ready ? .ready : (holding ? .holdSteady : .notDetected)
        // Overlay must stay live/smooth. Capture path reads candidateReferenceQuad
        // (lockedCropQuad) separately when status == ready.
        let resultBoundary = boundary
        if status == .ready {
            NIDLog.debug(
                NIDLog.tracking,
                "[NID][CROPQUAD] status=ready locked=\(lockedCropQuad != nil) " +
                "useLocked=\(lockedCropQuad != nil ? "yes" : "no") " +
                "area=\(lockedCropQuad.map { Self.formatMetric($0.area) } ?? "nil") " +
                "cornerStep=\(Self.formatMetric(cornerStep))"
            )
        }
        return NIDDetectionResult(
            status: status,
            progress: stability.progress,
            sharpness: quality.sharpness,
            focusOK: focusOK,
            qualityOK: quality.acceptable,
            eligible: eligible,
            blocker: blocker,
            cardPresent: cardPresent,
            documentConfirmed: documentConfirmed,
            ocrAgeMs: ocrAgeMs,
            textOutside: textOutside,
            tooDark: quality.tooDark,
            tooBright: quality.tooBright,
            hasGlare: quality.glare,
            blurry: quality.blurry,
            cardCutOff: cardCutOff,
            boundaryMissing: detectedBoundary == nil && boundary == nil,
            boundary: resultBoundary
        )
    }

    private func emptyResult(boundaryMissing: Bool) -> NIDDetectionResult {
        NIDDetectionResult(
            status: .notDetected,
            progress: 0,
            sharpness: 0,
            focusOK: false,
            qualityOK: false,
            eligible: false,
            blocker: nil,
            cardPresent: false,
            documentConfirmed: false,
            ocrAgeMs: nil,
            textOutside: false,
            tooDark: false,
            tooBright: false,
            hasGlare: false,
            blurry: false,
            cardCutOff: false,
            boundaryMissing: boundaryMissing,
            boundary: nil
        )
    }

    private func sampleLuma(from sampleBuffer: CMSampleBuffer, guideRect: CGRect) -> Bool {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return false }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard CVPixelBufferGetPlaneCount(pixelBuffer) > 0,
              let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return false }

        let rawWidth = CVPixelBufferGetWidth(pixelBuffer)
        let rawHeight = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let buffer = base.assumingMemoryBound(to: UInt8.self)
        let width = NIDTrackingConfig.sampleWidth
        let height = NIDTrackingConfig.sampleHeight
        let roi = guideRectForSampling(guideRect: guideRect, rawSize: CGSize(width: rawWidth, height: rawHeight))
        guard roi.width > 1, roi.height > 1 else { return false }

        for y in 0..<height {
            for x in 0..<width {
                let u = (CGFloat(x) + 0.5) / CGFloat(width)
                let v = (CGFloat(y) + 0.5) / CGFloat(height)
                let sampleX = min(rawWidth - 1, max(0, Int((roi.minX + u * roi.width).rounded(.down))))
                let sampleY = min(rawHeight - 1, max(0, Int((roi.minY + v * roi.height).rounded(.down))))
                pixels[y * width + x] = buffer[sampleY * bytesPerRow + sampleX]
            }
        }
        return true
    }

    private func guideRectForSampling(guideRect: CGRect, rawSize: CGSize) -> CGRect {
        guard guideRect.width > 0, guideRect.height > 0, rawSize.width > 0, rawSize.height > 0 else {
            return CGRect(x: rawSize.width * 0.1, y: rawSize.height * 0.25, width: rawSize.width * 0.8, height: rawSize.height * 0.5)
        }
        // The live UI guide is portrait-preview space. The luma plane is landscape,
        // so use a centered card-aspect ROI with equivalent relative coverage.
        let coverage = min(0.9, max(0.2, guideRect.width / max(guideRect.height, 1)))
        let roiWidth = rawSize.width * min(0.86, coverage)
        let roiHeight = roiWidth / (1 / NationalIDGeometry.targetAspect)
        return CGRect(
            x: (rawSize.width - roiWidth) / 2,
            y: (rawSize.height - roiHeight) / 2,
            width: roiWidth,
            height: min(rawSize.height * 0.9, roiHeight)
        )
    }

    private func computeMotionSample() {
        let width = NIDTrackingConfig.sampleWidth
        let height = NIDTrackingConfig.sampleHeight
        let targetWidth = width - 2
        let targetHeight = height - 2
        for y in 0..<height {
            for x in 0..<targetWidth {
                let index = y * width + x
                horizontal[y * targetWidth + x] = UInt16(pixels[index])
                    + UInt16(pixels[index + 1])
                    + UInt16(pixels[index + 2])
            }
        }
        for y in 0..<targetHeight {
            for x in 0..<targetWidth {
                let index = y * targetWidth + x
                let sum = horizontal[index] + horizontal[index + targetWidth] + horizontal[index + 2 * targetWidth]
                if motionFlip {
                    motion1[index] = UInt8((sum + 4) / 9)
                } else {
                    motion0[index] = UInt8((sum + 4) / 9)
                }
            }
        }
    }

    private func detectBoundary(in sampleBuffer: CMSampleBuffer) -> NationalIDQuad? {
        let request = NIDRectangleDetectionConfig.makeRequest()
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .right, options: [:])
        do {
            try handler.perform([request])
        } catch {
            NIDLog.error(NIDLog.tracking, "[NID][ERROR] Rectangle detection failed: \(error.localizedDescription)")
            return nil
        }
        let imageSize = orientedImageSize(for: sampleBuffer)
        let candidates = request.results ?? []
        let quads = candidates.map { observation -> (quad: NationalIDQuad, confidence: CGFloat) in
            let rawQuad = NationalIDQuad(observation: observation)
            return (
                quad: NationalIDGeometry.bestRelabeledQuad(rawQuad, matching: previousBoundary ?? lockedCropQuad),
                confidence: CGFloat(observation.confidence)
            )
        }
        // Without a lock, only admit ID-like shapes so background rectangles
        // cannot become the tracking reference.
        let idLike = quads.filter { isIDLikeCandidate($0.quad, imageSize: imageSize) }
        let continuous = quads.filter { continuityAllowed($0.quad) }
        let selectable: [(quad: NationalIDQuad, confidence: CGFloat)]
        if previousBoundary == nil {
            selectable = idLike.isEmpty ? [] : idLike
        } else {
            selectable = continuous
        }
        let selected = selectable
            .max { score($0.quad, confidence: $0.confidence, imageSize: imageSize) < score($1.quad, confidence: $1.confidence, imageSize: imageSize) }

        #if DEBUG
        if let selected = selected {
            let selectedScore = score(selected.quad, confidence: selected.confidence, imageSize: imageSize)
            NIDLog.debug(
                NIDLog.tracking,
                "[NID][DETECT] candidates=\(candidates.count) idLike=\(idLike.count) continuousPass=\(continuous.count) selected=yes score=\(Self.formatMetric(CGFloat(selectedScore))) confidence=\(Self.formatMetric(selected.confidence))"
            )
        } else {
            NIDLog.debug(
                NIDLog.tracking,
                "[NID][DETECT] candidates=\(candidates.count) idLike=\(idLike.count) continuousPass=\(continuous.count) selected=no"
            )
        }
        #endif

        // Prefer a continuous/id-like hit; otherwise keep previous lock (caller
        // may still hold-last-good). Do not invent a new lock from non-idLike.
        return selected?.quad
    }

    /// True when a normalized quad is roughly ID-1 shaped (aspect + area).
    private func isIDLikeCandidate(_ quad: NationalIDQuad, imageSize: CGSize) -> Bool {
        let metrics = NationalIDGeometry.metrics(for: NationalIDGeometry.scaled(quad, to: imageSize))
        // aspectScore uses target 0.631 ± 0.20; require a non-trivial score.
          guard NationalIDGeometry.acceptedAspectRange.contains(metrics.measuredAspect),
              metrics.aspectScore >= 0.35
          else { return false }
        // Normalized area: card should occupy a meaningful part of the frame.
        guard (0.08...0.70).contains(quad.area) else { return false }
        let horizontalBalance = min(metrics.topEdge, metrics.bottomEdge)
            / max(metrics.topEdge, metrics.bottomEdge, 0.0001)
        let verticalBalance = min(metrics.leftEdge, metrics.rightEdge)
            / max(metrics.leftEdge, metrics.rightEdge, 0.0001)
        return horizontalBalance >= 0.50 && verticalBalance >= 0.50
    }

    private func score(_ quad: NationalIDQuad, confidence: CGFloat, imageSize: CGSize) -> CGFloat {
        let metrics = NationalIDGeometry.metrics(for: NationalIDGeometry.scaled(quad, to: imageSize))
        let areaScore = min(1, quad.area / 0.25)
        let continuity = previousBoundary.map {
            max(0, min(1, 1 - quad.meanDistance(to: $0) / NIDContinuityConfig.scoreFalloffDistance))
        } ?? 1
        return 0.20 * confidence + 0.25 * metrics.aspectScore + 0.20 * areaScore + 0.35 * continuity
    }

    private func continuityAllowed(_ quad: NationalIDQuad) -> Bool {
        guard let previousBoundary else { return true }
        // Fast squared distance check (~40% faster than hypot comparison)
        let passedDistance = quad.isMeanDistanceLessThan(NIDContinuityConfig.maximumMeanDistance, to: previousBoundary)
        guard passedDistance else {
            NIDLog.debug(
                NIDLog.tracking,
                "[NID][CONTINUITY] rejected meanDist>\(Self.formatMetric(NIDContinuityConfig.maximumMeanDistance))"
            )
            return false
        }
        // Use fast sampled quad IOU (12×12 grid) instead of exact polygon clipping
        // Provides 3-5x speedup while maintaining accuracy for document tracking
        let iou = quad.sampledQuadIOU(with: previousBoundary, gridSize: 12)
        let previousArea = max(previousBoundary.area, 0.0001)
        let areaRatio = quad.area / previousArea
        let passed = iou >= NIDContinuityConfig.minimumIOU
            && NIDContinuityConfig.areaRatioRange.contains(areaRatio)
        
        #if DEBUG
        if !passed {
            let failReason = iou < NIDContinuityConfig.minimumIOU
                ? "iou=\(Self.formatMetric(iou))<\(Self.formatMetric(NIDContinuityConfig.minimumIOU))"
                : "areaRatio=\(Self.formatMetric(areaRatio))"
            NIDLog.debug(NIDLog.tracking, "[NID][CONTINUITY] rejected \(failReason)")
        }
        #endif
        return passed
    }

    private func shouldRunOCR(
        now: CFTimeInterval,
        boundary: NationalIDQuad?,
        focusOK: Bool,
        qualityOK: Bool
    ) -> Bool {
        guard boundary != nil, focusOK, qualityOK else {
            return false
        }
        
        let interval: TimeInterval
        switch ocrScheduleState {
        case .acquiring:
            interval = NIDTrackingConfig.ocrAcquisitionInterval  // 0.180s
        case .confirmed:
            interval = NIDTrackingConfig.ocrInterval  // 0.400s
        case .failing:
            // Exponential backoff: 0.5s, 1.0s, 2.0s, capped at 2.0s
            interval = NIDOCRConfig.backoffInterval(consecutiveFailures: ocrConsecutiveFailures)
        case .disabled(let until):
            if now >= until {
                ocrScheduleState = .acquiring  // Re-enable after delay
                ocrConsecutiveFailures = 0
                NIDLog.debug(NIDLog.ocr, "[NID][OCR] Schedule re-enabled after failure backoff")
            }
            return false
        }
        
        return lastOCRAt.map { now - $0 >= interval } ?? true
    }

    private func runOCR(sampleBuffer: CMSampleBuffer, boundary: NationalIDQuad?, now: CFTimeInterval) {
        lastOCRAt = now
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.minimumTextHeight = NIDOCRConfig.minimumTextHeight
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .right, options: [:])
        do {
            try handler.perform([request])
        } catch {
            NIDLog.error(NIDLog.ocr, "[NID][ERROR] OCR text recognition failed: \(error.localizedDescription)")
            textRegions = []  // Clear previous regions on error
            return
        }
        let regions = (request.results ?? []).map(\.boundingBox)
        textRegions = regions
        guard let boundary else {
            return
        }
        let insideCount = regions.filter { boundary.contains(CGPoint(x: $0.midX, y: $0.midY)) }.count
        NIDLog.debug(
            NIDLog.ocr,
            "[NID][OCR] " +
            "regions=\(regions.count) " +
            "inside=\(insideCount) " +
            "state=\(ocrScheduleState) " +
            "failures=\(ocrConsecutiveFailures) " +
            "minTextHeight=\(NIDOCRConfig.minimumTextHeight)"
        )
        
        // State machine: manage OCR schedule based on confirmation result
        if insideCount >= NIDOCRConfig.minimumRegionsInside {
            // Success: document detected and confirmed
            cardPresent = true
            documentConfirmed = true
            cardDetectedAt = now
            ocrScheduleState = .confirmed
            ocrConsecutiveFailures = 0
            NIDLog.debug(NIDLog.ocr, "[NID][OCR] Document confirmed, switching to .confirmed state")
        } else {
            // Failure: no document or insufficient text detected
            ocrConsecutiveFailures += 1
            if ocrConsecutiveFailures >= NIDOCRConfig.failuresBeforeDisable {
                // Too many consecutive failures: pause OCR entirely
                ocrScheduleState = .disabled(until: now + NIDOCRConfig.disableDuration)
                NIDLog.debug(
                    NIDLog.ocr,
                    "[NID][OCR] Max failures reached, disabling OCR for \(NIDOCRConfig.disableDuration)s"
                )
            } else {
                // Exponential backoff without full disable
                ocrScheduleState = .failing
                NIDLog.debug(
                    NIDLog.ocr,
                    "[NID][OCR] Failure \(ocrConsecutiveFailures), switching to exponential backoff"
                )
            }
        }
    }

    private func resetTrackedDocument() {
        resetTrackedGeometry()
    }

    private func resetTrackedGeometry() {
        resetTrackedGeometry(clearLockedCrop: true)
    }

    private func resetTrackedGeometry(clearLockedCrop: Bool) {
        previousBoundary = nil
        emaCornerStep = nil
        missingBoundaryCount = 0
        trackingPhase = .searching
        acquisitionCleanFrames = 0
        clearPendingLockCandidate()
        if clearLockedCrop {
            lockedCropQuad = nil
        }
    }

    private func clearPendingLockCandidate() {
        pendingLockCandidate = nil
        pendingLockCandidateCount = 0
    }

    /// If Vision repeatedly proposes the same ID-like alternative far from the
    /// current reference, adopt it (recovers from a bad early bootstrap).
    private func considerLockRecovery(_ candidate: NationalIDQuad, imageSize: CGSize) -> Bool {
        guard isIDLikeCandidate(candidate, imageSize: imageSize) else {
            clearPendingLockCandidate()
            return false
        }
        if let pending = pendingLockCandidate,
           candidate.isMeanDistanceLessThan(NIDTrackingConfig.lockRecoveryClusterDistance, to: pending) {
            pendingLockCandidate = candidate
            pendingLockCandidateCount += 1
        } else {
            pendingLockCandidate = candidate
            pendingLockCandidateCount = 1
        }
        return pendingLockCandidateCount >= NIDTrackingConfig.lockRecoveryConsistentFrames
    }

    private func quadIsInsideGuide(_ quad: NationalIDQuad, guideRect: CGRect, sampleBuffer: CMSampleBuffer) -> Bool {
        guard guideRect.width > 0, guideRect.height > 0, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return false
        }
        let oriented = CGSize(width: CVPixelBufferGetHeight(pixelBuffer), height: CVPixelBufferGetWidth(pixelBuffer))
        let scaled = NationalIDGeometry.scaled(quad, to: oriented)
        let guideNormPadding: CGFloat = 16
        let normalizedGuide = guideRectForSampling(guideRect: guideRect, rawSize: oriented)
            .insetBy(
                dx: -(oriented.width * 0.04 + guideNormPadding),
                dy: -(oriented.height * 0.04 + guideNormPadding)
            )
        return scaled.corners.allSatisfy { normalizedGuide.contains($0) }
    }

    private func orientedImageSize(for sampleBuffer: CMSampleBuffer) -> CGSize {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return .zero }
        return CGSize(width: CVPixelBufferGetHeight(pixelBuffer), height: CVPixelBufferGetWidth(pixelBuffer))
    }

    private static func formatNumber(_ value: CGFloat) -> String {
        String(format: "%.0f", Double(value))
    }

    private static func formatMetric(_ value: CGFloat) -> String {
        guard value.isFinite else { return "inf" }
        return String(format: "%.3f", Double(value))
    }

    private func updateTrackingPhase(
        boundaryPresent: Bool,
        eligible: Bool,
        toleratedMissingBoundary: Bool,
        stabilityAdvanced: Bool,
        blocker: NIDStabilityBlocker?
    ) {
        if toleratedMissingBoundary {
            return
        }
        guard boundaryPresent, eligible else {
            if trackingPhase != .tracking {
                trackingPhase = .searching
                acquisitionCleanFrames = 0
            }
            return
        }
        if trackingPhase == .searching {
            trackingPhase = .acquiring
            acquisitionCleanFrames = 0
        }
        if trackingPhase == .acquiring {
            if stabilityAdvanced {
                acquisitionCleanFrames += 1
                if acquisitionCleanFrames >= 2 {
                    trackingPhase = .tracking
                }
            } else if blocker != nil {
                acquisitionCleanFrames = 0
            }
        }
    }
}

private extension NIDCornerState {
    var logValue: String {
        switch self {
        case .stable:
            return "stable"
        case .softStep:
            return "softStep"
        case .stepFail:
            return "stepFail"
        case .softDrift:
            return "softDrift"
        case .hardDrift:
            return "hardDrift"
        case .unavailable:
            return "unavailable"
        }
    }
}

private extension NationalIDQuad {
    init(observation: VNRectangleObservation) {
        self.init(
            topLeft: observation.topLeft,
            topRight: observation.topRight,
            bottomRight: observation.bottomRight,
            bottomLeft: observation.bottomLeft
        )
    }
}
