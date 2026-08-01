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
        color: .black.opacity(0.33),
        radius: 13, x: 0, y: 11
    )

    /// Pressed / engaged shadow — shorter, tighter.
    static let pressed = ShadowSpec(
        color: .black.opacity(0.18),
        radius: 4, x: 0, y: 4
    )

    /// Subtle card shadow.
    static let card = ShadowSpec(
        color: .black.opacity(0.28),
        radius: 8, x: 0, y: 7
    )

    /// Small indicator / chip shadow.
    static let small = ShadowSpec(
        color: .black.opacity(0.28),
        radius: 2, x: 0, y: 2
    )

    // MARK: - Highlight gradient (top-left light source)

    static let highlightColors: [Color] = [
        .white.opacity(0.44),
        .white.opacity(0.10),
        .clear,
        .black.opacity(0.08)
    ]

    static let highlightStops: [Gradient.Stop] = [
        .init(color: .white.opacity(0.44), location: 0.00),
        .init(color: .white.opacity(0.10), location: 0.26),
        .init(color: .clear, location: 0.62),
        .init(color: .black.opacity(0.08), location: 1.00)
    ]

    static let highlightStart = UnitPoint(x: 0.0, y: 0.0)
    static let highlightEnd = UnitPoint(x: 1.0, y: 1.0)

    // MARK: - Edge stroke gradient (top light, bottom dark)

    static let edgeStrokeColors: [Color] = [
        .white.opacity(0.58),
        .white.opacity(0.10),
        .black.opacity(0.08)
    ]

    static let edgeStrokeStart = UnitPoint.top
    static let edgeStrokeEnd = UnitPoint.bottom
}
