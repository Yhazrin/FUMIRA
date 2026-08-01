import Foundation
import UIKit
import XCTest
@testable import FUMIRA

@MainActor
final class RemoteGenerationProviderTests: XCTestCase {
    func testRemoteGenerationRelaysTheSameExactTimeThroughTopLevelAndTargetBeat() async throws {
        defer { RelayURLProtocol.handler = nil }
        let baseURL = try XCTUnwrap(URL(string: "https://fumira.test/"))
        let target = TimePosition(offsetDays: 8_765.25)
        let understanding = SceneUnderstanding.parkReference
        let story = TemporalStory.fallback(
            understanding: understanding,
            targetTime: target
        )
        let targetBeat = try XCTUnwrap(story.targetBeat)
        let sourceJPEG = makeJPEG(size: CGSize(width: 900, height: 1_200))
        let resultJPEG = makeJPEG(size: CGSize(width: 1_200, height: 900))
        let recorder = RelayRequestRecorder()

        RelayURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            switch (request.httpMethod, path) {
            case ("POST", "/v1/uploads"):
                return relayResponse(
                    for: request,
                    statusCode: 201,
                    body: #"{"assetId":"asset-exact-time"}"#.data(using: .utf8)!
                )
            case ("POST", "/v1/generations"):
                recorder.recordGenerationBody(relayRequestBody(request))
                return relayResponse(
                    for: request,
                    statusCode: 202,
                    body: #"{"generationId":"generation-exact-time","status":"queued"}"#.data(using: .utf8)!
                )
            case ("GET", "/v1/generations/generation-exact-time"):
                return relayResponse(
                    for: request,
                    statusCode: 200,
                    body: #"{"generationId":"generation-exact-time","status":"succeeded","resultUrl":"https://fumira.test/result.jpg"}"#.data(using: .utf8)!
                )
            case ("GET", "/result.jpg"):
                return relayResponse(
                    for: request,
                    statusCode: 200,
                    body: resultJPEG,
                    contentType: "image/jpeg"
                )
            default:
                throw RelayTestError.unhandledRequest(request.httpMethod, path)
            }
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RelayURLProtocol.self]
        let provider = RemoteGenerationProvider(
            baseURL: baseURL,
            session: URLSession(configuration: configuration),
            pollIntervalNanoseconds: 1,
            maxPollAttempts: 2
        )
        let imageModel = try XCTUnwrap(
            AIModelCatalog.bundled.option(id: "fumira.image.identity")
        )
        let request = ImageGenerationRequest(
            photo: CapturedPhoto(
                data: sourceJPEG,
                pixelWidth: 900,
                pixelHeight: 1_200
            ),
            time: target,
            prompt: "unused-live-prompt",
            sessionID: UUID(),
            model: imageModel,
            understanding: understanding,
            temporalStory: story,
            storyBeat: targetBeat
        )

        let stream = await provider.generate(request: request)
        var completedFrame: GeneratedFrame?
        for try await event in stream {
            if case let .completed(frame) = event {
                completedFrame = frame
            }
        }

        let frame = try XCTUnwrap(completedFrame)
        XCTAssertEqual(frame.time.offsetDays, target.offsetDays, accuracy: 0.001)
        XCTAssertEqual(frame.storyBeatID, targetBeat.id)
        XCTAssertEqual(frame.imageData, resultJPEG)

        let body = try XCTUnwrap(recorder.generationBody())
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        let timePosition = try XCTUnwrap(json["timePosition"] as? [String: Any])
        let context = try XCTUnwrap(json["structuredContext"] as? [String: Any])
        let storyContext = try XCTUnwrap(context["story"] as? [String: Any])
        let beatContext = try XCTUnwrap(storyContext["targetBeat"] as? [String: Any])
        let exactTarget = try XCTUnwrap(beatContext["exactTarget"] as? [String: Any])

        XCTAssertEqual(json["contextVersion"] as? String, "generation.v3")
        XCTAssertEqual(context["schemaVersion"] as? String, "generation-context.v3")
        XCTAssertEqual(context["generationMode"] as? String, "captured_target")
        XCTAssertEqual(
            try XCTUnwrap(timePosition["offsetDays"] as? Double),
            target.offsetDays,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(exactTarget["offsetDays"] as? Double),
            target.offsetDays,
            accuracy: 0.001
        )
        XCTAssertEqual(exactTarget["compactLabel"] as? String, target.compactLabel)
        XCTAssertEqual(
            try XCTUnwrap(beatContext["anchorYears"] as? Double),
            target.offsetYears,
            accuracy: 0.001
        )
        XCTAssertNotNil(beatContext["renderPlan"])
    }

    private func makeJPEG(size: CGSize) -> Data {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return image.jpegData(compressionQuality: 0.85)!
    }
}

private func relayResponse(
    for request: URLRequest,
    statusCode: Int,
    body: Data,
    contentType: String = "application/json"
) -> (HTTPURLResponse, Data) {
    let response = HTTPURLResponse(
        url: request.url!,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: ["Content-Type": contentType]
    )!
    return (response, body)
}

private func relayRequestBody(_ request: URLRequest) -> Data {
    if let body = request.httpBody {
        return body
    }
    guard let stream = request.httpBodyStream else {
        return Data()
    }

    stream.open()
    defer { stream.close() }
    var data = Data()
    let bufferSize = 4_096
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    while stream.hasBytesAvailable {
        let count = stream.read(buffer, maxLength: bufferSize)
        guard count > 0 else { break }
        data.append(buffer, count: count)
    }
    return data
}

private enum RelayTestError: Error {
    case unhandledRequest(String?, String)
}

private final class RelayRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var body: Data?

    func recordGenerationBody(_ data: Data) {
        lock.withLock {
            body = data
        }
    }

    func generationBody() -> Data? {
        lock.withLock { body }
    }
}

private final class RelayURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    nonisolated(unsafe) static var handler: Handler?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: RelayTestError.unhandledRequest(nil, "missing handler"))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
