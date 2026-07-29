import SwiftUI

/// Full-screen flat poster backdrop for the connection screen.
/// Custom shapes only — no rounded card wrapper.
///
/// Layered park scenery: clouds + birds over a three-hill horizon, with flat
/// single-crown trees and meadow details anchoring the front slope.
/// Decorative planes ride the device-tilt motion field at their own depth.
struct ParkPosterBackdrop: View {
    var motionField: MotionFieldModel?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                // Slightly punchier lake blue than flat `sky` alone.
                LinearGradient(
                    colors: [
                        PosterPalette.skyDeep.opacity(0.42),
                        PosterPalette.sky,
                        PosterPalette.skySoft
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                cloud(at: CGPoint(x: size.width * 0.20, y: size.height * 0.115), scale: 1.0)
                    .spatialDepth(.background, motionField: motionField, reduceMotion: reduceMotion)

                cloud(at: CGPoint(x: size.width * 0.72, y: size.height * 0.315), scale: 0.6)
                    .spatialDepth(.background, motionField: motionField, reduceMotion: reduceMotion)

                birds(in: size)
                    .spatialDepth(.environment, motionField: motionField, reduceMotion: reduceMotion)

                backHill(in: size)
                    .spatialDepth(.background, motionField: motionField, reduceMotion: reduceMotion)

                distantTree(in: size)
                    .spatialDepth(.background, motionField: motionField, reduceMotion: reduceMotion)

                midHill(in: size)
                    .spatialDepth(.environment, motionField: motionField, reduceMotion: reduceMotion)

                grove(in: size)
                    .spatialDepth(.environment, motionField: motionField, reduceMotion: reduceMotion)

                frontHill(in: size)
                    .spatialDepth(.hero, motionField: motionField, reduceMotion: reduceMotion)

                meadowDetails(in: size)
                    .spatialDepth(.hero, motionField: motionField, reduceMotion: reduceMotion)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    // MARK: - Sky

    private func cloud(at point: CGPoint, scale: CGFloat) -> some View {
        let tint = PosterPalette.paperWhite
        return ZStack {
            Capsule()
                .fill(tint)
                .frame(width: 88, height: 26)
            Circle()
                .fill(tint)
                .frame(width: 34, height: 34)
                .offset(x: -18, y: -10)
            Circle()
                .fill(tint)
                .frame(width: 26, height: 26)
                .offset(x: 12, y: -12)
        }
        .scaleEffect(scale)
        .position(point)
    }

    private func birds(in size: CGSize) -> some View {
        let stroke = StrokeStyle(lineWidth: 2, lineCap: .round)
        let tint = PosterPalette.ink.opacity(0.38)
        return ZStack {
            PosterBirdMark()
                .stroke(tint, style: stroke)
                .frame(width: 22, height: 9)
                .position(x: size.width * 0.34, y: size.height * 0.21)
            PosterBirdMark()
                .stroke(tint, style: stroke)
                .frame(width: 16, height: 7)
                .position(x: size.width * 0.47, y: size.height * 0.165)
            PosterBirdMark()
                .stroke(tint, style: stroke)
                .frame(width: 12, height: 5)
                .position(x: size.width * 0.58, y: size.height * 0.235)
        }
    }

    // MARK: - Hills

    private func backHill(in size: CGSize) -> some View {
        PosterParkHorizonShape(
            leadingY: 0.58,
            controlX: 0.34,
            controlY: 0.48,
            trailingY: 0.64
        )
        .fill(PosterPalette.grassLight.opacity(0.88))
        .frame(width: size.width, height: size.height)
    }

    private func midHill(in size: CGSize) -> some View {
        PosterParkHorizonShape(
            leadingY: 0.74,
            controlX: 0.68,
            controlY: 0.62,
            trailingY: 0.80
        )
        .fill(PosterPalette.leafGreen.opacity(0.78))
        .frame(width: size.width, height: size.height)
    }

    private func frontHill(in size: CGSize) -> some View {
        PosterParkHorizonShape(
            leadingY: 0.90,
            controlX: 0.28,
            controlY: 0.80,
            trailingY: 0.98
        )
        .fill(PosterPalette.leafGreen)
        .frame(width: size.width, height: size.height)
    }

    // MARK: - Planting

    /// Single tree on the far ridge — depth cue on the right slope.
    private func distantTree(in size: CGSize) -> some View {
        let base = horizonPoint(
            t: 0.82,
            leadingY: 0.58, controlX: 0.34, controlY: 0.48, trailingY: 0.64,
            in: size
        )
        return tree(scale: 0.5, crown: PosterPalette.pine, trunk: PosterPalette.pine)
            .position(base)
    }

    /// Flat grove anchored along the mid-hill curve; keeps clear of the river.
    private func grove(in size: CGSize) -> some View {
        let hill: HorizonParams = (leadingY: 0.74, controlX: 0.68, controlY: 0.62, trailingY: 0.80)
        let crown = PosterPalette.pine
        let trunk = PosterPalette.pine
        return ZStack {
            tree(scale: 1.0, crown: crown, trunk: trunk)
                .position(horizonPoint(t: 0.20, leadingY: hill.leadingY, controlX: hill.controlX, controlY: hill.controlY, trailingY: hill.trailingY, in: size))
            tree(scale: 0.68, crown: crown, trunk: trunk)
                .position(horizonPoint(t: 0.42, leadingY: hill.leadingY, controlX: hill.controlX, controlY: hill.controlY, trailingY: hill.trailingY, in: size))
            tree(scale: 0.84, crown: crown, trunk: trunk)
                .position(horizonPoint(t: 0.62, leadingY: hill.leadingY, controlX: hill.controlX, controlY: hill.controlY, trailingY: hill.trailingY, in: size))
        }
    }

    private func tree(scale: CGFloat, crown: Color, trunk: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(trunk)
                .frame(width: 7, height: 32)
                .offset(y: 9)
            Circle()
                .fill(crown)
                .frame(width: 40, height: 40)
                .offset(y: -15)
        }
        .scaleEffect(scale)
    }

    /// Flowers and grass tufts on the left front slope only — keep the right
    /// side clear so the CTA sits on clean green without leaf clutter.
    private func meadowDetails(in size: CGSize) -> some View {
        let hill: HorizonParams = (leadingY: 0.90, controlX: 0.28, controlY: 0.80, trailingY: 0.98)
        let tuftStroke = StrokeStyle(lineWidth: 2, lineCap: .round)
        let tuftTint = PosterPalette.pine.opacity(0.3)
        return ZStack {
            flower(at: hillPoint(t: 0.14, hill: hill, in: size, drop: 18), diameter: 5, tint: PosterPalette.paper)
            flower(at: hillPoint(t: 0.24, hill: hill, in: size, drop: 10), diameter: 6, tint: PosterPalette.paper)
            flower(at: hillPoint(t: 0.33, hill: hill, in: size, drop: 20), diameter: 5, tint: PosterPalette.paper)

            PosterGrassTuft()
                .stroke(tuftTint, style: tuftStroke)
                .frame(width: 12, height: 10)
                .position(hillPoint(t: 0.10, hill: hill, in: size, drop: 4))
            PosterGrassTuft()
                .stroke(tuftTint, style: tuftStroke)
                .frame(width: 10, height: 8)
                .position(hillPoint(t: 0.20, hill: hill, in: size, drop: 5))
        }
    }

    private func flower(at point: CGPoint, diameter: CGFloat, tint: Color) -> some View {
        Circle()
            .fill(tint)
            .frame(width: diameter, height: diameter)
            .position(point)
    }

    // MARK: - Curve helpers

    private typealias HorizonParams = (leadingY: CGFloat, controlX: CGFloat, controlY: CGFloat, trailingY: CGFloat)

    private func hillPoint(t: CGFloat, hill: HorizonParams, in size: CGSize, drop: CGFloat) -> CGPoint {
        var point = horizonPoint(
            t: t,
            leadingY: hill.leadingY, controlX: hill.controlX, controlY: hill.controlY, trailingY: hill.trailingY,
            in: size
        )
        point.y += drop
        return point
    }

    /// Evaluates the top edge of a ``PosterParkHorizonShape`` so planted
    /// details stay glued to their hill at any screen size.
    private func horizonPoint(
        t: CGFloat,
        leadingY: CGFloat, controlX: CGFloat, controlY: CGFloat, trailingY: CGFloat,
        in size: CGSize
    ) -> CGPoint {
        let p0 = CGPoint(x: 0, y: size.height * leadingY)
        let control = CGPoint(x: size.width * controlX, y: size.height * controlY)
        let p1 = CGPoint(x: size.width, y: size.height * trailingY)
        let u = 1 - t
        return CGPoint(
            x: u * u * p0.x + 2 * u * t * control.x + t * t * p1.x,
            y: u * u * p0.y + 2 * u * t * control.y + t * t * p1.y
        )
    }
}

// MARK: - Shapes

struct PosterParkHorizonShape: Shape {
    var leadingY: CGFloat
    var controlX: CGFloat
    var controlY: CGFloat
    var trailingY: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.height * leadingY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.height * trailingY),
            control: CGPoint(x: rect.width * controlX, y: rect.height * controlY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Two-stroke gull silhouette — a light hand-drawn mark in the sky.
private struct PosterBirdMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control: CGPoint(x: rect.width * 0.28, y: rect.minY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.width * 0.72, y: rect.minY)
        )
        return path
    }
}

/// Three short blades fanning from one root — meadow texture.
private struct PosterGrassTuft: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.3))
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.25))
        return path
    }
}

#Preview {
    ParkPosterBackdrop()
}
