import Foundation

/// A story landmark projected into the same bounded, nonlinear time space as
/// the browsing rail. Markers explain the story; they are not snap targets.
struct TemporalInterpretationMarker: Identifiable, Hashable, Sendable {
    let id: UUID
    let normalized: Double
    let anchorYears: Double
    let title: String
    let isExactTarget: Bool
}

/// A deterministic, read-only explanation of the currently selected time.
///
/// This value describes one interpretation already present in the story data.
/// It does not mutate the selected time or claim a factual history/prediction.
struct TemporalInterpretationTrace: Hashable, Sendable {
    let selectedTime: TimePosition
    let activeBeatID: UUID?
    let activeBeatTitle: String?
    let narrative: String
    let changeTrace: String?
    let continuityAnchors: [String]
    let markers: [TemporalInterpretationMarker]
    let interpretationLabel: String

    static func resolve(
        story: TemporalStory?,
        understanding: SceneUnderstanding?,
        at selectedTime: TimePosition
    ) -> TemporalInterpretationTrace {
        // Use the exact target beat only when it matches this selected time;
        // `generationBeat(for:)` otherwise falls back to the nearest canonical
        // landmark. This keeps the explanation aligned with the generated
        // frame without leaking a previously captured target into browsing.
        let activeBeat = story?.generationBeat(for: selectedTime)
        let explicitContinuity = nonemptyValues(activeBeat?.unchangedAnchors)
        let fallbackContinuity = nonemptyValues(story?.identityRules)

        return TemporalInterpretationTrace(
            selectedTime: selectedTime,
            activeBeatID: activeBeat?.id,
            activeBeatTitle: nonemptyValue(activeBeat?.title),
            narrative: resolvedNarrative(
                activeBeat: activeBeat,
                story: story,
                understanding: understanding
            ),
            changeTrace: nonemptyValue(activeBeat?.transitionCause)
                ?? nonemptyValues(understanding?.changeDrivers).first,
            continuityAnchors: Array(
                (explicitContinuity.isEmpty ? fallbackContinuity : explicitContinuity)
                    .prefix(3)
            ),
            markers: story.map(resolvedMarkers) ?? [],
            interpretationLabel: "一种可能的时间解释 · \(selectedTime.compactLabel)"
        )
    }

    private static func resolvedNarrative(
        activeBeat: StoryBeat?,
        story: TemporalStory?,
        understanding: SceneUnderstanding?
    ) -> String {
        [
            activeBeat?.narrative,
            story?.presentTruth,
            story?.logline,
            understanding?.summary
        ]
        .lazy
        .compactMap(nonemptyValue)
        .first ?? "暂无足够线索形成时间解释。"
    }

    private static func resolvedMarkers(
        story: TemporalStory
    ) -> [TemporalInterpretationMarker] {
        let matchingCanonicalID = story.targetBeat.flatMap { targetBeat in
            story.beats.first(where: { isSameMarker($0, targetBeat) })?.id
        }
        var markers = story.beats.map { beat in
            marker(
                for: beat,
                isExactTarget: beat.id == matchingCanonicalID
            )
        }

        if let targetBeat = story.targetBeat,
           matchingCanonicalID == nil {
            markers.append(marker(for: targetBeat, isExactTarget: true))
        }

        return markers.sorted { lhs, rhs in
            let lhsAnchor = sortableAnchor(lhs.anchorYears)
            let rhsAnchor = sortableAnchor(rhs.anchorYears)
            if lhsAnchor != rhsAnchor {
                return lhsAnchor < rhsAnchor
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func marker(
        for beat: StoryBeat,
        isExactTarget: Bool
    ) -> TemporalInterpretationMarker {
        let mapped = TimePosition(offsetDays: beat.anchorYears * 365.25).normalized
        let boundedNormalized = mapped.isFinite
            ? min(max(mapped, -1), 1)
            : 0

        return TemporalInterpretationMarker(
            id: beat.id,
            normalized: boundedNormalized,
            anchorYears: beat.anchorYears,
            title: beat.title,
            isExactTarget: isExactTarget
        )
    }

    private static func isSameMarker(_ lhs: StoryBeat, _ rhs: StoryBeat) -> Bool {
        lhs.id == rhs.id || abs(lhs.anchorYears - rhs.anchorYears) * 365.25 < 0.5
    }

    private static func sortableAnchor(_ anchorYears: Double) -> Double {
        guard !anchorYears.isNaN else { return 0 }
        return anchorYears
    }

    private static func nonemptyValues(_ values: [String]?) -> [String] {
        (values ?? []).compactMap { nonemptyValue($0) }
    }

    private static func nonemptyValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
