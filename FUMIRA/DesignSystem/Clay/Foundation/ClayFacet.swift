import SwiftUI

/// Chamfer tokens for the clay-cream identity.
///
/// The reference language is a matte clay object sitting on a cream ground:
/// soft in the mass, but with one crisp lit edge where the top face turns into
/// the side. `ClayShadow` alone renders the soft half; this renders the crisp
/// half. Everything here is a thin surface treatment — it never changes layout.
enum ClayFacet {

    // MARK: - Chamfer geometry

    /// Width of the flat band between the top face and the side wall.
    static let bandWidth: CGFloat = 1.5

    /// Hairline that catches the key light along the upper edge.
    static let lightLineWidth: CGFloat = 1

    /// Faceted corners read slightly tighter than a pure squircle. Multiply a
    /// `ClayShape` radius by this to keep one radius scale across the system.
    static let radiusScale: CGFloat = 0.82

    static func radius(_ soft: CGFloat) -> CGFloat {
        soft >= ClayShape.pill ? soft : (soft * radiusScale).rounded()
    }

    // MARK: - Chamfer band

    /// Top-left lit, bottom-right shaded. Narrow stops keep the turn crisp
    /// instead of dissolving into the face like a plain highlight gradient.
    static let bandStops: [Gradient.Stop] = [
        .init(color: .white.opacity(0.62), location: 0.00),
        .init(color: .white.opacity(0.30), location: 0.14),
        .init(color: .white.opacity(0.05), location: 0.44),
        .init(color: .black.opacity(0.05), location: 0.66),
        .init(color: .black.opacity(0.14), location: 1.00)
    ]

    static let bandStart = UnitPoint(x: 0.12, y: 0.0)
    static let bandEnd = UnitPoint(x: 0.88, y: 1.0)

    // MARK: - Top light line

    /// A single bright arc across the upper edge. Stops die out by 55% so the
    /// line stays an edge and never becomes a gloss sweep.
    static let lightLineStops: [Gradient.Stop] = [
        .init(color: .white.opacity(0.78), location: 0.00),
        .init(color: .white.opacity(0.34), location: 0.28),
        .init(color: .clear, location: 0.55),
        .init(color: .clear, location: 1.00)
    ]

    static let lightLineStart = UnitPoint.topLeading
    static let lightLineEnd = UnitPoint.bottomTrailing

    // MARK: - Matte face

    /// Very low-contrast wash across the face. Keeps the surface reading as
    /// unglazed clay rather than plastic.
    static let faceStops: [Gradient.Stop] = [
        .init(color: .white.opacity(0.10), location: 0.00),
        .init(color: .clear, location: 0.48),
        .init(color: .black.opacity(0.028), location: 1.00)
    ]

    static let grainOpacity: Double = 0.05

    // MARK: - Recessed wells

    /// Inner shadow for surfaces that sit below the ground plane — time rails,
    /// input troughs, screen insets.
    static let wellStops: [Gradient.Stop] = [
        .init(color: .black.opacity(0.16), location: 0.00),
        .init(color: .black.opacity(0.04), location: 0.30),
        .init(color: .clear, location: 0.62),
        .init(color: .white.opacity(0.24), location: 1.00)
    ]

    static let wellLineWidth: CGFloat = 2.5
}

// MARK: - Surface treatment

extension View {
    /// Applies the chamfer band, top light line, matte wash, and grain that
    /// together read as a clay object rather than a flat rounded rectangle.
    func clayFacet(
        cornerRadius: CGFloat,
        isRecessed: Bool = false,
        grain: Bool = true
    ) -> some View {
        modifier(
            ClayFacetModifier(
                cornerRadius: cornerRadius,
                isRecessed: isRecessed,
                grain: grain
            )
        )
    }
}

private struct ClayFacetModifier: ViewModifier {
    let cornerRadius: CGFloat
    let isRecessed: Bool
    let grain: Bool

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                LinearGradient(
                    stops: ClayFacet.faceStops,
                    startPoint: ClayFacet.bandStart,
                    endPoint: ClayFacet.bandEnd
                )
                .clipShape(shape)
                .allowsHitTesting(false)
            }
            .overlay {
                if grain {
                    ClayNoiseTexture(opacity: ClayFacet.grainOpacity)
                        .clipShape(shape)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                shape
                    .strokeBorder(
                        LinearGradient(
                            stops: isRecessed
                                ? ClayFacet.wellStops
                                : ClayFacet.bandStops,
                            startPoint: ClayFacet.bandStart,
                            endPoint: ClayFacet.bandEnd
                        ),
                        lineWidth: isRecessed
                            ? ClayFacet.wellLineWidth
                            : ClayFacet.bandWidth
                    )
                    .allowsHitTesting(false)
            }
            .overlay {
                if !isRecessed {
                    shape
                        .strokeBorder(
                            LinearGradient(
                                stops: ClayFacet.lightLineStops,
                                startPoint: ClayFacet.lightLineStart,
                                endPoint: ClayFacet.lightLineEnd
                            ),
                            lineWidth: ClayFacet.lightLineWidth
                        )
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                }
            }
    }
}
