import Foundation

struct PosterSnapshot: Sendable {
    let time: TimePosition
}

protocol PosterStorage: Sendable {
    func save(_ poster: PosterSnapshot) async throws -> URL
}

actor MockPosterStorage: PosterStorage {
    func save(_ poster: PosterSnapshot) async throws -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("fumira-poster.png")
    }
}
