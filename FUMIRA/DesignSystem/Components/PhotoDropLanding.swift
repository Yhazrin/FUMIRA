import SwiftUI

/// Legacy bordered drop landing used by early matched-geometry experiments.
///
/// The persistent ``HeroPhotoSurface`` in ``RootView`` now owns capture continuity.
/// Prefer ``HeroPhotoSlot`` from pipeline pages. Kept for previews / fallback only.
struct PhotoDropLanding: View {
    let photo: CapturedPhoto?
    var aspectRatio: CGFloat
    var maximumHeight: CGFloat = 400
    var namespace: Namespace.ID?
    /// Optional overlay (scan line, caption chip) clipped to the photo bounds.
    var overlay: (() -> AnyView)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var angle: Double = 0
    @State private var shadowLift: CGFloat = 18
    @State private var didSettle = false
    /// Bumped once when the paper comes to rest so a one-shot sensory + symbol
    /// cue can fire. Reset between drops so a fresh photo triggers again.
    @State private var landingToken: Int = 0

    var body: some View {
        PhotoAspectContainer(
            aspectRatio: aspectRatio,
            maximumHeight: maximumHeight
        ) {
            ZStack {
                CapturedPhotoView(photo: photo, cornerRadius: 0)

                if let overlay {
                    overlay()
                }
            }
            .clipShape(Rectangle())
            .compositingGroup()
            .shadow(
                color: PosterPalette.ink.opacity(0.28),
                radius: shadowLift * 0.45,
                y: shadowLift * 0.35
            )
        }
        .padding(.horizontal, PosterSpacing.sm)
        .rotationEffect(.degrees(angle))
        .modifier(
            CapturedPhotoMatchedGeometry(
                namespace: namespace,
                reduceMotion: reduceMotion
            )
        )
        .accessibilityElement(children: .contain)
        .onAppear(perform: settleTiltIfNeeded)
        .posterSensoryFeedback(trigger: landingToken, .success)
        .posterSymbolBounce(trigger: landingToken)
    }

    private func settleTiltIfNeeded() {
        guard !didSettle else { return }
        didSettle = true

        let restTilt = Self.randomRestTilt()
        if reduceMotion {
            angle = restTilt
            shadowLift = 10
            landingToken &+= 1
            return
        }

        // Start already near the resting pose so matched-geometry travel stays
        // readable; then ease into the hung tilt.
        angle = restTilt + Double.random(in: -18...18)
        shadowLift = 22
        withAnimation(.timingCurve(0.16, 0.88, 0.18, 1, duration: PosterMotion.page)) {
            angle = restTilt
            shadowLift = 10
            landingToken &+= 1
        }
    }

    private static func randomRestTilt() -> Double {
        let magnitude = Double.random(in: 2.2...5.4)
        return Bool.random() ? magnitude : -magnitude
    }
}

extension PhotoDropLanding {
    init<Overlay: View>(
        photo: CapturedPhoto?,
        aspectRatio: CGFloat,
        maximumHeight: CGFloat = 400,
        namespace: Namespace.ID? = nil,
        @ViewBuilder overlay: @escaping () -> Overlay
    ) {
        self.photo = photo
        self.aspectRatio = aspectRatio
        self.maximumHeight = maximumHeight
        self.namespace = namespace
        self.overlay = { AnyView(overlay()) }
    }
}

/// Shared matched-geometry bridge for shutter feedback → reading page.
struct CapturedPhotoMatchedGeometry: ViewModifier {
    var namespace: Namespace.ID?
    var reduceMotion: Bool

    func body(content: Content) -> some View {
        if let namespace, !reduceMotion {
            content.matchedGeometryEffect(id: "camera-photo", in: namespace)
        } else {
            content
        }
    }
}

#Preview("Photo drop") {
    ZStack {
        PosterPalette.skyDeep.ignoresSafeArea()
        PhotoDropLanding(
            photo: nil,
            aspectRatio: 3.0 / 4.0,
            maximumHeight: 360
        )
        .padding()
    }
}
