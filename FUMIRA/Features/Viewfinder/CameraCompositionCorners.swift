import SwiftUI

/// Four corner focus arcs painted **directly against the outside of the
/// camera crop**. Each corner is a 1/4 circle of the crop's own
/// ``cornerRadius``, centered at the crop's bounding corner, so the bracket
/// and the crop share the same curve — no straight arms, no L-shape.
///
/// Replaces the old full-perimeter white border. The four endpoints of each
/// arc land exactly on the crop's straight edges, making the bracket read
/// as an extension of the crop's rounded corner.
struct CameraCompositionCorners: View {
    let frame: CGRect
    let cornerRadius: CGFloat
    /// Stroke thickness. Apple uses ~3.5pt at 1× scale; we go a touch
    /// heavier to keep the visual weight of the arc consistent with the
    /// crop's white edge.
    var lineWidth: CGFloat = 4
    /// Bracket tint.
    var color: Color = PosterPalette.paperWhite.opacity(0.85)

    private var strokeStyle: StrokeStyle {
        StrokeStyle(
            lineWidth: lineWidth,
            lineCap: .round,
            lineJoin: .round
        )
    }

    var body: some View {
        Canvas { context, size in
            // The four 1/4 arcs. Each arc center sits at one of the crop's
            // bounding corners; the arc radius matches the crop's
            // ``cornerRadius`` so the curve continues the crop's edge exactly.
            //
            // Screen coordinates: y grows downward. Angles in `addArc` follow
            // standard math (counterclockwise from +x), so 0° = east, 90° =
            // south, 180° = west, 270° = north.
            //
            // Top-left: arc center (0, 0) — west → north, clockwise (the short
            // way through the top-left quadrant, OUTSIDE the crop's corner).
            // Top-right: arc center (size.width, 0) — north → east.
            // Bottom-right: arc center (size.width, size.height) — east → south.
            // Bottom-left: arc center (0, size.height) — south → west.
            let path = makePath(size: size)
            context.stroke(path, with: .color(color), style: strokeStyle)
        }
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(
            .timingCurve(0.22, 1, 0.36, 1, duration: 0.28),
            value: frame
        )
    }

    private func makePath(size: CGSize) -> Path {
        var p = Path()
        let r = cornerRadius

        // Top-left: arc center (0, 0), west (180°) → north (270°).
        p.move(to: CGPoint(x: -r, y: 0))
        p.addArc(
            center: .zero,
            radius: r,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: true
        )

        // Top-right: arc center (size.width, 0), north → east.
        let trX = size.width
        p.move(to: CGPoint(x: trX, y: -r))
        p.addArc(
            center: CGPoint(x: trX, y: 0),
            radius: r,
            startAngle: .degrees(270),
            endAngle: .degrees(0),
            clockwise: true
        )

        // Bottom-right: arc center (size.width, size.height), east → south.
        let brX = size.width
        let brY = size.height
        p.move(to: CGPoint(x: brX + r, y: brY))
        p.addArc(
            center: CGPoint(x: brX, y: brY),
            radius: r,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: true
        )

        // Bottom-left: arc center (0, size.height), south → west.
        let blY = size.height
        p.move(to: CGPoint(x: 0, y: blY + r))
        p.addArc(
            center: CGPoint(x: 0, y: blY),
            radius: r,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: true
        )

        return p
    }
}

#Preview("Outer brackets on photo") {
    ZStack {
        LinearGradient(
            colors: [Color.gray.opacity(0.7), Color.black],
            startPoint: .top,
            endPoint: .bottom
        )
        CameraCompositionCorners(
            frame: CGRect(x: 60, y: 60, width: 200, height: 280),
            cornerRadius: 18
        )
    }
    .frame(width: 320, height: 400)
}
