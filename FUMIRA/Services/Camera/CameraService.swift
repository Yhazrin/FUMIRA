import Foundation
import SwiftUI
import UIKit

enum CameraAuthorization: Sendable {
    case authorized
}

enum CameraLensPosition: Sendable, Equatable {
    case back
    case front
}

enum CameraFlashMode: Sendable, Equatable, CaseIterable {
    case off
    case on
    case auto

    var next: CameraFlashMode {
        switch self {
        case .off: .on
        case .on: .auto
        case .auto: .off
        }
    }

    var systemImageName: String {
        switch self {
        case .off: "bolt.slash.fill"
        case .on: "bolt.fill"
        case .auto: "bolt.badge.automatic.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .off: "闪光灯关闭"
        case .on: "闪光灯打开"
        case .auto: "闪光灯自动"
        }
    }
}

/// The intentional composition selected in the viewfinder. Ratios follow the
/// device's physical orientation, so a horizontal capture stays horizontal all
/// the way through image generation.
enum CameraAspectRatio: String, CaseIterable, Sendable, Equatable {
    case fullScreen
    case widescreen
    case classic
    case square

    var label: String {
        switch self {
        case .fullScreen: "全屏"
        case .widescreen: "16:9"
        case .classic: "3:4"
        case .square: "1:1"
        }
    }

    var accessibilityHint: String {
        switch self {
        case .fullScreen: "保留相机原始画幅"
        case .widescreen: "竖持时拍摄 9 比 16，横持时拍摄 16 比 9"
        case .classic: "竖持时拍摄 3 比 4，横持时拍摄 4 比 3"
        case .square: "拍摄 1 比 1 的方形画面"
        }
    }

    /// `nil` means that no crop is applied and the camera's native photo
    /// aspect is retained.
    func targetAspectRatio(for size: CGSize) -> CGFloat? {
        guard size.width > 0, size.height > 0 else { return nil }
        let isLandscape = size.width > size.height
        switch self {
        case .fullScreen:
            return nil
        case .widescreen:
            return isLandscape ? 16.0 / 9.0 : 9.0 / 16.0
        case .classic:
            return isLandscape ? 4.0 / 3.0 : 3.0 / 4.0
        case .square:
            return 1
        }
    }

    /// Cycles through the standard ratios. Used by the in-app Dynamic Island
    /// control so the chrome stays self-contained.
    var next: CameraAspectRatio {
        switch self {
        case .fullScreen: .widescreen
        case .widescreen: .classic
        case .classic: .square
        case .square: .fullScreen
        }
    }

    /// Points of vertical drag needed to cross one framing step on the
    /// viewfinder lower band. Dragging the card's lower edge down expands
    /// toward full frame; dragging it up tightens toward square.
    static let verticalAspectStepDistance: CGFloat = 48

    /// Resolves a vertical lower-band drag into the nearest supported framing.
    /// Positive translation (finger down) expands toward full frame; negative
    /// (finger up) tightens toward square. Mapping always begins at the ratio
    /// held when the gesture began.
    static func aspectRatio(
        afterVerticalTranslation translation: CGFloat,
        startingAt start: CameraAspectRatio
    ) -> CameraAspectRatio {
        guard translation.isFinite else { return start }
        let offset = Int(
            (translation / verticalAspectStepDistance).rounded(.towardZero)
        )
        return aspectRatio(offsetting: offset, startingAt: start)
    }

    /// Resolves a two-finger pinch into the nearest supported camera framing.
    /// Kept for VoiceOver step adjustments that still speak in magnification
    /// terms. Opening expands toward full frame; closing tightens toward square.
    static func aspectRatio(
        afterPinchMagnification magnification: CGFloat,
        startingAt start: CameraAspectRatio
    ) -> CameraAspectRatio {
        guard magnification.isFinite, magnification > 0 else { return start }

        let pinchStep: CGFloat = 1.16
        let logarithmicDistance = log(magnification) / log(pinchStep)
        let offset = Int(logarithmicDistance.rounded(.towardZero))
        return aspectRatio(offsetting: offset, startingAt: start)
    }

    private static func aspectRatio(
        offsetting offset: Int,
        startingAt start: CameraAspectRatio
    ) -> CameraAspectRatio {
        let startIndex = framingOrder.firstIndex(of: start) ?? 0
        let resolvedIndex = min(max(startIndex + offset, 0), framingOrder.count - 1)
        return framingOrder[resolvedIndex]
    }

    private static let framingOrder: [CameraAspectRatio] = [
        .square,
        .classic,
        .widescreen,
        .fullScreen,
    ]
}

struct CameraControlSnapshot: Sendable, Equatable {
    var lensPosition: CameraLensPosition
    var flashMode: CameraFlashMode
    var canSwitchCamera: Bool
    var supportsFlash: Bool
}

struct CameraZoomSnapshot: Sendable, Equatable {
    var factor: CGFloat
    var displayFactor: CGFloat
    var minimumFactor: CGFloat
    var maximumFactor: CGFloat

    static let unavailable = CameraZoomSnapshot(
        factor: 1,
        displayFactor: 1,
        minimumFactor: 1,
        maximumFactor: 1
    )

    var isAvailable: Bool {
        maximumFactor - minimumFactor > 0.01
    }

    func clamping(_ proposedFactor: CGFloat) -> CameraZoomSnapshot {
        let clampedFactor = min(max(proposedFactor, minimumFactor), maximumFactor)
        let multiplier = factor > 0 ? displayFactor / factor : 1
        return CameraZoomSnapshot(
            factor: clampedFactor,
            displayFactor: clampedFactor * multiplier,
            minimumFactor: minimumFactor,
            maximumFactor: maximumFactor
        )
    }
}

/// Optional live-camera controls. Mock / simulator cameras do not adopt this.
protocol CameraControlProviding: Sendable {
    func currentControls() async -> CameraControlSnapshot
    func switchCamera() async throws -> CameraControlSnapshot
    func setFlashMode(_ mode: CameraFlashMode) async throws -> CameraControlSnapshot
}

/// Continuous zoom shared by touch gestures and supported Camera Control hardware.
protocol CameraZoomProviding: Sendable {
    func currentZoom() async -> CameraZoomSnapshot
    func setZoomFactor(_ factor: CGFloat)

    @MainActor
    func setZoomObserver(
        _ observer: (@MainActor @Sendable (CameraZoomSnapshot) -> Void)?
    )
}

/// Starts the capture session only when camera access is already authorized.
/// This lets entry motion overlap session startup without presenting permission
/// UI ahead of the product's consent screen.
protocol CameraPreviewPrewarming: Sendable {
    func prewarmPreviewIfAuthorized() async
}

/// Optional live subject following. Implementations perform detection and
/// tracking off the main actor and publish only compact normalized geometry.
protocol CameraSubjectTrackingProviding: Sendable {
    @MainActor
    func setSubjectTrackingObserver(
        _ observer: (@MainActor @Sendable (CameraTrackedSubject?) -> Void)?
    )
}

protocol CameraService: Sendable {
    func requestAuthorization() async throws -> CameraAuthorization
    func startPreview() async throws
    func stopPreview() async
    func capturePhoto(composition: CameraAspectRatio) async throws -> CapturedPhoto
}

/// Optional short-lived context sampler. It never produces a user-facing video
/// and retains only a bounded set of low-resolution frames around the shutter.
protocol TemporalCameraSampling: Sendable {
    func microTimeSlice(around shutterDate: Date) async -> MicroTimeSlice
}

protocol CameraOpticalContextProviding: Sendable {
    func opticalContext() async -> TemporalOpticalContext
}

actor MockCameraService: CameraService, TemporalCameraSampling, CameraOpticalContextProviding, CameraControlProviding {
    private var mostRecentCaptureData: Data?
    private var lensPosition: CameraLensPosition = .back
    private var flashMode: CameraFlashMode = .auto

    func requestAuthorization() async throws -> CameraAuthorization {
        .authorized
    }

    func startPreview() async throws {}

    func stopPreview() async {}

    func currentControls() async -> CameraControlSnapshot {
        CameraControlSnapshot(
            lensPosition: lensPosition,
            flashMode: flashMode,
            canSwitchCamera: true,
            supportsFlash: true
        )
    }

    func switchCamera() async throws -> CameraControlSnapshot {
        lensPosition = lensPosition == .back ? .front : .back
        return await currentControls()
    }

    func setFlashMode(_ mode: CameraFlashMode) async throws -> CameraControlSnapshot {
        flashMode = mode
        return await currentControls()
    }

    func capturePhoto(composition: CameraAspectRatio) async throws -> CapturedPhoto {
        let data = try await MainActor.run {
            // Keep SwiftUI's logical-point canvas near an iPhone width so
            // fixed-size poster details match the live preview. Renderer scale
            // raises pixel density without shrinking those details.
            let logicalSize = CGSize(width: 400, height: 1_600.0 / 3.0)
            let renderer = ImageRenderer(
                content: TemporalParkScene(time: .now, cornerRadius: 0)
                    .frame(
                        width: logicalSize.width,
                        height: logicalSize.height
                    )
            )
            renderer.proposedSize = ProposedViewSize(logicalSize)
            renderer.scale = 3
            renderer.isOpaque = true
            guard
                let image = renderer.uiImage,
                let data = image.jpegData(compressionQuality: 0.92)
            else {
                throw PhotoImportAdapter.ImportError.invalidImage
            }
            return data
        }
        let photo = try PhotoImportAdapter.makeCapturedPhoto(
            from: data,
            composition: composition
        )
        mostRecentCaptureData = photo.data
        return photo
    }

    func microTimeSlice(around shutterDate: Date) async -> MicroTimeSlice {
        try? await Task.sleep(for: .milliseconds(280))
        guard let data = mostRecentCaptureData else { return .unavailable }
        let offsets: [TimeInterval] = [-0.48, -0.32, -0.16, 0, 0.14, 0.28]
        return MicroTimeSlice(
            duration: 0.76,
            frames: offsets.map {
                TemporalFrameSample(offsetFromShutter: $0, jpegData: data)
            }
        )
    }

    func opticalContext() async -> TemporalOpticalContext {
        TemporalOpticalContext(
            lensPosition: .back,
            focusPosition: 0.62,
            exposureDurationSeconds: 1 / 120,
            iso: 80,
            exposureTargetOffset: 0,
            zoomFactor: 1,
            lightCondition: .balanced
        )
    }
}
