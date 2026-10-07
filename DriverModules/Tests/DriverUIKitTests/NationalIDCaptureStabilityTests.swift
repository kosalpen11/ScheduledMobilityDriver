//
//  NationalIDCaptureStabilityTests.swift
//  ScheduledMobilityDriver
//

@testable import NationalIDCapture
import CoreGraphics
import XCTest

final class NationalIDCaptureStabilityTests: XCTestCase {
    func testDocumentMotionIgnoresUniformExposureOffset() {
        let previous = [UInt8](repeating: 80, count: 12)
        let current = [UInt8](repeating: 95, count: 12)

        XCTAssertEqual(NIDMotionMetrics.documentMotion(previous, current), 0, accuracy: 0.001)
    }

    func testDocumentMotionDetectsSpatialMovementAfterExposureCompensation() {
        let previous = [UInt8](repeating: 80, count: 12)
        let current: [UInt8] = [95, 95, 95, 95, 65, 65, 95, 95, 95, 95, 95, 95]

        XCTAssertGreaterThan(NIDMotionMetrics.documentMotion(previous, current), 5)
    }

    func testMedian3UsesMiddleValueAfterWarmup() {
        XCTAssertEqual(NIDMotionMetrics.median3(2, nil, nil), 2)
        XCTAssertEqual(NIDMotionMetrics.median3(2, 8, nil), 8)
        XCTAssertEqual(NIDMotionMetrics.median3(30, 4, 5), 5)
    }

    func testFrameGapResetClearsHold() {
        let stability = NationalIDCaptureStability()
        addCleanSample(stability, now: 1.0)
        addCleanSample(stability, now: 1.1)
        XCTAssertGreaterThan(stability.frames, 0)

        addCleanSample(stability, now: 1.7)

        XCTAssertEqual(stability.blocker, .frameGap)
        XCTAssertEqual(stability.frames, 0)
    }

    func testCornerStepFailureBlocksHold() {
        let stability = NationalIDCaptureStability()
        addCleanSample(stability, now: 1.0)
        stability.add(now: 1.1, eligibilityBlocker: nil, motion: 0, cornerStep: 0.05, boundary: quad(), pixels: pixels())

        XCTAssertEqual(stability.blocker, .cornerStep)
        XCTAssertEqual(stability.frames, 0)
    }

    func testSoftCornerStepPausesHoldWithoutResettingProgress() {
        let stability = NationalIDCaptureStability()
        addCleanSample(stability, now: 1.0)
        addCleanSample(stability, now: 1.1)
        stability.add(now: 1.2, eligibilityBlocker: nil, motion: 0, cornerStep: 0.025, boundary: quad(), pixels: pixels())

        XCTAssertNil(stability.blocker)
        XCTAssertEqual(stability.cornerState, .softStep)
        XCTAssertEqual(stability.frames, 2)
        XCTAssertEqual(stability.holdDuration, 0.1, accuracy: 0.001)
    }

    func testSoftCornerDriftPausesHoldWithoutResettingProgress() {
        let stability = NationalIDCaptureStability()
        addCleanSample(stability, now: 1.0)
        addCleanSample(stability, now: 1.1)
        stability.add(now: 1.2, eligibilityBlocker: nil, motion: 0, cornerStep: 0.001, boundary: quad(offset: 0.03), pixels: pixels())

        XCTAssertNil(stability.blocker)
        XCTAssertEqual(stability.cornerState, .softDrift)
        XCTAssertEqual(stability.frames, 2)
        XCTAssertEqual(stability.holdDuration, 0.1, accuracy: 0.001)
    }

    func testHardCornerDriftFailureBlocksHold() {
        let stability = NationalIDCaptureStability()
        addCleanSample(stability, now: 1.0)
        addCleanSample(stability, now: 1.1)
        stability.add(now: 1.2, eligibilityBlocker: nil, motion: 0, cornerStep: 0.001, boundary: quad(offset: 0.05), pixels: pixels())

        XCTAssertEqual(stability.blocker, .cornerDrift)
        XCTAssertEqual(stability.frames, 0)
    }

    func testLumaDriftFailureBlocksHold() {
        let stability = NationalIDCaptureStability()
        addCleanSample(stability, now: 1.0, pixels: pixels(value: 80))
        addCleanSample(stability, now: 1.1, pixels: pixels(value: 80))

        let moved = pixels(value: 80).enumerated().map { index, value in
            UInt8(index % 2 == 0 ? 40 : Int(value))
        }
        stability.add(now: 1.2, eligibilityBlocker: nil, motion: 0, cornerStep: 0.001, boundary: quad(), pixels: moved)

        XCTAssertEqual(stability.blocker, .lumaDrift)
        XCTAssertEqual(stability.frames, 0)
    }

    func testMotionDoesNotBlockBeforeTrackingWhenEnforcementIsDisabled() {
        let stability = NationalIDCaptureStability()

        stability.add(
            now: 1.0,
            eligibilityBlocker: nil,
            motion: .infinity,
            cornerStep: 0.001,
            boundary: quad(),
            pixels: pixels(),
            tolerateMotionSpike: true,
            enforceMotion: false
        )

        XCTAssertNil(stability.blocker)
        XCTAssertEqual(stability.frames, 1)
    }

    func testLumaDriftDoesNotBlockBeforeTrackingWhenEnforcementIsDisabled() {
        let stability = NationalIDCaptureStability()
        addCleanSample(stability, now: 1.0, pixels: pixels(value: 80))
        addCleanSample(stability, now: 1.1, pixels: pixels(value: 80))

        let moved = pixels(value: 80).enumerated().map { index, value in
            UInt8(index % 2 == 0 ? 40 : Int(value))
        }
        stability.add(
            now: 1.2,
            eligibilityBlocker: nil,
            motion: 0,
            cornerStep: 0.001,
            boundary: quad(),
            pixels: moved,
            enforceMotion: false
        )

        XCTAssertNil(stability.blocker)
        XCTAssertEqual(stability.frames, 3)
    }

    func testFiveFramesAnd450MillisecondsBecomeReady() {
        let stability = NationalIDCaptureStability()
        for index in 0..<6 {
            addCleanSample(stability, now: 1.0 + Double(index) * 0.1)
        }

        XCTAssertTrue(stability.ready)
        XCTAssertEqual(stability.frames, 5)
        XCTAssertEqual(stability.holdDuration, 0.45, accuracy: 0.001)
    }

    func testFailedSampleDoesNotCountTowardHold() {
        let stability = NationalIDCaptureStability()
        addCleanSample(stability, now: 1.0)
        stability.add(now: 1.1, eligibilityBlocker: .quality, motion: 0, cornerStep: 0.001, boundary: quad(), pixels: pixels())

        XCTAssertEqual(stability.blocker, .quality)
        XCTAssertEqual(stability.frames, 0)
        XCTAssertEqual(stability.holdDuration, 0)
    }

    func testOCREvidenceExpiryConstantIs1500Milliseconds() {
        XCTAssertEqual(NIDTrackingConfig.ocrEvidenceLifetime, 1.5, accuracy: 0.001)
    }

    func testOCRRunsFasterDuringAcquisitionThanAfterConfirmation() {
        XCTAssertLessThan(NIDTrackingConfig.ocrAcquisitionInterval, NIDTrackingConfig.ocrInterval)
        XCTAssertEqual(NIDTrackingConfig.ocrAcquisitionInterval, 0.18, accuracy: 0.001)
        XCTAssertEqual(NIDTrackingConfig.ocrInterval, 0.4, accuracy: 0.001)
    }

    func testOCRBackoffDoublesFromHalfSecondAndCapsAtTwoSeconds() {
        XCTAssertEqual(NIDOCRConfig.backoffInterval(consecutiveFailures: 1), 0.5, accuracy: 0.001)
        XCTAssertEqual(NIDOCRConfig.backoffInterval(consecutiveFailures: 2), 1.0, accuracy: 0.001)
        XCTAssertEqual(NIDOCRConfig.backoffInterval(consecutiveFailures: 3), 2.0, accuracy: 0.001)
        XCTAssertEqual(NIDOCRConfig.backoffInterval(consecutiveFailures: 4), 2.0, accuracy: 0.001)
        XCTAssertEqual(NIDOCRConfig.backoffInterval(consecutiveFailures: 50), 2.0, accuracy: 0.001)
    }

    func testOCRBackoffNeverDropsBelowBaseForNonPositiveFailureCounts() {
        XCTAssertEqual(NIDOCRConfig.backoffInterval(consecutiveFailures: 0), 0.5, accuracy: 0.001)
        XCTAssertEqual(NIDOCRConfig.backoffInterval(consecutiveFailures: -3), 0.5, accuracy: 0.001)
    }

    func testOCRBackoffMaximumExceedsNormalIntervals() {
        XCTAssertGreaterThan(NIDOCRConfig.backoffMaximumInterval, NIDTrackingConfig.ocrInterval)
        XCTAssertGreaterThan(NIDOCRConfig.disableDuration, NIDOCRConfig.backoffMaximumInterval)
    }

    func testMotionSamplesSurviveWithinFilterTimeout() {
        let stability = NationalIDCaptureStability()
        addCleanSample(stability, now: 1.0)
        addCleanSample(stability, now: 1.1)

        XCTAssertNotNil(stability.motion0)
        XCTAssertNotNil(stability.motion1)
    }

    func testMotionFilterTimeoutDiscardsStaleSamplesWithoutFrameGap() {
        let stability = NationalIDCaptureStability()
        addCleanSample(stability, now: 1.0)
        addCleanSample(stability, now: 1.1)

        // 250ms: past the 200ms filter timeout but under the 500ms frame gap.
        addCleanSample(stability, now: 1.35)

        XCTAssertNil(stability.motion0)
        XCTAssertNil(stability.motion1)
        XCTAssertNotEqual(stability.blocker, .frameGap)
    }

    func testMotionFilterTimeoutIsShorterThanFrameGap() {
        XCTAssertLessThan(NIDTrackingConfig.motionFilterTimeout, NIDTrackingConfig.maximumFrameGap)
    }

    func testMedian3IsOrderIndependent() {
        let values: [CGFloat] = [3, 9, 6]
        let expected: CGFloat = 6
        XCTAssertEqual(NIDMotionMetrics.median3(values[0], values[1], values[2]), expected)
        XCTAssertEqual(NIDMotionMetrics.median3(values[1], values[2], values[0]), expected)
        XCTAssertEqual(NIDMotionMetrics.median3(values[2], values[0], values[1]), expected)
    }

    private func addCleanSample(
        _ stability: NationalIDCaptureStability,
        now: CFTimeInterval,
        pixels: [UInt8] = [UInt8](repeating: 80, count: 16)
    ) {
        stability.add(
            now: now,
            eligibilityBlocker: nil,
            motion: 0,
            cornerStep: 0.001,
            boundary: quad(),
            pixels: pixels
        )
    }

    private func quad(offset: CGFloat = 0) -> NationalIDQuad {
        NationalIDQuad(
            topLeft: CGPoint(x: 0.1 + offset, y: 0.1),
            topRight: CGPoint(x: 0.9 + offset, y: 0.1),
            bottomRight: CGPoint(x: 0.9 + offset, y: 0.7),
            bottomLeft: CGPoint(x: 0.1 + offset, y: 0.7)
        )
    }

    private func pixels(value: UInt8 = 80) -> [UInt8] {
        [UInt8](repeating: value, count: 16)
    }
}
