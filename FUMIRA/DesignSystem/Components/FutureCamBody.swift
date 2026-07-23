import SwiftUI

struct FutureCamBody: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PosterRadius.card, style: .continuous)
                .fill(PosterPalette.sky)
                .frame(width: 220, height: 160)
                .shadow(color: PosterEffects.floating, radius: 12, y: 8)

            VStack(spacing: PosterSpacing.md) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(PosterPalette.paperWhite)
                    .frame(width: 140, height: 72)
                    .overlay {
                        Circle()
                            .fill(PosterPalette.ink)
                            .frame(width: 44, height: 44)
                            .overlay {
                                Circle()
                                    .stroke(PosterPalette.moss, lineWidth: 3)
                                    .frame(width: 52, height: 52)
                            }
                    }

                HStack(spacing: PosterSpacing.lg) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(PosterPalette.pine)
                        .frame(width: 28, height: 8)
                    Circle()
                        .fill(PosterPalette.moss)
                        .frame(width: 20, height: 20)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct ShutterButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(PosterEffects.cameraShutterRing, lineWidth: 4)
                    .frame(width: 78, height: 78)
                Circle()
                    .fill(PosterEffects.cameraShutterFill)
                    .frame(width: 62, height: 62)
                // Moss as ≤5% accent ring — never a fluorescent / yellow full fill.
                Circle()
                    .stroke(PosterPalette.moss.opacity(0.75), lineWidth: 2)
                    .frame(width: 54, height: 54)
            }
            .frame(width: 88, height: 88)
            .contentShape(Circle())
            .shadow(color: PosterEffects.floating, radius: 10, y: 4)
        }
        .buttonStyle(PosterPressStyle())
        .accessibilityLabel("快门")
        .accessibilityHint("拍摄当前场景")
    }
}
