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

    private var pixels = [UInt8](repeating: 0, count: NIDTrackingConfig.sampleWidth * NIDTrackingConfig.sampleHeight)
    private var horizontal = [UInt16](repeating: 0, count: (NIDTrackingConfig.sampleWidth - 2) * NIDTrackingConfig.sampleHeight)
    private var motion0 = [UInt8](repeating: 0, count: (NIDTrackingConfig.sampleWidth - 2) * (NIDTrackingConfig.sampleHeight - 2))
    private var motion1 = [UInt8](repeating: 0, count: (NIDTrackingConfig.sampleWidth - 2) * (NIDTrackingConfig.sampleHeight - 2))

    private var cardPresent = false
    private var documentConfirmed = false
    private var cardDetectedAt: CFTimeInterval?
    private var textRegions: [CGRect] = []
    private var lastOCRAt: CFTimeInterval?
    private var missingBoundaryCount = 0
    private let maximumMissingBoundaryFrames = 1

    var candidateReferenceQuad: NationalIDQuad? {
        previousBoundary
    }

    func interruptStability() {
        stability.reset()
        emaSharpness = nil
        focusWasGood = false
        resetTrackedDocument()
    }

    func reset() {
        lastCheck = nil
        previousBoundary = nil
        emaCornerStep = nil
        hadPreviousPixels = false
        motionFlip = false
        emaSharpness = nil
        focusWasGood = false
        cardPresent = false
        documentConfirmed = false
        cardDetectedAt = nil
        textRegions = []
        lastOCRAt = nil
        missingBoundaryCount = 0
        stability.reset()
    }

    func process(
        sampleBuffer: CMSampleBuffer,
        guideRect: CGRect,
        isDeviceShaking: Bool,
        now: CFTimeInterval = CACurrentMediaTime()
    ) -> NIDDetectionResult {
        let gap = lastCheck.map { now - $0 > NIDTrackingConfig.maximumFrameGap || now - $0 <= 0 } ?? true
        lastCheck = now
        if gap {
            emaSharpness = nil
            focusWasGood = false
            stability.reset()
            resetTrackedDocument()
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
        let focusOK = focusWasGood
            ? quality.sharpness >= NIDTrackingConfig.focusRetainThreshold
            : quality.sharpness >= NIDTrackingConfig.focusAcquireThreshold
        focusWasGood = focusOK

        let boundary = detectBoundary(in: sampleBuffer)
        if shouldRunOCR(now: now) {
            runOCR(sampleBuffer: sampleBuffer, boundary: boundary, now: now)
        }
        let ocrAge = cardDetectedAt.map { now - $0 }
        let ocrFresh = cardPresent
            && ocrAge.map { $0 <= NIDTrackingConfig.ocrEvidenceLifetime } == true
        let ocrAgeMs = ocrAge.map { max(0, Int($0 * 1000)) }

        let cardCutOff = boundary.map { !quadIsInsideGuide($0, guideRect: guideRect, sampleBuffer: sampleBuffer) } ?? false
        var boundaryTrackLost = false
        if boundary == nil {
            missingBoundaryCount += 1
            if missingBoundaryCount > maximumMissingBoundaryFrames {
                boundaryTrackLost = true
                resetTrackedDocument()
                stability.reset()
            }
        } else {
            missingBoundaryCount = 0
        }
        let toleratedMissingBoundary = boundary == nil
            && !boundaryTrackLost
            && missingBoundaryCount <= maximumMissingBoundaryFrames
        let textOutside = boundary.map { quad in
            textRegions.contains { region in
                !quad.contains(CGPoint(x: region.midX, y: region.midY))
            }
        } ?? false

        let rawMotionHigh = previousBoundary != nil && rawMotion > NIDTrackingConfig.maximumMotion
        let cornerStep: CGFloat
        if let previousBoundary, let boundary {
            let step = boundary.meanDistance(to: previousBoundary)
            emaCornerStep = NIDTrackingConfig.emaAlpha * step
                + (1 - NIDTrackingConfig.emaAlpha) * (emaCornerStep ?? step)
            cornerStep = emaCornerStep ?? step
        } else {
            cornerStep = .infinity
        }
        if !rawMotionHigh {
            if let boundary {
                previousBoundary = boundary
            }
        }

        let eligibilityBlocker: NIDStabilityBlocker? = gap
            ? .frameGap
            : boundary == nil
            ? .missingBoundary
            : !documentConfirmed && !cardPresent
            ? .ocrMissing
            : !documentConfirmed && !ocrFresh
            ? .ocrExpired
            : cardCutOff
            ? .cardCutOff
            : !quality.acceptable
            ? .quality
            : !focusOK
            ? .focus
            : nil
        let eligible = eligibilityBlocker == nil && !isDeviceShaking

        if toleratedMissingBoundary {
            stability.preserveHoldForMissingBoundary(now: now)
        } else {
            stability.add(
                now: now,
                eligibilityBlocker: eligibilityBlocker,
                motion: rawMotion,
                cornerStep: cornerStep,
                boundary: boundary,
                pixels: currentMotion,
                tolerateMotionSpike: true
            )
        }
        let blocker = stability.blocker

        #if DEBUG
        print(
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
        print(
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
        print(
            "[NID][READY] " +
            "confirmed=\(documentConfirmed) " +
            "geometry=\(boundary != nil) " +
            "landscape=true " +
            "focus=\(focusOK) " +
            "quality=\(quality.acceptable) " +
            "motion=\(stability.motionState == .stable) " +
            "corner=\(stability.cornerState == .stable) " +
            "holdMs=\(Int(stability.holdDuration * 1000)) " +
            "frames=\(stability.frames) " +
            "progress=\(String(format: "%.2f", Double(stability.progress))) " +
            "blocker=\(blocker?.rawValue ?? "none")"
        )
        #endif

        let ready = stability.ready
            && stability.motionState == .stable
            && stability.cornerState == .stable
            && documentConfirmed
            && focusOK
            && quality.acceptable
            && boundary != nil

        let holding = boundary != nil
            && quality.acceptable
            && focusOK
            && !cardCutOff
            && documentConfirmed
        let status: NIDDetectionStatus = ready ? .ready : (holding ? .holdSteady : .notDetected)
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
            boundaryMissing: boundary == nil,
            boundary: boundary
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
        let request = VNDetectRectanglesRequest()
        request.minimumConfidence = 0.50
        request.minimumAspectRatio = 0.46
        request.maximumAspectRatio = 0.80
        request.minimumSize = 0.12
        request.quadratureTolerance = 22
        request.maximumObservations = 3
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .right, options: [:])
        try? handler.perform([request])
        let imageSize = orientedImageSize(for: sampleBuffer)
        let candidates = request.results ?? []
        let quads = candidates.map { observation -> (quad: NationalIDQuad, confidence: CGFloat) in
            let rawQuad = NationalIDQuad(observation: observation)
            return (
                quad: NationalIDGeometry.bestRelabeledQuad(rawQuad, matching: previousBoundary),
                confidence: CGFloat(observation.confidence)
            )
        }
        let continuous = quads.filter { continuityAllowed($0.quad) }
        let selectable = previousBoundary == nil ? quads : continuous
        return selectable
            .max { score($0.quad, confidence: $0.confidence, imageSize: imageSize) < score($1.quad, confidence: $1.confidence, imageSize: imageSize) }?
            .quad
    }

    private func score(_ quad: NationalIDQuad, confidence: CGFloat, imageSize: CGSize) -> CGFloat {
        let metrics = NationalIDGeometry.metrics(for: NationalIDGeometry.scaled(quad, to: imageSize))
        let areaScore = min(1, quad.area / 0.25)
        let continuity = previousBoundary.map { max(0, min(1, 1 - quad.meanDistance(to: $0) / 0.20)) } ?? 1
        return 0.20 * confidence + 0.25 * metrics.aspectScore + 0.20 * areaScore + 0.35 * continuity
    }

    private func continuityAllowed(_ quad: NationalIDQuad) -> Bool {
        guard let previousBoundary else { return true }
        let meanDistance = quad.meanDistance(to: previousBoundary)
        let iou = quad.iou(with: previousBoundary)
        let previousArea = max(previousBoundary.area, 0.0001)
        let areaRatio = quad.area / previousArea
        return meanDistance <= 0.22 && iou >= 0.35 && areaRatio >= 0.55 && areaRatio <= 1.8
    }

    private func shouldRunOCR(now: CFTimeInterval) -> Bool {
        lastOCRAt.map { now - $0 >= NIDTrackingConfig.ocrInterval } ?? true
    }

    private func runOCR(sampleBuffer: CMSampleBuffer, boundary: NationalIDQuad?, now: CFTimeInterval) {
        lastOCRAt = now
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.015
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .right, options: [:])
        try? handler.perform([request])
        let regions = (request.results ?? []).map(\.boundingBox)
        textRegions = regions
        guard let boundary else {
            return
        }
        let insideCount = regions.filter { boundary.contains(CGPoint(x: $0.midX, y: $0.midY)) }.count
        if insideCount >= 2 {
            cardPresent = true
            documentConfirmed = true
            cardDetectedAt = now
        }
    }

    private func resetTrackedDocument() {
        previousBoundary = nil
        emaCornerStep = nil
        cardPresent = false
        documentConfirmed = false
        cardDetectedAt = nil
        textRegions = []
        missingBoundaryCount = 0
    }

    private func quadIsInsideGuide(_ quad: NationalIDQuad, guideRect: CGRect, sampleBuffer: CMSampleBuffer) -> Bool {
        guard guideRect.width > 0, guideRect.height > 0, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return false
        }
        let oriented = CGSize(width: CVPixelBufferGetHeight(pixelBuffer), height: CVPixelBufferGetWidth(pixelBuffer))
        let scaled = NationalIDGeometry.scaled(quad, to: oriented)
        let normalizedGuide = guideRectForSampling(guideRect: guideRect, rawSize: oriented)
            .insetBy(dx: -oriented.width * 0.04, dy: -oriented.height * 0.04)
        return scaled.corners.allSatisfy { normalizedGuide.contains($0) }
    }

    private func orientedImageSize(for sampleBuffer: CMSampleBuffer) -> CGSize {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return .zero }
        return CGSize(width: CVPixelBufferGetHeight(pixelBuffer), height: CVPixelBufferGetWidth(pixelBuffer))
    }

    private static func formatNumber(_ value: CGFloat) -> String {
        String(format: "%.0f", Double(value))
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
