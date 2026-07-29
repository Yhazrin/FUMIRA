import SwiftUI

/// Shared spatial planes. The values are deliberately small: FUMIRA is a
/// printed-poster world with depth cues, not a floating-card interface.
enum SpatialDepthLayer: Int, CaseIterable, Sendable {
    case background
    case environment
    case hero
    case chrome

    var parallaxPoints: CGFloat {
        switch self {
        case .background: 2
        case .environment: 5
        case .hero: 8
        case .chrome: 1
        }
    }

    var rotationDegrees: Double {
        switch self {
        case .background: 0
        case .environment: 0.35
        case .hero: 2.8
        case .chrome: 0
        }
    }
}
