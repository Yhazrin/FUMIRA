import XCTest
@testable import FUMIRA

final class GenerationErrorTests: XCTestCase {
    func testRemoteErrorCopyIsDistinct() {
        XCTAssertEqual(
            GenerationError.networkFailure.errorDescription,
            "网络连接失败，请检查网络后重试。"
        )
        XCTAssertEqual(
            GenerationError.uploadFailure.errorDescription,
            "照片上传失败，请重试。"
        )
        XCTAssertEqual(
            GenerationError.invalidParameters.errorDescription,
            "生成参数无效，请调整时间或故事后重试。"
        )
        XCTAssertEqual(
            GenerationError.rateLimited.errorDescription,
            "生成服务繁忙，请稍后再试。"
        )
        XCTAssertFalse(GenerationError.invalidParameters.isRetryable)
        XCTAssertTrue(GenerationError.timedOut.isRetryable)
        XCTAssertTrue(GenerationError.networkFailure.isRetryable)
        XCTAssertTrue(GenerationError.uploadFailure.isRetryable)
        XCTAssertTrue(GenerationError.rateLimited.isRetryable)
        XCTAssertTrue(GenerationError.serverUnavailable.isRetryable)
        XCTAssertTrue(GenerationError.generationFailed(message: "x").isRetryable)
    }

    func testProgressStageCopyMatchesGrowthMetaphor() {
        XCTAssertEqual(GenerationProgressStage.queued.rowTitle, "时间正在排队生长")
        XCTAssertEqual(GenerationProgressStage.processing.rowTitle, "时间正在生长")
        XCTAssertEqual(GenerationProgressStage.finishing.rowTitle, "收成这一帧")
        XCTAssertLessThan(
            GenerationProgressStage.queued.indicativeProgress,
            GenerationProgressStage.processing.indicativeProgress
        )
    }

    func testAPIBaseURLNeverEmbedsVendorSecrets() {
        let plist = Bundle.main.object(forInfoDictionaryKey: "FUMIRA_API_BASE_URL") as? String ?? ""
        let resolved = FUMIRAAPIConfiguration.baseURL?.absoluteString ?? ""
        for raw in [plist, resolved] {
            let lower = raw.lowercased()
            XCTAssertFalse(lower.contains("minimax"), "vendor host must not appear in client config")
            XCTAssertFalse(lower.contains("api_key"), "API key names must not appear in client config")
            XCTAssertFalse(lower.contains("apikey"), "API key names must not appear in client config")
            XCTAssertFalse(raw.contains("sk-"), "secret-looking tokens must not appear in client config")
        }
    }

    func testDebugBuildDefaultsToLocalBackendWhenEnvUnset() {
        let env = ProcessInfo.processInfo.environment["FUMIRA_API_BASE_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard env.isEmpty else {
            // Scheme/CI override wins; skip asserting the Info.plist Debug default.
            return
        }

        #if DEBUG
        let base = FUMIRAAPIConfiguration.baseURL?.absoluteString ?? ""
        XCTAssertFalse(base.isEmpty, "Debug should default to the local FUMIRA relay")
        XCTAssertTrue(base.hasPrefix("http://") || base.hasPrefix("https://"))
        XCTAssertTrue(FUMIRAAPIConfiguration.usesRemoteGeneration)
        #else
        XCTAssertNil(FUMIRAAPIConfiguration.baseURL)
        XCTAssertFalse(FUMIRAAPIConfiguration.usesRemoteGeneration)
        #endif
    }
}
