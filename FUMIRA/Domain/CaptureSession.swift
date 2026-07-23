import Foundation

struct CaptureSession: Identifiable, Hashable, Sendable {
    let id: UUID
    let capturedAt: Date

    init(id: UUID = UUID(), capturedAt: Date = .now) {
        self.id = id
        self.capturedAt = capturedAt
    }
}
