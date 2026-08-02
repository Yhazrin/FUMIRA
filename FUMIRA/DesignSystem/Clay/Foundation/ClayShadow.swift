import SwiftUI

/// Shadow, depth, and lighting tokens for Clay OS.
/// Simulates soft contact shadows and top highlights of a clay surface.
enum ClayShadow {

    // MARK: - Shadow presets

    struct ShadowSpec {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    /// Default resting shadow for elevated clay surfaces.
    static let rest = ShadowSpec(
        color: .black.opacity(0.22),
        radius: 11, x: 0, y: 8
    )

    /// Pressed / engaged shadow — shorter, tighter.
    static let pressed = ShadowSpec(
        color: .black.opacity(0.13),
        radius: 3, x: 0, y: 2
    )

    /// Subtle card shadow.
    static let card = ShadowSpec(
        color: .black.opacity(0.17),
        radius: 11, x: 0, y: 7
    )

    /// Small indicator / chip shadow.
    static let small = ShadowSpec(
        color: .black.opacity(0.18),
        radius: 4, x: 0, y: 3
    )

    /// Buttons read as flat molded faces, not floating objects — a faint
    /// contact shadow only, no soft ambient halo underneath.
    static let buttonRest = ShadowSpec(
        color: .black.opacity(0.09),
        radius: 3, x: 0, y: 2
    )

    static let buttonPressed = ShadowSpec(
        color: .black.opacity(0.05),
        radius: 1.5, x: 0, y: 1
    )

    // MARK: - Layered shadows (cream ground)

    /// A clay object on a cream ground casts two shadows: a wide soft ambient
    /// and a tight dark contact patch. One shadow alone reads either floaty or
    /// pasted on; the pair is what makes the object feel physically seated.
    struct LayeredSpec {
        let ambient: ShadowSpec
        let contact: ShadowSpec
    }

    static let seatedRest = LayeredSpec(
        ambient: ShadowSpec(color: .black.opacity(0.085), radius: 24, x: 0, y: 14),
        contact: ShadowSpec(color: .black.opacity(0.155), radius: 5, x: 0, y: 3)
    )

    static let seatedCard = LayeredSpec(
        ambient: ShadowSpec(color: .black.opacity(0.070), radius: 30, x: 0, y: 18),
        contact: ShadowSpec(color: .black.opacity(0.130), radius: 6, x: 0, y: 4)
    )

    static let seatedPressed = LayeredSpec(
        ambient: ShadowSpec(color: .black.opacity(0.050), radius: 10, x: 0, y: 4),
        contact: ShadowSpec(color: .black.opacity(0.115), radius: 2, x: 0, y: 1)
    )

    static let seatedSmall = LayeredSpec(
        ambient: ShadowSpec(color: .black.opacity(0.075), radius: 12, x: 0, y: 7),
        contact: ShadowSpec(color: .black.opacity(0.130), radius: 3, x: 0, y: 2)
    )

    // MARK: - Highlight gradient (top-left light source)

    static let highlightColors: [Color] = [
        .white.opacity(0.34),
        .white.opacity(0.12),
        .clear,
        .black.opacity(0.045)
    ]

    static let highlightStops: [Gradient.Stop] = [
        .init(color: .white.opacity(0.34), location: 0.00),
        .init(color: .white.opacity(0.13), location: 0.32),
        .init(color: .clear, location: 0.70),
        .init(color: .black.opacity(0.045), location: 1.00)
    ]

    static let highlightStart = UnitPoint(x: 0.0, y: 0.0)
    static let highlightEnd = UnitPoint(x: 1.0, y: 1.0)

    // MARK: - Edge stroke gradient (top light, bottom dark)

    static let edgeStrokeColors: [Color] = [
        .white.opacity(0.42),
        .white.opacity(0.12),
        .black.opacity(0.055)
    ]

    static let edgeStrokeStart = UnitPoint.top
    static let edgeStrokeEnd = UnitPoint.bottom
}

// MARK: - Layered shadow modifier

extension View {
    /// Applies ambient + contact shadow as one step.
    func clayShadow(_ spec: ClayShadow.LayeredSpec) -> some View {
        self
            .shadow(
                color: spec.ambient.color,
                radius: spec.ambient.radius,
                x: spec.ambient.x,
                y: spec.ambient.y
            )
            .shadow(
                color: spec.contact.color,
                radius: spec.contact.radius,
                x: spec.contact.x,
                y: spec.contact.y
            )
    }
}
