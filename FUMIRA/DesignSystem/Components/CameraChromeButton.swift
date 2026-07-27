import SwiftUI

enum CameraChromeMetrics {
    static let topRowHeight: CGFloat = 48
    static let islandSideCapsuleWidth: CGFloat = 60
    static let islandSideCapsuleHeight: CGFloat = 44
}

/// Lightweight circular control for immersive camera chrome — no thick cards.
struct CameraChromeButton: View {
    let systemImage: String
    var isEnabled: Bool = true
    var accessibilityLabelText: String
    var accessibilityHintText: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(
                    isEnabled
                        ? PosterPalette.paperWhite
                        : PosterPalette.paperWhite.opacity(0.35)
                )
                .frame(width: 48, height: 48)
                .background(PosterEffects.cameraChromeFill)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(PosterEffects.cameraChromeStroke, lineWidth: 1)
                }
                .contentShape(Circle())
        }
        .buttonStyle(PosterPressStyle())
        .disabled(!isEnabled)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint(accessibilityHintText)
    }
}

#Preview {
    ZStack {
        PosterPalette.skyDeep.ignoresSafeArea()
        HStack(spacing: PosterSpacing.lg) {
            CameraChromeButton(
                systemImage: "bolt.badge.automatic.fill",
                accessibilityLabelText: "闪光灯"
            ) {}
            CameraChromeButton(
                systemImage: "arrow.triangle.2.circlepath",
                accessibilityLabelText: "翻转镜头"
            ) {}
        }
    }
}
