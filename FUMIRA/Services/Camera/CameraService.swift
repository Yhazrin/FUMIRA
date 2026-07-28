import Foundation
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

protocol CameraService: Sendable {
    func requestAuthorization() async throws -> CameraAuthorization
    func startPreview() async throws
    func stopPreview() async
    func capturePhoto(composition: CameraAspectRatio) async throws -> CapturedPhoto
}

actor MockCameraService: CameraService {
    func requestAuthorization() async throws -> CameraAuthorization {
        .authorized
    }

    func startPreview() async throws {}

    func stopPreview() async {}

    func capturePhoto(composition: CameraAspectRatio) async throws -> CapturedPhoto {
        let data = await MainActor.run {
            let size = CGSize(width: 1_200, height: 1_600)
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.jpegData(withCompressionQuality: 0.92) { context in
                let cg = context.cgContext
                UIColor(red: 0.49, green: 0.81, blue: 0.98, alpha: 1).setFill()
                cg.fill(CGRect(origin: .zero, size: size))

                UIColor(red: 0.39, green: 0.72, blue: 0.38, alpha: 1).setFill()
                cg.fillEllipse(in: CGRect(x: -300, y: 720, width: 1_300, height: 900))
                UIColor(red: 0.24, green: 0.60, blue: 0.30, alpha: 1).setFill()
                cg.fillEllipse(in: CGRect(x: 450, y: 650, width: 1_100, height: 1_000))

                UIColor(red: 0.95, green: 0.84, blue: 0.58, alpha: 1).setFill()
                let path = UIBezierPath()
                path.move(to: CGPoint(x: 510, y: 1_600))
                path.addLine(to: CGPoint(x: 690, y: 1_600))
                path.addLine(to: CGPoint(x: 630, y: 770))
                path.addLine(to: CGPoint(x: 570, y: 770))
                path.close()
                path.fill()

                for (x, y, scale) in [(250.0, 650.0, 1.0), (880.0, 720.0, 1.25), (520.0, 850.0, 0.72)] {
                    UIColor(red: 0.24, green: 0.34, blue: 0.16, alpha: 1).setFill()
                    cg.fill(CGRect(x: x - 16 * scale, y: y, width: 32 * scale, height: 250 * scale))
                    UIColor(red: 0.08, green: 0.47, blue: 0.23, alpha: 1).setFill()
                    cg.fillEllipse(in: CGRect(
                        x: x - 120 * scale,
                        y: y - 150 * scale,
                        width: 240 * scale,
                        height: 250 * scale
                    ))
                }
            }
        }
        return try PhotoImportAdapter.makeCapturedPhoto(from: data, composition: composition)
    }
}
