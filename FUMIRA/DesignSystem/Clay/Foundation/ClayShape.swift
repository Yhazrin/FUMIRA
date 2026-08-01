import SwiftUI

/// Shape and corner-radius tokens for Clay OS.
/// All surfaces use continuous corners for the clay aesthetic.
enum ClayShape {

    // MARK: - Corner radii

    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 21
    static let xl: CGFloat = 26
    static let xxl: CGFloat = 30
    static let pill: CGFloat = 999

    // MARK: - Component-specific

    static let button: CGFloat = 23
    static let buttonSmall: CGFloat = 18
    static let card: CGFloat = 26
    static let panel: CGFloat = 30
    static let chip: CGFloat = 999
    static let screen: CGFloat = 17
    static let indicator: CGFloat = 999

    // MARK: - Rim offset (clay depth)

    static let rimOffset: CGFloat = 7
    static let rimOffsetPressed: CGFloat = 3

    // MARK: - Shape helpers

    static func roundedRect(_ radius: CGFloat) -> some Shape {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}
