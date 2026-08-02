import Foundation

/// The set of time positions a session pre-generates.
///
/// Generation takes tens of seconds per frame, but the rail is continuous.
/// Rather than generating on every scrub, a session generates a small
/// symmetric set of anchors and interpolates between them for immediate
/// feedback. Anchor density is a tier decision.
struct TemporalAnchorPlan: Hashable, Sendable {
    /// Normalized rail positions in `[-1, 1]`, ascending, always containing
    /// `-1`, `0` and `1`.
    let normalizedPositions: [Double]

    init(tier: GenerationTier) {
        self.init(anchorCount: tier.anchorCount)
    }

    init(anchorCount: Int) {
        // Force odd and at least 3 so NOW is always an anchor and both bounds
        // are covered.
        let count = max(3, anchorCount.isMultiple(of: 2) ? anchorCount + 1 : anchorCount)
        let half = (count - 1) / 2
        normalizedPositions = (0..<count).map { index in
            Double(index - half) / Double(half)
        }
    }

    var anchorCount: Int { normalizedPositions.count }

    var positions: [TimePosition] {
        normalizedPositions.map { TimePosition(normalized: $0) }
    }

    /// The anchor a freshly opened result should show first.
    var nowIndex: Int { (anchorCount - 1) / 2 }

    func position(at index: Int) -> TimePosition? {
        guard normalizedPositions.indices.contains(index) else { return nil }
        return TimePosition(normalized: normalizedPositions[index])
    }

    func nearestIndex(to normalized: Double) -> Int {
        let clamped = min(max(normalized, -1), 1)
        var bestIndex = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, value) in normalizedPositions.enumerated() {
            let distance = abs(value - clamped)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    /// The two anchors bracketing `normalized`, plus how far between them the
    /// rail currently sits. Used to cross-dissolve while the exact frame for
    /// the held position is still generating.
    struct Bracket: Hashable, Sendable {
        let lowerIndex: Int
        let upperIndex: Int
        /// `0` at `lowerIndex`, `1` at `upperIndex`.
        let fraction: Double

        var isExactAnchor: Bool { lowerIndex == upperIndex }
    }

    func bracket(around normalized: Double) -> Bracket {
        let clamped = min(max(normalized, -1), 1)
        guard let upperIndex = normalizedPositions.firstIndex(where: { $0 >= clamped })
        else {
            let last = anchorCount - 1
            return Bracket(lowerIndex: last, upperIndex: last, fraction: 0)
        }
        guard upperIndex > 0 else {
            return Bracket(lowerIndex: 0, upperIndex: 0, fraction: 0)
        }
        let lowerIndex = upperIndex - 1
        let lower = normalizedPositions[lowerIndex]
        let upper = normalizedPositions[upperIndex]
        let span = upper - lower
        let fraction = span > 0 ? (clamped - lower) / span : 0
        return Bracket(
            lowerIndex: lowerIndex,
            upperIndex: upperIndex,
            fraction: min(max(fraction, 0), 1)
        )
    }

    /// Anchor indices ordered by how soon the user is likely to reach them,
    /// so prefetch spends its budget where the rail is heading.
    ///
    /// NOW comes first because it is what the result screen opens on.
    func prefetchOrder(from normalized: Double, direction: ScrubDirection) -> [Int] {
        let origin = nearestIndex(to: normalized)
        let remaining = normalizedPositions.indices.filter { $0 != nowIndex }
        let sorted = remaining.sorted { lhs, rhs in
            let lhsDistance = abs(lhs - origin)
            let rhsDistance = abs(rhs - origin)
            if lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }
            // Tie-break toward where the rail is moving.
            switch direction {
            case .towardFuture:
                return lhs > rhs
            case .towardPast:
                return lhs < rhs
            case .idle:
                return lhs < rhs
            }
        }
        return [nowIndex] + sorted
    }

    enum ScrubDirection: Hashable, Sendable {
        case towardPast
        case towardFuture
        case idle
    }
}
