import Foundation

/// MiniMax M2.7 story writing via the FUMIRA relay.
actor RemoteStoryProvider: StoryProvider {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func write(request: StoryRequest) async -> AsyncThrowingStream<StoryEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(.progress(label: "MiniMax 正在搭建时间线", value: 0.18))
                    let story = try await createStory(request: request)
                    continuation.yield(.progress(label: "校准七个年代的画面线索", value: 0.82))
                    continuation.yield(.completed(story))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func createStory(request: StoryRequest) async throws -> TemporalStory {
        var urlRequest = URLRequest(url: baseURL.appending(path: "v1/stories"))
        urlRequest.httpMethod = "POST"
        // The relay may retry one structurally invalid story response.
        urlRequest.timeoutInterval = 210
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(StoryRelayRequest(
            understanding: SceneUnderstandingRelayDTO(request.understanding),
            targetTime: StoryTargetRelayDTO(request.targetTime),
            copyConstraints: .appLayout,
            requestId: request.sessionID.uuidString
        ))

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw GenerationError.networkFailure }
        guard (200...299).contains(http.statusCode) else {
            throw decodeStoryError(data: data)
        }
        return try JSONDecoder().decode(StoryRelayResponse.self, from: data).story.temporalStory
    }
}

private struct StoryRelayRequest: Encodable {
    let understanding: SceneUnderstandingRelayDTO
    let targetTime: StoryTargetRelayDTO
    let copyConstraints: StoryCopyConstraintsRelayDTO
    let requestId: String
}

private struct StoryCopyConstraintsRelayDTO: Codable {
    let title: Int
    let logline: Int
    let presentTruth: Int
    let identityRule: Int
    let beatTitle: Int
    let beatNarrative: Int
    let visualPrompt: Int

    static let appLayout = StoryCopyConstraintsRelayDTO(
        title: StoryCopyPolicy.title,
        logline: StoryCopyPolicy.logline,
        presentTruth: StoryCopyPolicy.presentTruth,
        identityRule: StoryCopyPolicy.identityRule,
        beatTitle: StoryCopyPolicy.beatTitle,
        beatNarrative: StoryCopyPolicy.beatNarrative,
        visualPrompt: StoryCopyPolicy.visualPrompt
    )
}

private struct StoryTargetRelayDTO: Encodable {
    let offsetYears: Double
    let compactLabel: String

    init(_ time: TimePosition) {
        offsetYears = time.offsetYears
        compactLabel = time.compactLabel
    }
}

private struct StoryRelayResponse: Decodable {
    let story: TemporalStoryRelayDTO
}

private struct SceneUnderstandingRelayDTO: Codable {
    let summary: String
    let locationType: String
    let visualMood: String
    let timeClues: [String]
    let changeDrivers: [String]
    let subjects: [SceneSubjectRelayDTO]
    let cameraLock: CameraLockRelayDTO?
    let spatialAnchors: [SpatialAnchorRelayDTO]?
    let temporalLayers: [TemporalLayerRelayDTO]?
    let storySeeds: [String]?
    let hardConstraints: [String]?

    init(_ understanding: SceneUnderstanding) {
        summary = understanding.summary
        locationType = understanding.locationType
        visualMood = understanding.visualMood
        timeClues = understanding.timeClues
        changeDrivers = understanding.changeDrivers
        subjects = understanding.subjects.map(SceneSubjectRelayDTO.init)
        cameraLock = understanding.cameraLock.map(CameraLockRelayDTO.init)
        spatialAnchors = understanding.spatialAnchors?.map(SpatialAnchorRelayDTO.init)
        temporalLayers = understanding.temporalLayers?.map(TemporalLayerRelayDTO.init)
        storySeeds = understanding.storySeeds
        hardConstraints = understanding.hardConstraints
    }
}

private struct CameraLockRelayDTO: Codable {
    let viewpoint: String?
    let lensAndPerspective: String?
    let horizon: String?
    let depthStructure: String?

    init(_ lock: CameraLock) {
        viewpoint = lock.viewpoint
        lensAndPerspective = lock.lensAndPerspective
        horizon = lock.horizon
        depthStructure = lock.depthStructure
    }
}

private struct SpatialAnchorRelayDTO: Codable {
    let name: String
    let depth: String?
    let position: String?
    let geometry: String?
    let identityLock: String?

    init(_ anchor: SpatialAnchor) {
        name = anchor.name
        depth = anchor.depth
        position = anchor.position
        geometry = anchor.geometry
        identityLock = anchor.identityLock
    }
}

private struct TemporalLayerRelayDTO: Codable {
    let layer: String
    let visibleEvidence: String?
    let pastPotential: String?
    let futurePotential: String?
    let confidence: Double?

    init(_ layer: TemporalLayer) {
        self.layer = layer.layer
        visibleEvidence = layer.visibleEvidence
        pastPotential = layer.pastPotential
        futurePotential = layer.futurePotential
        confidence = layer.confidence
    }
}

private struct SceneSubjectRelayDTO: Codable {
    let name: String
    let confidence: Double
    let identityRule: String

    init(_ subject: SceneSubject) {
        name = subject.name
        confidence = subject.confidence
        identityRule = subject.identityRule
    }
}

private struct TemporalStoryRelayDTO: Codable {
    let title: String
    let logline: String
    let presentTruth: String
    let identityRules: [String]
    let beats: [StoryBeatRelayDTO]

    var temporalStory: TemporalStory {
        TemporalStory(
            title: title,
            logline: logline,
            presentTruth: presentTruth,
            identityRules: identityRules,
            beats: beats.map(\.storyBeat)
        )
    }
}

private struct StoryBeatRelayDTO: Codable {
    let anchorYears: Double
    let title: String
    let narrative: String
    let visualPrompt: String
    let transitionCause: String?
    let unchangedAnchors: [String]?
    let foregroundDelta: String?
    let midgroundDelta: String?
    let backgroundDelta: String?
    let subjectDelta: String?
    let environmentDelta: String?

    var storyBeat: StoryBeat {
        StoryBeat(
            anchorYears: anchorYears,
            title: title,
            narrative: narrative,
            visualPrompt: visualPrompt,
            transitionCause: transitionCause,
            unchangedAnchors: unchangedAnchors,
            foregroundDelta: foregroundDelta,
            midgroundDelta: midgroundDelta,
            backgroundDelta: backgroundDelta,
            subjectDelta: subjectDelta,
            environmentDelta: environmentDelta
        )
    }
}

private struct StoryRelayError: Decodable {
    let errorCode: String?
    let userMessage: String?
}

private func decodeStoryError(data: Data) -> GenerationError {
    guard let payload = try? JSONDecoder().decode(StoryRelayError.self, from: data) else {
        return .generationFailed(message: "时间故事服务返回异常，请重试。")
    }
    switch payload.errorCode {
    case "story_unavailable", "unauthorized":
        return .serverUnavailable
    case "intelligence_network":
        return .networkFailure
    default:
        return .generationFailed(message: payload.userMessage ?? "时间故事生成失败，请重试。")
    }
}
