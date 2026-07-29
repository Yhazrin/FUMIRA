import SwiftUI

/// Thin printed rings that travel across the photo during a result reveal.
/// This is a semantic time-change cue, intentionally lighter than a shader.
struct TimeRevealRipple: View {
    let progress: CGFloat
    let reduceMotion: Bool

    var body: some View {
        if !reduceMotion {
            GeometryReader { proxy in
                let p = FUMIRASpatialMotion.clamp(progress)
                let diameter = hypot(proxy.size.width, proxy.size.height)
                ZStack {
                    ForEach(0..<3, id: \.self) { index in
                        let lag = CGFloat(index) * 0.16
                        let ring = FUMIRASpatialMotion.map(
                            p,
                            from: lag...(min(lag + 0.56, 1)),
                            to: 0...1
                        )
                        Circle()
                            .stroke(
                                PosterPalette.paperWhite.opacity((1 - ring) * 0.32),
                                lineWidth: 1.5
                            )
                            .frame(
                                width: max(1, diameter * ring),
                                height: max(1, diameter * ring)
                            )
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
