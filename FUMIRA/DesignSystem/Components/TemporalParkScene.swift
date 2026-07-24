import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct TemporalParkScene: View {
    let time: TimePosition
    var showBorder: Bool = false
    var namespace: Namespace.ID?
    var sceneID: String = "park-scene"
    var cornerRadius: CGFloat = PosterRadius.card
    var motionField: MotionFieldModel?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var t: Double { time.normalized }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                sky(in: size)
                    .flatParallax(motionField, depth: .back)
                backHill(in: size)
                    .flatParallax(motionField, depth: .back)
                midHill(in: size)
                    .flatParallax(motionField, depth: .mid)
                pathCone(in: size)
                    .flatParallax(motionField, depth: .mid)
                trees(in: size)
                    .flatParallax(motionField, depth: .front)
                monolith(in: size)
                    .flatParallax(motionField, depth: .front)
                timeOverlay(in: size)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                if showBorder {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(PosterPalette.leafGreen, lineWidth: 4)
                }
            }
            .modifier(SceneIdentityModifier(namespace: namespace, id: sceneID, reduceMotion: reduceMotion))
        }
        .accessibilityHidden(true)
    }

    // MARK: - Layers

    private func sky(in size: CGSize) -> some View {
        let pastBlend = max(0, -t)
        let futureBlend = max(0, t)
        return LinearGradient(
            colors: [
                skyTop(pastBlend: pastBlend, futureBlend: futureBlend),
                skyBottom(pastBlend: pastBlend, futureBlend: futureBlend)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func skyTop(pastBlend: Double, futureBlend: Double) -> Color {
        lerpColor(
            lerpColor(PosterPalette.sky, PosterPalette.skyPastTop, pastBlend * 0.7),
            PosterPalette.skyFutureTop,
            futureBlend * 0.65
        )
    }

    private func skyBottom(pastBlend: Double, futureBlend: Double) -> Color {
        lerpColor(
            lerpColor(PosterPalette.skySoft, PosterPalette.skyPastBottom, pastBlend * 0.6),
            PosterPalette.skyFutureBottom,
            futureBlend * 0.5
        )
    }

    private func backHill(in size: CGSize) -> some View {
        let offset = CGFloat(t) * size.width * 0.08
        return HillShape(peak: 0.42, width: 1.3)
            .fill(hillColor(depth: 0.3))
            .frame(width: size.width * 1.2, height: size.height * 0.55)
            .offset(x: offset, y: size.height * 0.18)
    }

    private func midHill(in size: CGSize) -> some View {
        let offset = CGFloat(-t) * size.width * 0.06
        return HillShape(peak: 0.55, width: 1.0)
            .fill(hillColor(depth: 0.6))
            .frame(width: size.width * 1.1, height: size.height * 0.48)
            .offset(x: offset, y: size.height * 0.28)
    }

    private func pathCone(in size: CGSize) -> some View {
        let width = size.width * (0.22 + abs(t) * 0.08)
        return Path { path in
            path.move(to: CGPoint(x: size.width * 0.5, y: size.height * 0.35))
            path.addLine(to: CGPoint(x: size.width * 0.5 - width / 2, y: size.height))
            path.addLine(to: CGPoint(x: size.width * 0.5 + width / 2, y: size.height))
            path.closeSubpath()
        }
        .fill(
            LinearGradient(
                colors: [
                    pathColor.opacity(0.15 + (1 - abs(t)) * 0.25),
                    pathColor.opacity(0.45)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var pathColor: Color {
        if t < -0.2 { return PosterPalette.mutedInk }
        if t > 0.2 { return PosterPalette.skyDeep }
        return PosterPalette.paperWhite
    }

    private func trees(in size: CGSize) -> some View {
        let density = max(0.3, 1 - abs(t) * 0.5)
        let scale = 0.85 + (1 - abs(t)) * 0.2
        return ZStack {
            tree(at: CGPoint(x: size.width * 0.18, y: size.height * 0.52), scale: scale * density, in: size)
            tree(at: CGPoint(x: size.width * 0.72, y: size.height * 0.48), scale: scale * 0.9, in: size)
            if density > 0.5 {
                tree(at: CGPoint(x: size.width * 0.42, y: size.height * 0.55), scale: scale * 0.75, in: size)
            }
            if t < -0.1 {
                tree(at: CGPoint(x: size.width * 0.58, y: size.height * 0.58), scale: scale * 0.65, in: size)
            }
        }
    }

    private func tree(at point: CGPoint, scale: Double, in size: CGSize) -> some View {
        let trunkW = 10 * scale
        let crownR = 28 * scale
        return ZStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(treeTrunkColor)
                .frame(width: trunkW, height: 36 * scale)
                .offset(y: crownR * 0.5)
            Circle()
                .fill(treeCrownColor)
                .frame(width: crownR * 2, height: crownR * 2)
                .offset(y: -crownR * 0.2)
        }
        .position(point)
        .opacity(0.4 + (1 - abs(t)) * 0.6)
    }

    private var treeTrunkColor: Color {
        t < 0 ? PosterPalette.mutedInk : PosterPalette.ink.opacity(0.7)
    }

    private var treeCrownColor: Color {
        if t < -0.3 { return PosterPalette.mutedInk.opacity(0.8) }
        if t > 0.3 { return PosterPalette.grassLight.opacity(0.75) }
        return PosterPalette.leafGreen
    }

    private func monolith(in size: CGSize) -> some View {
        let prominence = max(0, (t - 0.1) / 0.9)
        return RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [PosterPalette.sky, PosterPalette.skyDeep],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: size.width * 0.12, height: size.height * (0.25 + prominence * 0.15))
            .position(x: size.width * 0.62, y: size.height * 0.42)
            .opacity(prominence)
    }

    private func timeOverlay(in size: CGSize) -> some View {
        let pastOverlay = max(0, -t) * 0.25
        let futureOverlay = max(0, t) * 0.2
        return ZStack {
            if pastOverlay > 0 {
                PosterPalette.paper.opacity(pastOverlay)
            }
            if futureOverlay > 0 {
                PosterPalette.sky.opacity(futureOverlay * 0.35)
            }
        }
    }

    private func hillColor(depth: Double) -> Color {
        let nowGreen = depth < 0.45 ? PosterPalette.grassLight : PosterPalette.leafGreen
        let pastGreen = PosterPalette.mutedInk.opacity(0.7)
        let futureGreen = PosterPalette.skyDeep.opacity(0.55 + depth * 0.2)
        if t < 0 {
            return lerpColor(nowGreen, pastGreen, min(1, abs(t) * 1.2))
        }
        return lerpColor(nowGreen, futureGreen, min(1, t * 1.1))
    }

    private func lerpColor(_ a: Color, _ b: Color, _ amount: Double) -> Color {
        #if canImport(UIKit)
        let t = CGFloat(min(max(amount, 0), 1))
        let uiA = UIColor(a)
        let uiB = UIColor(b)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        uiA.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        uiB.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return Color(
            red: Double(r1 + (r2 - r1) * t),
            green: Double(g1 + (g2 - g1) * t),
            blue: Double(b1 + (b2 - b1) * t),
            opacity: Double(a1 + (a2 - a1) * t)
        )
        #else
        amount < 0.5 ? a : b
        #endif
    }
}

// MARK: - Shapes

private struct HillShape: Shape {
    var peak: CGFloat
    var width: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: 0, y: h))
        path.addQuadCurve(
            to: CGPoint(x: w, y: h),
            control: CGPoint(x: w * 0.5 * width, y: h * (1 - peak))
        )
        path.closeSubpath()
        return path
    }
}

private struct SceneIdentityModifier: ViewModifier {
    let namespace: Namespace.ID?
    let id: String
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if let namespace, !reduceMotion {
            content.matchedGeometryEffect(id: id, in: namespace)
        } else {
            content
        }
    }
}
