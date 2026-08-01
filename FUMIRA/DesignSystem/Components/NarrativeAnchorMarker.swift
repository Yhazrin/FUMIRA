import SwiftUI

/// Four soft corner marks around the subject Vision is following.
/// Only the corners are drawn — never a full rounded rectangle — and the host
/// stays a compact 1:1 square so the lock stays quiet on the live preview.
struct SubjectTrackingReticle: View {
    let confidence: Double

    var body: some View {
        GeometryReader { proxy in
            let side = max(min(proxy.size.width, proxy.size.height), 1)
            let outerRect = CGRect(origin: .zero, size: proxy.size)
                .insetBy(dx: 1.5, dy: 1.5)
            let cornerRadius = min(max(side * 0.22, 10), 16)
            let armLength = min(max(side * 0.22, 10), 18)
            let innerInset = min(max(side * 0.12, 5), 10)
            let innerRect = outerRect.insetBy(dx: innerInset, dy: innerInset)
            let innerRadius = max(cornerRadius - innerInset * 0.35, 7)
            let innerArm = max(armLength - innerInset * 0.25, 8)

            Canvas { context, _ in
                drawRoundedCorners(
                    in: outerRect,
                    radius: cornerRadius,
                    armLength: armLength,
                    context: &context,
                    color: PosterPalette.paperWhite.opacity(0.72),
                    lineWidth: 1.25
                )
                drawRoundedCorners(
                    in: innerRect,
                    radius: innerRadius,
                    armLength: innerArm,
                    context: &context,
                    color: PosterPalette.actionBlue.opacity(0.94),
                    lineWidth: 2
                )

                let center = CGPoint(x: outerRect.midX, y: outerRect.midY)
                context.fill(
                    Path(
                        ellipseIn: CGRect(x: center.x - 1.5, y: center.y - 1.5, width: 3, height: 3)
                    ),
                    with: .color(PosterPalette.paperWhite)
                )
            }
        }
        // Confidence changes should not read as a flicker. Geometry owns the
        // motion; the lock artwork keeps one stable visual intensity.
        .opacity(0.94)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("viewfinder.subject-tracking")
        .accessibilityLabel("正在跟焦时间主体")
        .accessibilityValue("识别置信度 \(Int((confidence * 100).rounded()))%")
        .accessibilityHint("相机会自动跟随画面主体，快门仍可随时拍摄")
    }

    private func drawRoundedCorners(
        in rect: CGRect,
        radius: CGFloat,
        armLength: CGFloat,
        context: inout GraphicsContext,
        color: Color,
        lineWidth: CGFloat
    ) {
        let r = min(radius, min(rect.width, rect.height) * 0.45)
        let arm = max(armLength, r + 2)
        var path = Path()

        // Top leading
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + arm))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + r, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + arm, y: rect.minY))

        // Top trailing
        path.move(to: CGPoint(x: rect.maxX - arm, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + r),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + arm))

        // Bottom trailing
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - arm))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - r, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - arm, y: rect.maxY))

        // Bottom leading
        path.move(to: CGPoint(x: rect.minX + arm, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - r),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - arm))

        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        )
    }
}

#Preview {
    ZStack {
        PosterPalette.skyDeep
        SubjectTrackingReticle(confidence: 0.91)
            .frame(width: 96, height: 96)
    }
}
