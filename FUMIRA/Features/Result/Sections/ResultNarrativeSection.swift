import SwiftUI

/// Narrative copy plus the collapsible evidence ribbon.
///
/// Read-only: it explains the browsed time without becoming another time
/// control.
struct ResultNarrativeSection: View {
    let narrative: String
    let trace: TemporalInterpretationTrace
    let provenance: String
    @Binding var isEvidenceExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ClaySpacing.sm) {
            Text(narrative)
                .font(ClayTypography.bodySmall)
                .foregroundStyle(ClayPalette.textMuted)
                .lineLimit(isEvidenceExpanded ? nil : 1)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)

            DisclosureGroup(isExpanded: $isEvidenceExpanded) {
                TemporalWitnessRibbon(trace: trace)
                    .padding(.top, ClaySpacing.sm)
            } label: {
                Text("画面线索")
                    .font(ClayTypography.label)
                    .foregroundStyle(ClayPalette.textMuted)
                    .frame(minHeight: ClaySpacing.minTapTarget, alignment: .leading)
            }
            .tint(ClayPalette.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("result.temporal-interpretation")
        .accessibilityValue(provenance)
    }
}
