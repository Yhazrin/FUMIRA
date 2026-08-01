import SwiftUI

/// Typography tokens for Clay OS.
/// SF Pro Rounded for product language; monospaced for time values, coordinates, terminal states.
enum ClayTypography {

    // MARK: - Font helpers

    static func rounded(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .rounded, weight: weight)
    }

    static func mono(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .monospaced, weight: weight)
    }

    // MARK: - Display

    static let displayLarge = rounded(.largeTitle, weight: .black)
    static let displayMedium = rounded(.title, weight: .black)
    static let displaySmall = rounded(.title2, weight: .bold)

    // MARK: - Heading

    static let heading = rounded(.title3, weight: .bold)
    static let subheading = rounded(.headline, weight: .bold)
    static let label = rounded(.subheadline, weight: .heavy)
    static let labelSmall = rounded(.caption, weight: .bold)

    // MARK: - Body

    static let body = rounded(.body)
    static let bodyBold = rounded(.body, weight: .bold)
    static let bodySmall = rounded(.callout)

    // MARK: - Mono (time, coordinates, terminal)

    static let monoLarge = mono(.headline, weight: .bold)
    static let monoMedium = mono(.subheadline, weight: .bold)
    static let monoSmall = mono(.caption, weight: .heavy)
    static let monoTiny = mono(.caption2, weight: .black)

    // MARK: - Special

    static let terminalCode = mono(.caption, weight: .bold)
    static let chipLabel = mono(.caption2, weight: .black)

    // MARK: - Tracking

    static let trackingWide: CGFloat = 1.5
    static let trackingMedium: CGFloat = 0.8
    static let trackingTight: CGFloat = 0.3
}
