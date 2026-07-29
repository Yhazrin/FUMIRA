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
                    continuation.yield(.progress(label: "封存源照片", value: 0.12))
                    let assetID = try await upload(photo: request.photo)
                    continuation.yield(.progress(label: "正在读取源场景圣经", value: 0.48))
                    let understanding = try await understand(
                        assetID: assetID,
                        targetTime: request.targetTime,
                        requestID: request.sessionID,
                        narrativeAnchor: request.narrativeAnchor,
                        opticalContext: request.opticalContext
                    )
                    continuation.yield(.progress(label: "锁定空间锚点与时间层", value: 0.82))
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

    private func understand(
        assetID: String,
        targetTime: TimePosition,
        requestID: UUID,
        narrativeAnchor: TemporalSubjectAnchor?,
        opticalContext: TemporalOpticalContext
    ) async throws -> SceneUnderstanding {
        var urlRequest = URLRequest(url: baseURL.appending(path: "v1/understand"))
        urlRequest.httpMethod = "POST"
        // The relay may retry one malformed VLM response before returning.
        urlRequest.timeoutInterval = 210
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(UnderstandRequest(
            sourceAssetId: assetID,
            targetTime: UnderstandingTargetTimeRelayDTO(targetTime),
            copyConstraints: .appLayout,
            requestId: requestID.uuidString,
            narrativeAnchor: narrativeAnchor.map(NarrativeAnchorRelayDTO.init),
            opticalContext: opticalContext.isAvailable
                ? OpticalContextRelayDTO(opticalContext)
                : nil
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
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return GenerationError.timedOut
            case .notConnectedToInternet,
                 .networkConnectionLost,
                 .cannotConnectToHost,
                 .cannotFindHost,
                 .dnsLookupFailed,
                 .internationalRoamingOff,
                 .dataNotAllowed:
                return GenerationError.networkFailure
            default:
                return GenerationError.networkFailure
            }
        }
        return error
    }
}

private struct UploadResponse: Decodable {
    let assetId: String
}

private struct UnderstandRequest: Encodable {
    let sourceAssetId: String
    let targetTime: UnderstandingTargetTimeRelayDTO
    let copyConstraints: UnderstandingCopyConstraintsRelayDTO
    let requestId: String
    let narrativeAnchor: NarrativeAnchorRelayDTO?
    let opticalContext: OpticalContextRelayDTO?
}

private struct NarrativeAnchorRelayDTO: Codable {
    let normalizedX: Double
    let normalizedY: Double

    init(_ anchor: TemporalSubjectAnchor) {
        normalizedX = anchor.normalizedX
        normalizedY = anchor.normalizedY
    }
}

private struct OpticalContextRelayDTO: Codable {
    let lensPosition: String?
    let focusPosition: Float?
    let exposureDurationSeconds: Double?
    let iso: Float?
    let exposureTargetOffset: Float?
    let zoomFactor: Double?
    let lightCondition: String

    init(_ context: TemporalOpticalContext) {
        lensPosition = switch context.lensPosition {
        case .front: "front"
        case .back: "back"
        case nil: nil
        }
        focusPosition = context.focusPosition
        exposureDurationSeconds = context.exposureDurationSeconds
        iso = context.iso
        exposureTargetOffset = context.exposureTargetOffset
        zoomFactor = context.zoomFactor
        lightCondition = context.lightCondition.rawValue
    }
}

private struct UnderstandingTargetTimeRelayDTO: Codable {
    let offsetYears: Double
    let compactLabel: String

    init(_ time: TimePosition) {
        offsetYears = time.offsetYears
        compactLabel = time.compactLabel
    }
}

private struct UnderstandingCopyConstraintsRelayDTO: Codable {
    let summary: Int
    let locationType: Int
    let visualMood: Int
    let timeClue: Int
    let changeDriver: Int
    let subjectName: Int
    let identityRule: Int

    static let appLayout = UnderstandingCopyConstraintsRelayDTO(
        summary: UnderstandingCopyPolicy.summary,
        locationType: UnderstandingCopyPolicy.locationType,
        visualMood: UnderstandingCopyPolicy.visualMood,
        timeClue: UnderstandingCopyPolicy.timeClue,
        changeDriver: UnderstandingCopyPolicy.changeDriver,
        subjectName: UnderstandingCopyPolicy.subjectName,
        identityRule: UnderstandingCopyPolicy.identityRule
    )
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
    let cameraLock: CameraLockDTO?
    let spatialAnchors: [SpatialAnchorDTO]?
    let temporalLayers: [TemporalLayerDTO]?
    let storySeeds: [String]?
    let hardConstraints: [String]?
    let sceneGraph: SceneGraphDTO?

    var sceneUnderstanding: SceneUnderstanding {
        SceneUnderstanding(
            summary: summary,
            locationType: locationType,
            visualMood: visualMood,
            timeClues: timeClues,
            changeDrivers: changeDrivers,
            subjects: subjects.map(\.sceneSubject),
            cameraLock: cameraLock.map(\.cameraLock),
            spatialAnchors: spatialAnchors?.map(\.spatialAnchor),
            temporalLayers: temporalLayers?.map(\.temporalLayer),
            storySeeds: storySeeds,
            hardConstraints: hardConstraints,
            sceneGraph: sceneGraph.map(\.sceneGraph)
        )
    }
}

private struct SceneGraphDTO: Codable {
    let baseline: SceneBaselineDTO
    let cameraLock: CameraLockDTO
    let regions: [SceneRegionDTO]
    let globalDrivers: [String]
    let uncertainties: [String]

    var sceneGraph: SceneGraph {
        SceneGraph(
            baseline: baseline.sceneBaseline,
            cameraLock: cameraLock.cameraLock,
            regions: regions.map(\.sceneRegion),
            globalDrivers: globalDrivers,
            uncertainties: uncertainties
        )
    }
}

private struct SceneBaselineDTO: Codable {
    let locationType: String
    let broadCulturalContext: String?
    let probableCaptureEra: String?
    let season: String?
    let timeOfDay: String?
    let weather: String?

    var sceneBaseline: SceneBaseline {
        SceneBaseline(
            locationType: locationType,
            broadCulturalContext: broadCulturalContext,
            probableCaptureEra: probableCaptureEra,
            season: season,
            timeOfDay: timeOfDay,
            weather: weather
        )
    }
}

private struct SceneRegionDTO: Codable {
    let id: String
    let depth: SceneDepth
    let category: SceneRegionCategory
    let description: String
    let spatialAnchor: String
    let materials: [String]
    let currentCondition: String
    let confidence: Double
    let salience: Double
    let temporalPolicy: TemporalPolicy

    var sceneRegion: SceneRegion {
        SceneRegion(
            id: id,
            depth: depth,
            category: category,
            description: description,
            spatialAnchor: spatialAnchor,
            materials: materials,
            currentCondition: currentCondition,
            confidence: confidence,
            salience: salience,
            temporalPolicy: temporalPolicy
        )
    }
}

private struct CameraLockDTO: Codable {
    let viewpoint: String?
    let lensAndPerspective: String?
    let horizon: String?
    let depthStructure: String?

    var cameraLock: CameraLock {
        CameraLock(
            viewpoint: viewpoint,
            lensAndPerspective: lensAndPerspective,
            horizon: horizon,
            depthStructure: depthStructure
        )
    }
}

private struct SpatialAnchorDTO: Codable {
    let name: String
    let depth: String?
    let position: String?
    let geometry: String?
    let identityLock: String?

    var spatialAnchor: SpatialAnchor {
        SpatialAnchor(
            name: name,
            depth: depth,
            position: position,
            geometry: geometry,
            identityLock: identityLock
        )
    }
}

private struct TemporalLayerDTO: Codable {
    let layer: String
    let visibleEvidence: String?
    let pastPotential: String?
    let futurePotential: String?
    let confidence: Double?

    var temporalLayer: TemporalLayer {
        TemporalLayer(
            layer: layer,
            visibleEvidence: visibleEvidence,
            pastPotential: pastPotential,
            futurePotential: futurePotential,
            confidence: confidence
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
    let message = payload.userMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
    switch payload.errorCode {
    case "invalid_source_asset", "invalid_image", "file_too_large", "unsupported_content_type":
        return .uploadFailure
    case "intelligence_network":
        // Server→MiniMax failed. Do NOT map to client networkFailure — Safari can
        // still reach the Mac while the relay cannot reach the vendor.
        return .generationFailed(
            message: (message?.isEmpty == false)
                ? message!
                : "中转服务无法连接图片理解上游，请稍后重试。"
        )
    case "understanding_unavailable", "unauthorized", "vision_credentials_required":
        return .serverUnavailable
    default:
        return .generationFailed(message: message ?? "图片理解失败，请重试。")
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
