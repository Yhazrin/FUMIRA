import SwiftUI

struct FlatParallaxOffset: ViewModifier {
    let motionField: MotionFieldModel?
    let depth: FlatMotionLayerDepth

    func body(content: Content) -> some View {
        content.offset(motionField?.offset(for: depth) ?? .zero)
    }
}

struct FlatDecorationRotation: ViewModifier {
    let motionField: MotionFieldModel?

    func body(content: Content) -> some View {
        content.rotationEffect(motionField?.decorationRotation() ?? .zero)
    }
}

extension View {
    func flatParallax(
        _ motionField: MotionFieldModel?,
        depth: FlatMotionLayerDepth
    ) -> some View {
        modifier(FlatParallaxOffset(motionField: motionField, depth: depth))
    }

    func flatDecorationRotation(_ motionField: MotionFieldModel?) -> some View {
        modifier(FlatDecorationRotation(motionField: motionField))
    }
}

struct FlatMotionEntrance: ViewModifier {
    let isVisible: Bool
    let reduceMotion: Bool
    var delay: Duration = .zero

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : 10)
            .animation(entranceAnimation, value: isVisible)
    }

    private var entranceAnimation: Animation? {
        guard !reduceMotion else {
            return .linear(duration: PosterMotion.reduced)
        }
        let delaySeconds = Double(delay.components.seconds)
            + Double(delay.components.attoseconds) / 1_000_000_000_000_000_000
        return PosterMotion.decelerate.delay(delaySeconds)
    }
}

extension View {
    func flatMotionEntrance(
        isVisible: Bool,
        reduceMotion: Bool,
        delay: Duration = .zero
    ) -> some View {
        modifier(FlatMotionEntrance(isVisible: isVisible, reduceMotion: reduceMotion, delay: delay))
    }
}
