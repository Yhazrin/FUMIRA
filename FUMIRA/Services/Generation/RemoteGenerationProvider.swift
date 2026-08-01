import Foundation

/// Remote image generation against the FUMIRA backend.
/// Flow: upload JPEG → create generation → poll until succeeded/failed → download result.
/// Vendor credentials never leave the server.
actor RemoteGenerationProvider: GenerationProvider {
    static let defaultPollIntervalNanoseconds: UInt64 = 800_000_000
    static let defaultMaxPollAttempts = 600
    static let defaultPollingWindowSeconds =
        Double(defaultPollIntervalNanoseconds)
        / 1_000_000_000
        * Double(defaultMaxPollAttempts)

    private let baseURL: URL
    private let session: URLSession
    private let pollIntervalNanoseconds: UInt64
    private let maxPollAttempts: Int
    /// In-flight createGeneration requestIds — drop duplicate concurrent submits.
    private var inFlightRequestIDs: Set<String> = []

    init(
        baseURL: URL,
        session: URLSession = .shared,
        pollIntervalNanoseconds: UInt64 = RemoteGenerationProvider.defaultPollIntervalNanoseconds,
        maxPollAttempts: Int = RemoteGenerationProvider.defaultMaxPollAttempts
    ) {
        self.baseURL = baseURL
        self.session = session
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
        self.maxPollAttempts = maxPollAttempts
    }

    func generate(
        request: ImageGenerationRequest
    ) async -> AsyncThrowingStream<GenerationEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(.progress(
                        label: "收集此刻的种子",
                        value: 0.05,
                        stage: .preparing
                    ))
                    let assetId = try await upload(photo: request.photo)
                    try Task.checkCancellation()
                    continuation.yield(.progress(
                        label: "把时间埋进画面",
                        value: 0.2,
                        stage: .uploading
                    ))

                    let generationId = try await createGeneration(
                        assetId: assetId,
                        request: request
                    )
                    try Task.checkCancellation()
                    continuation.yield(.progress(
                        label: "时间正在排队生长",
                        value: 0.35,
                        stage: .queued
                    ))

                    let resultURL = try await poll(generationId: generationId) { label, progress, stage in
                        continuation.yield(.progress(label: label, value: progress, stage: stage))
                    }

                    try Task.checkCancellation()
                    continuation.yield(.progress(
                        label: "收成这一帧",
                        value: 0.92,
                        stage: .finishing
                    ))
                    let imageData = try await download(resultURL: resultURL)

                    // Prompt is now compiled server-side; store a marker for diagnostics.
                    continuation.yield(.completed(GeneratedFrame(
                        sessionID: request.sessionID,
                        time: request.time,
                        storyBeatID: request.storyBeat?.id
                            ?? request.temporalStory?.generationBeat(for: request.time)?.id,
                        prompt: "[server-compiled-v3]",
                        modelOptionID: request.model.id,
                        imageData: imageData
                    )))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as URLError where error.code == .cancelled {
                    continuation.finish()
                } catch {
                    if Task.isCancelled {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: Self.mapError(error))
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func upload(photo: CapturedPhoto) async throws -> String {
        try Task.checkCancellation()
        let jpegData: Data
        do {
            jpegData = try UploadImageEncoder.jpegData(from: photo.data)
        } catch {
            throw GenerationError.uploadFailure
        }

        let boundary = "fumira-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"capture.jpg\"\r\n")
        body.append("Content-Type: image/jpeg\r\n\r\n")
        body.append(jpegData)
        body.append("\r\n--\(boundary)--\r\n")

        var request = URLRequest(url: baseURL.appending(path: "v1/uploads"))
        request.httpMethod = "POST"
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = body
        request.timeoutInterval = 60

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            try Task.checkCancellation()
            if Self.isCancellation(error) { throw CancellationError() }
            throw GenerationError.uploadFailure
        }

        try Task.checkCancellation()

        guard let http = response as? HTTPURLResponse else {
            throw GenerationError.uploadFailure
        }

        if http.statusCode == 413 {
            throw GenerationError.uploadFailure
        }
        guard (200...299).contains(http.statusCode) else {
            throw Self.decodeAPIError(data: data, fallback: .uploadFailure)
        }

        let decoded = try JSONDecoder().decode(UploadResponse.self, from: data)
        return decoded.assetId
    }

    private func createGeneration(
        assetId: String,
        request: ImageGenerationRequest
    ) async throws -> String {
        try Task.checkCancellation()
        let requestId = request.sessionID.uuidString
        guard !inFlightRequestIDs.contains(requestId) else {
            throw GenerationError.generationFailed(message: "同一请求仍在进行中，请稍候。")
        }
        inFlightRequestIDs.insert(requestId)
        defer { inFlightRequestIDs.remove(requestId) }

        guard
            let understanding = request.understanding,
            let story = request.temporalStory,
            let targetBeat = request.storyBeat ?? story.generationBeat(for: request.time),
            targetBeat.renderPlan != nil
        else {
            throw GenerationError.invalidParameters
        }

        let payload = CreateGenerationRequest(
            contextVersion: "generation.v3",
            sourceAssetId: assetId,
            timePosition: TimePositionDTO(time: request.time),
            aspectRatio: Self.aspectRatio(for: request.photo),
            imageProvider: request.model.provider.imageGenerationRoute ?? "minimax",
            imageModel: Self.relayImageModel(for: request.model),
            requestId: requestId,
            structuredContext: StructuredContextDTO(
                schemaVersion: "generation-context.v3",
                understanding: UnderstandingRelayDTO(understanding),
                story: StoryContextRelayDTO(story, targetBeat: targetBeat),
                generationMode: "captured_target"
            )
        )

        var urlRequest = URLRequest(url: baseURL.appending(path: "v1/generations"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(payload)
        urlRequest.timeoutInterval = 30

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            try Task.checkCancellation()
            if Self.isCancellation(error) { throw CancellationError() }
            throw GenerationError.networkFailure
        }

        try Task.checkCancellation()

        guard let http = response as? HTTPURLResponse else {
            throw GenerationError.networkFailure
        }

        if http.statusCode == 503 {
            throw GenerationError.serverUnavailable
        }
        guard http.statusCode == 202 else {
            throw Self.decodeAPIError(data: data, fallback: .generationFailed(message: ""))
        }

        let decoded = try JSONDecoder().decode(CreateGenerationResponse.self, from: data)
        return decoded.generationId
    }

    private func poll(
        generationId: String,
        onProgress: (String, Double, GenerationProgressStage) -> Void
    ) async throws -> URL {
        for attempt in 0..<maxPollAttempts {
            try Task.checkCancellation()
            let status = try await fetchStatus(generationId: generationId)
            try Task.checkCancellation()

            switch status.status {
            case "queued":
                let fraction = min(0.5, 0.35 + Double(attempt) * 0.008)
                let label = attempt >= 180
                    ? "生成服务仍在排队，已为你继续等待"
                    : "时间正在排队生长"
                onProgress(label, fraction, .queued)
                try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            case "processing":
                let fraction = min(0.9, 0.5 + Double(attempt) * 0.01)
                let label = attempt >= 180
                    ? "这一帧仍在精细生长，请继续等待"
                    : "时间正在生长"
                onProgress(label, fraction, .processing)
                try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            case "succeeded":
                onProgress("这一帧已经长成", 0.9, .finishing)
                guard
                    let raw = status.resultUrl,
                    let url = URL(string: raw)
                else {
                    throw GenerationError.generationFailed(message: "生成完成但缺少结果地址。")
                }
                return url
            case "failed":
                throw Self.mapServerFailure(
                    errorCode: status.errorCode,
                    userMessage: status.userMessage,
                    retryable: status.retryable
                )
            default:
                let fraction = min(0.9, 0.35 + Double(attempt) * 0.01)
                onProgress("时间正在生长", fraction, .processing)
                try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            }
        }
        throw GenerationError.timedOut
    }

    private func fetchStatus(generationId: String) async throws -> GenerationStatusResponse {
        var request = URLRequest(
            url: baseURL.appending(path: "v1/generations/\(generationId)")
        )
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            try Task.checkCancellation()
            if Self.isCancellation(error) { throw CancellationError() }
            throw GenerationError.networkFailure
        }

        try Task.checkCancellation()

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw GenerationError.networkFailure
        }
        return try JSONDecoder().decode(GenerationStatusResponse.self, from: data)
    }

    private func download(resultURL: URL) async throws -> Data {
        try Task.checkCancellation()
        do {
            let (data, response) = try await session.data(from: resultURL)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw GenerationError.generationFailed(message: "无法下载生成结果。")
            }
            return data
        } catch let error as GenerationError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Self.isCancellation(error) { throw CancellationError() }
            try Task.checkCancellation()
            throw GenerationError.networkFailure
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return Task.isCancelled
    }

    /// Vendor model id for the relay (e.g. `gpt-image-2`). MiniMax omits this.
    private static func relayImageModel(for option: AIModelOption) -> String? {
        guard option.provider.imageGenerationRoute == "apimart" else { return nil }
        if option.modelID.hasPrefix("apimart/") {
            return String(option.modelID.dropFirst("apimart/".count))
        }
        return option.modelID
    }

    private static func aspectRatio(for photo: CapturedPhoto) -> String {
        guard photo.pixelWidth > 0, photo.pixelHeight > 0 else { return "3:4" }
        let ratio = Double(photo.pixelWidth) / Double(photo.pixelHeight)
        let candidates: [(String, Double)] = [
            ("1:1", 1),
            ("3:4", 0.75),
            ("2:3", 2.0 / 3.0),
            ("4:3", 4.0 / 3.0),
            ("3:2", 1.5),
            ("16:9", 16.0 / 9.0),
            ("9:16", 9.0 / 16.0),
            ("21:9", 21.0 / 9.0),
        ]
        return candidates.min { abs($0.1 - ratio) < abs($1.1 - ratio) }?.0 ?? "3:4"
    }

    private static func mapError(_ error: Error) -> Error {
        if let generationError = error as? GenerationError {
            return generationError
        }
        if error is DecodingError {
            return GenerationError.generationFailed(message: "服务返回格式异常。")
        }
        if isCancellation(error) {
            return CancellationError()
        }
        return GenerationError.networkFailure
    }

    private static func decodeAPIError(data: Data, fallback: GenerationError) -> GenerationError {
        if let payload = try? JSONDecoder().decode(APIErrorPayload.self, from: data) {
            return mapServerFailure(
                errorCode: payload.errorCode,
                userMessage: payload.userMessage,
                retryable: payload.retryable
            )
        }
        return fallback
    }

    private static func mapServerFailure(
        errorCode: String?,
        userMessage: String?,
        retryable: Bool?
    ) -> GenerationError {
        switch errorCode {
        case "invalid_params", "invalid_aspect_ratio", "invalid_image_provider", "missing_prompt",
             "invalid_time_position", "invalid_source_asset", "missing_request_id",
             "invalid_generation_contract", "missing_target_beat",
             "invalid_target_beat", "missing_scene_graph",
             "missing_temporal_render_plan", "unsupported_schema_version":
            return .invalidParameters
        case "rate_limited":
            return .rateLimited
        case "timeout":
            return .timedOut
        case "generation_unavailable":
            return .serverUnavailable
        case "file_too_large", "invalid_image", "unsupported_content_type", "missing_file":
            return .uploadFailure
        case "network_error":
            return .networkFailure
        default:
            let message = userMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if retryable == false, message.contains("参数") {
                return .invalidParameters
            }
            return .generationFailed(message: message)
        }
    }
}

private struct UploadResponse: Decodable {
    let assetId: String
}

private struct CreateGenerationRequest: Encodable {
    let contextVersion: String
    let sourceAssetId: String
    let timePosition: TimePositionDTO
    let aspectRatio: String
    let imageProvider: String
    let imageModel: String?
    let requestId: String
    let structuredContext: StructuredContextDTO
}

private struct StructuredContextDTO: Encodable {
    let schemaVersion: String
    let understanding: UnderstandingRelayDTO
    let story: StoryContextRelayDTO
    let generationMode: String
}

private struct UnderstandingRelayDTO: Encodable {
    let summary: String
    let locationType: String
    let visualMood: String
    let timeClues: [String]
    let changeDrivers: [String]
    let subjects: [SubjectRelayDTO]
    let cameraLock: CameraLockRelayDTO?
    let spatialAnchors: [SpatialAnchorRelayDTO]?
    let temporalLayers: [TemporalLayerRelayDTO]?
    let storySeeds: [String]?
    let hardConstraints: [String]?
    let sceneGraph: SceneGraph?

    init(_ understanding: SceneUnderstanding) {
        summary = understanding.summary
        locationType = understanding.locationType
        visualMood = understanding.visualMood
        timeClues = understanding.timeClues
        changeDrivers = understanding.changeDrivers
        subjects = understanding.subjects.map(SubjectRelayDTO.init)
        cameraLock = understanding.cameraLock.map(CameraLockRelayDTO.init)
        spatialAnchors = understanding.spatialAnchors?.map(SpatialAnchorRelayDTO.init)
        temporalLayers = understanding.temporalLayers?.map(TemporalLayerRelayDTO.init)
        storySeeds = understanding.storySeeds
        hardConstraints = understanding.hardConstraints
        sceneGraph = understanding.sceneGraph
    }
}

private struct SubjectRelayDTO: Encodable {
    let name: String
    let confidence: Double
    let identityRule: String

    init(_ subject: SceneSubject) {
        name = subject.name
        confidence = subject.confidence
        identityRule = subject.identityRule
    }
}

private struct CameraLockRelayDTO: Encodable {
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

private struct SpatialAnchorRelayDTO: Encodable {
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

private struct TemporalLayerRelayDTO: Encodable {
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

private struct StoryContextRelayDTO: Encodable {
    let schemaVersion: String
    let title: String
    let logline: String
    let presentTruth: String
    let identityRules: [String]
    let beats: [StoryBeatContextRelayDTO]
    let targetBeat: StoryBeatContextRelayDTO

    init(_ story: TemporalStory, targetBeat: StoryBeat) {
        schemaVersion = "temporal-story.v3"
        title = story.title
        logline = story.logline
        presentTruth = story.presentTruth
        identityRules = story.identityRules
        beats = story.beats.map { StoryBeatContextRelayDTO($0) }
        self.targetBeat = StoryBeatContextRelayDTO(targetBeat)
    }
}

private struct StoryBeatContextRelayDTO: Encodable {
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
    let exactTarget: ExactTargetContextRelayDTO?
    let renderPlan: TemporalRenderPlan?

    init(_ beat: StoryBeat) {
        anchorYears = beat.anchorYears
        title = beat.title
        narrative = beat.narrative
        visualPrompt = beat.visualPrompt
        transitionCause = beat.transitionCause
        unchangedAnchors = beat.unchangedAnchors
        foregroundDelta = beat.foregroundDelta
        midgroundDelta = beat.midgroundDelta
        backgroundDelta = beat.backgroundDelta
        subjectDelta = beat.subjectDelta
        environmentDelta = beat.environmentDelta
        exactTarget = beat.exactTarget.map { ExactTargetContextRelayDTO($0) }
        renderPlan = beat.renderPlan
    }
}

private struct ExactTargetContextRelayDTO: Encodable {
    let offsetDays: Double
    let targetDateISO: String
    let compactLabel: String

    init(_ target: ExactTarget) {
        offsetDays = target.offsetDays
        targetDateISO = target.targetDateISO
        compactLabel = target.compactLabel
    }
}

private struct CreateGenerationResponse: Decodable {
    let generationId: String
    let status: String
}

private struct GenerationStatusResponse: Decodable {
    let generationId: String
    let status: String
    let resultUrl: String?
    let errorCode: String?
    let userMessage: String?
    let retryable: Bool?
}

private struct APIErrorPayload: Decodable {
    let errorCode: String?
    let userMessage: String?
    let retryable: Bool?
}

private struct TimePositionDTO: Encodable {
    let normalized: Double
    let offsetDays: Double
    let offsetYears: Double
    let compactLabel: String

    init(time: TimePosition) {
        normalized = time.normalized
        offsetDays = time.offsetDays
        offsetYears = time.offsetYears
        compactLabel = time.compactLabel
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
