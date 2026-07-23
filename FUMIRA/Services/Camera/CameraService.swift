import Foundation
import UIKit

enum CameraAuthorization: Sendable {
    case authorized
}

protocol CameraService: Sendable {
    func requestAuthorization() async throws -> CameraAuthorization
    func startPreview() async throws
    func stopPreview() async
    func capturePhoto() async throws -> CapturedPhoto
}

actor MockCameraService: CameraService {
    func requestAuthorization() async throws -> CameraAuthorization {
        .authorized
    }

    func startPreview() async throws {}

    func stopPreview() async {}

    func capturePhoto() async throws -> CapturedPhoto {
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
        return CapturedPhoto(data: data, pixelWidth: 1_200, pixelHeight: 1_600)
    }
}
