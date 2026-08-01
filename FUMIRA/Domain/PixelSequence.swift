import Foundation

struct PixelSequenceLibrary: Decodable, Sendable {
    let version: Int
    let frameSize: PixelSequenceSize
    let sequences: [PixelSequence]

    func sequence(id: String) -> PixelSequence? {
        sequences.first { $0.id == id }
    }

    static func decode(_ data: Data) throws -> PixelSequenceLibrary {
        try JSONDecoder().decode(PixelSequenceLibrary.self, from: data)
    }

    static func bundled(
        resource: String = "fumira_doraemon_sequences",
        bundle: Bundle = .main
    ) throws -> PixelSequenceLibrary {
        guard let url = bundle.url(forResource: resource, withExtension: "json") else {
            throw PixelSequenceLibraryError.missingManifest(resource)
        }
        return try decode(Data(contentsOf: url))
    }
}

struct PixelSequenceSize: Decodable, Equatable, Sendable {
    let width: Int
    let height: Int
}

enum PixelSequencePlaybackMode: String, Decodable, Sendable {
    case oneShot
    case randomLoop
}

enum PixelSequenceClipKind: String, Decodable, Sendable {
    case linear
    case base
    case action
}

struct PixelSequenceClip: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let kind: PixelSequenceClipKind
    let frameDurationMilliseconds: Int
    let weight: Double
    let frames: [String]

    var frameDuration: Duration {
        .milliseconds(max(frameDurationMilliseconds, 16))
    }

    var duration: TimeInterval {
        TimeInterval(max(frameDurationMilliseconds, 16) * frames.count) / 1_000
    }
}

struct PixelSequence: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let playbackMode: PixelSequencePlaybackMode
    let baseClipID: String?
    let actionProbability: Double
    let minimumBaseLoops: Int
    let reduceMotionClipID: String
    let reduceMotionFrameIndex: Int
    let clips: [PixelSequenceClip]

    var totalSourceFrames: Int {
        clips.reduce(0) { $0 + $1.frames.count }
    }

    var totalDuration: TimeInterval {
        clips.reduce(0) { $0 + $1.duration }
    }

    var firstClip: PixelSequenceClip? {
        switch playbackMode {
        case .oneShot:
            clips.first
        case .randomLoop:
            baseClip
        }
    }

    var baseClip: PixelSequenceClip? {
        guard let baseClipID else { return nil }
        return clip(id: baseClipID)
    }

    var actionClips: [PixelSequenceClip] {
        clips.filter { $0.kind == .action && !$0.frames.isEmpty }
    }

    var reduceMotionFrame: String? {
        guard
            let clip = clip(id: reduceMotionClipID),
            !clip.frames.isEmpty
        else {
            return firstClip?.frames.first
        }
        let index = min(max(reduceMotionFrameIndex, 0), clip.frames.count - 1)
        return clip.frames[index]
    }

    func clip(id: String) -> PixelSequenceClip? {
        clips.first { $0.id == id }
    }
}

enum PixelSequenceLibraryError: LocalizedError {
    case missingManifest(String)

    var errorDescription: String? {
        switch self {
        case let .missingManifest(resource):
            "Missing bundled pixel-sequence manifest: \(resource).json"
        }
    }
}

enum PixelSequencePlayback {
    static func shouldInsertAction(
        probability: Double,
        completedBaseLoops: Int,
        minimumBaseLoops: Int,
        randomUnit: Double
    ) -> Bool {
        guard completedBaseLoops >= max(minimumBaseLoops, 0) else { return false }
        let clampedProbability = min(max(probability, 0), 1)
        let clampedUnit = min(max(randomUnit, 0), 1)
        return clampedUnit < clampedProbability
    }

    static func weightedAction(
        from clips: [PixelSequenceClip],
        randomUnit: Double
    ) -> PixelSequenceClip? {
        let candidates = clips.filter { $0.kind == .action && $0.weight > 0 }
        let totalWeight = candidates.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }

        let clampedUnit = min(max(randomUnit, 0), 0.999_999_999)
        let target = clampedUnit * totalWeight
        var accumulated = 0.0
        for candidate in candidates {
            accumulated += candidate.weight
            if target < accumulated {
                return candidate
            }
        }
        return candidates.last
    }
}
