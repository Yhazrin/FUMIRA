import SwiftUI

/// Experimental: alternate futures for the same target year.
///
/// Gated by `ExperimentalFeature.futureFork`. Shake-to-advance is a further
/// opt-in on top of this; the button fallback always works.
struct ResultFutureForkSection: View {
    let items: [TemporalFutureForkView.PresentationItem]
    let branches: [TemporalFutureForkBranch]
    let selectedIndex: Int
    let currentForkID: String?
    let targetLabel: String
    let reduceMotion: Bool
    let shakeFeedbackTrigger: Int?
    let isShakeEnabled: Bool
    let onSelect: (Int) -> Void
    let onRequestAdvance: () -> Void
    let onGenerate: (TemporalFutureForkBranch) -> Void

    private var selectedBranch: TemporalFutureForkBranch? {
        guard !branches.isEmpty else { return nil }
        return branches[min(max(selectedIndex, 0), branches.count - 1)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ClaySpacing.sm) {
            TemporalFutureForkView(
                items: items,
                selectedIndex: selectedIndex,
                reduceMotion: reduceMotion,
                shakeFeedbackTrigger: shakeFeedbackTrigger,
                onSelect: onSelect
            )

            if let selectedBranch {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: ClaySpacing.lg) {
                        advanceAction
                        Spacer(minLength: ClaySpacing.sm)
                        generateAction(selectedBranch)
                    }

                    VStack(alignment: .leading, spacing: ClaySpacing.xxs) {
                        generateAction(selectedBranch)
                        advanceAction
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var advanceAction: some View {
        if isShakeEnabled {
            Button(action: onRequestAdvance) {
                Label(
                    "下一种",
                    systemImage: "arrow.trianglehead.2.clockwise.rotate.90"
                )
                .font(ClayTypography.label)
                .foregroundStyle(ClayPalette.textMuted)
                .frame(minHeight: ClaySpacing.minTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(PosterPressStyle())
            .accessibilityLabel("换一种可能")
            .accessibilityIdentifier("result.future-fork.advance")
        }
    }

    private func generateAction(
        _ branch: TemporalFutureForkBranch
    ) -> some View {
        let isCurrent = currentForkID == branch.id

        return Button {
            onGenerate(branch)
        } label: {
            Text(isCurrent ? "已经显影" : "显影这一可能")
                .font(ClayTypography.label)
                .foregroundStyle(
                    isCurrent ? ClayPalette.textMuted : ClayPalette.warmWhite
                )
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .padding(.horizontal, ClaySpacing.lg)
                .frame(minHeight: ClaySpacing.minTapTarget)
                .background(
                    isCurrent ? ClayPalette.warmWhite : ClayPalette.orange,
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                stops: ClayFacet.bandStops,
                                startPoint: ClayFacet.bandStart,
                                endPoint: ClayFacet.bandEnd
                            ),
                            lineWidth: ClayFacet.bandWidth
                        )
                }
                .clayShadow(
                    isCurrent ? ClayShadow.seatedSmall : ClayShadow.seatedRest
                )
        }
        .buttonStyle(PosterPressStyle())
        .disabled(isCurrent)
        .accessibilityHint(
            "保持 \(targetLabel) 不变，从原始照片生成所选未来分支"
        )
        .accessibilityIdentifier("result.future-fork.generate")
    }
}
