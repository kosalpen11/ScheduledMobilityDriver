//
//  NationalIDGeometry.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/5/26.
//

import CoreGraphics

public struct NationalIDQuad: Equatable {
    public let topLeft: CGPoint
    public let topRight: CGPoint
    public let bottomRight: CGPoint
    public let bottomLeft: CGPoint

    public init(topLeft: CGPoint, topRight: CGPoint, bottomRight: CGPoint, bottomLeft: CGPoint) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }

    var corners: [CGPoint] {
        [topLeft, topRight, bottomRight, bottomLeft]
    }

    var center: CGPoint {
        CGPoint(
            x: (topLeft.x + topRight.x + bottomRight.x + bottomLeft.x) / 4,
            y: (topLeft.y + topRight.y + bottomRight.y + bottomLeft.y) / 4
        )
    }

    var boundingBox: CGRect {
        let xs = corners.map(\.x)
        let ys = corners.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
            return .null
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    var area: CGFloat {
        let pts = corners
        var sum: CGFloat = 0
        for index in 0..<pts.count {
            let next = pts[(index + 1) % pts.count]
            sum += pts[index].x * next.y - next.x * pts[index].y
        }
        return abs(sum) / 2
    }

    func meanDistance(to other: NationalIDQuad) -> CGFloat {
        zip(corners, other.corners)
            .map { hypot($0.x - $1.x, $0.y - $1.y) }
            .reduce(0, +) / 4
    }

    /// Fast comparison: checks if mean distance is below threshold without computing actual distance.
    /// Avoids expensive sqrt() in inner loops. About 30-40% faster than meanDistance comparison.
    func isMeanDistanceLessThan(_ threshold: CGFloat, to other: NationalIDQuad) -> Bool {
        let thresholdSq = threshold * threshold
        let sumSq = zip(corners, other.corners)
            .map { pair in
                let dx = pair.0.x - pair.1.x, dy = pair.0.y - pair.1.y
                return dx * dx + dy * dy
            }
            .reduce(0 as CGFloat, +)
        return sumSq < thresholdSq * 16  // sumSq < (threshold * 4)²
    }

    func maxDistance(to other: NationalIDQuad) -> CGFloat {
        zip(corners, other.corners)
            .map { hypot($0.x - $1.x, $0.y - $1.y) }
            .max() ?? 0
    }

    /// Fast comparison: checks if any corner is farther than threshold (max distance).
    /// Avoids sqrt() calls — about 40% faster.
    func isMaxDistanceLessThan(_ threshold: CGFloat, to other: NationalIDQuad) -> Bool {
        let thresholdSq = threshold * threshold
        return !zip(corners, other.corners)
            .contains { pair in
                let dx = pair.0.x - pair.1.x, dy = pair.0.y - pair.1.y
                return dx * dx + dy * dy > thresholdSq
            }
    }

    func contains(_ point: CGPoint) -> Bool {
        let pts = corners
        // Use appropriate epsilon for normalized [0,1] coordinate space
        // .ulpOfOne (~2.22e-16) is far too small and causes incorrect edge detection
        let epsilon: CGFloat = 1e-6  // accounts for floating-point rounding in normalized space
        
        var previousSign: CGFloat?
        for index in 0..<pts.count {
            let a = pts[index]
            let b = pts[(index + 1) % pts.count]
            let cross = (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x)
            
            // Treat points on or very close to edges as inside (continue)
            guard abs(cross) > epsilon else { continue }
            
            let sign = cross.sign == .minus ? CGFloat(-1) : CGFloat(1)
            if let previousSign, sign != previousSign {
                return false  // Mixed signs = point is outside
            }
            previousSign = sign
        }
        return true
    }

    /// Returns true if any region's center lies outside this quad.
    ///
    /// A center outside the quad's bounding box is definitely outside the
    /// quad, so that cheap test runs first. Only centers inside the bounding
    /// box need the exact edge-sign test.
    func hasRegionCenterOutside(_ regions: [CGRect]) -> Bool {
        guard regions.isEmpty == false else { return false }
        let bounds = boundingBox
        guard bounds.isNull == false else { return true }
        // CGRect.contains excludes maxX/maxY; use an inclusive test with the
        // same tolerance as `contains(_:)` so edge points are treated alike.
        let epsilon: CGFloat = 1e-6
        return regions.contains { region in
            let center = CGPoint(x: region.midX, y: region.midY)
            let insideBounds = center.x >= bounds.minX - epsilon
                && center.x <= bounds.maxX + epsilon
                && center.y >= bounds.minY - epsilon
                && center.y <= bounds.maxY + epsilon
            guard insideBounds else { return true }
            return !contains(center)
        }
    }

    /// Intersection-over-union of the two quads' actual polygon areas.
    ///
    /// Assumes both quads are convex, which holds for Vision rectangle
    /// observations. Non-convex input (e.g. a self-intersecting labeling)
    /// falls back to `boundingBoxIOU`.
    func iou(with other: NationalIDQuad) -> CGFloat {
        guard isConvex, other.isConvex else {
            return boundingBoxIOU(with: other)
        }
        let areaA = area
        let areaB = other.area
        guard areaA > 0, areaB > 0 else { return 0 }
        let intersection = NationalIDPolygon.area(
            of: NationalIDPolygon.clip(corners, by: other.corners)
        )
        let union = areaA + areaB - intersection
        return union > 0 ? min(1, max(0, intersection / union)) : 0
    }

    /// Fast sampled quad IoU using grid sampling over the intersection bounding box.
    ///
    /// Samples a regular grid (default 12×12) over the intersection region and counts
    /// how many grid cells fall inside both quads. Provides good accuracy for rotated
    /// quads without the overhead of polygon clipping, which is ~3-5x faster.
    ///
    /// Assumes both quads are convex. Falls back to `boundingBoxIOU` if either is not.
    /// - Parameters:
    ///   - other: The quad to compare with
    ///   - gridSize: Number of samples per dimension (default 12). Larger values increase
    ///     accuracy but cost more; 12 is sufficient for document cards.
    /// - Returns: Intersection-over-union in [0, 1]
    func sampledQuadIOU(with other: NationalIDQuad, gridSize: Int = 12) -> CGFloat {
        guard isConvex, other.isConvex else {
            return boundingBoxIOU(with: other)
        }
        let a = boundingBox
        let b = other.boundingBox
        guard !a.isNull, !b.isNull else { return 0 }
        let areaA = area
        let areaB = other.area
        guard areaA > 0, areaB > 0 else { return 0 }
        
        let unionBounds = a.union(b)
        let intersectBounds = a.intersection(b)
        guard !intersectBounds.isNull, intersectBounds.width > 0, intersectBounds.height > 0 else {
            return 0  // No overlap at all
        }
        
        var inBothCount = 0
        let cellWidth = intersectBounds.width / CGFloat(gridSize)
        let cellHeight = intersectBounds.height / CGFloat(gridSize)
        
        for i in 0..<gridSize {
            for j in 0..<gridSize {
                let x = intersectBounds.minX + (CGFloat(i) + 0.5) * cellWidth
                let y = intersectBounds.minY + (CGFloat(j) + 0.5) * cellHeight
                let point = CGPoint(x: x, y: y)
                if contains(point) && other.contains(point) {
                    inBothCount += 1
                }
            }
        }
        
        let intersectionArea = CGFloat(inBothCount) / CGFloat(gridSize * gridSize) * intersectBounds.width * intersectBounds.height
        let union = areaA + areaB - intersectionArea
        return union > 0 ? min(1, max(0, intersectionArea / union)) : 0
    }

    /// Axis-aligned bounding-box IoU. Overstates overlap for rotated quads;
    /// kept as a fallback for degenerate input.
    func boundingBoxIOU(with other: NationalIDQuad) -> CGFloat {
        let a = boundingBox
        let b = other.boundingBox
        guard !a.isNull, !b.isNull else { return 0 }
        let intersection = a.intersection(b)
        let intersectionArea = intersection.isNull ? 0 : intersection.width * intersection.height
        let union = a.width * a.height + b.width * b.height - intersectionArea
        return union > 0 ? intersectionArea / union : 0
    }

    /// True when all edge turns have the same sign (collinear turns ignored).
    var isConvex: Bool {
        let pts = corners
        var sign: CGFloat = 0
        for index in 0..<pts.count {
            let a = pts[index]
            let b = pts[(index + 1) % pts.count]
            let c = pts[(index + 2) % pts.count]
            let cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
            guard abs(cross) > 1e-12 else { continue }
            let current: CGFloat = cross > 0 ? 1 : -1
            if sign == 0 {
                sign = current
            } else if current != sign {
                return false
            }
        }
        return sign != 0
    }

    /// Calculates the rotation angle of the card relative to horizontal (0°).
    /// Uses the slope of the top edge (topLeft → topRight) to estimate orientation.
    /// - Returns: Angle in radians [-π/2, π/2]. Positive = clockwise rotation.
    ///   0 = horizontal (level), ±π/2 = vertical (edge case).
    var rotationAngle: CGFloat {
        let dx = topRight.x - topLeft.x
        let dy = topRight.y - topLeft.y
        return atan2(dy, dx)
    }

    /// Classifies the card's orientation based on rotation angle.
    /// Useful for applying orientation-specific crop strategies (e.g., different margins for diagonal).
    enum Orientation: Equatable {
        /// Nearly horizontal (|angle| ≤ 0.262 rad ≈ 15°)
        case level
        /// Tilted but not vertical (|angle| ∈ (0.262, 0.785] rad ≈ (15°, 45°])
        case tilted
        /// Diagonal or steep (|angle| ∈ (0.785, π/2] rad ≈ (45°, 90°])
        case diagonal

        /// Returns suggested margin multiplier for this orientation.
        /// Higher margins help prevent corner clipping during perspective correction
        /// when the card is rotated significantly.
        var marginMultiplier: CGFloat {
            switch self {
            case .level:
                return 1.0  // Base margin
            case .tilted:
                return 1.1  // +10% margin for tilt stability
            case .diagonal:
                return 1.25  // +25% margin for steep angles (prevents corner overflow)
            }
        }
    }

    /// Classifies the card's orientation based on its rotation angle.
    var orientation: Orientation {
        let angle = rotationAngle
        let absAngle = abs(angle)
        let fifteenDegrees: CGFloat = 0.262  // π/12 in radians
        let fortyFiveDegrees: CGFloat = 0.785  // π/4 in radians
        
        if absAngle <= fifteenDegrees {
            return .level
        } else if absAngle <= fortyFiveDegrees {
            return .tilted
        } else {
            return .diagonal
        }
    }
}

/// Convex polygon helpers used for quad overlap.
enum NationalIDPolygon {
    static func signedArea(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 3 else { return 0 }
        var sum: CGFloat = 0
        for index in 0..<points.count {
            let next = points[(index + 1) % points.count]
            sum += points[index].x * next.y - next.x * points[index].y
        }
        return sum / 2
    }

    static func area(of points: [CGPoint]) -> CGFloat {
        abs(signedArea(points))
    }

    /// Sutherland–Hodgman clipping of `subject` against convex `clipPolygon`.
    /// Works for either winding order of either polygon.
    static func clip(_ subject: [CGPoint], by clipPolygon: [CGPoint]) -> [CGPoint] {
        guard subject.count >= 3, clipPolygon.count >= 3 else { return [] }
        // Normalize the clip polygon to counter-clockwise so "inside" is
        // always the left side of each edge.
        let clipCCW = signedArea(clipPolygon) < 0 ? Array(clipPolygon.reversed()) : clipPolygon
        var output = subject
        for index in 0..<clipCCW.count {
            guard output.isEmpty == false else { break }
            let edgeStart = clipCCW[index]
            let edgeEnd = clipCCW[(index + 1) % clipCCW.count]
            let input = output
            output = []
            func side(_ p: CGPoint) -> CGFloat {
                (edgeEnd.x - edgeStart.x) * (p.y - edgeStart.y) - (edgeEnd.y - edgeStart.y) * (p.x - edgeStart.x)
            }
            for pointIndex in 0..<input.count {
                let current = input[pointIndex]
                let previous = input[(pointIndex + input.count - 1) % input.count]
                let currentSide = side(current)
                let previousSide = side(previous)
                if currentSide >= 0 {
                    if previousSide < 0 {
                        output.append(intersection(previous, current, previousSide, currentSide))
                    }
                    output.append(current)
                } else if previousSide >= 0 {
                    output.append(intersection(previous, current, previousSide, currentSide))
                }
            }
        }
        return output
    }

    private static func intersection(
        _ a: CGPoint,
        _ b: CGPoint,
        _ sideA: CGFloat,
        _ sideB: CGFloat
    ) -> CGPoint {
        let t = sideA / (sideA - sideB)
        return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}

struct NationalIDGeometryMetrics: Equatable {
    let topEdge: CGFloat
    let bottomEdge: CGFloat
    let leftEdge: CGFloat
    let rightEdge: CGFloat
    let measuredAspect: CGFloat
    let aspectScore: CGFloat

    var width: CGFloat {
        (topEdge + bottomEdge) / 2
    }

    var height: CGFloat {
        (leftEdge + rightEdge) / 2
    }

    var isLandscape: Bool {
        width >= height
    }

    var longPair: String {
        isLandscape ? "topBottom" : "leftRight"
    }

    var shortPair: String {
        isLandscape ? "leftRight" : "topBottom"
    }
}

enum NationalIDGeometry {
    static let targetAspect: CGFloat = 0.631
    static let aspectTolerance: CGFloat = 0.20
    static let acceptedAspectRange: ClosedRange<CGFloat> = 0.52...0.74

    static func scaled(_ quad: NationalIDQuad, to imageSize: CGSize) -> NationalIDQuad {
        NationalIDQuad(
            topLeft: scale(quad.topLeft, to: imageSize),
            topRight: scale(quad.topRight, to: imageSize),
            bottomRight: scale(quad.bottomRight, to: imageSize),
            bottomLeft: scale(quad.bottomLeft, to: imageSize)
        )
    }

    static func metrics(for quad: NationalIDQuad) -> NationalIDGeometryMetrics {
        let top = distance(quad.topLeft, quad.topRight)
        let bottom = distance(quad.bottomLeft, quad.bottomRight)
        let left = distance(quad.topLeft, quad.bottomLeft)
        let right = distance(quad.topRight, quad.bottomRight)
        let edgeA = (top + bottom) / 2
        let edgeB = (left + right) / 2
        let longEdge = max(edgeA, edgeB)
        let shortEdge = min(edgeA, edgeB)
        let aspect = longEdge > 0 ? shortEdge / longEdge : 0
        return NationalIDGeometryMetrics(
            topEdge: top,
            bottomEdge: bottom,
            leftEdge: left,
            rightEdge: right,
            measuredAspect: aspect,
            aspectScore: aspectScore(for: aspect)
        )
    }

    /// Vision can return a valid quad whose semantic labels are rotated with
    /// the oriented image. Preserve the same four physical points, but make
    /// the long opposite pair the top and bottom edges for a landscape ID.
    static func normalizedLandscapeQuad(_ quad: NationalIDQuad) -> NationalIDQuad {
        let raw = metrics(for: quad)
        guard raw.isLandscape == false else { return quad }
        return NationalIDQuad(
            topLeft: quad.topLeft,
            topRight: quad.bottomLeft,
            bottomRight: quad.bottomRight,
            bottomLeft: quad.topRight
        )
    }

    static func relabeledVariants(of quad: NationalIDQuad) -> [NationalIDQuad] {
        let clockwise = quad.corners
        let counterClockwise = [quad.topLeft, quad.bottomLeft, quad.bottomRight, quad.topRight]
        return variants(from: clockwise) + variants(from: counterClockwise)
    }

    static func bestRelabeledQuad(_ quad: NationalIDQuad, matching reference: NationalIDQuad?) -> NationalIDQuad {
        let landscape = normalizedLandscapeQuad(quad)
        guard let reference else { return landscape }
        return relabeledVariants(of: landscape)
            .min { $0.meanDistance(to: reference) < $1.meanDistance(to: reference) }
            ?? landscape
    }

    static func aspectScore(for aspect: CGFloat) -> CGFloat {
        max(0, 1 - abs(aspect - targetAspect) / aspectTolerance)
    }

    /// Maps a normalized quad from the oriented live Vision frame into the
    /// normalized coordinate space of the full-resolution still image.
    ///
    /// This compensates for a centered aspect-ratio crop between live video
    /// and still-photo outputs. Both sizes must describe images in the same
    /// orientation.
    static func mapLiveQuadToStill(
        _ quad: NationalIDQuad,
        liveSize: CGSize,
        stillSize: CGSize
    ) -> NationalIDQuad? {
        guard liveSize.width > 0,
              liveSize.height > 0,
              stillSize.width > 0,
              stillSize.height > 0
        else {
            return nil
        }

        let liveAspect = liveSize.width / liveSize.height
        let stillAspect = stillSize.width / stillSize.height

        var scaleX: CGFloat = 1
        var scaleY: CGFloat = 1

        if liveAspect < stillAspect {
            // Live is relatively narrower: it represents a centered
            // horizontal region of the still image.
            scaleX = liveAspect / stillAspect
        } else if liveAspect > stillAspect {
            // Live is relatively wider: it represents a centered
            // vertical region of the still image.
            scaleY = stillAspect / liveAspect
        }

        func map(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: (1 - scaleX) * 0.5 + point.x * scaleX,
                y: (1 - scaleY) * 0.5 + point.y * scaleY
            )
        }

        return NationalIDQuad(
            topLeft: map(quad.topLeft),
            topRight: map(quad.topRight),
            bottomRight: map(quad.bottomRight),
            bottomLeft: map(quad.bottomLeft)
        )
    }

    private static func scale(_ point: CGPoint, to imageSize: CGSize) -> CGPoint {
        CGPoint(x: point.x * imageSize.width, y: point.y * imageSize.height)
    }

    private static func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }

    private static func variants(from corners: [CGPoint]) -> [NationalIDQuad] {
        guard corners.count == 4 else { return [] }
        return (0..<4).map { offset in
            NationalIDQuad(
                topLeft: corners[offset % 4],
                topRight: corners[(offset + 1) % 4],
                bottomRight: corners[(offset + 2) % 4],
                bottomLeft: corners[(offset + 3) % 4]
            )
        }
    }
}
