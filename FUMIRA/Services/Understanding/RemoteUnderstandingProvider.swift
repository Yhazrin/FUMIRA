import Foundation

/// Hosted MiniMax image understanding via the FUMIRA relay.
/// The client never receives vendor credentials and sends canonical JPEG only.
actor RemoteUnderstandingProvider: ImageUnderstandingProvider {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func analyze(
        request: ImageUnderstandingRequest
    ) async -> AsyncThrowingStream<UnderstandingEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(.progress(label: "整理相机原片", value: 0.12))
                    let assetID = try await upload(photo: request.photo)
                    continuation.yield(.progress(label: "MiniMax 正在理解画面", value: 0.48))
                    let understanding = try await understand(
                        assetID: assetID,
                        requestID: request.sessionID
                    )
                    continuation.yield(.progress(label: "提取时间变化线索", value: 0.82))
                    continuation.yield(.completed(understanding))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.mapError(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func upload(photo: CapturedPhoto) async throws -> String {
        let jpegData: Data
        do {
            jpegData = try UploadImageEncoder.jpegData(from: photo.data)
        } catch {
            throw GenerationError.uploadFailure
        }

        let boundary = "fumira-understanding-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"capture.jpg\"\r\n")
        body.append("Content-Type: image/jpeg\r\n\r\n")
        body.append(jpegData)
        body.append("\r\n--\(boundary)--\r\n")

        var urlRequest = URLRequest(url: baseURL.appending(path: "v1/uploads"))
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 60
        urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = body

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw GenerationError.uploadFailure }
        guard (200...299).contains(http.statusCode) else {
            throw decodeError(data: data, fallback: .uploadFailure)
        }
        return try JSONDecoder().decode(UploadResponse.self, from: data).assetId
    }

    private func understand(assetID: String, requestID: UUID) async throws -> SceneUnderstanding {
        var urlRequest = URLRequest(url: baseURL.appending(path: "v1/understand"))
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 95
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(UnderstandRequest(
            sourceAssetId: assetID,
            requestId: requestID.uuidString
        ))

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw GenerationError.networkFailure }
        guard (200...299).contains(http.statusCode) else {
            throw decodeError(data: data, fallback: .generationFailed(message: "图片理解失败，请重试。"))
        }
        return try JSONDecoder().decode(UnderstandResponse.self, from: data).understanding.sceneUnderstanding
    }

    private static func mapError(_ error: Error) -> Error {
        if error is DecodingError {
            return GenerationError.generationFailed(message: "图片理解返回格式异常，请重试。")
        }
        return error
    }
}

private struct UploadResponse: Decodable {
    let assetId: String
}

private struct UnderstandRequest: Encodable {
    let sourceAssetId: String
    let requestId: String
}

private struct UnderstandResponse: Decodable {
    let understanding: SceneUnderstandingDTO
}

private struct SceneUnderstandingDTO: Codable {
    let summary: String
    let locationType: String
    let visualMood: String
    let timeClues: [String]
    let changeDrivers: [String]
    let subjects: [SceneSubjectDTO]

    var sceneUnderstanding: SceneUnderstanding {
        SceneUnderstanding(
            summary: summary,
            locationType: locationType,
            visualMood: visualMood,
            timeClues: timeClues,
            changeDrivers: changeDrivers,
            subjects: subjects.map(\.sceneSubject)
        )
    }
}

private struct SceneSubjectDTO: Codable {
    let name: String
    let confidence: Double
    let identityRule: String

    var sceneSubject: SceneSubject {
        SceneSubject(name: name, confidence: confidence, identityRule: identityRule)
    }
}

private struct RelayAPIError: Decodable {
    let errorCode: String?
    let userMessage: String?
    let retryable: Bool?
}

private func decodeError(data: Data, fallback: GenerationError) -> GenerationError {
    guard let payload = try? JSONDecoder().decode(RelayAPIError.self, from: data) else {
        return fallback
    }
    switch payload.errorCode {
    case "invalid_source_asset", "invalid_image", "file_too_large", "unsupported_content_type":
        return .uploadFailure
    case "intelligence_network":
        return .networkFailure
    case "understanding_unavailable", "unauthorized":
        return .serverUnavailable
    default:
        return .generationFailed(message: payload.userMessage ?? "图片理解失败，请重试。")
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
