import Foundation

/// Placeholder for a future hosted image-understanding provider.
///
/// MiniMax image understanding is currently available only through the project
/// MCP tool during development. There is **no** documented public HTTP endpoint
/// in `MINIMAX_API_GUIDE.md` for production understanding — do not invent one.
///
/// Until FUMIRA backend exposes a stable `/v1/understand` (or equivalent)
/// contract, keep using `MockImageUnderstandingProvider` at runtime.
///
/// See `docs/engineering/REMOTE_UNDERSTANDING_TODO.md`.
protocol RemoteUnderstandingProvider: ImageUnderstandingProvider {
    /// Backend base URL owned by FUMIRA — never a vendor key.
    var baseURL: URL { get }
}

/// Stub that fails closed until a real FUMIRA understanding route exists.
/// Not wired into `AppDependencies.runtime` yet.
actor UnimplementedRemoteUnderstandingProvider: RemoteUnderstandingProvider {
    let baseURL: URL

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    func analyze(
        request: ImageUnderstandingRequest
    ) async -> AsyncThrowingStream<UnderstandingEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(
                throwing: UnderstandingRemoteError.notImplemented
            )
        }
    }
}

enum UnderstandingRemoteError: LocalizedError, Sendable {
    case notImplemented

    var errorDescription: String? {
        "远程图片理解尚未接入。请继续使用本地 Demo 识图路由。"
    }
}
