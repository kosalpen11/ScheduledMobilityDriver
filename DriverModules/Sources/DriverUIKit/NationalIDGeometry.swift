//
//  NationalIDGeometry.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/5/26.
//

import CoreGraphics

struct NationalIDQuad: Equatable {
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomRight: CGPoint
    let bottomLeft: CGPoint

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

    func maxDistance(to other: NationalIDQuad) -> CGFloat {
        zip(corners, other.corners)
            .map { hypot($0.x - $1.x, $0.y - $1.y) }
            .max() ?? 0
    }

    func contains(_ point: CGPoint) -> Bool {
        let pts = corners
        var previousSign: CGFloat?
        for index in 0..<pts.count {
            let a = pts[index]
            let b = pts[(index + 1) % pts.count]
            let cross = (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x)
            guard abs(cross) > .ulpOfOne else { continue }
            let sign = cross.sign == .minus ? CGFloat(-1) : CGFloat(1)
            if let previousSign, sign != previousSign {
                return false
            }
            previousSign = sign
        }
        return true
    }

    func iou(with other: NationalIDQuad) -> CGFloat {
        let a = boundingBox
        let b = other.boundingBox
        guard !a.isNull, !b.isNull else { return 0 }
        let intersection = a.intersection(b)
        let intersectionArea = intersection.isNull ? 0 : intersection.width * intersection.height
        let union = a.width * a.height + b.width * b.height - intersectionArea
        return union > 0 ? intersectionArea / union : 0
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
