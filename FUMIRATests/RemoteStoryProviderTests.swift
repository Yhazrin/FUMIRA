import Foundation
import XCTest
@testable import FUMIRA

@MainActor
final class RemoteStoryProviderTests: XCTestCase {
    func testTargetBeatRequestCarriesRequestIDAndExactTime() async throws {
        defer { StoryRelayURLProtocol.handler = nil }
        let baseURL = try XCTUnwrap(URL(string: "https://fumira.test/"))
        let target = TimePosition(offsetDays: 8_765.25)
        let recorder = StoryRelayRequestRecorder()

        StoryRelayURLProtocol.handler = { request in
            recorder.record(request)
            let responseBody: [String: Any] = [
                "schemaVersion": "target-beat.v1",
                "target": [
                    "offsetDays": target.offsetDays,
                    "targetDateISO": "2050-01-01",
                    "compactLabel": target.compactLabel,
                ],
                "targetBeat": [
                    "anchorYears": target.offsetYears,
                    "title": "目标时间",
                    "narrative": "同一处现实抵达另一个时间。",
                    "visualPrompt": "Preserve the exact camera and subject identity.",
                    "exactTarget": [
                        "offsetDays": target.offsetDays,
                        "targetDateISO": "2050-01-01",
                        "compactLabel": target.compactLabel,
                    ],
                ],
            ]
            let data = try JSONSerialization.data(withJSONObject: responseBody)
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                data
            )
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StoryRelayURLProtocol.self]
        let provider = RemoteStoryProvider(
            baseURL: baseURL,
            session: URLSession(configuration: configuration)
        )

        let beat = try await provider.writeTargetBeat(
            understanding: .parkReference,
            story: .parkReference,
            target: target
        )

        let request = try XCTUnwrap(recorder.request())
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/v1/target-beats")
        let body = storyRelayRequestBody(request)
        XCTAssertFalse(body.isEmpty)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        let requestID = try XCTUnwrap(json["requestId"] as? String)
        let requestTarget = try XCTUnwrap(json["target"] as? [String: Any])

        XCTAssertFalse(requestID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertNotNil(UUID(uuidString: requestID))
        XCTAssertEqual(
            try XCTUnwrap(requestTarget["offsetDays"] as? Double),
            target.offsetDays,
            accuracy: 0.001
        )
        let exactTarget = try XCTUnwrap(beat.exactTarget)
        XCTAssertEqual(exactTarget.offsetDays, target.offsetDays, accuracy: 0.001)
        XCTAssertEqual(exactTarget.compactLabel, target.compactLabel)
    }
}

private func storyRelayRequestBody(_ request: URLRequest) -> Data {
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

private final class StoryRelayRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedRequest: URLRequest?

    func record(_ request: URLRequest) {
        lock.withLock {
            recordedRequest = request
        }
    }

    func request() -> URLRequest? {
        lock.withLock { recordedRequest }
    }
}

private enum StoryRelayTestError: Error {
    case missingHandler
}

private final class StoryRelayURLProtocol: URLProtocol, @unchecked Sendable {
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
            client?.urlProtocol(self, didFailWithError: StoryRelayTestError.missingHandler)
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
