import SwiftUI

/// Clay app background — the cream ground every clay object sits on.
/// Apply to the outermost container of every screen.
struct ClayAppBackground: View {
    let color: Color
    let grainOpacity: Double

    init(
        color: Color = ClayPalette.cream,
        grainOpacity: Double = 0.10
    ) {
        self.color = color
        self.grainOpacity = grainOpacity
    }

    var body: some View {
        ZStack {
            color
                .ignoresSafeArea()

            // A single soft pool of light from the upper left, matching the
            // key light direction every clay surface is lit from.
            RadialGradient(
                colors: [
                    .white.opacity(0.55),
                    .clear
                ],
                center: UnitPoint(x: 0.22, y: 0.06),
                startRadius: 0,
                endRadius: 620
            )
            .ignoresSafeArea()
            .blendMode(.softLight)

            ClayNoiseTexture(opacity: grainOpacity)
                .ignoresSafeArea()
        }
    }
}

// MARK: - View extension

extension View {
    func clayBackground(
        color: Color = ClayPalette.cream,
        grainOpacity: Double = 0.10
    ) -> some View {
        self.background {
            ClayAppBackground(color: color, grainOpacity: grainOpacity)
        }
    }
}
