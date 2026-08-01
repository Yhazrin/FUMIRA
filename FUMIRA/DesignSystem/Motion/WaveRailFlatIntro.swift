import SwiftUI

/// Flat-graphic entrance for the shutter wave rail.
///
/// Vertical bars are the rail's own language, so the intro rises from the
/// baseline like waveform strokes growing — never a horizontal hairline.
struct WaveRailFlatIntro: ViewModifier {
    var progress: CGFloat
    var reduceMotion: Bool

    func body(content: Content) -> some View {
        let clamped = FUMIRASpatialMotion.clamp(progress)
        let rise = FUMIRASpatialMotion.map(clamped, from: 0...0.72, to: 0...1)
        let settle = FUMIRASpatialMotion.map(clamped, from: 0.55...1, to: 0...1)

        content
            .mask {
                RoundedRectangle(cornerRadius: PosterRadius.control, style: .continuous)
                    .scaleEffect(
                        x: 1,
                        y: reduceMotion ? 1 : max(rise, 0.001),
                        anchor: .bottom
                    )
            }
            .opacity(reduceMotion ? 1 : (0.18 + 0.82 * rise))
            .scaleEffect(
                x: reduceMotion ? 1 : (0.98 + 0.02 * settle),
                y: reduceMotion ? 1 : (0.92 + 0.08 * rise),
                anchor: .bottom
            )
            .accessibilityHidden(clamped < 0.45)
    }
}

extension View {
    func waveRailFlatIntro(progress: CGFloat, reduceMotion: Bool) -> some View {
        modifier(WaveRailFlatIntro(progress: progress, reduceMotion: reduceMotion))
    }
}
