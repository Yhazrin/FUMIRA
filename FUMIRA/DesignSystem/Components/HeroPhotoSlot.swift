import SwiftUI

/// Named coordinate space hosting the persistent hero surface in ``RootView``.
enum HeroCoordinateSpace {
    static let name = "hero-root"
}

/// Geometry a page reports so ``RootView`` can animate the shared hero into place.
struct HeroSlotPreference: Equatable, Sendable {
    var frame: CGRect
    var cornerRadius: CGFloat
}

/// Identifies the phase that owns a shared-photo destination. During an
/// animated phase swap SwiftUI keeps both pages alive briefly, so retaining
/// every destination prevents the outgoing page from overwriting the incoming
/// page's geometry.
enum HeroSlotOwner: Hashable, Sendable {
    case shuttered
    case understanding
    case storyWriting
    case generating
}

struct HeroSlotPreferenceKey: PreferenceKey {
    static let defaultValue: [HeroSlotOwner: HeroSlotPreference] = [:]

    static func reduce(
        value: inout [HeroSlotOwner: HeroSlotPreference],
        nextValue: () -> [HeroSlotOwner: HeroSlotPreference]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, incoming in incoming })
    }
}

/// Clear placeholder that reserves photo layout and publishes its frame in
/// ``HeroCoordinateSpace/name``. Pages must not draw the photo body themselves.
struct HeroPhotoSlot: View {
    var owner: HeroSlotOwner
    var aspectRatio: CGFloat
    var maximumHeight: CGFloat? = nil
    var cornerRadius: CGFloat = PosterRadius.card
    /// Optional fixed frame in the **local parent** coordinate space
    /// (e.g. viewfinder ``CameraCompositionGeometry/Layout/heroFrame``).
    /// Prefer overlay+offset over `.position` — position expands layout bounds and
    /// makes `frame(in:)` drift relative to the visual crop.
    var fixedFrame: CGRect? = nil

    var body: some View {
        Group {
            if let fixedFrame {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .topLeading) {
                        Color.clear
                            .frame(width: fixedFrame.width, height: fixedFrame.height)
                            .offset(x: fixedFrame.minX, y: fixedFrame.minY)
                            .background {
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: HeroSlotPreferenceKey.self,
                                        value: [
                                            owner: HeroSlotPreference(
                                                frame: proxy.frame(
                                                    in: .named(HeroCoordinateSpace.name)
                                                ),
                                                cornerRadius: cornerRadius
                                            )
                                        ]
                                    )
                                }
                            }
                    }
            } else {
                PhotoAspectContainer(
                    aspectRatio: aspectRatio,
                    maximumHeight: maximumHeight
                ) {
                    // Reporter lives *inside* the aspect-fitted content so it
                    // inherits the true photo rect — not the maxWidth-expanded
                    // outer container (which collapses tall ratios toward 1:1).
                    Color.clear
                        .background {
                            GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: HeroSlotPreferenceKey.self,
                                        value: [
                                            owner: HeroSlotPreference(
                                                frame: proxy.frame(
                                                    in: .named(HeroCoordinateSpace.name)
                                                ),
                                                cornerRadius: cornerRadius
                                            )
                                        ]
                                    )
                                }
                            }
                }
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// Reports an absolute rect already expressed in ``HeroCoordinateSpace``.
struct HeroPhotoFrameReporter: View {
    var owner: HeroSlotOwner
    var frame: CGRect
    var cornerRadius: CGFloat

    var body: some View {
        Color.clear
            .preference(
                key: HeroSlotPreferenceKey.self,
                value: [
                    owner: HeroSlotPreference(
                        frame: frame,
                        cornerRadius: cornerRadius
                    )
                ]
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
