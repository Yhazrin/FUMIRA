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
