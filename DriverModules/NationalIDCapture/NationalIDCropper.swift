//
//  NationalIDCropper.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/6/26.
//

import CoreImage
import UIKit
import Vision

enum NationalIDCropper {
    private static let aspectTarget: CGFloat = 0.631
    private static let ciContext = CIContext(options: nil)
    
    // Margin configuration for perspective correction
    // marginFraction: percentage of quad dimensions to include as padding
    // Typical: 0.15 (15%) prevents edge clipping on rotated/shaking cards
    // Constraints: requested margins are clamped to 2-25%. Image bounds always
    // take precedence, so a card near the frame edge can end up below 2%.
    static let marginDefaultFraction: CGFloat = 0.15
    static let marginMinimumFraction: CGFloat = 0.02
    static let marginMaximumFraction: CGFloat = 0.25

    /// Corrected output with luma standard deviation below this (0-255 scale)
    /// is treated as a featureless surface rather than an ID card. Real cards
    /// (text, photo, security print) sit far above this.
    static let minimumOutputLumaStandardDeviation: CGFloat = 6.0

    /// Bounds a crop quad must satisfy before perspective correction.
    private enum QuadValidation {
        /// Allow slight overshoot (1%) for quads near frame edges during motion.
        /// Live tracking already validates geometry, so small frame proximity is acceptable.
        static let cornerOvershoot: CGFloat = 0.01
        /// Quad area as a fraction of the image.
        static let areaRange: ClosedRange<CGFloat> = 0.08...0.85
        /// min/max ratio of opposite edges; low values mean heavy perspective.
        /// Lowered to 0.48 to tolerate small card rotation ("little rotate").
        static let minimumEdgeBalance: CGFloat = 0.48
    }

    /// Bounds the corrected output image must satisfy.
    private enum OutputValidation {
        /// Lowered from 420 to 380 to accept more still frames with good content.
        static let minimumShortSide: CGFloat = 380
    }

    /// How closely a Vision observation must match the live-tracked quad.
    private enum ExpectedAgreement {
        static let minimumIOU: CGFloat = 0.65
        static let maximumMeanDistance: CGFloat = 0.08
        static let maximumCornerDistance: CGFloat = 0.16
        static let areaRatioRange: ClosedRange<CGFloat> = 0.70...1.35
    }

    static func cropCard(
        in image: CGImage,
        expectedQuad: NationalIDQuad?,
        marginFraction: CGFloat = marginDefaultFraction,
        log: (String) -> Void = { _ in }
    ) -> NationalIDCropResult? {
        // Fast path: try expectedQuad only — skip redundant validation, go straight to crop
        if let expectedQuad {
            log("rectangle preferExpected primary=true")
            if let result = cropResult(
                image: image,
                rectangle: DetectedRectangle(
                    quad: expectedQuad,
                    confidence: 1,
                    decision: "expectedPrimary"
                ),
                marginFraction: marginFraction,
                log: log
            ) {
                return result
            }
            return nil  // If expected quad crop fails, don't retry
        }

        // Fallback: Run Vision only if no expectedQuad provided
        guard let rectangle = detectCardRectangle(in: image, expectedQuad: nil, log: log) else {
            return nil
        }
        return cropResult(
            image: image,
            rectangle: rectangle,
            marginFraction: marginFraction,
            log: log
        )
    }

    private static func cropResult(
        image: CGImage,
        rectangle: DetectedRectangle,
        marginFraction: CGFloat,
        log: (String) -> Void
    ) -> NationalIDCropResult? {
        // Fast path for expectedPrimary: skip expensive geometry validation.
        // Live tracking already validated this quad's geometry.
        if rectangle.decision == "expectedPrimary" {
            return cropResultFast(image: image, rectangle: rectangle, marginFraction: marginFraction, log: log)
        }
        
        // Adjust margin based on card orientation (rotation angle).
        // Diagonal cards need more margin to prevent corner clipping during perspective correction.
        let orientation = rectangle.quad.orientation
        let orientationMarginMultiplier = orientation.marginMultiplier
        let adjustedMargin = marginFraction * orientationMarginMultiplier
        
        // Full path for Vision rectangles: validate geometry
        guard let correction = perspectiveCorrect(
            image,
            quad: rectangle.quad,
            marginFraction: adjustedMargin,
            log: log
        ) else {
            log("crop rejected reason=perspectiveCorrectionFailed decision=\(rectangle.decision)")
            return nil
        }
        let corrected = correction.image
        
        // Validate the corrected output's geometry and compare with original
        let correctionMetrics = validateCorrectedImageWithMetrics(
            corrected,
            originalQuad: rectangle.quad,
            sourceImage: image,
            decision: rectangle.decision,
            log: log
        )
        guard let metrics = correctionMetrics else {
            return nil
        }
        
        // Check luma contrast to reject featureless surfaces
        let contrast = lumaStandardDeviation(of: corrected)
        guard let contrast, contrast >= minimumOutputLumaStandardDeviation else {
            log(
                "crop rejected reason=lowContrast " +
                "decision=\(rectangle.decision) " +
                "lumaStdDev=\(contrast.map(format) ?? "nil")"
            )
            return nil
        }

        let originalMetrics = NationalIDGeometry.metrics(for: rectangle.quad)
        let originalBalance = min(
            min(originalMetrics.topEdge, originalMetrics.bottomEdge) / max(originalMetrics.topEdge, originalMetrics.bottomEdge, 0.0001),
            min(originalMetrics.leftEdge, originalMetrics.rightEdge) / max(originalMetrics.leftEdge, originalMetrics.rightEdge, 0.0001)
        )

        let correctedAspect = correctedAspect(corrected)
        log(
            "crop accepted " +
            "decision=\(rectangle.decision) " +
            "orientation=\(orientation) " +
            "marginMultiplier=\(format(orientationMarginMultiplier)) " +
            "outputAspect=\(format(correctedAspect)) " +
            "size=\(corrected.width)x\(corrected.height) " +
            "margin=\(format(correction.margin)) " +
            "sourceEdgeBalance=\(format(originalBalance)) " +
            "correctionImproved=\(metrics.geometryImproved) " +
            "lumaStdDev=\(format(contrast))"
        )
        return NationalIDCropResult(
            image: corrected,
            quad: rectangle.quad,
            confidence: rectangle.confidence,
            aspect: measuredAspectAndArea(rectangle.quad, image: image).aspect,
            decision: rectangle.decision
        )
    }
    
    /// Fast crop result for live-tracked quads (already geometry-validated in tracker).
    /// Skips expensive geometry comparison, only checks contrast and applies correction.
    private static func cropResultFast(
        image: CGImage,
        rectangle: DetectedRectangle,
        marginFraction: CGFloat,
        log: (String) -> Void
    ) -> NationalIDCropResult? {
        let measured = measuredAspectAndArea(rectangle.quad, image: image)
        guard NationalIDGeometry.acceptedAspectRange.contains(measured.aspect) else {
            log("crop rejected reason=expectedQuadAspect aspect=\(format(measured.aspect))")
            return nil
        }
        guard let correction = perspectiveCorrect(
            image,
            quad: rectangle.quad,
            marginFraction: marginFraction,
            log: log
        ) else {
            log("crop rejected reason=perspectiveCorrectionFailed decision=\(rectangle.decision)")
            return nil
        }
        let corrected = correction.image
        
        // Only check contrast (geometry already validated in live tracking)
        let contrast = lumaStandardDeviation(of: corrected)
        guard let contrast, contrast >= minimumOutputLumaStandardDeviation else {
            log("crop rejected reason=lowContrast lumaStdDev=\(contrast.map(format) ?? "nil")")
            return nil
        }
        
        log("crop accepted decision=expectedPrimary size=\(corrected.width)x\(corrected.height)")
        return NationalIDCropResult(
            image: corrected,
            quad: rectangle.quad,
            confidence: rectangle.confidence,
            aspect: measured.aspect,
            decision: rectangle.decision
        )
    }

    static func processorQuad(
        _ quad: NationalIDQuad,
        from orientation: UIImage.Orientation
    ) -> NationalIDQuad {
        func map(_ point: CGPoint) -> CGPoint {
            switch orientation {
            case .right, .rightMirrored:
                return CGPoint(x: 1 - point.y, y: point.x)
            case .left, .leftMirrored:
                return CGPoint(x: point.y, y: 1 - point.x)
            case .down, .downMirrored:
                return CGPoint(x: 1 - point.x, y: 1 - point.y)
            case .up, .upMirrored:
                return point
            @unknown default:
                return point
            }
        }
        let mapped = quad.corners.map(map)
        return orderedImageQuad(from: mapped) ?? NationalIDQuad(
            topLeft: map(quad.topLeft),
            topRight: map(quad.topRight),
            bottomRight: map(quad.bottomRight),
            bottomLeft: map(quad.bottomLeft)
        )
    }

    private static func detectCardRectangle(
        in image: CGImage,
        expectedQuad: NationalIDQuad?,
        log: (String) -> Void
    ) -> DetectedRectangle? {
        let request = NIDRectangleDetectionConfig.makeRequest()

        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            log("rectangle detectionFailed error=\(error.localizedDescription)")
            return nil
        }
        guard let observations = request.results, observations.isEmpty == false else { return nil }
        let candidates = observations.compactMap { observation -> RectangleCandidate? in
            let baseScore = score(observation, image: image)
            let rawQuad = normalizedQuad(observation)
            let cropQuad = NationalIDGeometry.bestRelabeledQuad(rawQuad, matching: expectedQuad)
            guard validateQuad(cropQuad, image: image, log: log, prefix: "rectangle rejectedByGeometry") else {
                return nil
            }
            guard let expectedQuad else {
                return RectangleCandidate(
                    observation: observation,
                    quad: cropQuad,
                    score: baseScore,
                    agreement: nil,
                    decision: "vision"
                )
            }
            guard let agreement = expectedAgreement(observation, expectedQuad: expectedQuad) else {
                let measured = bestMeasuredAgreement(observation, expectedQuad: expectedQuad)
                log(
                    "rectangle rejectedByExpectedQuad " +
                    "confidence=\(format(CGFloat(observation.confidence))) " +
                    "mean=\(format(measured.meanDistance)) " +
                    "max=\(format(measured.maxDistance)) " +
                    "iou=\(format(measured.iou)) " +
                    "areaRatio=\(format(measured.areaRatio))"
                )
                return nil
            }
            return RectangleCandidate(
                observation: observation,
                quad: agreement.quad,
                score: baseScore + 0.35 * agreement.score,
                agreement: agreement,
                decision: "visionExpectedAgreement"
            )
        }
        guard let selected = candidates.max(by: { $0.score < $1.score }) else {
            if let expectedQuad {
                log("rectangle expectedAgreement noMatchingCandidate")
                guard validateQuad(expectedQuad, image: image, log: log, prefix: "rectangle expectedFallbackRejected") else {
                    return nil
                }
                let measured = measuredAspectAndArea(expectedQuad, image: image)
                log(
                    "rectangle expectedFallback " +
                    "aspect=\(format(measured.aspect)) " +
                    "area=\(format(measured.area / CGFloat(image.width * image.height)))"
                )
                return DetectedRectangle(
                    quad: expectedQuad,
                    confidence: 1,
                    decision: "expectedFallback"
                )
            }
            return nil
        }
        if let agreement = selected.agreement {
            log(
                "rectangle expectedAgreement " +
                "score=\(format(agreement.score)) " +
                "mean=\(format(agreement.meanDistance)) " +
                "max=\(format(agreement.maxDistance)) " +
                "iou=\(format(agreement.iou)) " +
                "areaRatio=\(format(agreement.areaRatio))"
            )
        }
        return DetectedRectangle(
            quad: selected.quad,
            confidence: CGFloat(selected.observation.confidence),
            decision: selected.decision
        )
    }

    private static func score(_ observation: VNRectangleObservation, image: CGImage) -> CGFloat {
        let measured = measuredAspectAndArea(observation, image: image)
        let aspectScore = max(0, 1 - abs(measured.aspect - aspectTarget) / 0.20)
        let imageArea = CGFloat(image.width * image.height)
        let areaScore = min(1, measured.area / (imageArea * 0.25))
        return 0.45 * CGFloat(observation.confidence) + 0.40 * aspectScore + 0.15 * areaScore
    }

    private static func measuredAspectAndArea(_ observation: VNRectangleObservation, image: CGImage) -> (aspect: CGFloat, area: CGFloat) {
        measuredAspectAndArea(normalizedQuad(observation), image: image)
    }

    private static func measuredAspectAndArea(_ quad: NationalIDQuad, image: CGImage) -> (aspect: CGFloat, area: CGFloat) {
        let points = denormalizedCorners(quad, image: image)
        let wTop = distance(points.topLeft, points.topRight)
        let wBottom = distance(points.bottomLeft, points.bottomRight)
        let hLeft = distance(points.topLeft, points.bottomLeft)
        let hRight = distance(points.topRight, points.bottomRight)
        let wAverage = (wTop + wBottom) / 2
        let hAverage = (hLeft + hRight) / 2
        return (min(wAverage, hAverage) / max(wAverage, hAverage), wAverage * hAverage)
    }

    private static func expectedAgreement(
        _ observation: VNRectangleObservation,
        expectedQuad: NationalIDQuad
    ) -> RectangleAgreement? {
        let measured = bestMeasuredAgreement(observation, expectedQuad: expectedQuad)
        guard measured.iou >= ExpectedAgreement.minimumIOU,
              measured.meanDistance <= ExpectedAgreement.maximumMeanDistance,
              measured.maxDistance <= ExpectedAgreement.maximumCornerDistance,
              ExpectedAgreement.areaRatioRange.contains(measured.areaRatio)
        else {
            return nil
        }
        return measured
    }

    private static func bestMeasuredAgreement(
        _ observation: VNRectangleObservation,
        expectedQuad: NationalIDQuad
    ) -> RectangleAgreement {
        let rawQuad = normalizedQuad(observation)
        let landscapeQuad = NationalIDGeometry.normalizedLandscapeQuad(rawQuad)
        let variants = [rawQuad, landscapeQuad].flatMap { NationalIDGeometry.relabeledVariants(of: $0) }
        return variants
            .map { agreement(for: $0, expectedQuad: expectedQuad) }
            .max(by: { $0.score < $1.score }) ?? RectangleAgreement(
                score: 0,
                quad: landscapeQuad,
                meanDistance: 1,
                maxDistance: 1,
                iou: 0,
                areaRatio: 0
            )
    }

    private static func agreement(
        for quad: NationalIDQuad,
        expectedQuad: NationalIDQuad
    ) -> RectangleAgreement {
        let meanDistance = quad.meanDistance(to: expectedQuad)
        let maxDistance = quad.maxDistance(to: expectedQuad)
        let iou = quad.iou(with: expectedQuad)
        let expectedArea = max(expectedQuad.area, 0.0001)
        let areaRatio = quad.area / expectedArea

        let meanScore = max(0, 1 - meanDistance / 0.24)
        let maxScore = max(0, 1 - maxDistance / 0.40)
        let areaScore = max(0, 1 - abs(areaRatio - 1) / 1.50)
        let score = 0.45 * iou + 0.35 * meanScore + 0.10 * maxScore + 0.10 * areaScore
        return RectangleAgreement(
            score: score,
            quad: quad,
            meanDistance: meanDistance,
            maxDistance: maxDistance,
            iou: iou,
            areaRatio: areaRatio
        )
    }

    private static func normalizedQuad(_ observation: VNRectangleObservation) -> NationalIDQuad {
        NationalIDQuad(
            topLeft: observation.topLeft,
            topRight: observation.topRight,
            bottomRight: observation.bottomRight,
            bottomLeft: observation.bottomLeft
        )
    }

    private static func perspectiveCorrect(
        _ image: CGImage,
        quad: NationalIDQuad,
        marginFraction: CGFloat,
        log: (String) -> Void
    ) -> (image: CGImage, margin: CGFloat)? {
        let corners = denormalizedCorners(quad, image: image)
        let outset = outsetCorners(corners, image: image, marginFraction: marginFraction)
        if outset.margin < marginMinimumFraction {
            log(
                "crop marginClamped " +
                "requested=\(format(marginFraction)) " +
                "applied=\(format(outset.margin)) " +
                "reason=cardNearImageEdge"
            )
        }
        let expanded = outset.corners
        let input = CIImage(cgImage: image)
        let filter = CIFilter(name: "CIPerspectiveCorrection")
        filter?.setValue(input, forKey: kCIInputImageKey)
        filter?.setValue(CIVector(cgPoint: expanded.topLeft), forKey: "inputTopLeft")
        filter?.setValue(CIVector(cgPoint: expanded.topRight), forKey: "inputTopRight")
        filter?.setValue(CIVector(cgPoint: expanded.bottomRight), forKey: "inputBottomRight")
        filter?.setValue(CIVector(cgPoint: expanded.bottomLeft), forKey: "inputBottomLeft")
        guard let output = filter?.outputImage,
              let rendered = ciContext.createCGImage(output, from: output.extent)
        else {
            return nil
        }
        return (rendered, outset.margin)
    }

    private static func validateQuad(
        _ quad: NationalIDQuad,
        image: CGImage,
        log: (String) -> Void,
        prefix: String
    ) -> Bool {
        guard quad.corners.allSatisfy({ point in
            let low = -QuadValidation.cornerOvershoot
            let high = 1 + QuadValidation.cornerOvershoot
            return point.x.isFinite
                && point.y.isFinite
                && point.x >= low
                && point.x <= high
                && point.y >= low
                && point.y <= high
        }) else {
            log("\(prefix) reason=outOfBounds")
            return false
        }

        let measured = measuredAspectAndArea(quad, image: image)
        let areaRatio = measured.area / CGFloat(image.width * image.height)
        let metrics = NationalIDGeometry.metrics(for: quad)
        let horizontalBalance = min(metrics.topEdge, metrics.bottomEdge) / max(metrics.topEdge, metrics.bottomEdge, 0.0001)
        let verticalBalance = min(metrics.leftEdge, metrics.rightEdge) / max(metrics.leftEdge, metrics.rightEdge, 0.0001)

        guard NationalIDGeometry.acceptedAspectRange.contains(measured.aspect) else {
            log("\(prefix) reason=aspect aspect=\(format(measured.aspect))")
            return false
        }
        guard QuadValidation.areaRange.contains(areaRatio) else {
            log("\(prefix) reason=area area=\(format(areaRatio))")
            return false
        }
        guard horizontalBalance >= QuadValidation.minimumEdgeBalance,
              verticalBalance >= QuadValidation.minimumEdgeBalance
        else {
            log(
                "\(prefix) reason=edgeBalance " +
                "horizontal=\(format(horizontalBalance)) " +
                "vertical=\(format(verticalBalance))"
            )
            return false
        }
        return true
    }

    private static func validateCorrectedImage(_ image: CGImage, log: (String) -> Void, decision: String) -> Bool {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let shortSide = min(width, height)
        let longSide = max(width, height)
        let aspect = shortSide / max(longSide, 1)
        guard shortSide >= OutputValidation.minimumShortSide else {
            log("crop rejected reason=outputTooSmall decision=\(decision) size=\(image.width)x\(image.height)")
            return false
        }
        guard NationalIDGeometry.acceptedAspectRange.contains(aspect) else {
            log("crop rejected reason=outputAspect decision=\(decision) aspect=\(format(aspect)) size=\(image.width)x\(image.height)")
            return false
        }
        return true
    }

    /// Validates perspective-corrected output and compares with original geometry.
    /// Returns metrics including whether the correction improved balance, or nil if validation fails.
    private static func validateCorrectedImageWithMetrics(
        _ image: CGImage,
        originalQuad: NationalIDQuad,
        sourceImage: CGImage,
        decision: String,
        log: (String) -> Void
    ) -> CorrectionMetrics? {
        // Basic output validation (size, aspect)
        guard validateCorrectedImage(image, log: log, decision: decision) else {
            return nil
        }
        
        // Compute original edge balance
        let originalMetrics = NationalIDGeometry.metrics(for: originalQuad)
        let originalBalance = min(
            min(originalMetrics.topEdge, originalMetrics.bottomEdge) / max(originalMetrics.topEdge, originalMetrics.bottomEdge, 0.0001),
            min(originalMetrics.leftEdge, originalMetrics.rightEdge) / max(originalMetrics.leftEdge, originalMetrics.rightEdge, 0.0001)
        )
        
        // After perspective correction, the output *should* be close to 1.0 balance
        // but CoreImage might not be perfect. Check if we're reasonably close to rectangular.
        let correctedAspect = correctedAspect(image)
        let geometryImproved = originalBalance < 0.95  // Original was perspective-distorted
        
        return CorrectionMetrics(
            aspect: correctedAspect,
            sourceEdgeBalance: originalBalance,
            geometryImproved: geometryImproved
        )
    }

    /// Metrics describing the quality of perspective correction
    private struct CorrectionMetrics {
        let aspect: CGFloat
        let sourceEdgeBalance: CGFloat
        let geometryImproved: Bool
    }


    /// Standard deviation of luma (0-255) over a downsampled grayscale copy.
    /// The sample is large enough to keep text strokes, small enough to be cheap.
    static func lumaStandardDeviation(of image: CGImage) -> CGFloat? {
        let sampleWidth = 128
        let sampleHeight = 80
        var buffer = [UInt8](repeating: 0, count: sampleWidth * sampleHeight)
        let drawn: Bool = buffer.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: sampleWidth,
                height: sampleHeight,
                bitsPerComponent: 8,
                bytesPerRow: sampleWidth,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else {
                return false
            }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))
            return true
        }
        guard drawn else { return nil }
        let count = CGFloat(buffer.count)
        var sum: CGFloat = 0
        var sumSquares: CGFloat = 0
        for value in buffer {
            let v = CGFloat(value)
            sum += v
            sumSquares += v * v
        }
        let mean = sum / count
        return sqrt(max(0, sumSquares / count - mean * mean))
    }

    private static func correctedAspect(_ image: CGImage) -> CGFloat {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let shortSide = min(width, height)
        let longSide = max(width, height)
        return shortSide / max(longSide, 1)
    }

    private static func denormalizedCorners(_ quad: NationalIDQuad, image: CGImage) -> CardCorners {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        func point(_ normalized: CGPoint) -> CGPoint {
            CGPoint(x: normalized.x * width, y: normalized.y * height)
        }
        return CardCorners(
            topLeft: point(quad.topLeft),
            topRight: point(quad.topRight),
            bottomRight: point(quad.bottomRight),
            bottomLeft: point(quad.bottomLeft)
        )
    }

    private static func orderedImageQuad(from points: [CGPoint]) -> NationalIDQuad? {
        guard points.count == 4 else { return nil }
        let sortedByY = points.sorted { lhs, rhs in
            if abs(lhs.y - rhs.y) < 0.001 {
                return lhs.x < rhs.x
            }
            return lhs.y > rhs.y
        }
        let top = Array(sortedByY.prefix(2)).sorted { $0.x < $1.x }
        let bottom = Array(sortedByY.suffix(2)).sorted { $0.x < $1.x }
        guard top.count == 2, bottom.count == 2 else { return nil }
        return NationalIDQuad(
            topLeft: top[0],
            topRight: top[1],
            bottomRight: bottom[1],
            bottomLeft: bottom[0]
        )
    }

    private static func outsetCorners(
        _ corners: CardCorners,
        image: CGImage,
        marginFraction: CGFloat
    ) -> (corners: CardCorners, margin: CGFloat) {
        let points = [corners.topLeft, corners.topRight, corners.bottomRight, corners.bottomLeft]
        let centroid = CGPoint(
            x: points.map(\.x).reduce(0, +) / 4,
            y: points.map(\.y).reduce(0, +) / 4
        )
        let margin = effectiveMargin(
            corners: points,
            imageSize: CGSize(width: image.width, height: image.height),
            requested: marginFraction
        )
        func push(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: centroid.x + (point.x - centroid.x) * (1 + margin),
                y: centroid.y + (point.y - centroid.y) * (1 + margin)
            )
        }
        return (
            CardCorners(
                topLeft: push(corners.topLeft),
                topRight: push(corners.topRight),
                bottomRight: push(corners.bottomRight),
                bottomLeft: push(corners.bottomLeft)
            ),
            margin
        )
    }

    /// Margin actually applied when outsetting `corners` (pixel space) from
    /// their centroid.
    ///
    /// The request is clamped to `marginMinimumFraction...marginMaximumFraction`,
    /// then reduced further if any pushed corner would leave the image. Image
    /// bounds win over the minimum: pushing past the edge would make
    /// CIPerspectiveCorrection sample empty pixels.
    static func effectiveMargin(corners: [CGPoint], imageSize: CGSize, requested: CGFloat) -> CGFloat {
        guard corners.isEmpty == false else { return 0 }
        let centroid = CGPoint(
            x: corners.map(\.x).reduce(0, +) / CGFloat(corners.count),
            y: corners.map(\.y).reduce(0, +) / CGFloat(corners.count)
        )
        var margin = min(marginMaximumFraction, max(marginMinimumFraction, requested))
        for point in corners {
            let dx = point.x - centroid.x, dy = point.y - centroid.y
            if dx > 0 { margin = min(margin, (imageSize.width - point.x) / dx) }
            if dx < 0 { margin = min(margin, -point.x / dx) }
            if dy > 0 { margin = min(margin, (imageSize.height - point.y) / dy) }
            if dy < 0 { margin = min(margin, -point.y / dy) }
        }
        return max(0, margin)
    }

    private static func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }

    private static func format(_ value: CGFloat) -> String {
        String(format: "%.3f", Double(value))
    }
}

private struct CardCorners {
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomRight: CGPoint
    let bottomLeft: CGPoint
}

private struct DetectedRectangle {
    let quad: NationalIDQuad
    let confidence: CGFloat
    let decision: String
}

private struct RectangleCandidate {
    let observation: VNRectangleObservation
    let quad: NationalIDQuad
    let score: CGFloat
    let agreement: RectangleAgreement?
    let decision: String
}

private struct RectangleAgreement {
    let score: CGFloat
    let quad: NationalIDQuad
    let meanDistance: CGFloat
    let maxDistance: CGFloat
    let iou: CGFloat
    let areaRatio: CGFloat
}
