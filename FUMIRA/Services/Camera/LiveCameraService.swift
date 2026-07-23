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
        }
    }
}

final class LiveCameraService: NSObject, CameraService, CameraPreviewFactory, @unchecked Sendable {
    let isLive = true

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.fumira.camera.session")
    private var isConfigured = false
    private var captureDelegates: [Int64: PhotoCaptureDelegate] = [:]

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

    func capturePhoto() async throws -> CapturedPhoto {
        try await startPreview()

        return try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                let settings = AVCapturePhotoSettings()
                settings.photoQualityPrioritization = .quality
                if photoOutput.supportedFlashModes.contains(.auto) {
                    settings.flashMode = .auto
                }

                if
                    let connection = photoOutput.connection(with: .video),
                    connection.isVideoRotationAngleSupported(90)
                {
                    connection.videoRotationAngle = 90
                }

                let uniqueID = settings.uniqueID
                let delegate = PhotoCaptureDelegate { [service = self] result in
                    service.sessionQueue.async { [service] in
                        service.captureDelegates[uniqueID] = nil
                    }
                    switch result {
                    case let .success(data):
                        let dimensions = Self.pixelDimensions(for: data)
                        continuation.resume(returning: CapturedPhoto(
                            data: data,
                            pixelWidth: dimensions.width,
                            pixelHeight: dimensions.height
                        ))
                    case let .failure(error):
                        continuation.resume(throwing: error)
                    }
                }
                captureDelegates[uniqueID] = delegate
                photoOutput.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }

    @MainActor
    func makePreview() -> AnyView {
        AnyView(LiveCameraPreviewView(session: session))
    }

    private func configureIfNeeded() throws {
        guard !isConfigured else { return }
        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            throw LiveCameraError.cameraUnavailable
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw LiveCameraError.inputUnavailable
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo

        guard session.canAddInput(input) else {
            throw LiveCameraError.inputUnavailable
        }
        session.addInput(input)

        guard session.canAddOutput(photoOutput) else {
            throw LiveCameraError.outputUnavailable
        }
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality
        isConfigured = true
    }

    private static func pixelDimensions(for data: Data) -> (width: Int, height: Int) {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any]
        else {
            return (0, 0)
        }
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        return (width, height)
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
            connection.isVideoRotationAngleSupported(90)
        else {
            return
        }
        connection.videoRotationAngle = 90
    }
}
