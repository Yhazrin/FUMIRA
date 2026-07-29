import SwiftUI

struct TimeAnchorReticle: View {
    let motion: CaptureMotionModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { index in
                Capsule()
                    .fill(segmentColor(index: index))
                    .frame(width: segmentWidth(index: index), height: 2)
                    .offset(x: reticleRadius)
                    .rotationEffect(.degrees(Double(index) * 30))
            }

            Circle()
                .stroke(
                    PosterPalette.paperWhite.opacity(0.26),
                    style: StrokeStyle(lineWidth: 1, dash: [2, 5])
                )
                .frame(width: 56, height: 56)

            Circle()
                .fill(
                    motion.isAnchored
                        ? PosterPalette.bellYellow
                        : PosterPalette.paperWhite.opacity(0.82)
                )
                .frame(width: motion.isAnchored ? 8 : 5, height: motion.isAnchored ? 8 : 5)
        }
        .frame(width: 112, height: 112)
        .offset(
            x: reduceMotion ? 0 : CGFloat(motion.roll) * 16,
            y: reduceMotion ? 0 : CGFloat(-motion.pitch) * 12
        )
        .animation(PosterMotion.interaction, value: motion.isAnchored)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("时间定锚")
        .accessibilityValue(
            motion.isAnchored
                ? "已稳定"
                : "稳定度 \(Int(motion.stability * 100))%"
        )
        .accessibilityHint("定锚可以帮助获得更稳定的画面，但不会阻止拍摄")
    }

    private var reticleRadius: CGFloat {
        45 - CGFloat(motion.anchorProgress) * 10
    }

    private func segmentColor(index: Int) -> Color {
        let activeCount = Int((motion.anchorProgress * 12).rounded(.down))
        if motion.isAnchored {
            return PosterPalette.bellYellow
        }
        if index < activeCount {
            return PosterPalette.paperWhite
        }
        return PosterPalette.paperWhite.opacity(0.34)
    }

    private func segmentWidth(index: Int) -> CGFloat {
        let breathing = 1 - CGFloat(motion.stability) * 0.28
        return (index.isMultiple(of: 3) ? 15 : 10) * breathing
    }
}
