import SwiftUI

/// Clay time dial — continuous nonlinear time selector ±100 years.
/// Replaces the default Slider with a clay-styled rotary/linear control.
struct ClayTimeDial: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let label: String
    let formatValue: (Double) -> String

    @State private var isDragging = false
    @State private var dragStart: CGFloat = 0
    @State private var valueAtDragStart: Double = 0

    init(
        value: Binding<Double>,
        range: ClosedRange<Double> = -100...100,
        label: String = "TIME OFFSET",
        formatValue: @escaping (Double) -> String = { v in
            let yrs = Int(v)
            if yrs == 0 { return "NOW" }
            return yrs > 0 ? "+\(yrs)y" : "\(yrs)y"
        }
    ) {
        self._value = value
        self.range = range
        self.label = label
        self.formatValue = formatValue
    }

    var body: some View {
        VStack(spacing: ClaySpacing.stackTight) {
            // Label
            HStack {
                Text(label)
                    .font(ClayTypography.monoTiny)
                    .foregroundStyle(ClayPalette.textMuted)
                Spacer()
                Text(formatValue(value))
                    .font(ClayTypography.monoLarge)
                    .foregroundStyle(ClayPalette.orange)
            }

            // Dial track
            GeometryReader { proxy in
                let width = proxy.size.width
                let progress = normalizedProgress()

                ZStack(alignment: .leading) {
                    // Track background
                    Capsule()
                        .fill(ClayPalette.charcoal.opacity(0.12))

                    // Fill
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [ClayPalette.orange, ClayPalette.yellow],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: width * abs(progress))

                    // Thumb
                    Circle()
                        .fill(ClayPalette.orange)
                        .frame(width: 32, height: 32)
                        .overlay {
                            Circle()
                                .fill(.white.opacity(0.32))
                                .frame(width: 12, height: 12)
                                .offset(y: -2)
                        }
                        .shadow(
                            color: isDragging
                                ? ClayShadow.pressed.color
                                : ClayShadow.rest.color,
                            radius: isDragging
                                ? ClayShadow.pressed.radius
                                : ClayShadow.rest.radius,
                            x: 0,
                            y: isDragging
                                ? ClayShadow.pressed.y
                                : ClayShadow.rest.y
                        )
                        .scaleEffect(isDragging ? 1.1 : 1.0)
                        .offset(x: width * progress - 16)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { drag in
                                    if !isDragging {
                                        isDragging = true
                                        dragStart = drag.startLocation.x
                                        valueAtDragStart = value
                                    }
                                    let delta = drag.location.x - dragStart
                                    let deltaProgress = delta / width
                                    let rangeSpan = range.upperBound - range.lowerBound
                                    let newValue = valueAtDragStart + deltaProgress * rangeSpan
                                    value = min(max(newValue, range.lowerBound), range.upperBound)
                                }
                                .onEnded { _ in
                                    isDragging = false
                                }
                        )

                    // Center marker (NOW)
                    if range.contains(0) {
                        let centerProgress = (0 - range.lowerBound) / (range.upperBound - range.lowerBound)
                        Rectangle()
                            .fill(ClayPalette.charcoal.opacity(0.3))
                            .frame(width: 2, height: 12)
                            .offset(x: width * centerProgress - 1)
                    }
                }
            }
            .frame(height: 44)
        }
        .animation(ClayMotion.hoverSpring, value: isDragging)
    }

    private func normalizedProgress() -> Double {
        let span = range.upperBound - range.lowerBound
        return (value - range.lowerBound) / span
    }
}
