//
//  NationalIDCropperTests.swift
//  ScheduledMobilityDriver
//

@testable import NationalIDCapture
import CoreGraphics
import XCTest

final class NationalIDCropperTests: XCTestCase {
    // MARK: - Margin

    func testCenteredCardGetsRequestedMargin() {
        let margin = NationalIDCropper.effectiveMargin(
            corners: rect(minX: 300, minY: 300, maxX: 700, maxY: 700),
            imageSize: CGSize(width: 1_000, height: 1_000),
            requested: 0.10
        )
        XCTAssertEqual(margin, 0.10, accuracy: 1e-9)
    }

    func testRequestedMarginIsClampedToMaximum() {
        let margin = NationalIDCropper.effectiveMargin(
            corners: rect(minX: 400, minY: 400, maxX: 600, maxY: 600),
            imageSize: CGSize(width: 1_000, height: 1_000),
            requested: 0.50
        )
        XCTAssertEqual(margin, NationalIDCropper.marginMaximumFraction, accuracy: 1e-9)
    }

    func testRequestedMarginIsClampedUpToMinimumWhenRoomAllows() {
        let margin = NationalIDCropper.effectiveMargin(
            corners: rect(minX: 300, minY: 300, maxX: 700, maxY: 700),
            imageSize: CGSize(width: 1_000, height: 1_000),
            requested: 0
        )
        XCTAssertEqual(margin, NationalIDCropper.marginMinimumFraction, accuracy: 1e-9)
    }

    func testCardNearEdgeReducesMarginToStayInsideImage() {
        // Corners are 20px from the edge, 480px from the centroid.
        let margin = NationalIDCropper.effectiveMargin(
            corners: rect(minX: 20, minY: 20, maxX: 980, maxY: 980),
            imageSize: CGSize(width: 1_000, height: 1_000),
            requested: 0.10
        )
        XCTAssertEqual(margin, 20.0 / 480.0, accuracy: 1e-9)
    }

    func testImageBoundsWinOverMinimumMargin() {
        // A card touching the frame edge must not be pushed outside the image,
        // even though that leaves less than the 2% minimum.
        let margin = NationalIDCropper.effectiveMargin(
            corners: rect(minX: 0, minY: 100, maxX: 1_000, maxY: 900),
            imageSize: CGSize(width: 1_000, height: 1_000),
            requested: 0.10
        )
        XCTAssertEqual(margin, 0, accuracy: 1e-9)
        XCTAssertLessThan(margin, NationalIDCropper.marginMinimumFraction)
    }

    func testNonSquareImageUsesPerAxisBounds() {
        // 100px of room horizontally (dx=400 -> 0.25), 25px vertically (dy=250 -> 0.10).
        let margin = NationalIDCropper.effectiveMargin(
            corners: rect(minX: 100, minY: 25, maxX: 900, maxY: 525),
            imageSize: CGSize(width: 1_000, height: 550),
            requested: 0.25
        )
        XCTAssertEqual(margin, 0.10, accuracy: 1e-9)
    }

    func testDefaultMarginIsWithinConfiguredBounds() {
        XCTAssertGreaterThanOrEqual(NationalIDCropper.marginDefaultFraction, NationalIDCropper.marginMinimumFraction)
        XCTAssertLessThanOrEqual(NationalIDCropper.marginDefaultFraction, NationalIDCropper.marginMaximumFraction)
    }

    // MARK: - Output contrast

    func testUniformImageHasNearZeroLumaDeviation() throws {
        let image = try XCTUnwrap(makeGrayImage(width: 512, height: 320) { _, _ in 128 })
        let deviation = try XCTUnwrap(NationalIDCropper.lumaStandardDeviation(of: image))
        XCTAssertLessThan(deviation, 1)
        XCTAssertLessThan(deviation, NationalIDCropper.minimumOutputLumaStandardDeviation)
    }

    func testHighContrastImagePassesLumaDeviationCheck() throws {
        let image = try XCTUnwrap(makeGrayImage(width: 512, height: 320) { x, _ in
            (x / 16) % 2 == 0 ? 20 : 235
        })
        let deviation = try XCTUnwrap(NationalIDCropper.lumaStandardDeviation(of: image))
        XCTAssertGreaterThan(deviation, 50)
    }

    func testCardLikeImageWithSmallTextPassesLumaDeviationCheck() throws {
        // Light background with thin dark "text" rows and a darker photo block.
        let image = try XCTUnwrap(makeGrayImage(width: 856, height: 540) { x, y in
            if x > 40, x < 260, y > 120, y < 420 { return 90 }
            if x > 320, y % 40 < 4, (x / 6) % 3 != 0 { return 40 }
            return 220
        })
        let deviation = try XCTUnwrap(NationalIDCropper.lumaStandardDeviation(of: image))
        XCTAssertGreaterThan(deviation, NationalIDCropper.minimumOutputLumaStandardDeviation * 3)
    }

    // MARK: - Shared Vision config

    func testRectangleRequestUsesSharedConfiguration() {
        let request = NIDRectangleDetectionConfig.makeRequest()
        XCTAssertEqual(request.minimumConfidence, NIDRectangleDetectionConfig.minimumConfidence)
        XCTAssertEqual(request.minimumAspectRatio, NIDRectangleDetectionConfig.minimumAspectRatio)
        XCTAssertEqual(request.maximumAspectRatio, NIDRectangleDetectionConfig.maximumAspectRatio)
        XCTAssertEqual(request.minimumSize, NIDRectangleDetectionConfig.minimumSize)
        XCTAssertEqual(request.quadratureTolerance, NIDRectangleDetectionConfig.quadratureToleranceDegrees)
        XCTAssertEqual(request.maximumObservations, NIDRectangleDetectionConfig.maximumObservations)
    }

    func testRectangleAspectRangeAdmitsIDCardAspect() {
        let range = CGFloat(NIDRectangleDetectionConfig.minimumAspectRatio)...CGFloat(NIDRectangleDetectionConfig.maximumAspectRatio)
        XCTAssertTrue(range.contains(NationalIDGeometry.targetAspect))
    }

    // MARK: - Helpers

    private func rect(minX: CGFloat, minY: CGFloat, maxX: CGFloat, maxY: CGFloat) -> [CGPoint] {
        [
            CGPoint(x: minX, y: minY),
            CGPoint(x: maxX, y: minY),
            CGPoint(x: maxX, y: maxY),
            CGPoint(x: minX, y: maxY)
        ]
    }

    private func makeGrayImage(width: Int, height: Int, value: (Int, Int) -> UInt8) -> CGImage? {
        var pixels = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                pixels[y * width + x] = value(x, y)
            }
        }
        return pixels.withUnsafeMutableBytes { raw -> CGImage? in
            CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            )?.makeImage()
        }
    }
}
