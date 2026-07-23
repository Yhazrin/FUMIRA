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
    case progress(Double)
    case completed(GeneratedFrame)
}
