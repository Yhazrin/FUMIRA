import AVFoundation
import Foundation
import ImageIO
import SwiftUI
import UIKit

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

final class LiveCameraService: NSObject, CameraService, CameraControlProviding, CameraPreviewFactory, @unchecked Sendable {
    let isLive = true

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.fumira.camera.session")
    private var isConfigured = false
    private var captureDelegates: [Int64: PhotoCaptureDelegate] = [:]
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var currentPosition: AVCaptureDevice.Position = .back
    private var preferredFlashMode: AVCaptureDevice.FlashMode = .auto

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

        try await startPreview()
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

    func currentControls() async -> CameraControlSnapshot {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                continuation.resume(returning: makeSnapshot())
            }
        }
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
                    currentPosition = nextPosition
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

        guard session.canAddOutput(photoOutput) else {
            throw LiveCameraError.outputUnavailable
        }
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality
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
    }

    private func makeSnapshot() -> CameraControlSnapshot {
        CameraControlSnapshot(
            lensPosition: currentPosition == .front ? .front : .back,
            flashMode: CameraFlashMode(avFlashMode: preferredFlashMode),
            canSwitchCamera: Self.canSwitchBetweenCameras,
            supportsFlash: currentDeviceSupportsFlash
        )
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
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    /// AVCapture uses rotation angles, not interface orientation. Mapping this
    /// at the shutter keeps the JPEG's pixel axes aligned to how the person is
    /// holding the phone, including a landscape capture.
    private static func captureRotationAngle(for orientation: UIDeviceOrientation) -> CGFloat {
        switch orientation {
        case .landscapeLeft: 180
        case .landscapeRight: 0
        case .portraitUpsideDown: 270
        case .portrait, .faceUp, .faceDown, .unknown: 90
        @unknown default: 90
        }
    }
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
        uiView.previewLayer.session = session
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
        connection.videoRotationAngle = previewRotationAngle
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
