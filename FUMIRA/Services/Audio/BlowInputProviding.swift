import Foundation

enum BlowInputFallbackReason: Equatable, Sendable {
    case microphonePermissionDenied
    case microphoneUsageDescriptionMissing
    case inputUnavailable
    case configurationFailed
}

enum BlowInputAvailability: Equatable, Sendable {
    case unknown
    case liveMicrophone
    case fallbackRequired(BlowInputFallbackReason)
}

struct BlowInputLevelSample: Equatable, Sendable {
    /// RMS power for one in-memory input buffer, expressed in decibels and
    /// normally bounded to `-120...0`. No audio samples leave the service.
    let decibels: Double
    let timestamp: TimeInterval
}

enum BlowInputEvent: Equatable, Sendable {
    case availability(BlowInputAvailability)
    case level(BlowInputLevelSample)
}

/// Short-lived microphone level input for the result reveal.
///
/// Implementations publish only aggregate dB levels. They must not retain raw
/// buffers, create recordings, or write microphone data to storage. Consumers
/// use `fallbackRequired` to expose an accessible non-audio completion path.
@MainActor
protocol BlowInputProviding: AnyObject, Sendable {
    func events() -> AsyncStream<BlowInputEvent>
    func start()
    func stop()
}
