import AVFoundation
import CoreImage
import Foundation
import ImageIO
import SwiftUI
import UIKit
import Vision

enum LiveCameraError: LocalizedError, Sendable {
    case accessDenied
    case cameraUnavailable
    case inputUnavailable
    case outputUnavailable
    case captureFailed
    case switchUnavailable

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            "相机权限已关闭。请在系统设置中允许 FUMIRA 使用相机。"
        case .cameraUnavailable:
            "没有找到可用的后置相机。"
        case .inputUnavailable:
            "无法建立相机输入。"
        case .outputUnavailable:
            "无法建立照片输出。"
        case .captureFailed:
            "这次快门没有得到完整照片，请再拍一次。"
        case .switchUnavailable:
            "当前设备无法切换前后摄像头。"
        }
    }
}

final class LiveCameraService: NSObject, CameraService, CameraControlProviding, CameraZoomProviding, CameraPreviewFactory, TemporalCameraSampling, CameraOpticalContextProviding, CameraPreviewPrewarming, CameraSubjectTrackingProviding, @unchecked Sendable {
    let isLive = true

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let temporalFrameSampler = TemporalFrameSampler()
    private let sessionQueue = DispatchQueue(label: "com.fumira.camera.session")
    private let temporalFrameQueue = DispatchQueue(
        label: "com.fumira.camera.temporal-frames",
        qos: .userInitiated
    )
    private var isConfigured = false
    private var captureDelegates: [Int64: PhotoCaptureDelegate] = [:]
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var currentPosition: AVCaptureDevice.Position = .back
    private var preferredFlashMode: AVCaptureDevice.FlashMode = .auto
    private let zoomObserverLock = NSLock()
    private var zoomObserver: (@MainActor @Sendable (CameraZoomSnapshot) -> Void)?

    func requestAuthorization() async throws -> CameraAuthorization {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                throw LiveCameraError.accessDenied
            }
        case .denied, .restricted:
            throw LiveCameraError.accessDenied
        @unknown default:
            throw LiveCameraError.accessDenied
        }

        // Authorization only — preview starts when the viewfinder asks via startPreview().
        return .authorized
    }

    func startPreview() async throws {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                do {
                    try configureIfNeeded()
                    if !session.isRunning {
                        session.startRunning()
                    }
                    publishZoomSnapshot(makeZoomSnapshot())
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stopPreview() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                if session.isRunning {
                    session.stopRunning()
                }
                continuation.resume()
            }
        }
    }

    func prewarmPreviewIfAuthorized() async {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            return
        }
        try? await startPreview()
    }

    @MainActor
    func setSubjectTrackingObserver(
        _ observer: (@MainActor @Sendable (CameraTrackedSubject?) -> Void)?
    ) {
        temporalFrameSampler.setSubjectTrackingObserver(observer)
    }

    func capturePhoto(composition: CameraAspectRatio) async throws -> CapturedPhoto {
        try await startPreview()
        let rotationAngle = await MainActor.run {
            Self.captureRotationAngle(for: UIDevice.current.orientation)
        }

        return try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                // Make capture format explicit. Some devices otherwise return HEIC
                // bytes from `fileDataRepresentation()`, which cannot truthfully be
                // sent as the relay's JPEG multipart field.
                let settings = AVCapturePhotoSettings(
                    format: [AVVideoCodecKey: AVVideoCodecType.jpeg]
                )
                settings.photoQualityPrioritization = .quality
                let flashMode = resolvedFlashMode()
                if photoOutput.supportedFlashModes.contains(flashMode) {
                    settings.flashMode = flashMode
                }

                if let connection = photoOutput.connection(with: .video) {
                    if connection.isVideoRotationAngleSupported(rotationAngle) {
                        connection.videoRotationAngle = rotationAngle
                    }
                }

                let uniqueID = settings.uniqueID
                let delegate = PhotoCaptureDelegate { [service = self] result in
                    service.sessionQueue.async { [service] in
                        service.captureDelegates[uniqueID] = nil
                    }
                    switch result {
                    case let .success(data):
                        do {
                            continuation.resume(returning: try PhotoImportAdapter.makeCapturedPhoto(
                                from: data,
                                composition: composition
                            ))
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    case let .failure(error):
                        continuation.resume(throwing: error)
                    }
                }
                captureDelegates[uniqueID] = delegate
                photoOutput.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }

    func microTimeSlice(around shutterDate: Date) async -> MicroTimeSlice {
        // Keep sampling briefly after the shutter. The UI already shows the
        // frozen still, so this never makes the camera feel unresponsive.
        try? await Task.sleep(for: .milliseconds(280))
        return temporalFrameSampler.snapshot(around: shutterDate)
    }

    func opticalContext() async -> TemporalOpticalContext {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                guard let device = videoDeviceInput?.device else {
                    continuation.resume(returning: .unavailable)
                    return
                }
                let exposureDuration = device.exposureDuration.seconds
                let iso = device.iso
                let lightCondition: TemporalLightCondition
                if iso >= 640 || exposureDuration >= 1.0 / 30.0 {
                    lightCondition = .lowLight
                } else if iso <= 80, exposureDuration <= 1.0 / 250.0 {
                    lightCondition = .bright
                } else {
                    lightCondition = .balanced
                }
                continuation.resume(returning: TemporalOpticalContext(
                    lensPosition: currentPosition == .front ? .front : .back,
                    focusPosition: device.lensPosition,
                    exposureDurationSeconds: exposureDuration,
                    iso: iso,
                    exposureTargetOffset: device.exposureTargetOffset,
                    zoomFactor: Double(device.videoZoomFactor),
                    lightCondition: lightCondition
                ))
            }
        }
    }

    func currentControls() async -> CameraControlSnapshot {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                continuation.resume(returning: makeSnapshot())
            }
        }
    }

    func currentZoom() async -> CameraZoomSnapshot {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                continuation.resume(returning: makeZoomSnapshot())
            }
        }
    }

    func setZoomFactor(_ factor: CGFloat) {
        sessionQueue.async { [self] in
            guard let device = videoDeviceInput?.device else { return }
            let snapshot = makeZoomSnapshot().clamping(factor)
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = snapshot.factor
                device.unlockForConfiguration()
                publishZoomSnapshot(makeZoomSnapshot())
            } catch {
                return
            }
        }
    }

    @MainActor
    func setZoomObserver(
        _ observer: (@MainActor @Sendable (CameraZoomSnapshot) -> Void)?
    ) {
        zoomObserverLock.lock()
        zoomObserver = observer
        zoomObserverLock.unlock()
    }

    func switchCamera() async throws -> CameraControlSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                do {
                    try configureIfNeeded()
                    let nextPosition: AVCaptureDevice.Position =
                        currentPosition == .back ? .front : .back
                    guard Self.device(for: nextPosition) != nil else {
                        throw LiveCameraError.switchUnavailable
                    }

                    session.beginConfiguration()
                    defer { session.commitConfiguration() }

                    if let videoDeviceInput {
                        session.removeInput(videoDeviceInput)
                        self.videoDeviceInput = nil
                    }

                    try installInput(position: nextPosition)
                    configureSystemZoomControlIfAvailable()
                    currentPosition = nextPosition
                    temporalFrameSampler.resetSubjectTracking(
                        cameraPosition: nextPosition
                    )
                    publishZoomSnapshot(makeZoomSnapshot())
                    continuation.resume(returning: makeSnapshot())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func setFlashMode(_ mode: CameraFlashMode) async throws -> CameraControlSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                do {
                    try configureIfNeeded()
                    preferredFlashMode = mode.avFlashMode
                    continuation.resume(returning: makeSnapshot())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    @MainActor
    func makePreview() -> AnyView {
        AnyView(LiveCameraPreviewView(session: session))
    }

    private func configureIfNeeded() throws {
        guard !isConfigured else { return }

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo

        try installInput(position: .back)
        configureSystemZoomControlIfAvailable()

        guard session.canAddOutput(photoOutput) else {
            throw LiveCameraError.outputUnavailable
        }
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality

        // Optional context output. Failure to add it must never disable normal
        // photo capture on a constrained or older device.
        if session.canAddOutput(videoOutput) {
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_32BGRA
            ]
            videoOutput.setSampleBufferDelegate(
                temporalFrameSampler,
                queue: temporalFrameQueue
            )
            session.addOutput(videoOutput)
            temporalFrameSampler.resetSubjectTracking(cameraPosition: .back)
        }
        currentPosition = .back
        isConfigured = true
    }

    private func installInput(position: AVCaptureDevice.Position) throws {
        guard let device = Self.device(for: position) else {
            throw LiveCameraError.cameraUnavailable
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw LiveCameraError.inputUnavailable
        }

        guard session.canAddInput(input) else {
            throw LiveCameraError.inputUnavailable
        }
        session.addInput(input)
        videoDeviceInput = input
        currentPosition = position
        try applyDefaultWideAngleZoom(on: device)
    }

    /// Dual-wide / triple cameras open at the ultra-wide end (UI 0.5×). Jump to
    /// the first virtual-device switch-over so the default read is Camera's 1×.
    private func applyDefaultWideAngleZoom(on device: AVCaptureDevice) throws {
        let switchOvers = device.virtualDeviceSwitchOverVideoZoomFactors
        let target: CGFloat
        if let first = switchOvers.first {
            target = CGFloat(truncating: first)
        } else if #available(iOS 18.0, *) {
            let multiplier = device.displayVideoZoomFactorMultiplier
            if multiplier > 0, multiplier < 0.999 {
                target = 1 / multiplier
            } else {
                target = max(device.minAvailableVideoZoomFactor, 1)
            }
        } else {
            target = max(device.minAvailableVideoZoomFactor, 1)
        }

        let clamped = min(
            max(target, device.minAvailableVideoZoomFactor),
            device.maxAvailableVideoZoomFactor
        )
        guard abs(device.videoZoomFactor - clamped) > 0.01 else { return }
        try device.lockForConfiguration()
        device.videoZoomFactor = clamped
        device.unlockForConfiguration()
    }

    private func makeSnapshot() -> CameraControlSnapshot {
        CameraControlSnapshot(
            lensPosition: currentPosition == .front ? .front : .back,
            flashMode: CameraFlashMode(avFlashMode: preferredFlashMode),
            canSwitchCamera: Self.canSwitchBetweenCameras,
            supportsFlash: currentDeviceSupportsFlash
        )
    }

    private func makeZoomSnapshot() -> CameraZoomSnapshot {
        guard let device = videoDeviceInput?.device else {
            return .unavailable
        }

        let hardwareMinimum = device.minAvailableVideoZoomFactor
        let hardwareMaximum = device.maxAvailableVideoZoomFactor
        let recommendedRange: ClosedRange<CGFloat>
        if #available(iOS 18.0, *) {
            recommendedRange = device.activeFormat.systemRecommendedVideoZoomRange
                ?? hardwareMinimum...min(hardwareMaximum, 10)
        } else {
            recommendedRange = hardwareMinimum...min(hardwareMaximum, 10)
        }

        let minimum = max(hardwareMinimum, recommendedRange.lowerBound)
        let maximum = max(minimum, min(hardwareMaximum, recommendedRange.upperBound))
        let factor = min(max(device.videoZoomFactor, minimum), maximum)
        let displayMultiplier: CGFloat
        if #available(iOS 18.0, *) {
            displayMultiplier = max(device.displayVideoZoomFactorMultiplier, 0.01)
        } else {
            displayMultiplier = 1
        }
        return CameraZoomSnapshot(
            factor: factor,
            displayFactor: factor * displayMultiplier,
            minimumFactor: minimum,
            maximumFactor: maximum
        )
    }

    private func publishZoomSnapshot(_ snapshot: CameraZoomSnapshot) {
        zoomObserverLock.lock()
        let observer = zoomObserver
        zoomObserverLock.unlock()
        guard let observer else { return }
        Task { @MainActor in
            observer(snapshot)
        }
    }

    private func configureSystemZoomControlIfAvailable() {
        guard #available(iOS 18.0, *), session.supportsControls else {
            return
        }
        session.controls.forEach(session.removeControl)
        session.setControlsDelegate(self, queue: .main)
        guard let device = videoDeviceInput?.device else { return }
        let slider = AVCaptureSystemZoomSlider(device: device) { [weak self] _ in
            guard let self else { return }
            sessionQueue.async { [self] in
                publishZoomSnapshot(makeZoomSnapshot())
            }
        }
        guard session.canAddControl(slider) else { return }
        session.addControl(slider)
    }

    private var currentDeviceSupportsFlash: Bool {
        guard let device = videoDeviceInput?.device else { return false }
        return device.hasFlash && !photoOutput.supportedFlashModes.isEmpty
    }

    private func resolvedFlashMode() -> AVCaptureDevice.FlashMode {
        guard currentDeviceSupportsFlash else { return .off }
        if photoOutput.supportedFlashModes.contains(preferredFlashMode) {
            return preferredFlashMode
        }
        return .off
    }

    private static var canSwitchBetweenCameras: Bool {
        device(for: .back) != nil && device(for: .front) != nil
    }

    private static func device(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if position == .front {
            return AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: .front
            )
        }

        return AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }

    /// AVCapture uses rotation angles, not interface orientation. Mapping this
    /// at the shutter keeps the JPEG's pixel axes aligned to how the person is
    /// holding the phone, including a landscape capture.
    private static func captureRotationAngle(for orientation: UIDeviceOrientation) -> CGFloat {
        // Match previewRotationAngle / Apple AVCam mapping. Landscape left/right
        // were previously swapped, which wrote upside-down JPEGs for horizontal
        // captures while the live preview looked correct.
        switch orientation {
        case .landscapeLeft: 0
        case .landscapeRight: 180
        case .portraitUpsideDown: 270
        case .portrait, .faceUp, .faceDown, .unknown: 90
        @unknown default: 90
        }
    }
}

@available(iOS 18.0, *)
extension LiveCameraService: AVCaptureSessionControlsDelegate {
    func sessionControlsDidBecomeActive(_ session: AVCaptureSession) {}

    func sessionControlsWillEnterFullscreenAppearance(_ session: AVCaptureSession) {}

    func sessionControlsWillExitFullscreenAppearance(_ session: AVCaptureSession) {}

    func sessionControlsDidBecomeInactive(_ session: AVCaptureSession) {}
}

private extension CameraFlashMode {
    var avFlashMode: AVCaptureDevice.FlashMode {
        switch self {
        case .off: .off
        case .on: .on
        case .auto: .auto
        }
    }

    init(avFlashMode: AVCaptureDevice.FlashMode) {
        switch avFlashMode {
        case .on: self = .on
        case .auto: self = .auto
        case .off: self = .off
        @unknown default: self = .off
        }
    }
}

private final class TemporalFrameSampler: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private struct BufferedFrame {
        let date: Date
        let data: Data
    }

    private let lock = NSLock()
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let subjectTracker = LiveSubjectTracker()
    private let subjectObserverLock = NSLock()
    private var subjectObserver: (@MainActor @Sendable (CameraTrackedSubject?) -> Void)?
    private var frames: [BufferedFrame] = []
    private var lastEncodedAt = Date.distantPast

    func setSubjectTrackingObserver(
        _ observer: (@MainActor @Sendable (CameraTrackedSubject?) -> Void)?
    ) {
        subjectObserverLock.lock()
        subjectObserver = observer
        subjectObserverLock.unlock()
        subjectTracker.setEnabled(observer != nil)
    }

    func resetSubjectTracking(cameraPosition: AVCaptureDevice.Position) {
        subjectTracker.reset(cameraPosition: cameraPosition)
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = Date()
        if let update = subjectTracker.process(sampleBuffer: sampleBuffer, at: now) {
            publishTrackedSubject(update.subject)
        }

        guard now.timeIntervalSince(lastEncodedAt) >= 0.12 else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        lastEncodedAt = now

        let source = CIImage(cvPixelBuffer: pixelBuffer)
        let scale = min(240 / max(source.extent.width, 1), 1)
        let scaled = source.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale)
        )
        let normalized = scaled.transformed(
            by: CGAffineTransform(
                translationX: -scaled.extent.minX,
                y: -scaled.extent.minY
            )
        )
        guard let data = context.jpegRepresentation(
            of: normalized,
            colorSpace: colorSpace,
            options: [:]
        ) else {
            return
        }

        lock.lock()
        frames.append(BufferedFrame(date: now, data: data))
        let cutoff = now.addingTimeInterval(-1.6)
        frames.removeAll { $0.date < cutoff }
        if frames.count > 12 {
            frames.removeFirst(frames.count - 12)
        }
        lock.unlock()
    }

    private func publishTrackedSubject(_ subject: CameraTrackedSubject?) {
        subjectObserverLock.lock()
        let observer = subjectObserver
        subjectObserverLock.unlock()
        guard let observer else { return }
        Task { @MainActor in
            observer(subject)
        }
    }

    func snapshot(around shutterDate: Date) -> MicroTimeSlice {
        lock.lock()
        let selected = frames.filter {
            let offset = $0.date.timeIntervalSince(shutterDate)
            return offset >= -0.72 && offset <= 0.38
        }
        lock.unlock()

        guard !selected.isEmpty else { return .unavailable }
        let samples = selected.map {
            TemporalFrameSample(
                offsetFromShutter: $0.date.timeIntervalSince(shutterDate),
                jpegData: $0.data
            )
        }
        let first = selected.first?.date ?? shutterDate
        let last = selected.last?.date ?? first
        return MicroTimeSlice(
            duration: max(last.timeIntervalSince(first), 0),
            frames: samples
        )
    }
}

private struct LiveSubjectTrackingUpdate {
    let subject: CameraTrackedSubject?
}

/// Camera-queue Vision tracker. Saliency periodically nominates a semantic
/// subject; a fast sequence request follows that same region between discovery
/// passes. UI receives a smoothed box at a bounded cadence.
private final class LiveSubjectTracker: @unchecked Sendable {
    private let lock = NSLock()
    // Vision samples fast enough to follow a real camera subject, while the
    // persistent reticle receives only filtered geometry and never remounts.
    // A high processing cadence plus a near-immediate re-detection retry
    // makes the very first lock feel instant; the exponential smoothing in
    // ``CameraTrackedSubject/smoothed(toward:response:)`` keeps that extra
    // sampling from reading as jitter — more samples per second just means
    // the same easing curve resolves sooner.
    private let minimumProcessingInterval: TimeInterval = 1.0 / 24.0
    private let minimumDetectionInterval: TimeInterval = 0.05
    private let redetectionFrameInterval = 168
    private let minimumTrackingConfidence: VNConfidence = 0.38
    private let missingFrameTolerance = 30

    private var isEnabled = false
    private var cameraPosition: AVCaptureDevice.Position = .back
    private var lastProcessedAt = Date.distantPast
    private var lastDetectionAt = Date.distantPast
    private var framesSinceDetection = 0
    private var missingFrameCount = 0
    private var sequenceHandler = VNSequenceRequestHandler()
    private var trackingRequest: VNTrackObjectRequest?
    private var smoothedSubject: CameraTrackedSubject?
    private var lastDeliveredSubject: CameraTrackedSubject?

    func setEnabled(_ enabled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        isEnabled = enabled
        if !enabled {
            clearTracking()
        }
    }

    func reset(cameraPosition: AVCaptureDevice.Position) {
        lock.lock()
        defer { lock.unlock() }
        self.cameraPosition = cameraPosition
        clearTracking()
    }

    func process(
        sampleBuffer: CMSampleBuffer,
        at date: Date
    ) -> LiveSubjectTrackingUpdate? {
        lock.lock()
        defer { lock.unlock() }

        guard isEnabled else { return nil }
        guard date.timeIntervalSince(lastProcessedAt) >= minimumProcessingInterval else {
            return nil
        }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return recordMissingFrame()
        }
        lastProcessedAt = date

        let orientation: CGImagePropertyOrientation =
            cameraPosition == .front ? .leftMirrored : .right

        if trackingRequest == nil {
            guard date.timeIntervalSince(lastDetectionAt) >= minimumDetectionInterval else {
                return nil
            }
            lastDetectionAt = date
            return detectSubject(in: pixelBuffer, orientation: orientation)
        }
        if framesSinceDetection >= redetectionFrameInterval {
            lastDetectionAt = date
            return detectSubject(in: pixelBuffer, orientation: orientation)
        }
        return trackSubject(in: pixelBuffer, orientation: orientation)
    }

    private func detectSubject(
        in pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) -> LiveSubjectTrackingUpdate? {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: orientation
        )
        do {
            try handler.perform([request])
        } catch {
            framesSinceDetection = 0
            return nil
        }

        guard
            let candidates = request.results?.first?.salientObjects,
            let observation = candidates.max(by: {
                candidateScore($0) < candidateScore($1)
            })
        else {
            framesSinceDetection = 0
            return nil
        }

        sequenceHandler = VNSequenceRequestHandler()
        let seed = VNDetectedObjectObservation(boundingBox: observation.boundingBox)
        let tracker = VNTrackObjectRequest(detectedObjectObservation: seed)
        tracker.trackingLevel = .fast
        trackingRequest = tracker
        framesSinceDetection = 0
        return accept(
            boundingBox: observation.boundingBox,
            confidence: Double(observation.confidence)
        )
    }

    private func trackSubject(
        in pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) -> LiveSubjectTrackingUpdate? {
        guard let trackingRequest else {
            return recordMissingFrame()
        }
        do {
            try sequenceHandler.perform(
                [trackingRequest],
                on: pixelBuffer,
                orientation: orientation
            )
        } catch {
            self.trackingRequest = nil
            return recordMissingFrame()
        }

        guard
            let observation = trackingRequest.results?.first
                as? VNDetectedObjectObservation,
            observation.confidence >= minimumTrackingConfidence
        else {
            self.trackingRequest = nil
            return recordMissingFrame()
        }

        trackingRequest.inputObservation = observation
        framesSinceDetection += 1
        return accept(
            boundingBox: observation.boundingBox,
            confidence: Double(observation.confidence)
        )
    }

    private func accept(
        boundingBox: CGRect,
        confidence: Double
    ) -> LiveSubjectTrackingUpdate? {
        missingFrameCount = 0

        let candidate = CameraTrackedSubject(
            normalizedX: boundingBox.minX,
            normalizedY: 1 - boundingBox.maxY,
            normalizedWidth: boundingBox.width,
            normalizedHeight: boundingBox.height,
            confidence: confidence
        ).focused(
            horizontalScale: 0.36,
            verticalScale: 0.40,
            maximumWidth: 0.24,
            maximumHeight: 0.28
        )

        let resolved: CameraTrackedSubject
        if let previous = smoothedSubject {
            let dx = previous.center.x - candidate.center.x
            let dy = previous.center.y - candidate.center.y
            let distance = hypot(dx, dy)
            resolved = previous.smoothed(
                toward: candidate,
                response: CameraTrackedSubject.trackingResponse(
                    forCenterDistance: distance
                )
            )
        } else {
            resolved = candidate
        }
        smoothedSubject = resolved

        if let lastDeliveredSubject,
           !hasMeaningfulGeometryChange(
               from: lastDeliveredSubject,
               to: resolved
           ) {
            return nil
        }
        lastDeliveredSubject = resolved
        return LiveSubjectTrackingUpdate(subject: resolved)
    }

    private func recordMissingFrame() -> LiveSubjectTrackingUpdate? {
        missingFrameCount += 1
        guard missingFrameCount >= missingFrameTolerance else { return nil }
        trackingRequest = nil
        framesSinceDetection = 0
        // Keep the last accepted subject visible while Vision reacquires. A
        // temporary miss should look like a held camera lock, not a new flash.
        return nil
    }

    private func clearTracking() {
        lastProcessedAt = .distantPast
        lastDetectionAt = .distantPast
        framesSinceDetection = 0
        missingFrameCount = 0
        sequenceHandler = VNSequenceRequestHandler()
        trackingRequest = nil
        smoothedSubject = nil
        lastDeliveredSubject = nil
    }

    private func candidateScore(_ observation: VNRectangleObservation) -> Double {
        let box = observation.boundingBox
        let area = box.width * box.height
        let centerDistance = hypot(box.midX - 0.5, box.midY - 0.5)
        let preferredArea = 0.18
        let areaFit = max(0, 1 - abs(area - preferredArea) / preferredArea)

        let continuity: Double
        if let current = smoothedSubject {
            let currentVisionCenter = CGPoint(
                x: current.center.x,
                y: 1 - current.center.y
            )
            let distance = hypot(
                box.midX - currentVisionCenter.x,
                box.midY - currentVisionCenter.y
            )
            continuity = max(0, 1 - distance / 0.36)
        } else {
            continuity = max(0, 1 - centerDistance / 0.7)
        }

        return Double(observation.confidence) * 0.20
            + continuity * 0.74
            + areaFit * 0.06
    }

    private func hasMeaningfulGeometryChange(
        from previous: CameraTrackedSubject,
        to current: CameraTrackedSubject
    ) -> Bool {
        let centerDistance = hypot(
            previous.center.x - current.center.x,
            previous.center.y - current.center.y
        )
        let sizeDelta = max(
            abs(previous.normalizedWidth - current.normalizedWidth),
            abs(previous.normalizedHeight - current.normalizedHeight)
        )
        return centerDistance >= 0.010 || sizeDelta >= 0.018
    }
}

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: @Sendable (Result<Data, Error>) -> Void
    private var hasCompleted = false
    private let lock = NSLock()

    init(completion: @escaping @Sendable (Result<Data, Error>) -> Void) {
        self.completion = completion
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        finish {
            if let error {
                return .failure(error)
            }
            guard let data = photo.fileDataRepresentation() else {
                return .failure(LiveCameraError.captureFailed)
            }
            return .success(data)
        }
    }

    private func finish(_ result: () -> Result<Data, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !hasCompleted else { return }
        hasCompleted = true
        completion(result())
    }
}

private struct LiveCameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
    }
}

private final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard
            let connection = previewLayer.connection,
            connection.isVideoRotationAngleSupported(previewRotationAngle)
        else {
            return
        }
        let angle = previewRotationAngle
        if abs(connection.videoRotationAngle - angle) > 0.5 {
            connection.videoRotationAngle = angle
        }
    }

    private var previewRotationAngle: CGFloat {
        switch window?.windowScene?.interfaceOrientation {
        case .landscapeLeft: 0
        case .landscapeRight: 180
        case .portraitUpsideDown: 270
        case .portrait, .none, .unknown: 90
        @unknown default: 90
        }
    }
}
