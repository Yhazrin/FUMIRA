import SwiftUI

/// A soft travelling reveal for the generated time image. It preserves the
/// photo's exact crop: only opacity inside its existing bounds is changed.
struct TimeRevealMask: View {
    let progress: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let clamped = FUMIRASpatialMotion.clamp(progress)
            if clamped >= 0.999 {
                Color.white
            } else if clamped > 0 {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: max(width * clamped - 30, 0))
                    LinearGradient(
                        colors: [.white, .white.opacity(0.72), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: min(30, width * clamped))
                    Spacer(minLength: 0)
                }
            } else {
                Color.clear
            }
        }
        .accessibilityHidden(true)
    }
}
