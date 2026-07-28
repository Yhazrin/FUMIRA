import SwiftUI

/// iOS 26 native glass button. Falls back to the legacy painted capsule
/// on iOS 17–25 so the rest of the app keeps working. iOS 26 turns on the
/// real system glass material via ``PrimitiveButtonStyle.glass``; older
/// releases get the existing brand-blue capsule so the entry point never
/// looks broken.
@available(iOS 17.0, *)
struct PosterGlassButton: View {
    let title: LocalizedStringKey
    let systemImage: String?
    let accessibilityHint: LocalizedStringKey
    let action: () -> Void

    init(
        title: LocalizedStringKey,
        systemImage: String? = nil,
        accessibilityHint: LocalizedStringKey = "",
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.accessibilityHint = accessibilityHint
        self.action = action
    }

    @ViewBuilder
    private var labelContent: some View {
        HStack(spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title)
        }
        .font(.headline.weight(.bold))
        .padding(.horizontal, PosterSpacing.lg)
        .frame(maxWidth: .infinity, minHeight: 58)
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            // Native glass on iOS 26+. The system handles the capsule,
            // the highlight, and the press feedback. ``tint`` colours the
            // glyph + label.
            Button(action: action) {
                labelContent
            }
            .buttonStyle(.glass)
            .tint(PosterPalette.actionBlue)
            .accessibilityLabel(title)
            .accessibilityHint(accessibilityHint)
        } else {
            // Legacy painted capsule for iOS 17–25.
            Button(action: action) {
                labelContent
                    .foregroundStyle(PosterPalette.paperWhite)
                    .background(PosterPalette.actionBlue)
                    .clipShape(Capsule())
                    .shadow(color: PosterEffects.floating, radius: 12, y: 6)
            }
            .buttonStyle(ConnectionStartPressStyle())
            .accessibilityLabel(title)
            .accessibilityHint(accessibilityHint)
        }
    }
}
