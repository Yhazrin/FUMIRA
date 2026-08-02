import SwiftUI

/// Four soft corner marks around the subject Vision is following. Only the
/// corners are drawn — never a full rounded rectangle — so the lock reads as
/// quiet and precise rather than a boxed selection. The host stays a compact
/// 1:1 square so the lock stays quiet on the live preview.
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
                    color: ClayPalette.orange.opacity(0.94),
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

/// A one-shot, code-like scanline that sweeps once over the subject the
/// instant a lock is confirmed — never a lingering outline. Retriggers only
/// when confidence newly crosses the lock threshold, runs for about a
/// second, and clears itself completely when done.
struct SubjectLockScanEffect: View {
    let confidence: Double

    private static let lockedConfidenceThreshold: Double = 0.62
    private static let scanDuration: TimeInterval = 0.9
    private static let codeGlyphs = ["01", "10", "{ }", "</>", "0x2F", "if()", "##", "11", "->"]

    @State private var wasLocked = false
    @State private var scanStartedAt: Date?
    @State private var scanTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            if let scanStartedAt {
                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        let elapsed = timeline.date.timeIntervalSince(scanStartedAt)
                        let progress = min(max(elapsed / Self.scanDuration, 0), 1)
                        drawScan(progress: progress, size: size, context: &context)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: confidence) { _, newValue in
            let isLocked = newValue >= Self.lockedConfidenceThreshold
            if isLocked, !wasLocked {
                scanStartedAt = Date()
                scanTask?.cancel()
                scanTask = Task {
                    try? await Task.sleep(for: .seconds(Self.scanDuration))
                    if !Task.isCancelled {
                        scanStartedAt = nil
                    }
                }
            }
            wasLocked = isLocked
        }
        .onDisappear {
            scanTask?.cancel()
        }
    }

    private func drawScan(progress: Double, size: CGSize, context: inout GraphicsContext) {
        guard size.width > 0, size.height > 0 else { return }
        let lineY = size.height * progress
        let bandHeight = size.height * 0.24

        let bandRect = CGRect(
            x: 0,
            y: max(lineY - bandHeight, 0),
            width: size.width,
            height: min(bandHeight, lineY)
        )
        context.fill(
            Path(bandRect),
            with: .linearGradient(
                Gradient(colors: [ClayPalette.orange.opacity(0), ClayPalette.orange.opacity(0.3)]),
                startPoint: CGPoint(x: 0, y: bandRect.minY),
                endPoint: CGPoint(x: 0, y: bandRect.maxY)
            )
        )

        context.fill(
            Path(CGRect(x: 0, y: lineY - 4, width: size.width, height: 8)),
            with: .color(ClayPalette.orange.opacity(0.55))
        )
        context.fill(
            Path(CGRect(x: 0, y: lineY - 1, width: size.width, height: 2)),
            with: .color(PosterPalette.paperWhite.opacity(0.92))
        )

        // Fixed columns so the glyphs read as decoded, not randomly jittering.
        let columns = Self.codeGlyphs.count
        for (index, glyph) in Self.codeGlyphs.enumerated() {
            let columnX = size.width * (CGFloat(index) + 0.5) / CGFloat(columns)
            let glyphY = size.height * CGFloat(index % 3 + 1) / 4
            let distance = abs(glyphY - lineY)
            guard distance < bandHeight else { continue }
            let glyphOpacity = max(0, 1 - distance / bandHeight)
            context.draw(
                Text(glyph)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(ClayPalette.orange.opacity(glyphOpacity * 0.85)),
                at: CGPoint(x: columnX, y: glyphY)
            )
        }
    }
}

#Preview {
    ZStack {
        PosterPalette.skyDeep
        SubjectTrackingReticle(confidence: 0.91)
            .frame(width: 96, height: 96)
    }
}

