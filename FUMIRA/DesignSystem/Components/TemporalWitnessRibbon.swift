import SwiftUI

/// A quiet, read-only explanation layer for the continuous time rail.
///
/// Story markers provide orientation only. This view intentionally owns no
/// gesture, binding, generation work, or time-position mutation.
struct TemporalWitnessRibbon: View {
    let trace: TemporalInterpretationTrace

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var changeTrace: String? {
        trace.changeTrace?.trimmedNonEmpty
    }

    private var continuityText: String? {
        let anchors = trace.continuityAnchors
            .compactMap(\.trimmedNonEmpty)
            .prefix(3)
        guard !anchors.isEmpty else { return nil }
        return anchors.joined(separator: " · ")
    }

    private var drawingIdentity: RibbonDrawingIdentity {
        RibbonDrawingIdentity(
            selectedNormalized: trace.selectedTime.normalized,
            markers: trace.markers.map {
                RibbonMarkerIdentity(
                    id: $0.id,
                    normalized: $0.normalized,
                    isExactTarget: $0.isExactTarget
                )
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PosterSpacing.sm) {
            ZStack {
                timeline
                    .id(drawingIdentity)
                    .transition(.opacity)
            }
            .animation(
                reduceMotion
                    ? .easeOut(duration: PosterMotion.reduced)
                    : nil,
                value: drawingIdentity
            )

            if changeTrace != nil || continuityText != nil {
                VStack(alignment: .leading, spacing: PosterSpacing.xs) {
                    if let changeTrace {
                        WitnessExplanationLine(
                            label: "变化线索",
                            value: changeTrace,
                            reduceMotion: reduceMotion
                        )
                    }

                    if let continuityText {
                        WitnessExplanationLine(
                            label: "仍然保持",
                            value: continuityText,
                            reduceMotion: reduceMotion
                        )
                    }
                }
            }
        }
        .frame(
            minHeight: PosterSpacing.xl * 2 + PosterSpacing.lg,
            alignment: .topLeading
        )
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("时间见证带")
        .accessibilityValue(accessibilitySummary)
    }

    private var timeline: some View {
        TemporalFingerprintMark(
            markers: trace.markers,
            selectedTime: trace.selectedTime,
            size: .compact
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }

    private var accessibilitySummary: String {
        var parts = [trace.interpretationLabel, trace.selectedTime.compactLabel]

        if let activeBeatTitle = trace.activeBeatTitle?.trimmedNonEmpty {
            parts.append("当前解释：\(activeBeatTitle)")
        }
        if let changeTrace {
            parts.append("变化线索：\(changeTrace)")
        }
        if let continuityText {
            parts.append("仍然保持：\(continuityText)")
        }

        return parts.joined(separator: "，")
    }
}

private struct WitnessExplanationLine: View {
    let label: String
    let value: String
    let reduceMotion: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: PosterSpacing.sm) {
            Text(label)
                .font(PosterTypography.caption)
                .foregroundStyle(PosterPalette.mutedInk)
                .layoutPriority(1)

            Text(value)
                .font(PosterTypography.supporting)
                .foregroundStyle(PosterPalette.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .contentTransition(.opacity)
                .animation(
                    reduceMotion
                        ? .easeOut(duration: PosterMotion.reduced)
                        : nil,
                    value: value
                )
        }
    }
}

private struct RibbonDrawingIdentity: Hashable {
    let selectedNormalized: Double
    let markers: [RibbonMarkerIdentity]
}

private struct RibbonMarkerIdentity: Hashable {
    let id: UUID
    let normalized: Double
    let isExactTarget: Bool
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#Preview("Temporal witness ribbon") {
    TemporalWitnessRibbon(
        trace: TemporalInterpretationTrace(
            selectedTime: TimePosition(normalized: 0.36),
            activeBeatID: nil,
            activeBeatTitle: "树荫重新覆盖小路",
            narrative: "同一个视角里，公园沿着树木生长留下另一种可能的样子。",
            changeTrace: "树冠生长让步道从开阔转向林荫",
            continuityAnchors: ["长椅的位置", "人物轮廓", "道路走向"],
            markers: [
                TemporalInterpretationMarker(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                    normalized: -0.58,
                    anchorYears: -28,
                    title: "幼树",
                    isExactTarget: false
                ),
                TemporalInterpretationMarker(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                    normalized: 0,
                    anchorYears: 0,
                    title: "现在",
                    isExactTarget: false
                ),
                TemporalInterpretationMarker(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                    normalized: 0.36,
                    anchorYears: 9,
                    title: "目标时刻",
                    isExactTarget: true
                )
            ],
            interpretationLabel: "一种可能的时间解释"
        )
    )
    .padding(PosterSpacing.lg)
    .background(PosterPalette.canvas)
}
