import Foundation

enum PosterSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

enum PosterControlMetric {
    /// Minimum interactive dimension required by the product accessibility contract.
    static let minimumTouchTarget: CGFloat = 44

    /// Standard compact circular control used beside a primary result action.
    static let compactDiameter: CGFloat = 56
}
