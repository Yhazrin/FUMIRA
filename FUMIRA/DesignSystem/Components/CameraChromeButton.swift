import SwiftUI
import UIKit

enum CameraChromeMetrics {
    static let topRowHeight: CGFloat = 44
    static let controlDiameter: CGFloat = 44
    static let compactFeedbackHeight: CGFloat = 36
    static let waveRailStageHeight: CGFloat = 100
    static let waveRailHeight: CGFloat = 132

    @MainActor
    static var activeWindowSafeAreaInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets ?? .zero
    }
}

struct CameraChromeButton: View {
    let systemImage: String
    var isEnabled: Bool = true
    var rotation: Angle = .zero
    var accessibilityLabelText: String
    var accessibilityHintText: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CameraChromeGlyph(
                systemImage: systemImage,
                isEnabled: isEnabled,
                rotation: rotation
            )
        }
        .clayButtonStyle(
            base: PosterEffects.cameraActionFill,
            rim: ClayPalette.orangeDepth,
            foreground: PosterEffects.cameraActionForeground,
            cornerRadius: ClayShape.pill,
            depth: 4
        )
        .disabled(!isEnabled)
        .frame(
            minWidth: CameraChromeMetrics.controlDiameter,
            minHeight: CameraChromeMetrics.controlDiameter
        )
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint(accessibilityHintText)
    }
}

struct CameraChromeGlyph: View {
    let systemImage: String
    var isEnabled: Bool = true
    var rotation: Angle = .zero

    var body: some View {
        Image(systemName: systemImage)
            .font(ClayTypography.label)
            .foregroundStyle(
                isEnabled
                    ? PosterEffects.cameraActionForeground
                    : PosterEffects.cameraActionForeground.opacity(0.35)
            )
            .rotationEffect(rotation)
            .frame(
                width: CameraChromeMetrics.controlDiameter,
                height: CameraChromeMetrics.controlDiameter
            )
            .contentShape(Circle())
    }
}

#Preview {
    ZStack {
        ClayPalette.orangeRim.ignoresSafeArea()
        HStack(spacing: ClaySpacing.xxl) {
            CameraChromeButton(
                systemImage: "photo.on.rectangle",
                accessibilityLabelText: "从相册导入"
            ) {}
            CameraChromeButton(
                systemImage: "arrow.triangle.2.circlepath",
                accessibilityLabelText: "翻转摄像头"
            ) {}
        }
    }
}
