import Foundation

/// Remote image generation against the FUMIRA backend.
/// Flow: upload JPEG → create generation → poll until succeeded/failed → download result.
/// Vendor credentials never leave the server.
actor RemoteGenerationProvider: GenerationProvider {
    private let baseURL: URL
    private let session: URLSession
    private let pollIntervalNanoseconds: UInt64
    private let maxPollAttempts: Int
    /// In-flight createGeneration requestIds — drop duplicate concurrent submits.
    private var inFlightRequestIDs: Set<String> = []

    init(
        baseURL: URL,
        session: URLSession = .shared,
        pollIntervalNanoseconds: UInt64 = 800_000_000,
        maxPollAttempts: Int = 180
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

                    let prompt = request.story.generationPrompt(
                        for: request.time,
                        understanding: request.understanding
                    )
                    continuation.yield(.completed(GeneratedFrame(
                        sessionID: request.sessionID,
                        time: request.time,
                        storyBeatID: request.story.beat(for: request.time)?.id,
                        prompt: prompt,
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

        let storyText = request.story.generationPrompt(
            for: request.time,
            understanding: request.understanding
        )
        let payload = CreateGenerationRequest(
            sourceAssetId: assetId,
            timePosition: TimePositionDTO(time: request.time),
            story: storyText,
            aspectRatio: Self.aspectRatio(for: request.photo),
            requestId: requestId
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
                onProgress("时间正在排队生长", fraction, .queued)
                try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            case "processing":
                let fraction = min(0.9, 0.5 + Double(attempt) * 0.01)
                onProgress("时间正在生长", fraction, .processing)
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
        case "invalid_params", "invalid_aspect_ratio", "missing_story",
             "invalid_time_position", "invalid_source_asset", "missing_request_id":
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
    let sourceAssetId: String
    let timePosition: TimePositionDTO
    let story: String
    let aspectRatio: String
    let requestId: String
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
