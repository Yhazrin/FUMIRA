import Foundation

enum GenerationError: LocalizedError, Sendable, Equatable {
    case timedOut
    case networkFailure
    case uploadFailure
    case invalidParameters
    case rateLimited
    case generationFailed(message: String)
    case serverUnavailable

    var errorDescription: String? {
        switch self {
        case .timedOut:
            "目标时间生成超时，其他结果仍然可用。"
        case .networkFailure:
            "网络连接失败，请检查网络后重试。"
        case .uploadFailure:
            "照片上传失败，请重试。"
        case .invalidParameters:
            "生成参数无效，请调整时间或故事后重试。"
        case .rateLimited:
            "生成服务繁忙，请稍后再试。"
        case let .generationFailed(message):
            message.isEmpty ? "变迁图生成失败，请稍后重试。" : message
        case .serverUnavailable:
            "远程生成暂未就绪，请稍后重试或改用本地 Demo。"
        }
    }

    var isRetryable: Bool {
        switch self {
        case .invalidParameters:
            false
        case .timedOut, .networkFailure, .uploadFailure, .rateLimited,
             .generationFailed, .serverUnavailable:
            true
        }
    }
}
