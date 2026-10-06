//
//  NationalIDCropper.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/6/26.
//

import CoreImage
import UIKit
import Vision

struct NationalIDCropResult {
    let image: CGImage
    let quad: NationalIDQuad
    let confidence: CGFloat
    let aspect: CGFloat
}

enum NationalIDCropper {
    private static let aspectTarget: CGFloat = 0.631
    private static let ciContext = CIContext(options: nil)

    static func cropCard(
        in image: CGImage,
        expectedQuad: NationalIDQuad?,
        marginFraction: CGFloat = 0.10,
        log: (String) -> Void = { _ in }
    ) -> NationalIDCropResult? {
        guard let rectangle = detectCardRectangle(in: image, expectedQuad: expectedQuad, log: log) else {
            return nil
        }
        guard let corrected = perspectiveCorrect(image, quad: rectangle.quad, marginFraction: marginFraction) else {
            return nil
        }
        return NationalIDCropResult(
            image: corrected,
            quad: rectangle.quad,
            confidence: rectangle.confidence,
            aspect: measuredAspectAndArea(rectangle.quad, image: image).aspect
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
        return NationalIDQuad(
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
        let request = VNDetectRectanglesRequest()
        request.minimumConfidence = 0.50
        request.minimumAspectRatio = 0.46
        request.maximumAspectRatio = 0.80
        request.minimumSize = 0.12
        request.quadratureTolerance = 22
        request.maximumObservations = 3

        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        try? handler.perform([request])
        guard let observations = request.results, observations.isEmpty == false else { return nil }
        let candidates = observations.compactMap { observation -> RectangleCandidate? in
            let baseScore = score(observation, image: image)
            let rawQuad = normalizedQuad(observation)
            let cropQuad = NationalIDGeometry.bestRelabeledQuad(rawQuad, matching: expectedQuad)
            guard let expectedQuad else {
                return RectangleCandidate(
                    observation: observation,
                    quad: cropQuad,
                    score: baseScore,
                    agreement: nil
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
                agreement: agreement
            )
        }
        guard let selected = candidates.max(by: { $0.score < $1.score }) else {
            if expectedQuad != nil {
                log("rectangle expectedAgreement noMatchingCandidate")
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
            observation: selected.observation,
            quad: selected.quad,
            confidence: CGFloat(selected.observation.confidence)
        )
    }

    private static func score(_ observation: VNRectangleObservation, image: CGImage) -> CGFloat {
        let measured = measuredAspectAndArea(observation, image: image)
        let aspectScore = max(0, 1 - abs(measured.aspect - aspectTarget) / 0.20)
        let imageArea = CGFloat(image.width * image.height)
        let areaScore = min(1, measured.area / (imageArea * 0.25))
        return 0.58 * CGFloat(observation.confidence) + 0.27 * aspectScore + 0.15 * areaScore
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
        guard measured.iou >= 0.20,
              measured.meanDistance <= 0.24,
              measured.maxDistance <= 0.40,
              measured.areaRatio >= 0.35,
              measured.areaRatio <= 2.50
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

    private static func perspectiveCorrect(_ image: CGImage, quad: NationalIDQuad, marginFraction: CGFloat) -> CGImage? {
        let corners = denormalizedCorners(quad, image: image)
        let expanded = outsetCorners(corners, image: image, marginFraction: marginFraction)
        let input = CIImage(cgImage: image)
        let filter = CIFilter(name: "CIPerspectiveCorrection")
        filter?.setValue(input, forKey: kCIInputImageKey)
        filter?.setValue(CIVector(cgPoint: expanded.topLeft), forKey: "inputTopLeft")
        filter?.setValue(CIVector(cgPoint: expanded.topRight), forKey: "inputTopRight")
        filter?.setValue(CIVector(cgPoint: expanded.bottomRight), forKey: "inputBottomRight")
        filter?.setValue(CIVector(cgPoint: expanded.bottomLeft), forKey: "inputBottomLeft")
        guard let output = filter?.outputImage else { return nil }
        return ciContext.createCGImage(output, from: output.extent)
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

    private static func outsetCorners(_ corners: CardCorners, image: CGImage, marginFraction: CGFloat) -> CardCorners {
        let centroid = CGPoint(
            x: (corners.topLeft.x + corners.topRight.x + corners.bottomRight.x + corners.bottomLeft.x) / 4,
            y: (corners.topLeft.y + corners.topRight.y + corners.bottomRight.y + corners.bottomLeft.y) / 4
        )
        var margin = marginFraction
        for point in [corners.topLeft, corners.topRight, corners.bottomRight, corners.bottomLeft] {
            let dx = point.x - centroid.x, dy = point.y - centroid.y
            if dx > 0 { margin = min(margin, (CGFloat(image.width) - point.x) / dx) }
            if dx < 0 { margin = min(margin, -point.x / dx) }
            if dy > 0 { margin = min(margin, (CGFloat(image.height) - point.y) / dy) }
            if dy < 0 { margin = min(margin, -point.y / dy) }
        }
        margin = max(0, margin)
        func push(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: centroid.x + (point.x - centroid.x) * (1 + margin),
                y: centroid.y + (point.y - centroid.y) * (1 + margin)
            )
        }
        return CardCorners(
            topLeft: push(corners.topLeft),
            topRight: push(corners.topRight),
            bottomRight: push(corners.bottomRight),
            bottomLeft: push(corners.bottomLeft)
        )
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
    let observation: VNRectangleObservation
    let quad: NationalIDQuad
    let confidence: CGFloat
}

private struct RectangleCandidate {
    let observation: VNRectangleObservation
    let quad: NationalIDQuad
    let score: CGFloat
    let agreement: RectangleAgreement?
}

private struct RectangleAgreement {
    let score: CGFloat
    let quad: NationalIDQuad
    let meanDistance: CGFloat
    let maxDistance: CGFloat
    let iou: CGFloat
    let areaRatio: CGFloat
}
