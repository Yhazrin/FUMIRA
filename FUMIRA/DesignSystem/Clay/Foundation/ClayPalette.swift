import SwiftUI

/// FUMIRA Clay OS palette — warm charcoal, cream, time blue, park green, orange, lime, yellow.
/// All raw hex values live here. Feature code must use semantic tokens.
enum ClayPalette {

    // MARK: - Core

    static let charcoal = Color(hex: 0x202425)
    static let charcoalLight = Color(hex: 0x3A3E3F)
    static let warmWhite = Color(hex: 0xF2EEE5)
    static let warmWhiteRim = Color(hex: 0xCEC7B8)

    // MARK: - Accent

    static let orange = Color(hex: 0xFF672A)
    static let orangeRim = Color(hex: 0xC9441D)
    static let orangeDepth = Color(hex: 0xA93618)
    static let timeBlue = Color(hex: 0x4A90D9)
    static let timeBlueRim = Color(hex: 0x3570A8)
    static let parkGreen = Color(hex: 0x8FCB7E)
    static let parkGreenRim = Color(hex: 0x5FA04E)
    static let lime = Color(hex: 0xB7D83D)
    static let limeRim = Color(hex: 0x7E9A27)
    static let yellow = Color(hex: 0xFFC52A)
    static let yellowRim = Color(hex: 0xC18B14)

    // MARK: - Semantic

    static let primaryAction = orange
    static let primaryActionRim = orangeRim
    static let accentBlue = timeBlue
    static let accentBlueRim = timeBlueRim
    static let success = lime
    static let successRim = limeRim
    static let progress = yellow
    static let progressRim = yellowRim

    // MARK: - Surface

    static let surfaceLight = warmWhite
    static let surfaceLightRim = warmWhiteRim
    static let surfaceDark = charcoal
    static let surfaceDarkRim = charcoalLight

    // MARK: - Text

    static let textPrimary = charcoal
    static let textOnDark = warmWhite
    static let textMuted = charcoal.opacity(0.55)
    static let textOnAccent = charcoal

    // MARK: - Feedback

    static let error = Color(hex: 0xE95E52)
    static let warning = yellow
}

// MARK: - Hex initializer

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
