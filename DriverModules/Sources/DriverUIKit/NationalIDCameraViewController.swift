//
//  NationalIDCameraViewController.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/5/26.
//

import AVFoundation
import CoreMotion
import UIKit
import Vision

struct NationalIDCapturedPhoto {
    let image: UIImage
    let expectedStillQuad: NationalIDQuad?
}

final class NationalIDCameraViewController: UIViewController {
    private let onCapture: (NationalIDCapturedPhoto) -> Void
    private let onCancel: () -> Void
    private let onPhotoLibrary: () -> Void
    private let onFiles: () -> Void
    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let motionManager = CMMotionManager()
    private let sessionQueue = DispatchQueue(label: "driver.nid.camera.session")
    private let visionQueue = DispatchQueue(label: "driver.nid.camera.vision")
    private let tracker = NationalIDFrameTracker()
    private let overlayLayer = CAShapeLayer()
    private let guideDimLayer = CAShapeLayer()
    private let guideBorderLayer = CAShapeLayer()
    private let scanLine = CALayer()
    private var lastGuideBounds: CGRect?
    private var lastGuideRect: CGRect?
    private var captureGuide: CGRect = .zero
    private let statusLabel = UILabel()
    private let visionOrientation: CGImagePropertyOrientation = .right
    private let videoOrientation: AVCaptureVideoOrientation = .portrait
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var isCapturing = false
    private var frameLogCounter = 0
    private var captureDevice: AVCaptureDevice?
    private var latestMotionMagnitude: Double = 0
    private var lastFocusSteerDate = Date.distantPast
    private var lastVisionSampleTime: CMTime?
    private let visionInterval: Double = 0.12
    private var displayedPreviewQuad: NationalIDQuad?
    private var lastPreviewUpdate: CFTimeInterval?
    private let bufferSizeLock = NSLock()
    private var previewBufferSize: CGSize = .zero

    /// Last trustworthy normalized Vision quad that caused the live pipeline to reach READY.
    private var lastStableLiveQuad: NationalIDQuad?

    /// Oriented live-frame size that produced `lastStableLiveQuad`.
    /// Live Vision uses `.right`, so this size is height × width from the raw pixel buffer.
    private var lastStableLiveImageSize: CGSize?

    init(
        onCapture: @escaping (NationalIDCapturedPhoto) -> Void,
        onCancel: @escaping () -> Void,
        onPhotoLibrary: @escaping () -> Void = {},
        onFiles: @escaping () -> Void = {}
    ) {
        self.onCapture = onCapture
        self.onCancel = onCancel
        self.onPhotoLibrary = onPhotoLibrary
        self.onFiles = onFiles
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configurePreview()
        configureChrome()
        configureSession()
        configureMotion()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        let safe = view.safeAreaLayoutGuide.layoutFrame
        let width = max(0, min(safe.width - 40, 460, (safe.height - 160) / 0.631))
        let guide = CGRect(x: safe.midX - width / 2, y: safe.midY - width * 0.631 / 2,
                           width: width, height: width * 0.631)
        bufferSizeLock.lock()
        captureGuide = guide
        bufferSizeLock.unlock()
        guard lastGuideBounds != view.bounds || lastGuideRect != guide else { return }
        lastGuideBounds = view.bounds
        lastGuideRect = guide
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let mask = UIBezierPath(rect: view.bounds)
        mask.append(UIBezierPath(roundedRect: guide, cornerRadius: 12))
        guideDimLayer.path = mask.cgPath
        guideBorderLayer.path = UIBezierPath(roundedRect: guide, cornerRadius: 12).cgPath
        scanLine.frame = CGRect(x: guide.minX + 12, y: guide.minY + 12, width: max(0, guide.width - 24), height: 2)
        scanLine.removeAllAnimations()
        if !UIAccessibility.isReduceMotionEnabled {
            let sweep = CABasicAnimation(keyPath: "transform.translation.y")
            sweep.fromValue = 0
            sweep.toValue = max(0, guide.height - 26)
            sweep.duration = 0.85
            sweep.autoreverses = true
            sweep.repeatCount = .infinity
            sweep.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            scanLine.add(sweep, forKey: "scan")
        }
        CATransaction.commit()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        lastGuideBounds = nil
        view.setNeedsLayout()
        startMotionUpdates()
        sessionQueue.async { [session] in
            if session.isRunning == false {
                session.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopMotionUpdates()
        displayedPreviewQuad = nil
        scanLine.removeAllAnimations()
        lastStableLiveQuad = nil
        lastStableLiveImageSize = nil

        sessionQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    private func configurePreview() {
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        configurePreviewConnection(preview)
        view.layer.addSublayer(preview)
        previewLayer = preview

        guideDimLayer.fillRule = .evenOdd
        guideDimLayer.fillColor = UIColor.black.withAlphaComponent(0.60).cgColor
        view.layer.addSublayer(guideDimLayer)
        guideBorderLayer.fillColor = UIColor.clear.cgColor
        guideBorderLayer.strokeColor = UIColor.white.cgColor
        guideBorderLayer.lineWidth = 2
        view.layer.addSublayer(guideBorderLayer)
        scanLine.backgroundColor = UIColor.systemTeal.withAlphaComponent(0.75).cgColor
        view.layer.addSublayer(scanLine)
        NotificationCenter.default.addObserver(self, selector: #selector(reduceMotionChanged), name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)

        overlayLayer.strokeColor = UIColor.systemGreen.cgColor
        overlayLayer.fillColor = UIColor.clear.cgColor
        overlayLayer.lineWidth = 3
        overlayLayer.lineJoin = .round
        view.layer.addSublayer(overlayLayer)
    }

    private func configureChrome() {
        let close = UIButton(type: .system)
        close.translatesAutoresizingMaskIntoConstraints = false
        close.configuration = .filled()
        close.configuration?.image = UIImage(systemName: "xmark")
        close.configuration?.baseBackgroundColor = UIColor.black.withAlphaComponent(0.55)
        close.tintColor = .white
        close.accessibilityLabel = "Close camera"
        close.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        let photo = UIButton(type: .system)
        photo.translatesAutoresizingMaskIntoConstraints = false
        photo.configuration = .filled()
        photo.configuration?.image = UIImage(systemName: "photo.on.rectangle")
        photo.configuration?.baseBackgroundColor = UIColor.black.withAlphaComponent(0.55)
        photo.tintColor = .white
        photo.accessibilityLabel = "Choose from photo library"
        photo.addTarget(self, action: #selector(photoLibraryTapped), for: .touchUpInside)

        let files = UIButton(type: .system)
        files.translatesAutoresizingMaskIntoConstraints = false
        files.configuration = .filled()
        files.configuration?.image = UIImage(systemName: "folder")
        files.configuration?.baseBackgroundColor = UIColor.black.withAlphaComponent(0.55)
        files.tintColor = .white
        files.accessibilityLabel = "Choose from files"
        files.addTarget(self, action: #selector(filesTapped), for: .touchUpInside)

        let sourceStack = UIStackView(arrangedSubviews: [photo, files])
        sourceStack.translatesAutoresizingMaskIntoConstraints = false
        sourceStack.axis = .horizontal
        sourceStack.spacing = 10
        sourceStack.distribution = .fillEqually

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.text = "Place your National ID inside the frame"
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = .white
        statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.layer.cornerRadius = 12
        statusLabel.layer.masksToBounds = true

        view.addSubview(close)
        view.addSubview(sourceStack)
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            close.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            close.widthAnchor.constraint(equalToConstant: 48),
            close.heightAnchor.constraint(equalToConstant: 48),
            sourceStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            sourceStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            photo.widthAnchor.constraint(equalToConstant: 48),
            photo.heightAnchor.constraint(equalToConstant: 48),
            files.widthAnchor.constraint(equalToConstant: 48),
            files.heightAnchor.constraint(equalToConstant: 48),
            statusLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            statusLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -28),
            statusLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 52)
        ])
    }

    @objc private func reduceMotionChanged() {
        lastGuideBounds = nil
        view.setNeedsLayout()
    }

    private func configurePreviewConnection(_ preview: AVCaptureVideoPreviewLayer) {
        guard let connection = preview.connection else { return }
        if connection.isVideoOrientationSupported {
            connection.videoOrientation = videoOrientation
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
    }

    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            defer { self.session.commitConfiguration() }

            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: camera),
                  self.session.canAddInput(input)
            else { return }
            self.captureDevice = camera
            self.session.addInput(input)

            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
            self.videoOutput.setSampleBufferDelegate(self, queue: self.visionQueue)
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
            }
            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
            }
            self.videoOutput.connection(with: .video)?.videoOrientation = self.videoOrientation
            self.photoOutput.connection(with: .video)?.videoOrientation = self.videoOrientation
            DispatchQueue.main.async { [weak self] in
                guard let self, let previewLayer = self.previewLayer else { return }
                self.configurePreviewConnection(previewLayer)
                self.debugLog("ORIENTATION vision=\(self.visionOrientation.rawValue) video=\(self.videoOrientation.rawValue) preview=\(previewLayer.connection?.videoOrientation.rawValue ?? -1) mirrored=\(previewLayer.connection?.isVideoMirrored ?? false)")
            }
        }
    }

    private func configureMotion() {
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
    }

    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let rotation = motion.rotationRate
            let acceleration = motion.userAcceleration
            let rotationMagnitude = sqrt(rotation.x * rotation.x + rotation.y * rotation.y + rotation.z * rotation.z)
            let accelerationMagnitude = sqrt(acceleration.x * acceleration.x + acceleration.y * acceleration.y + acceleration.z * acceleration.z)
            self.latestMotionMagnitude = max(rotationMagnitude / 2.2, accelerationMagnitude / 0.18)
        }
    }

    private func stopMotionUpdates() {
        motionManager.stopDeviceMotionUpdates()
        latestMotionMagnitude = 0
    }

    private var isDeviceShaking: Bool {
        latestMotionMagnitude > 1
    }

    private func updateOverlay(corners: NationalIDQuad?, stable: Bool, status: NationalIDCaptureStatus) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            defer { CATransaction.commit() }
            if let corners,
               let candidateQuad = self.previewQuad(for: corners),
               let previewQuad = self.smoothPreviewQuad(candidateQuad) {
                let path = UIBezierPath()
                path.move(to: previewQuad.topLeft)
                path.addLine(to: previewQuad.topRight)
                path.addLine(to: previewQuad.bottomRight)
                path.addLine(to: previewQuad.bottomLeft)
                path.close()
                self.overlayLayer.path = path.cgPath
                self.overlayLayer.strokeColor = stable ? UIColor.systemGreen.cgColor : UIColor.systemYellow.cgColor
            } else {
                self.displayedPreviewQuad = nil
                self.overlayLayer.path = nil
            }
            if self.statusLabel.text != status.message {
                self.statusLabel.text = status.message
                self.statusLabel.accessibilityLabel = status.message
            }
        }
    }

    /// Smooth only the visible overlay. Detection, readiness, and capture use
    /// the authoritative tracked geometry and are never delayed by this EMA.
    private func smoothPreviewQuad(_ candidate: NationalIDQuad) -> NationalIDQuad? {
        let now = CACurrentMediaTime()
        let elapsed = lastPreviewUpdate.map { now - $0 } ?? 0
        defer { lastPreviewUpdate = now }
        let alpha = CGFloat(1 - exp(-max(0, elapsed) / 0.12))
        func bounds(_ quad: NationalIDQuad) -> CGRect {
            let points = [quad.topLeft, quad.topRight, quad.bottomRight, quad.bottomLeft]
            let xs = points.map(\.x), ys = points.map(\.y)
            return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        }
        func overlaps(_ previous: NationalIDQuad) -> Bool {
            let a = bounds(previous), b = bounds(candidate)
            let intersection = a.intersection(b)
            let area = intersection.isNull ? 0 : intersection.width * intersection.height
            let union = a.width * a.height + b.width * b.height - area
            return union > 0 && area / union >= 0.5
        }
        func blend(_ previous: CGPoint, _ current: CGPoint) -> CGPoint {
            CGPoint(
                x: previous.x + alpha * (current.x - previous.x),
                y: previous.y + alpha * (current.y - previous.y)
            )
        }

        guard let previous = displayedPreviewQuad, elapsed > 0, elapsed <= 0.5,
              overlaps(previous), !UIAccessibility.isReduceMotionEnabled else {
            displayedPreviewQuad = candidate
            return candidate
        }
        let smoothed = NationalIDQuad(
            topLeft: blend(previous.topLeft, candidate.topLeft),
            topRight: blend(previous.topRight, candidate.topRight),
            bottomRight: blend(previous.bottomRight, candidate.bottomRight),
            bottomLeft: blend(previous.bottomLeft, candidate.bottomLeft)
        )
        displayedPreviewQuad = smoothed
        return smoothed
    }

    private func previewPoint(fromVisionPoint point: CGPoint, previewLayer: AVCaptureVideoPreviewLayer) -> CGPoint {
        bufferSizeLock.lock()
        let size = previewBufferSize
        bufferSizeLock.unlock()
        return NationalIDPreviewTransform.portraitPreviewPoint(point, bufferSize: size, bounds: previewLayer.frame)
    }

    private func previewQuad(for corners: NationalIDQuad) -> NationalIDQuad? {
        guard let previewLayer else { return nil }
        let points = [corners.topLeft, corners.topRight, corners.bottomRight, corners.bottomLeft]
            .map { previewPoint(fromVisionPoint: $0, previewLayer: previewLayer) }
        return NationalIDPreviewTransform.orderedPreviewQuad(from: points)
    }

    private func captureDevicePoint(fromVisionPoint point: CGPoint) -> CGPoint {
        NationalIDPreviewTransform.captureDevicePoint(
            fromVisionPoint: point,
            visionOrientation: visionOrientation,
            videoOrientation: videoOrientation,
            isMirrored: false
        )
    }

    private func steerFocusIfNeeded(to corners: NationalIDQuad?) {
        guard let corners else { return }
        let now = Date()
        guard now.timeIntervalSince(lastFocusSteerDate) > 1.5 else { return }
        lastFocusSteerDate = now
        let center = corners.center
        let focusPoint = captureDevicePoint(fromVisionPoint: center)
        sessionQueue.async { [weak self] in
            guard let device = self?.captureDevice, device.isFocusPointOfInterestSupported || device.isExposurePointOfInterestSupported else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = focusPoint
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = focusPoint
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()
                self?.debugLog("FOCUS point=\(Self.format(focusPoint))")
            } catch {
                self?.debugLog("FOCUS failed error=\(error.localizedDescription)")
            }
        }
    }

    private func status(for result: NIDDetectionResult, isShaking: Bool, previewMetrics: NationalIDGeometryMetrics?) -> NationalIDCaptureStatus {
        guard result.boundary != nil else { return .noDocument }
        if result.cardCutOff { return .align }
        if isShaking { return .unstable }
        if let previewMetrics, previewMetrics.isLandscape == false { return .wrongOrientation }
        if result.tooDark || result.tooBright { return .align }
        if result.hasGlare { return .glare }
        if result.blurry { return .blurry }
        if result.status == .ready { return .ready }
        return .unstable
    }

    private func capturePhoto() {
        guard isCapturing == false else { return }
        isCapturing = true
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func isInsideCaptureGuide(_ corners: NationalIDQuad) -> Bool {
        guard let quad = previewQuad(for: corners) else { return false }
        bufferSizeLock.lock()
        let guide = captureGuide
        bufferSizeLock.unlock()
        guard !guide.isEmpty else { return false }
        return [quad.topLeft, quad.topRight, quad.bottomRight, quad.bottomLeft]
            .allSatisfy { guide.contains($0) }
    }

    @objc private func cancelTapped() {
        dismiss(animated: true) { [onCancel] in onCancel() }
    }

    @objc private func photoLibraryTapped() {
        dismiss(animated: true) { [onPhotoLibrary] in onPhotoLibrary() }
    }

    @objc private func filesTapped() {
        dismiss(animated: true) { [onFiles] in onFiles() }
    }

    private func debugLogFrame(result: NIDDetectionResult, status: NationalIDCaptureStatus) {
        #if DEBUG
        frameLogCounter += 1
        guard frameLogCounter % 10 == 0 || result.status == .ready else { return }
        let previewMetrics = previewMetrics(for: result.boundary)
        let cornersText = result.boundary.map {
            "tl=\(Self.format($0.topLeft)) tr=\(Self.format($0.topRight)) br=\(Self.format($0.bottomRight)) bl=\(Self.format($0.bottomLeft))"
        } ?? "corners=none"
        let previewText: String
        if let corners = result.boundary, let previewQuad = previewQuad(for: corners) {
            previewText = " previewTL=\(Self.format(previewQuad.topLeft)) previewTR=\(Self.format(previewQuad.topRight)) previewBR=\(Self.format(previewQuad.bottomRight)) previewBL=\(Self.format(previewQuad.bottomLeft))"
        } else {
            previewText = ""
        }
        let previewMetricsText = previewMetrics.map {
            " previewWidth=\(Self.formatNumber($0.width)) previewHeight=\(Self.formatNumber($0.height)) isLandscapeInPreview=\($0.isLandscape) previewTopEdge=\(Self.formatNumber($0.topEdge)) previewBottomEdge=\(Self.formatNumber($0.bottomEdge)) previewLeftEdge=\(Self.formatNumber($0.leftEdge)) previewRightEdge=\(Self.formatNumber($0.rightEdge))"
        } ?? " previewWidth=0.000 previewHeight=0.000 isLandscapeInPreview=false"
        print(
            "[NID][FRAME] status=\(status.rawValue) result=\(result.status) progress=\(Self.formatNumber(result.progress)) sharp=\(Self.formatNumber(result.sharpness)) focusOK=\(result.focusOK) qualityOK=\(result.qualityOK) eligible=\(result.eligible) blocker=\(result.blocker?.rawValue ?? "none") cardPresent=\(result.cardPresent) documentConfirmed=\(result.documentConfirmed) ocrAgeMs=\(result.ocrAgeMs.map(String.init) ?? "nil") textOutside=\(result.textOutside) dark=\(result.tooDark) bright=\(result.tooBright) glare=\(result.hasGlare) blurry=\(result.blurry) cutoff=\(result.cardCutOff) missing=\(result.boundaryMissing) deviceMotion=\(Self.formatNumber(CGFloat(latestMotionMagnitude)))\(previewMetricsText) \(cornersText)\(previewText)"
        )
        if let previewMetrics {
            print("[NID][Orientation] visionOrientation=\(visionOrientation.rawValue) videoOrientation=\(videoOrientation.rawValue) previewOrientation=\(previewLayer?.connection?.videoOrientation.rawValue ?? -1) horizontalPair=\(Self.formatNumber(previewMetrics.width)) verticalPair=\(Self.formatNumber(previewMetrics.height)) landscape=\(previewMetrics.isLandscape)")
        }
        #endif
    }

    private func previewMetrics(for corners: NationalIDQuad?) -> NationalIDGeometryMetrics? {
        guard let corners, let previewQuad = previewQuad(for: corners) else { return nil }
        return NationalIDGeometry.metrics(for: previewQuad)
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[NID] \(message)")
        #endif
    }

    private static func format(_ point: CGPoint) -> String {
        "(\(formatNumber(point.x)),\(formatNumber(point.y)))"
    }

    private static func formatNumber(_ value: CGFloat) -> String {
        String(format: "%.3f", Double(value))
    }
}

extension NationalIDCameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isCapturing == false else { return }

        if let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            bufferSizeLock.lock()
            previewBufferSize = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
            bufferSizeLock.unlock()
        }
        // Throttle and cheap pre-checks precede Vision and tracking.
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if let lastVisionSampleTime,
           timestamp.isValid,
           timestamp.seconds - lastVisionSampleTime.seconds < visionInterval {
            return
        }
        if timestamp.isValid {
            lastVisionSampleTime = timestamp
        }

        let shaking = isDeviceShaking
        if shaking {
            debugLog("PIPELINE precheck=motion action=trackNoReady")
        }

        bufferSizeLock.lock()
        let guide = captureGuide
        bufferSizeLock.unlock()
        let result = tracker.process(
            sampleBuffer: sampleBuffer,
            guideRect: guide,
            isDeviceShaking: shaking,
            now: CACurrentMediaTime()
        )
        let previewMetrics = previewMetrics(for: result.boundary)
        let status = status(for: result, isShaking: shaking, previewMetrics: previewMetrics)
        steerFocusIfNeeded(to: result.boundary)
        debugLogFrame(result: result, status: status)
        updateOverlay(corners: result.boundary, stable: status == .ready, status: status)
        if shaking == false,
           status == .ready,
           let stableQuad = result.boundary,
           let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {

            lastStableLiveQuad = stableQuad

            // Vision runs with `.right`, therefore use the oriented frame size.
            let bufferWidth = CVPixelBufferGetWidth(pixelBuffer)
            let bufferHeight = CVPixelBufferGetHeight(pixelBuffer)
            lastStableLiveImageSize = CGSize(
                width: bufferHeight,
                height: bufferWidth
            )

            debugLog(
                "CAPTURE auto " +
                "progress=\(Self.formatNumber(result.progress)) " +
                "sharp=\(Self.formatNumber(result.sharpness)) " +
                "liveSize=\(bufferHeight)x\(bufferWidth) " +
                "liveQuad=stored"
            )

            capturePhoto()
        }
    }
}

extension NationalIDCameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data)
        else {
            DispatchQueue.main.async { [weak self] in
                self?.isCapturing = false
                self?.statusLabel.text = "Could not capture. Try again."
                self?.debugLog(
                    "CAPTURE failed error=\(error?.localizedDescription ?? "unknown")"
                )
            }
            return
        }

        debugLog(
            "CAPTURE didCapture " +
            "bytes=\(data.count) " +
            "size=\(Int(image.size.width))x\(Int(image.size.height)) " +
            "orientation=\(image.imageOrientation.rawValue)"
        )

        var expectedStillQuad: NationalIDQuad?

        if let liveQuad = lastStableLiveQuad,
           let liveSize = lastStableLiveImageSize {

            debugLog(
                "CAPTURE liveQuad " +
                "tl=\(Self.format(liveQuad.topLeft)) " +
                "tr=\(Self.format(liveQuad.topRight)) " +
                "br=\(Self.format(liveQuad.bottomRight)) " +
                "bl=\(Self.format(liveQuad.bottomLeft))"
            )

            let stillSize = Self.orientedStillSize(for: image)

            debugLog(
                "CAPTURE mapping " +
                "liveSize=\(Int(liveSize.width))x\(Int(liveSize.height)) " +
                "rawStillSize=\(Int(image.size.width))x\(Int(image.size.height)) " +
                "orientedStillSize=\(Int(stillSize.width))x\(Int(stillSize.height))"
            )

            if let mappedQuad = NationalIDGeometry.mapLiveQuadToStill(
                liveQuad,
                liveSize: liveSize,
                stillSize: stillSize
            ) {
                expectedStillQuad = mappedQuad
                debugLog(
                    "CAPTURE expectedStillQuad " +
                    "tl=\(Self.format(mappedQuad.topLeft)) " +
                    "tr=\(Self.format(mappedQuad.topRight)) " +
                    "br=\(Self.format(mappedQuad.bottomRight)) " +
                    "bl=\(Self.format(mappedQuad.bottomLeft))"
                )
            } else {
                debugLog("CAPTURE expectedStillQuad mappingFailed")
            }
        } else {
            debugLog("CAPTURE expectedStillQuad missingLiveGeometry")
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.dismiss(animated: true) {
                self.onCapture(NationalIDCapturedPhoto(image: image, expectedStillQuad: expectedStillQuad))
            }
        }
    }

    private static func orientedStillSize(for image: UIImage) -> CGSize {
        switch image.imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            return CGSize(width: image.size.height, height: image.size.width)
        default:
            return image.size
        }
    }
}
