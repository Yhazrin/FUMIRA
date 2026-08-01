import SwiftUI
import UIKit

enum CameraChromeMetrics {
    static let topRowHeight: CGFloat = 44
    static let controlDiameter: CGFloat = 44
    static let compactFeedbackHeight: CGFloat = 36
    /// Fixed optical bounds for the morphing shutter + waveform. Geometry
    /// placement uses the same height so it can decide whether the control
    /// fits in the exposed blue body or must float over the preview.
    static let waveRailStageHeight: CGFloat = 100
    static let waveRailHeight: CGFloat = 132

    /// Root camera surfaces are full-bleed, so their local GeometryReader
    /// reports zero safe-area insets. Read the system-owned window geometry
    /// once here so live chrome and its capture afterimage cannot disagree.
    @MainActor
    static var activeWindowSafeAreaInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets ?? .zero
    }
}

/// Solid circular camera action: Doraemon blue, white SF Symbol, no glass card.
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
        .buttonStyle(PosterPressStyle())
        .disabled(!isEnabled)
        .frame(
            minWidth: CameraChromeMetrics.controlDiameter,
            minHeight: CameraChromeMetrics.controlDiameter
        )
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint(accessibilityHintText)
    }
}

/// Shared visual surface for the viewfinder's 44pt camera controls. Keeping
/// the glyph separate lets `PhotosPicker` use the exact same button geometry.
struct CameraChromeGlyph: View {
    let systemImage: String
    var isEnabled: Bool = true
    var rotation: Angle = .zero

    var body: some View {
        Image(systemName: systemImage)
            .font(PosterTypography.label)
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
            .background {
                Circle()
                    .fill(PosterEffects.cameraActionFill)
            }
            .clipShape(Circle())
            .contentShape(Circle())
    }
}

#Preview {
    ZStack {
        PosterPalette.skyDeep.ignoresSafeArea()
        HStack(spacing: PosterSpacing.lg) {
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
