import SwiftUI

/// Full-screen flat poster backdrop for the connection screen.
/// Custom shapes only — no rounded card wrapper.
struct ParkPosterBackdrop: View {
    var motionField: MotionFieldModel?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                PosterPalette.sky

                skyMarks(in: size)
                    .flatParallax(motionField, depth: .back)

                backHill(in: size)
                    .flatParallax(motionField, depth: .back)

                midHill(in: size)
                    .flatParallax(motionField, depth: .mid)

                frontHill(in: size)
                    .flatParallax(motionField, depth: .front)

                riverCut(in: size)
                    .flatParallax(motionField, depth: .mid)

                foregroundMarks(in: size)
                    .flatParallax(motionField, depth: .front)

                botanicalMarks(in: size)
                    .flatParallax(motionField, depth: .front)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    // MARK: - Layers

    private func skyMarks(in size: CGSize) -> some View {
        ZStack {
            Circle()
                .fill(PosterPalette.paper.opacity(0.92))
                .frame(width: 76, height: 76)
                .position(x: size.width * 0.82, y: size.height * 0.18)

            Circle()
                .stroke(PosterPalette.leafGreen.opacity(0.7), lineWidth: 3)
                .frame(width: 22, height: 22)
                .position(x: size.width * 0.16, y: size.height * 0.13)

            RoundedRectangle(cornerRadius: 2)
                .fill(PosterPalette.skyDeep.opacity(0.55))
                .frame(width: 54, height: 4)
                .rotationEffect(.degrees(-8))
                .position(x: size.width * 0.22, y: size.height * 0.22)
        }
        .frame(width: size.width, height: size.height)
    }

    private func backHill(in size: CGSize) -> some View {
        PosterParkHorizonShape(
            leadingY: 0.61,
            controlX: 0.34,
            controlY: 0.50,
            trailingY: 0.67
        )
        .fill(PosterPalette.grassLight)
        .frame(width: size.width, height: size.height)
    }

    private func midHill(in size: CGSize) -> some View {
        PosterParkHorizonShape(
            leadingY: 0.79,
            controlX: 0.72,
            controlY: 0.66,
            trailingY: 0.84
        )
        .fill(PosterPalette.skyDeep.opacity(0.48))
        .frame(width: size.width, height: size.height)
    }

    private func frontHill(in size: CGSize) -> some View {
        PosterParkHorizonShape(
            leadingY: 0.94,
            controlX: 0.24,
            controlY: 0.82,
            trailingY: 1.02
        )
        .fill(PosterPalette.pine.opacity(0.92))
        .frame(width: size.width, height: size.height)
    }

    private func riverCut(in size: CGSize) -> some View {
        PosterParkRiverShape()
            .fill(PosterPalette.skySoft.opacity(0.9))
            .frame(width: size.width * 0.12, height: size.height * 0.2)
            .position(x: size.width * 0.84, y: size.height * 0.71)
    }

    private func foregroundMarks(in size: CGSize) -> some View {
        ZStack {
            Circle()
                .fill(PosterPalette.paper.opacity(0.88))
                .frame(width: 18, height: 18)
                .position(x: size.width * 0.1, y: size.height * 0.88)

            RoundedRectangle(cornerRadius: 2)
                .fill(PosterPalette.paper.opacity(0.75))
                .frame(width: 42, height: 4)
                .rotationEffect(.degrees(7))
                .position(x: size.width * 0.88, y: size.height * 0.91)
        }
    }

    private func botanicalMarks(in size: CGSize) -> some View {
        ZStack {
            PosterParkLeafMark()
                .fill(PosterPalette.leafGreen.opacity(0.85))
                .frame(width: 22, height: 30)
                .position(x: size.width * 0.14, y: size.height * 0.53)

            PosterParkLeafMark()
                .fill(PosterPalette.leafGreen.opacity(0.7))
                .frame(width: 18, height: 24)
                .rotationEffect(.degrees(-18))
                .position(x: size.width * 0.86, y: size.height * 0.48)
        }
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

private struct PosterParkRiverShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX * 0.72, y: rect.maxY),
            control: CGPoint(x: rect.maxX * 0.95, y: rect.midY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control: CGPoint(x: rect.minX * 0.2, y: rect.midY * 1.1)
        )
        path.closeSubpath()
        return path
    }
}

private struct PosterParkLeafMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.midY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.midY)
        )
        path.closeSubpath()
        return path
    }
}

#Preview {
    ParkPosterBackdrop()
}
