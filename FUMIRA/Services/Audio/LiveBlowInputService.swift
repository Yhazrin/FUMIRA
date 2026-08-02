import AVFAudio
import Foundation

/// Reads short-lived microphone RMS levels through an `AVAudioEngine` input
/// tap. The tap is reduced to one dB value per buffer; raw samples are never
/// retained, encoded, recorded, or written to disk.
@MainActor
final class LiveBlowInputService: BlowInputProviding {
    private let audioEngine: AVAudioEngine
    private let audioSession: AVAudioSession
    private let clock: @Sendable () -> TimeInterval

    private var continuation: AsyncStream<BlowInputEvent>.Continuation?
    private var permissionTask: Task<Void, Never>?
    private var availability: BlowInputAvailability = .unknown
    private var isStarted = false
    private var isTapInstalled = false

    init(
        audioEngine: AVAudioEngine = AVAudioEngine(),
        audioSession: AVAudioSession = .sharedInstance(),
        clock: @escaping @Sendable () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        }
    ) {
        self.audioEngine = audioEngine
        self.audioSession = audioSession
        self.clock = clock
    }

    func events() -> AsyncStream<BlowInputEvent> {
        AsyncStream { continuation in
            self.continuation?.finish()
            self.continuation = continuation
            if self.availability != .unknown {
                continuation.yield(.availability(self.availability))
            }
        }
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

#if targetEnvironment(simulator)
        publishFallback(.inputUnavailable)
#else
        guard hasMicrophoneUsageDescription else {
            publishFallback(.microphoneUsageDescriptionMissing)
            return
        }

        permissionTask?.cancel()
        permissionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let granted = await self.requestMicrophonePermissionIfNeeded()
            guard !Task.isCancelled, self.isStarted else { return }
            self.permissionTask = nil

            guard granted else {
                self.publishFallback(.microphonePermissionDenied)
                return
            }
            self.beginLevelMonitoring()
        }
#endif
    }

    func stop() {
        guard isStarted || continuation != nil else { return }
        isStarted = false
        permissionTask?.cancel()
        permissionTask = nil
        stopLevelMonitoring()
        availability = .unknown
        continuation?.finish()
        continuation = nil
    }

    private var hasMicrophoneUsageDescription: Bool {
        guard let value = Bundle.main.object(
            forInfoDictionaryKey: "NSMicrophoneUsageDescription"
        ) as? String else {
            return false
        }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func requestMicrophonePermissionIfNeeded() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await AVAudioApplication.requestRecordPermission()
        @unknown default:
            return false
        }
    }

    private func beginLevelMonitoring() {
        guard isStarted else { return }
        guard audioSession.isInputAvailable else {
            publishFallback(.inputUnavailable)
            return
        }

        let engine = audioEngine
        let session = audioSession
        let clock = self.clock

        // Audio session + engine setup can block for 100-500 ms.
        // Dispatch to a background queue so the main run loop stays responsive.
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try session.setCategory(.record, mode: .measurement, options: [])
                try session.setActive(true)

                let inputNode = engine.inputNode
                let format = inputNode.outputFormat(forBus: 0)
                guard format.channelCount > 0, format.sampleRate > 0 else {
                    Task { @MainActor [weak self] in
                        self?.publishFallback(.inputUnavailable)
                    }
                    return
                }

                inputNode.installTap(
                    onBus: 0,
                    bufferSize: 1_024,
                    format: format
                ) { buffer, _ in
                    let decibels = Self.decibels(in: buffer)
                    let timestamp = clock()
                    Task { @MainActor [weak self] in
                        self?.publish(decibels: decibels, at: timestamp)
                    }
                }

                engine.prepare()
                try engine.start()
                Task { @MainActor [weak self] in
                    guard let self, self.isStarted else { return }
                    self.isTapInstalled = true
                    self.setAvailability(.liveMicrophone)
                }
            } catch {
                Task { @MainActor [weak self] in
                    self?.publishFallback(.configurationFailed)
                }
            }
        }
    }

    private func stopLevelMonitoring() {
        let engine = audioEngine
        let session = audioSession
        let tapInstalled = isTapInstalled
        isTapInstalled = false
        DispatchQueue.global(qos: .utility).async {
            if tapInstalled {
                engine.inputNode.removeTap(onBus: 0)
            }
            if engine.isRunning {
                engine.stop()
            }
            engine.reset()
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func publish(decibels: Double, at timestamp: TimeInterval) {
        guard isStarted, availability == .liveMicrophone else { return }
        guard decibels.isFinite, timestamp.isFinite else { return }
        continuation?.yield(
            .level(
                BlowInputLevelSample(
                    decibels: min(max(decibels, -120), 0),
                    timestamp: timestamp
                )
            )
        )
    }

    private func publishFallback(_ reason: BlowInputFallbackReason) {
        stopLevelMonitoring()
        isStarted = false
        setAvailability(.fallbackRequired(reason))
    }

    private func setAvailability(_ next: BlowInputAvailability) {
        guard next != availability else { return }
        availability = next
        continuation?.yield(.availability(next))
    }

    nonisolated private static func decibels(in buffer: AVAudioPCMBuffer) -> Double {
        guard let channel = buffer.floatChannelData?.pointee else { return -120 }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return -120 }

        var sumOfSquares = 0.0
        for index in 0..<frameCount {
            let sample = Double(channel[index])
            sumOfSquares += sample * sample
        }
        let rootMeanSquare = sqrt(sumOfSquares / Double(frameCount))
        let decibels = 20 * log10(max(rootMeanSquare, 0.000_001))
        return min(max(decibels, -120), 0)
    }
}
