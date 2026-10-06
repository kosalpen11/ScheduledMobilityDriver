//
//  NationalIDPreviewTransform.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/6/26.
//

import AVFoundation
import CoreGraphics
import ImageIO

enum NationalIDPreviewTransform {
    /// Undo Vision's `.right` orientation into the portrait video buffer,
    /// then apply the preview's centered aspect-fill scale and crop.
    static func portraitPreviewPoint(_ point: CGPoint, bufferSize: CGSize, bounds: CGRect) -> CGPoint {
        guard bufferSize.width > 0, bufferSize.height > 0 else { return .zero }
        let bufferPoint = CGPoint(x: 1 - point.y, y: 1 - point.x)
        let scale = max(bounds.width / bufferSize.width, bounds.height / bufferSize.height)
        return CGPoint(
            x: bounds.midX + (bufferPoint.x - 0.5) * bufferSize.width * scale,
            y: bounds.midY + (bufferPoint.y - 0.5) * bufferSize.height * scale
        )
    }

    /// Converts Vision bottom-left points to the unrotated capture-device
    /// space expected by `AVCaptureVideoPreviewLayer`.
    ///
    /// The preview layer applies its connection's video orientation and
    /// aspect-fill transform in `layerPointConverted`. Applying the Vision
    /// orientation here as well rotates the overlay twice.
    static func previewLayerCaptureDevicePoint(
        fromVisionPoint point: CGPoint,
        isMirrored: Bool
    ) -> CGPoint {
        let captureDevicePoint = CGPoint(x: point.x, y: 1 - point.y)
        guard isMirrored == false else {
            return CGPoint(x: 1 - captureDevicePoint.x, y: captureDevicePoint.y)
        }
        return captureDevicePoint
    }

    /// Converts Vision bottom-left normalized points into the normalized
    /// capture-device space consumed by AVCaptureVideoPreviewLayer.
    ///
    /// This orientation-aware conversion is retained for camera focus and
    /// exposure points, which are sent directly to AVCaptureDevice. Preview
    /// overlays must use `previewLayerCaptureDevicePoint` instead.
    static func captureDevicePoint(
        fromVisionPoint point: CGPoint,
        visionOrientation: CGImagePropertyOrientation,
        videoOrientation: AVCaptureVideoOrientation,
        isMirrored: Bool
    ) -> CGPoint {
        let topLeftOriented = CGPoint(x: point.x, y: 1 - point.y)
        let portraitPoint = rotateToPortraitCaptureSpace(
            topLeftOriented,
            visionOrientation: visionOrientation
        )
        let videoPoint = rotateFromPortraitCaptureSpace(
            portraitPoint,
            videoOrientation: videoOrientation
        )
        guard isMirrored == false else {
            return CGPoint(x: 1 - videoPoint.x, y: videoPoint.y)
        }
        return videoPoint
    }

    static func orderedPreviewQuad(from points: [CGPoint]) -> NationalIDQuad? {
        guard points.count == 4 else { return nil }
        let sortedByY = points.sorted { lhs, rhs in
            if abs(lhs.y - rhs.y) < 0.001 {
                return lhs.x < rhs.x
            }
            return lhs.y < rhs.y
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

    private static func rotateToPortraitCaptureSpace(
        _ point: CGPoint,
        visionOrientation: CGImagePropertyOrientation
    ) -> CGPoint {
        switch visionOrientation {
        case .right:
            return CGPoint(x: 1 - point.y, y: 1 - point.x)
        case .left:
            return CGPoint(x: point.y, y: 1 - point.x)
        case .down:
            return CGPoint(x: 1 - point.x, y: point.y)
        case .up:
            return point
        default:
            return point
        }
    }

    private static func rotateFromPortraitCaptureSpace(
        _ point: CGPoint,
        videoOrientation: AVCaptureVideoOrientation
    ) -> CGPoint {
        switch videoOrientation {
        case .portrait:
            return point
        case .portraitUpsideDown:
            return CGPoint(x: 1 - point.x, y: 1 - point.y)
        case .landscapeRight:
            return CGPoint(x: point.y, y: 1 - point.x)
        case .landscapeLeft:
            return CGPoint(x: 1 - point.y, y: point.x)
        @unknown default:
            return point
        }
    }
}
