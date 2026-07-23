import SwiftUI

struct FutureCamBody: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PosterRadius.card, style: .continuous)
                .fill(PosterPalette.timeBlue)
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
                                    .stroke(PosterPalette.energyLime, lineWidth: 3)
                                    .frame(width: 52, height: 52)
                            }
                    }

                HStack(spacing: PosterSpacing.lg) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(PosterPalette.parkGreen)
                        .frame(width: 28, height: 8)
                    Circle()
                        .fill(PosterPalette.energyLime)
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
                    .stroke(PosterPalette.ink, lineWidth: 3)
                    .frame(width: 76, height: 76)
                Circle()
                    .fill(PosterPalette.energyLime)
                    .frame(width: 60, height: 60)
            }
            .frame(width: 88, height: 88)
            .contentShape(Circle())
        }
        .buttonStyle(PosterPressStyle())
        .accessibilityLabel("快门")
        .accessibilityHint("拍摄当前场景")
    }
}
