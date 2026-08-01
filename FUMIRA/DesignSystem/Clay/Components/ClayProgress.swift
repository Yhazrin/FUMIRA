import SwiftUI

/// Clay progress — block-based progress bar with clay styling.
/// Replaces system spinners and thin progress bars.
struct ClayProgress: View {
    let progress: Double
    let fillColor: Color
    let trackColor: Color
    let height: CGFloat

    init(
        progress: Double,
        fillColor: Color = ClayPalette.lime,
        trackColor: Color = ClayPalette.charcoal.opacity(0.12),
        height: CGFloat = 22
    ) {
        self.progress = min(max(progress, 0), 1)
        self.fillColor = fillColor
        self.trackColor = trackColor
        self.height = height
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(trackColor)

                // Fill
                Capsule()
                    .fill(fillColor)
                    .frame(width: proxy.size.width * progress)
                    .overlay(alignment: .top) {
                        // Top highlight
                        Capsule()
                            .fill(.white.opacity(0.32))
                            .frame(height: height * 0.23)
                            .padding(.horizontal, 8)
                            .padding(.top, 4)
                    }
            }
        }
        .frame(height: height)
        .animation(ClayMotion.progressSpring, value: progress)
    }
}

/// Indeterminate block loader — a bouncing clay block.
struct ClayBlockLoader: View {
    let color: Color
    let size: CGFloat

    @State private var isAnimating = false

    init(
        color: Color = ClayPalette.orange,
        size: CGFloat = 12
    ) {
        self.color = color
        self.size = size
    }

    var body: some View {
        HStack(spacing: size * 0.6) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                    .fill(color)
                    .frame(width: size, height: size)
                    .scaleEffect(isAnimating ? 1.0 : 0.5)
                    .opacity(isAnimating ? 1.0 : 0.4)
                    .animation(
                        ClayMotion.toggleSpring
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                        value: isAnimating
                    )
            }
        }
        .onAppear { isAnimating = true }
    }
}
