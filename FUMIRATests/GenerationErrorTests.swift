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
    }

    func testAPIBaseURLDefaultsToMockWithoutConfiguration() {
        // Unit tests do not inject FUMIRA_API_BASE_URL; remote must stay off.
        XCTAssertNil(FUMIRAAPIConfiguration.baseURL)
        XCTAssertFalse(FUMIRAAPIConfiguration.usesRemoteGeneration)
    }
}
