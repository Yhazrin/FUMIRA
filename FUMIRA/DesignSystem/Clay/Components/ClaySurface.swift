import SwiftUI

/// Base clay surface with rim, chamfer, highlight, grain, and seated shadow.
/// All clay components build on this.
struct ClaySurface: View {

    /// How the edge is rendered. `soft` is the original pure-squircle look;
    /// `faceted` adds the chamfer band and top light line of the clay-cream
    /// identity — soft mass, one crisp lit edge.
    enum Profile {
        case soft
        case faceted
        /// Cut into the ground rather than raised above it.
        case recessed
    }

    let base: Color
    let rim: Color
    let cornerRadius: CGFloat
    let profile: Profile
    let shadowSpec: ClayShadow.ShadowSpec
    let layeredShadow: ClayShadow.LayeredSpec?

    init(
        base: Color = ClayPalette.warmWhite,
        rim: Color = ClayPalette.warmWhiteRim,
        cornerRadius: CGFloat = ClayShape.card,
        profile: Profile = .faceted,
        shadow: ClayShadow.ShadowSpec = ClayShadow.rest,
        layeredShadow: ClayShadow.LayeredSpec? = ClayShadow.seatedRest
    ) {
        self.base = base
        self.rim = rim
        self.cornerRadius = cornerRadius
        self.profile = profile
        self.shadowSpec = shadow
        self.layeredShadow = layeredShadow
    }

    private var resolvedRadius: CGFloat {
        profile == .soft ? cornerRadius : ClayFacet.radius(cornerRadius)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: resolvedRadius, style: .continuous)
    }

    var body: some View {
        switch profile {
        case .soft:
            softBody
        case .faceted:
            facetedBody
        case .recessed:
            recessedBody
        }
    }

    // MARK: - Raised, chamfered

    @ViewBuilder
    private var facetedBody: some View {
        let stack = ZStack {
            shape
                .fill(rim)
                .offset(y: ClayShape.rimOffset)

            shape
                .fill(base)
                .clayFacet(cornerRadius: resolvedRadius)
        }

        if let layeredShadow {
            stack.clayShadow(layeredShadow)
        } else {
            stack
        }
    }

    // MARK: - Cut into the ground

    private var recessedBody: some View {
        shape
            .fill(base)
            .clayFacet(cornerRadius: resolvedRadius, isRecessed: true)
    }

    // MARK: - Legacy soft profile

    private var softBody: some View {
        ZStack {
            // Rim (darker lower layer)
            shape
                .fill(rim)
                .offset(y: ClayShape.rimOffset)

            // Main face
            shape
                .fill(base)
                // Top highlight gradient
                .overlay {
                    LinearGradient(
                        stops: ClayShadow.highlightStops,
                        startPoint: ClayShadow.highlightStart,
                        endPoint: ClayShadow.highlightEnd
                    )
                    .clipShape(shape)
                }
                // Grain texture
                .overlay {
                    ClayNoiseTexture(opacity: 0.04)
                        .clipShape(shape)
                }
                // Edge stroke
                .overlay {
                    shape
                        .stroke(
                            LinearGradient(
                                colors: ClayShadow.edgeStrokeColors,
                                startPoint: ClayShadow.edgeStrokeStart,
                                endPoint: ClayShadow.edgeStrokeEnd
                            ),
                            lineWidth: 1
                        )
                }
        }
        .shadow(
            color: shadowSpec.color,
            radius: shadowSpec.radius,
            x: shadowSpec.x,
            y: shadowSpec.y
        )
    }
}
