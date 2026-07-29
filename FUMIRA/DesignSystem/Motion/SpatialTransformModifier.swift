import SwiftUI

/// Applies the shared, low-amplitude motion field to a spatial depth plane.
/// Text and controls use `.chrome`, keeping them readable while the scenery
/// establishes depth behind them.
struct SpatialTransformModifier: ViewModifier {
    let motionField: MotionFieldModel?
    let layer: SpatialDepthLayer
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        let offset = offset
        return content
            .offset(offset)
            .rotation3DEffect(
                .degrees(rotationX),
                axis: (x: 1, y: 0, z: 0),
                perspective: PosterMotion.spatialPerspective
            )
            .rotation3DEffect(
                .degrees(rotationY),
                axis: (x: 0, y: 1, z: 0),
                perspective: PosterMotion.spatialPerspective
            )
    }

    private var offset: CGSize {
        guard !reduceMotion, motionField?.isActive == true else { return .zero }
        let magnitude = layer.parallaxPoints
        return CGSize(
            width: (motionField?.roll ?? 0) * magnitude,
            height: -(motionField?.pitch ?? 0) * magnitude * 0.65
        )
    }

    private var rotationX: Double {
        guard !reduceMotion else { return 0 }
        return -(motionField?.pitch ?? 0) * layer.rotationDegrees
    }

    private var rotationY: Double {
        guard !reduceMotion else { return 0 }
        return (motionField?.roll ?? 0) * layer.rotationDegrees
    }
}

extension View {
    func spatialDepth(
        _ layer: SpatialDepthLayer,
        motionField: MotionFieldModel?,
        reduceMotion: Bool
    ) -> some View {
        modifier(
            SpatialTransformModifier(
                motionField: motionField,
                layer: layer,
                reduceMotion: reduceMotion
            )
        )
    }
}
