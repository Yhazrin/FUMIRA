import Foundation

struct GeneratedFrame: Identifiable, Hashable, Sendable {
    let id: UUID
    let sessionID: UUID
    let time: TimePosition
    let storyBeatID: UUID?
    let prompt: String
    let modelOptionID: String
    let imageData: Data?

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        time: TimePosition,
        storyBeatID: UUID? = nil,
        prompt: String = "",
        modelOptionID: String = AIModelConfiguration.demo.imageOptionID,
        imageData: Data? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.time = time
        self.storyBeatID = storyBeatID
        self.prompt = prompt
        self.modelOptionID = modelOptionID
        self.imageData = imageData
    }
}

enum GenerationEvent: Sendable {
    /// Progress updates for the generation UI.
    /// - Parameters:
    ///   - label: User-facing status copy (e.g.「时间正在生长」).
    ///   - value: Normalized progress in `0...1`.
    ///   - stage: Coarse backend-aligned stage for progress row mapping.
    case progress(label: String, value: Double, stage: GenerationProgressStage)
    case completed(GeneratedFrame)
}

/// Coarse generation stages mapped from upload / poll status into the progress UI.
enum GenerationProgressStage: String, Sendable, Equatable {
    case preparing
    case uploading
    case queued
    case processing
    case finishing

    var rowTitle: String {
        switch self {
        case .preparing, .uploading:
            "收集此刻的种子"
        case .queued:
            "时间正在排队生长"
        case .processing:
            "时间正在生长"
        case .finishing:
            "收成这一帧"
        }
    }

    /// Representative progress floors used by the three-row Generation UI.
    var indicativeProgress: Double {
        switch self {
        case .preparing: 0.05
        case .uploading: 0.2
        case .queued: 0.4
        case .processing: 0.65
        case .finishing: 0.92
        }
    }
}
