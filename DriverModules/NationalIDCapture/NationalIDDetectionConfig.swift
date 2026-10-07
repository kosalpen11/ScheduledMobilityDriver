//
//  NationalIDDetectionConfig.swift
//  ScheduledMobilityDriver
//

import CoreGraphics
import Foundation
import os
import Vision

/// Shared Vision rectangle-detection parameters.
///
/// The live tracker and the still-image cropper must agree on what counts as a
/// card-shaped rectangle; otherwise a frame can be "ready" live and then fail
/// to crop. Keep a single source of truth here.
enum NIDRectangleDetectionConfig {
    /// Minimum Vision observation confidence (0...1).
    static let minimumConfidence: VNConfidence = 0.50
    /// Short/long side ratio bounds. ID-1 cards are 0.631; the range is wide
    /// enough to admit perspective-skewed cards before our own geometry checks.
    static let minimumAspectRatio: VNAspectRatio = 0.46
    static let maximumAspectRatio: VNAspectRatio = 0.80
    /// Minimum rectangle size as a fraction of the smaller image dimension.
    static let minimumSize: Float = 0.12
    /// Maximum deviation from 90° for each corner angle, in degrees.
    static let quadratureToleranceDegrees: VNDegrees = 22
    static let maximumObservations = 3

    static func makeRequest() -> VNDetectRectanglesRequest {
        let request = VNDetectRectanglesRequest()
        request.minimumConfidence = minimumConfidence
        request.minimumAspectRatio = minimumAspectRatio
        request.maximumAspectRatio = maximumAspectRatio
        request.minimumSize = minimumSize
        request.quadratureTolerance = quadratureToleranceDegrees
        request.maximumObservations = maximumObservations
        return request
    }
}

/// Live-frame boundary continuity gates (normalized coordinates).
enum NIDContinuityConfig {
    /// Max mean corner displacement from the previous boundary.
    static let maximumMeanDistance: CGFloat = 0.22
    /// Min polygon IoU with the previous boundary.
    static let minimumIOU: CGFloat = 0.35
    /// Allowed area ratio (current / previous).
    static let areaRatioRange: ClosedRange<CGFloat> = 0.55...1.8
    /// Mean distance at which the continuity score reaches zero.
    static let scoreFalloffDistance: CGFloat = 0.20
}

/// OCR confirmation and failure backoff.
enum NIDOCRConfig {
    /// Text regions whose centers must fall inside the boundary to confirm a document.
    static let minimumRegionsInside = 2
    /// Minimum text height as a fraction of image height.
    static let minimumTextHeight: Float = 0.010
    /// First backoff interval after a failed OCR pass.
    static let backoffBaseInterval: TimeInterval = 0.5
    static let backoffMaximumInterval: TimeInterval = 2.0
    /// Consecutive failures before OCR is paused entirely.
    static let failuresBeforeDisable = 5
    static let disableDuration: TimeInterval = 3.0

    /// Exponential backoff: 0.5s, 1.0s, 2.0s, then capped.
    static func backoffInterval(consecutiveFailures: Int) -> TimeInterval {
        let exponent = Double(max(0, consecutiveFailures - 1))
        return min(backoffMaximumInterval, backoffBaseInterval * pow(2.0, exponent))
    }
}

/// Structured debug logging for NID capture.
///
/// Uses `os.Logger` so messages carry a subsystem/category (filterable in
/// Console.app and Xcode) and cost almost nothing when not being streamed.
/// Message bodies keep the existing `[NID][TAG] key=value` format so existing
/// grep-based debugging workflows keep working.
enum NIDLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "ScheduledMobilityDriver"

    static let tracking = Logger(subsystem: subsystem, category: "NID.tracking")
    static let ocr = Logger(subsystem: subsystem, category: "NID.ocr")
    static let motion = Logger(subsystem: subsystem, category: "NID.motion")
    static let crop = Logger(subsystem: subsystem, category: "NID.crop")

    /// Debug-level message. Compiled out of release builds.
    static func debug(_ logger: Logger, _ message: @autoclosure () -> String) {
        #if DEBUG
        let text = message()
        logger.debug("\(text, privacy: .public)")
        #endif
    }

    /// Error-level message. Kept in release builds; contains no user data.
    static func error(_ logger: Logger, _ message: @autoclosure () -> String) {
        let text = message()
        logger.error("\(text, privacy: .public)")
    }
}
