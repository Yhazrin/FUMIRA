import SwiftUI

/// Procedural grain texture applied to all clay surfaces.
/// Avoids the pure-plastic look; gives a handcrafted matte feel.
struct ClayNoiseTexture: View {
    let opacity: Double

    init(opacity: Double = 0.14) {
        self.opacity = opacity
    }

    var body: some View {
        Canvas { context, size in
            for index in 0..<110 {
                let x = deterministic(index * 13 + 7) * size.width
                let y = deterministic(index * 29 + 11) * size.height
                let diameter = 0.8 + deterministic(index * 17 + 5) * 2.2
                let isLight = index.isMultiple(of: 3)
                let color = isLight ? Color.white : Color.black
                let rect = CGRect(x: x, y: y, width: diameter, height: diameter)
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(color.opacity(opacity * (isLight ? 0.24 : 0.14)))
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func deterministic(_ seed: Int) -> CGFloat {
        let value = sin(Double(seed) * 12.9898) * 43758.5453
        return CGFloat(value - floor(value))
    }
}
