import SwiftUI

/// Clay app background — the root background with charcoal and grain.
/// Apply to the outermost container of every screen.
struct ClayAppBackground: View {
    let color: Color
    let grainOpacity: Double

    init(
        color: Color = ClayPalette.charcoal,
        grainOpacity: Double = 0.18
    ) {
        self.color = color
        self.grainOpacity = grainOpacity
    }

    var body: some View {
        ZStack {
            color
                .ignoresSafeArea()

            ClayNoiseTexture(opacity: grainOpacity)
                .ignoresSafeArea()
        }
    }
}

// MARK: - View extension

extension View {
    func clayBackground(
        color: Color = ClayPalette.charcoal,
        grainOpacity: Double = 0.18
    ) -> some View {
        self.background {
            ClayAppBackground(color: color, grainOpacity: grainOpacity)
        }
    }
}
