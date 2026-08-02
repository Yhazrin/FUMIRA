import Foundation

/// Session-scoped store of generated frames, keyed by quantized rail position.
///
/// The rail is continuous but generation is not, so scrubbing needs an answer
/// for positions that were never generated. This cache answers with the frame
/// on either side, letting the UI cross-dissolve immediately instead of
/// showing a spinner for every pixel of drag.
///
/// Entries are dropped when the session changes; there is no persistence and
/// no cross-session reuse, because a frame is only valid for its source photo.
actor GeneratedFrameCache {
    /// Positions closer than this are treated as the same frame. Matches the
    /// server's time-position tolerance so the client never asks for two
    /// frames the server would consider identical.
    private static let quantizationSteps = 2_000.0

    private var sessionID: UUID?
    private var frames: [Int: GeneratedFrame] = [:]
    private var inFlight: Set<Int> = []

    private static func key(for normalized: Double) -> Int {
        let clamped = min(max(normalized, -1), 1)
        return Int((clamped * quantizationSteps).rounded())
    }

    /// Frames survive only within one session. Any other session ID resets.
    private func ensureSession(_ id: UUID) {
        guard sessionID != id else { return }
        sessionID = id
        frames.removeAll(keepingCapacity: true)
        inFlight.removeAll(keepingCapacity: true)
    }

    func store(_ frame: GeneratedFrame) {
        ensureSession(frame.sessionID)
        let key = Self.key(for: frame.time.normalized)
        frames[key] = frame
        inFlight.remove(key)
    }

    func frame(sessionID: UUID, normalized: Double) -> GeneratedFrame? {
        guard self.sessionID == sessionID else { return nil }
        return frames[Self.key(for: normalized)]
    }

    /// Nearest generated frames on either side of `normalized`, for
    /// cross-dissolve. Either side may be `nil` near the ends of the rail.
    struct Neighbours: Sendable {
        let lower: GeneratedFrame?
        let upper: GeneratedFrame?
        /// `0` at `lower`, `1` at `upper`. Zero when only one side exists.
        let fraction: Double

        var best: GeneratedFrame? {
            guard let lower else { return upper }
            guard let upper else { return lower }
            return fraction < 0.5 ? lower : upper
        }
    }

    func neighbours(sessionID: UUID, normalized: Double) -> Neighbours {
        guard self.sessionID == sessionID, !frames.isEmpty else {
            return Neighbours(lower: nil, upper: nil, fraction: 0)
        }
        let target = Self.key(for: normalized)
        if let exact = frames[target] {
            return Neighbours(lower: exact, upper: exact, fraction: 0)
        }

        var lowerKey: Int?
        var upperKey: Int?
        for key in frames.keys {
            if key <= target, lowerKey.map({ key > $0 }) ?? true {
                lowerKey = key
            }
            if key >= target, upperKey.map({ key < $0 }) ?? true {
                upperKey = key
            }
        }

        // One side missing means the rail is past the outermost generated
        // frame; hold that frame rather than dissolving into nothing.
        guard let lowerKey, let upperKey else {
            return Neighbours(
                lower: lowerKey.flatMap { frames[$0] },
                upper: upperKey.flatMap { frames[$0] },
                fraction: 0
            )
        }

        let span = Double(upperKey - lowerKey)
        let fraction = span > 0 ? Double(target - lowerKey) / span : 0
        return Neighbours(
            lower: frames[lowerKey],
            upper: frames[upperKey],
            fraction: min(max(fraction, 0), 1)
        )
    }

    /// Claims a slot so concurrent scrubs never request the same frame twice.
    /// Returns `false` when the frame is cached or already being generated.
    func claim(sessionID: UUID, normalized: Double) -> Bool {
        ensureSession(sessionID)
        let key = Self.key(for: normalized)
        guard frames[key] == nil, !inFlight.contains(key) else { return false }
        inFlight.insert(key)
        return true
    }

    func release(sessionID: UUID, normalized: Double) {
        guard self.sessionID == sessionID else { return }
        inFlight.remove(Self.key(for: normalized))
    }

    func isSatisfied(sessionID: UUID, normalized: Double) -> Bool {
        guard self.sessionID == sessionID else { return false }
        let key = Self.key(for: normalized)
        return frames[key] != nil || inFlight.contains(key)
    }

    var count: Int { frames.count }

    func reset() {
        sessionID = nil
        frames.removeAll()
        inFlight.removeAll()
    }
}
