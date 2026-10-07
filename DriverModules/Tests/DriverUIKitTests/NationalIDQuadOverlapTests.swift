//
//  NationalIDQuadOverlapTests.swift
//  ScheduledMobilityDriver
//

@testable import NationalIDCapture
import CoreGraphics
import XCTest

final class NationalIDQuadOverlapTests: XCTestCase {
    // MARK: - contains(_:) edge cases

    func testPointExactlyOnEdgeIsInside() {
        XCTAssertTrue(unitSquare.contains(CGPoint(x: 0.5, y: 0)))
        XCTAssertTrue(unitSquare.contains(CGPoint(x: 1, y: 0.5)))
    }

    func testCornerPointIsInside() {
        XCTAssertTrue(unitSquare.contains(CGPoint(x: 1, y: 1)))
        XCTAssertTrue(unitSquare.contains(CGPoint(x: 0, y: 0)))
    }

    func testPointJustOutsideEdgeIsOutside() {
        XCTAssertFalse(unitSquare.contains(CGPoint(x: 0.5, y: -0.001)))
        XCTAssertFalse(unitSquare.contains(CGPoint(x: 1.001, y: 0.5)))
    }

    func testContainsIsWindingIndependent() {
        let reversed = NationalIDQuad(
            topLeft: unitSquare.topLeft,
            topRight: unitSquare.bottomLeft,
            bottomRight: unitSquare.bottomRight,
            bottomLeft: unitSquare.topRight
        )
        for point in [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.5, y: 0), CGPoint(x: 1.2, y: 0.5)] {
            XCTAssertEqual(unitSquare.contains(point), reversed.contains(point), "point=\(point)")
        }
    }

    // MARK: - Polygon IoU

    func testIdenticalQuadsHaveIOUOfOne() {
        XCTAssertEqual(unitSquare.iou(with: unitSquare), 1, accuracy: 1e-9)
    }

    func testDisjointQuadsHaveIOUOfZero() {
        let far = square(minX: 2, minY: 2, size: 1)
        XCTAssertEqual(unitSquare.iou(with: far), 0, accuracy: 1e-9)
    }

    func testAxisAlignedPartialOverlapMatchesExactArea() {
        // Half of each square overlaps: 0.5 / (1 + 1 - 0.5) = 1/3.
        let shifted = square(minX: 0.5, minY: 0, size: 1)
        XCTAssertEqual(unitSquare.iou(with: shifted), 1.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(unitSquare.boundingBoxIOU(with: shifted), 1.0 / 3.0, accuracy: 1e-9)
    }

    func testRotatedQuadIOUIsNotOverstatedByBoundingBox() {
        // A diamond inscribed in the unit square covers exactly half of it.
        // Bounding-box IoU reports a perfect match; polygon IoU must not.
        XCTAssertEqual(unitSquare.boundingBoxIOU(with: diamond), 1, accuracy: 1e-9)
        XCTAssertEqual(unitSquare.iou(with: diamond), 0.5, accuracy: 1e-9)
        XCTAssertEqual(diamond.iou(with: unitSquare), 0.5, accuracy: 1e-9)
    }

    func testIOUIsIndependentOfCornerLabeling() {
        let shifted = square(minX: 0.25, minY: 0.25, size: 1)
        let expected = unitSquare.iou(with: shifted)
        for variant in NationalIDGeometry.relabeledVariants(of: shifted) {
            XCTAssertEqual(unitSquare.iou(with: variant), expected, accuracy: 1e-9)
        }
    }

    func testSkewedVisionLikeQuadsProduceIOUBetweenZeroAndOne() {
        let a = NationalIDQuad(
            topLeft: CGPoint(x: 0.20, y: 0.70),
            topRight: CGPoint(x: 0.80, y: 0.72),
            bottomRight: CGPoint(x: 0.78, y: 0.32),
            bottomLeft: CGPoint(x: 0.22, y: 0.30)
        )
        let b = NationalIDQuad(
            topLeft: CGPoint(x: 0.22, y: 0.71),
            topRight: CGPoint(x: 0.81, y: 0.70),
            bottomRight: CGPoint(x: 0.79, y: 0.31),
            bottomLeft: CGPoint(x: 0.21, y: 0.31)
        )
        let iou = a.iou(with: b)
        XCTAssertGreaterThan(iou, 0.9)
        XCTAssertLessThan(iou, 1)
        XCTAssertLessThanOrEqual(iou, a.boundingBoxIOU(with: b) + 1e-9)
    }

    func testSelfIntersectingQuadFallsBackToBoundingBoxIOU() {
        let bowtie = NationalIDQuad(
            topLeft: CGPoint(x: 0, y: 0),
            topRight: CGPoint(x: 1, y: 1),
            bottomRight: CGPoint(x: 1, y: 0),
            bottomLeft: CGPoint(x: 0, y: 1)
        )
        XCTAssertFalse(bowtie.isConvex)
        XCTAssertEqual(unitSquare.iou(with: bowtie), unitSquare.boundingBoxIOU(with: bowtie), accuracy: 1e-9)
    }

    func testDegenerateCollinearQuadIsNotConvexAndHasZeroOverlap() {
        let line = NationalIDQuad(
            topLeft: CGPoint(x: 0, y: 0),
            topRight: CGPoint(x: 0.5, y: 0),
            bottomRight: CGPoint(x: 1, y: 0),
            bottomLeft: CGPoint(x: 0.25, y: 0)
        )
        XCTAssertFalse(line.isConvex)
        XCTAssertEqual(line.area, 0, accuracy: 1e-12)
    }

    // MARK: - Text region containment

    func testNoRegionsMeansNothingOutside() {
        XCTAssertFalse(unitSquare.hasRegionCenterOutside([]))
    }

    func testRegionsInsideQuadAreNotOutside() {
        let regions = [
            CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.05),
            CGRect(x: 0.5, y: 0.6, width: 0.3, height: 0.05)
        ]
        XCTAssertFalse(unitSquare.hasRegionCenterOutside(regions))
    }

    func testRegionOutsideBoundingBoxIsOutside() {
        let regions = [
            CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.05),
            CGRect(x: 1.5, y: 0.5, width: 0.2, height: 0.05)
        ]
        XCTAssertTrue(unitSquare.hasRegionCenterOutside(regions))
    }

    func testRegionInsideBoundingBoxButOutsideRotatedQuadIsOutside() {
        // (0.1, 0.1) is inside the diamond's bounding box but outside the diamond.
        let region = CGRect(x: 0.05, y: 0.05, width: 0.1, height: 0.1)
        XCTAssertTrue(diamond.hasRegionCenterOutside([region]))
    }

    func testRegionCenteredOnBoundingBoxMaxEdgeMatchesContains() {
        // CGRect.contains would exclude maxX; containment must stay inclusive.
        let region = CGRect(x: 0.95, y: 0.45, width: 0.1, height: 0.1)
        XCTAssertTrue(unitSquare.contains(CGPoint(x: region.midX, y: region.midY)))
        XCTAssertFalse(unitSquare.hasRegionCenterOutside([region]))
    }

    func testRegionContainmentMatchesExactPolygonTest() {
        let quad = NationalIDQuad(
            topLeft: CGPoint(x: 0.20, y: 0.70),
            topRight: CGPoint(x: 0.80, y: 0.75),
            bottomRight: CGPoint(x: 0.85, y: 0.30),
            bottomLeft: CGPoint(x: 0.15, y: 0.28)
        )
        var generator = SplitMix64(seed: 42)
        for _ in 0..<500 {
            let center = CGPoint(x: generator.nextUnit(), y: generator.nextUnit())
            let region = CGRect(x: center.x - 0.01, y: center.y - 0.01, width: 0.02, height: 0.02)
            XCTAssertEqual(
                quad.hasRegionCenterOutside([region]),
                !quad.contains(CGPoint(x: region.midX, y: region.midY)),
                "center=\(center)"
            )
        }
    }

    // MARK: - Fixtures

    private var unitSquare: NationalIDQuad { square(minX: 0, minY: 0, size: 1) }

    private var diamond: NationalIDQuad {
        NationalIDQuad(
            topLeft: CGPoint(x: 0.5, y: 0),
            topRight: CGPoint(x: 1, y: 0.5),
            bottomRight: CGPoint(x: 0.5, y: 1),
            bottomLeft: CGPoint(x: 0, y: 0.5)
        )
    }

    private func square(minX: CGFloat, minY: CGFloat, size: CGFloat) -> NationalIDQuad {
        NationalIDQuad(
            topLeft: CGPoint(x: minX, y: minY),
            topRight: CGPoint(x: minX + size, y: minY),
            bottomRight: CGPoint(x: minX + size, y: minY + size),
            bottomLeft: CGPoint(x: minX, y: minY + size)
        )
    }
}

/// Deterministic generator so property-style tests are reproducible.
private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func nextUnit() -> CGFloat {
        CGFloat(Double(next() >> 11) / Double(1 << 53))
    }
}
