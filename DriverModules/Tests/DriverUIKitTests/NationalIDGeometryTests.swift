//
//  NationalIDGeometryTests.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/5/26.
//

@testable import NationalIDCapture
import AVFoundation
import CoreGraphics
import ImageIO
import UIKit
import XCTest

final class NationalIDGeometryTests: XCTestCase {
    func testPortraitCameraBufferWithLandscapeCardKeepsPhysicalAspect() {
        let imageSize = CGSize(width: 1_920, height: 1_080)
        let normalized = normalizedQuad(
            topLeft: CGPoint(x: 530, y: 270),
            topRight: CGPoint(x: 1_390, y: 270),
            bottomRight: CGPoint(x: 1_390, y: 810),
            bottomLeft: CGPoint(x: 530, y: 810),
            imageSize: imageSize
        )

        let metrics = NationalIDGeometry.metrics(for: NationalIDGeometry.scaled(normalized, to: imageSize))

        XCTAssertEqual(metrics.topEdge, 860, accuracy: 0.001)
        XCTAssertEqual(metrics.leftEdge, 540, accuracy: 0.001)
        XCTAssertEqual(metrics.measuredAspect, 540.0 / 860.0, accuracy: 0.001)
        XCTAssertGreaterThan(metrics.aspectScore, 0.98)
    }

    func testRotatedVisionCoordinateSpaceUsesOrientedPixelSize() {
        let orientedSize = CGSize(width: 1_920, height: 1_080)
        let quad = normalizedQuad(
            topLeft: CGPoint(x: 500, y: 250),
            topRight: CGPoint(x: 1_360, y: 250),
            bottomRight: CGPoint(x: 1_360, y: 790),
            bottomLeft: CGPoint(x: 500, y: 790),
            imageSize: orientedSize
        )

        let correctlyScaled = NationalIDGeometry.metrics(for: NationalIDGeometry.scaled(quad, to: orientedSize))
        let incorrectlyScaled = NationalIDGeometry.metrics(for: quad)

        XCTAssertEqual(correctlyScaled.measuredAspect, 540.0 / 860.0, accuracy: 0.001)
        XCTAssertNotEqual(correctlyScaled.measuredAspect, incorrectlyScaled.measuredAspect, accuracy: 0.05)
    }

    func testSkewedQuadUsesEdgeDistancesNotBoundingBoxOrDiagonals() {
        let quad = NationalIDQuad(
            topLeft: CGPoint(x: 100, y: 100),
            topRight: CGPoint(x: 960, y: 130),
            bottomRight: CGPoint(x: 900, y: 660),
            bottomLeft: CGPoint(x: 130, y: 620)
        )

        let metrics = NationalIDGeometry.metrics(for: quad)
        let expectedTop = hypot(CGFloat(860), CGFloat(30))
        let expectedBottom = hypot(CGFloat(770), CGFloat(40))
        let expectedLeft = hypot(CGFloat(30), CGFloat(520))
        let expectedRight = hypot(CGFloat(60), CGFloat(530))
        let expectedWidth = (expectedTop + expectedBottom) / 2
        let expectedHeight = (expectedLeft + expectedRight) / 2

        XCTAssertEqual(metrics.topEdge, expectedTop, accuracy: 0.001)
        XCTAssertEqual(metrics.bottomEdge, expectedBottom, accuracy: 0.001)
        XCTAssertEqual(metrics.leftEdge, expectedLeft, accuracy: 0.001)
        XCTAssertEqual(metrics.rightEdge, expectedRight, accuracy: 0.001)
        XCTAssertEqual(metrics.measuredAspect, min(expectedWidth, expectedHeight) / max(expectedWidth, expectedHeight), accuracy: 0.001)
    }

    func testCornerOrderMapsEdgesCorrectly() {
        let quad = NationalIDQuad(
            topLeft: CGPoint(x: 0, y: 0),
            topRight: CGPoint(x: 10, y: 0),
            bottomRight: CGPoint(x: 10, y: 6),
            bottomLeft: CGPoint(x: 0, y: 6)
        )

        let metrics = NationalIDGeometry.metrics(for: quad)

        XCTAssertEqual(metrics.topEdge, 10, accuracy: 0.001)
        XCTAssertEqual(metrics.bottomEdge, 10, accuracy: 0.001)
        XCTAssertEqual(metrics.leftEdge, 6, accuracy: 0.001)
        XCTAssertEqual(metrics.rightEdge, 6, accuracy: 0.001)
    }

    func testMeanDistanceAveragesCornerDisplacement() {
        let first = NationalIDQuad(
            topLeft: CGPoint(x: 0, y: 0),
            topRight: CGPoint(x: 1, y: 0),
            bottomRight: CGPoint(x: 1, y: 1),
            bottomLeft: CGPoint(x: 0, y: 1)
        )
        let second = NationalIDQuad(
            topLeft: CGPoint(x: 0.01, y: 0),
            topRight: CGPoint(x: 1.02, y: 0),
            bottomRight: CGPoint(x: 1.03, y: 1),
            bottomLeft: CGPoint(x: 0.04, y: 1)
        )

        XCTAssertEqual(first.meanDistance(to: second), 0.025, accuracy: 0.001)
    }

    func testMaxDistanceUsesWorstCornerDisplacement() {
        let first = NationalIDQuad(
            topLeft: CGPoint(x: 0, y: 0),
            topRight: CGPoint(x: 1, y: 0),
            bottomRight: CGPoint(x: 1, y: 1),
            bottomLeft: CGPoint(x: 0, y: 1)
        )
        let second = NationalIDQuad(
            topLeft: CGPoint(x: 0.01, y: 0),
            topRight: CGPoint(x: 1.02, y: 0),
            bottomRight: CGPoint(x: 1.03, y: 1),
            bottomLeft: CGPoint(x: 0.04, y: 1)
        )

        XCTAssertEqual(first.maxDistance(to: second), 0.04, accuracy: 0.001)
    }

    func testSwappedEdgeAxesStillValidatePhysicalShape() {
        let portraitCardShape = NationalIDQuad(
            topLeft: CGPoint(x: 0, y: 0),
            topRight: CGPoint(x: 540, y: 0),
            bottomRight: CGPoint(x: 540, y: 860),
            bottomLeft: CGPoint(x: 0, y: 860)
        )

        let metrics = NationalIDGeometry.metrics(for: portraitCardShape)

        XCTAssertEqual(metrics.measuredAspect, 540.0 / 860.0, accuracy: 0.001)
        XCTAssertGreaterThan(metrics.aspectScore, 0.98)
        XCTAssertFalse(metrics.isLandscape)
    }

    func testPreviewSpaceOrientationIsSeparateFromShapeValidation() {
        let landscapePreview = NationalIDGeometry.metrics(
            for: NationalIDQuad(
                topLeft: CGPoint(x: 20, y: 20),
                topRight: CGPoint(x: 220, y: 20),
                bottomRight: CGPoint(x: 220, y: 146),
                bottomLeft: CGPoint(x: 20, y: 146)
            )
        )
        let portraitPreview = NationalIDGeometry.metrics(
            for: NationalIDQuad(
                topLeft: CGPoint(x: 20, y: 20),
                topRight: CGPoint(x: 146, y: 20),
                bottomRight: CGPoint(x: 146, y: 220),
                bottomLeft: CGPoint(x: 20, y: 220)
            )
        )

        XCTAssertTrue(landscapePreview.isLandscape)
        XCTAssertFalse(portraitPreview.isLandscape)
        XCTAssertEqual(landscapePreview.measuredAspect, portraitPreview.measuredAspect, accuracy: 0.001)
    }

    func testStableCardKeepsSameGeometryStateAcrossConsecutiveFrames() {
        let frames = [
            NationalIDQuad(topLeft: CGPoint(x: 100, y: 100), topRight: CGPoint(x: 960, y: 102), bottomRight: CGPoint(x: 958, y: 642), bottomLeft: CGPoint(x: 101, y: 640)),
            NationalIDQuad(topLeft: CGPoint(x: 101, y: 100), topRight: CGPoint(x: 961, y: 101), bottomRight: CGPoint(x: 959, y: 641), bottomLeft: CGPoint(x: 102, y: 641)),
            NationalIDQuad(topLeft: CGPoint(x: 100, y: 101), topRight: CGPoint(x: 960, y: 102), bottomRight: CGPoint(x: 960, y: 642), bottomLeft: CGPoint(x: 100, y: 641)),
            NationalIDQuad(topLeft: CGPoint(x: 102, y: 99), topRight: CGPoint(x: 962, y: 101), bottomRight: CGPoint(x: 960, y: 640), bottomLeft: CGPoint(x: 102, y: 639))
        ]

        let states = frames.map { quad -> String in
            let metrics = NationalIDGeometry.metrics(for: quad)
            return metrics.aspectScore > 0.95 && metrics.isLandscape ? "readyShape" : "notReadyShape"
        }

        XCTAssertEqual(Set(states), ["readyShape"])
    }

    func testRotatedQuadNormalizesLongPairToLandscapeTopAndBottom() {
        let raw = NationalIDQuad(
            topLeft: CGPoint(x: 100, y: 100),
            topRight: CGPoint(x: 100, y: 390),
            bottomRight: CGPoint(x: 560, y: 390),
            bottomLeft: CGPoint(x: 540, y: 100)
        )

        let rawMetrics = NationalIDGeometry.metrics(for: raw)
        let normalized = NationalIDGeometry.normalizedLandscapeQuad(raw)
        let normalizedMetrics = NationalIDGeometry.metrics(for: normalized)

        XCTAssertEqual(rawMetrics.longPair, "leftRight")
        XCTAssertEqual(normalized.topLeft, raw.topLeft)
        XCTAssertEqual(normalized.topRight, raw.bottomLeft)
        XCTAssertEqual(normalized.bottomRight, raw.bottomRight)
        XCTAssertEqual(normalized.bottomLeft, raw.topRight)
        XCTAssertGreaterThan(normalizedMetrics.topEdge, normalizedMetrics.leftEdge)
        XCTAssertTrue(normalizedMetrics.isLandscape)
        XCTAssertEqual(normalizedMetrics.measuredAspect, rawMetrics.measuredAspect, accuracy: 0.001)
    }

    func testLandscapeQuadKeepsItsFourPhysicalPointsAndLabels() {
        let raw = NationalIDQuad(
            topLeft: CGPoint(x: 100, y: 100),
            topRight: CGPoint(x: 560, y: 110),
            bottomRight: CGPoint(x: 550, y: 400),
            bottomLeft: CGPoint(x: 105, y: 390)
        )

        let normalized = NationalIDGeometry.normalizedLandscapeQuad(raw)
        let normalizedPoints = [normalized.topLeft, normalized.topRight, normalized.bottomRight, normalized.bottomLeft]
        let rawPoints = [raw.topLeft, raw.topRight, raw.bottomRight, raw.bottomLeft]
        XCTAssertTrue(normalizedPoints.allSatisfy { rawPoints.contains($0) })
        XCTAssertTrue(rawPoints.allSatisfy { normalizedPoints.contains($0) })
        XCTAssertTrue(NationalIDGeometry.metrics(for: normalized).isLandscape)
    }

    func testPortraitAppOrientationRotatesVisionQuadIntoLandscapePreview() {
        let visionQuad = [
            CGPoint(x: 0.20, y: 0.85),
            CGPoint(x: 0.80, y: 0.85),
            CGPoint(x: 0.80, y: 0.15),
            CGPoint(x: 0.20, y: 0.15)
        ].map {
            NationalIDPreviewTransform.captureDevicePoint(
                fromVisionPoint: $0,
                visionOrientation: .right,
                videoOrientation: .portrait,
                isMirrored: false
            )
        }

        let previewQuad = NationalIDPreviewTransform.orderedPreviewQuad(from: visionQuad)
        XCTAssertNotNil(previewQuad)
        XCTAssertTrue(NationalIDGeometry.metrics(for: previewQuad!).isLandscape)
    }

    func testVisionBottomLeftCoordinatesAreFlippedBeforePreviewConversion() {
        let point = NationalIDPreviewTransform.captureDevicePoint(
            fromVisionPoint: CGPoint(x: 0.25, y: 0.75),
            visionOrientation: .up,
            videoOrientation: .portrait,
            isMirrored: false
        )

        XCTAssertEqual(point.x, 0.25, accuracy: 0.001)
        XCTAssertEqual(point.y, 0.25, accuracy: 0.001)
    }

    func testPreviewLayerMappingDoesNotApplyVisionRotationTwice() {
        let point = NationalIDPreviewTransform.previewLayerCaptureDevicePoint(
            fromVisionPoint: CGPoint(x: 0.25, y: 0.75),
            isMirrored: false
        )

        // The preview layer receives unrotated capture-device coordinates and
        // applies its portrait connection orientation exactly once.
        XCTAssertEqual(point.x, 0.25, accuracy: 0.001)
        XCTAssertEqual(point.y, 0.25, accuracy: 0.001)
    }

    func testMirroredPreviewOnlyFlipsHorizontalAxis() {
        let normal = NationalIDPreviewTransform.captureDevicePoint(
            fromVisionPoint: CGPoint(x: 0.20, y: 0.80),
            visionOrientation: .right,
            videoOrientation: .portrait,
            isMirrored: false
        )
        let mirrored = NationalIDPreviewTransform.captureDevicePoint(
            fromVisionPoint: CGPoint(x: 0.20, y: 0.80),
            visionOrientation: .right,
            videoOrientation: .portrait,
            isMirrored: true
        )

        XCTAssertEqual(mirrored.x, 1 - normal.x, accuracy: 0.001)
        XCTAssertEqual(mirrored.y, normal.y, accuracy: 0.001)
    }

    func testAllTransformedCornersAreReorderedBeforeEdgeMeasurement() {
        let points = [
            CGPoint(x: 160, y: 420),
            CGPoint(x: 160, y: 80),
            CGPoint(x: 760, y: 90),
            CGPoint(x: 760, y: 410)
        ]

        let quad = NationalIDPreviewTransform.orderedPreviewQuad(from: points)
        XCTAssertNotNil(quad)
        let metrics = NationalIDGeometry.metrics(for: quad!)
        XCTAssertGreaterThan(metrics.topEdge, metrics.leftEdge)
        XCTAssertTrue(metrics.isLandscape)
    }

    func testProcessorQuadReordersDownOrientedExpectedQuadForCoreImageCoordinates() {
        let expectedStillQuad = NationalIDQuad(
            topLeft: CGPoint(x: 0.25, y: 0.63),
            topRight: CGPoint(x: 0.75, y: 0.62),
            bottomRight: CGPoint(x: 0.76, y: 0.38),
            bottomLeft: CGPoint(x: 0.25, y: 0.40)
        )

        let processorQuad = NationalIDCropper.processorQuad(expectedStillQuad, from: .down)

        XCTAssertGreaterThan(processorQuad.topLeft.y, processorQuad.bottomLeft.y)
        XCTAssertGreaterThan(processorQuad.topRight.y, processorQuad.bottomRight.y)
        XCTAssertLessThan(processorQuad.topLeft.x, processorQuad.topRight.x)
        XCTAssertLessThan(processorQuad.bottomLeft.x, processorQuad.bottomRight.x)
        XCTAssertTrue(NationalIDGeometry.metrics(for: processorQuad).isLandscape)
    }

    private func normalizedQuad(
        topLeft: CGPoint,
        topRight: CGPoint,
        bottomRight: CGPoint,
        bottomLeft: CGPoint,
        imageSize: CGSize
    ) -> NationalIDQuad {
        NationalIDQuad(
            topLeft: normalize(topLeft, imageSize: imageSize),
            topRight: normalize(topRight, imageSize: imageSize),
            bottomRight: normalize(bottomRight, imageSize: imageSize),
            bottomLeft: normalize(bottomLeft, imageSize: imageSize)
        )
    }

    private func normalize(_ point: CGPoint, imageSize: CGSize) -> CGPoint {
        CGPoint(x: point.x / imageSize.width, y: point.y / imageSize.height)
    }
}
