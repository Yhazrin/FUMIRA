import Foundation

enum TemporalCaptureOrigin: Sendable, Equatable {
    case camera
    case photoLibrary
}

/// A user-authored narrative priority inside the frame. Coordinates are
/// normalized so the anchor survives device size, orientation, and the
/// canonical image crop without carrying view geometry into the domain.
struct TemporalSubjectAnchor: Sendable, Equatable, Codable {
    let normalizedX: Double
    let normalizedY: Double

    init(normalizedX: Double, normalizedY: Double) {
        self.normalizedX = min(max(normalizedX, 0), 1)
        self.normalizedY = min(max(normalizedY, 0), 1)
    }
}

/// A tiny, deliberately bounded preview of motion around the shutter moment.
/// It is context for scene interpretation, not a user-facing video recording.
struct TemporalFrameSample: Sendable, Equatable {
    let offsetFromShutter: TimeInterval
    let jpegData: Data
}

struct MicroTimeSlice: Sendable, Equatable {
    let duration: TimeInterval
    let frames: [TemporalFrameSample]

    static let unavailable = MicroTimeSlice(duration: 0, frames: [])

    var isAvailable: Bool {
        !frames.isEmpty
    }
}

struct TemporalSalientRegion: Identifiable, Sendable, Equatable, Codable {
    let id: UUID
    let normalizedX: Double
    let normalizedY: Double
    let normalizedWidth: Double
    let normalizedHeight: Double

    init(
        id: UUID = UUID(),
        normalizedX: Double,
        normalizedY: Double,
        normalizedWidth: Double,
        normalizedHeight: Double
    ) {
        self.id = id
        self.normalizedX = min(max(normalizedX, 0), 1)
        self.normalizedY = min(max(normalizedY, 0), 1)
        self.normalizedWidth = min(max(normalizedWidth, 0), 1)
        self.normalizedHeight = min(max(normalizedHeight, 0), 1)
    }
}

struct TemporalVisualContext: Sendable, Equatable {
    let foregroundMaskPNG: Data?
    let salientRegions: [TemporalSalientRegion]

    static let unavailable = TemporalVisualContext(
        foregroundMaskPNG: nil,
        salientRegions: []
    )

    var isAvailable: Bool {
        foregroundMaskPNG != nil || !salientRegions.isEmpty
    }
}

enum TemporalLightCondition: String, Sendable, Equatable, Codable {
    case lowLight
    case balanced
    case bright
    case unknown

    var shortLabel: String {
        switch self {
        case .lowLight: "暗光"
        case .balanced: "自然光"
        case .bright: "强光"
        case .unknown: "光线"
        }
    }
}

/// Native camera state frozen immediately around the shutter. It helps the
/// interpretation preserve how reality was observed, not only what the JPEG
/// contains. Imported photos intentionally fall back to `.unavailable`.
struct TemporalOpticalContext: Sendable, Equatable {
    let lensPosition: CameraLensPosition?
    let focusPosition: Float?
    let exposureDurationSeconds: Double?
    let iso: Float?
    let exposureTargetOffset: Float?
    let zoomFactor: Double?
    let lightCondition: TemporalLightCondition

    static let unavailable = TemporalOpticalContext(
        lensPosition: nil,
        focusPosition: nil,
        exposureDurationSeconds: nil,
        iso: nil,
        exposureTargetOffset: nil,
        zoomFactor: nil,
        lightCondition: .unknown
    )

    var isAvailable: Bool {
        lensPosition != nil
            || focusPosition != nil
            || exposureDurationSeconds != nil
            || iso != nil
            || zoomFactor != nil
    }
}

struct CaptureMotionSample: Sendable, Equatable {
    let timestamp: TimeInterval
    let roll: Double
    let pitch: Double
    let yaw: Double
    let rotationRate: Double
    let acceleration: Double
    let stability: Double
}

struct TemporalMotionContext: Sendable, Equatable {
    let samples: [CaptureMotionSample]
    let stabilityAtShutter: Double
    let wasAnchored: Bool

    static let unavailable = TemporalMotionContext(
        samples: [],
        stabilityAtShutter: 0,
        wasAnchored: false
    )
}

/// The capture is intentionally richer than the JPEG while remaining bounded
/// and privacy-safe. Future depth, segmentation, or ambient summaries can be
/// added without changing the main capture pipeline.
struct TemporalCapturePacket: Identifiable, Sendable, Equatable {
    let id: UUID
    let photo: CapturedPhoto
    let origin: TemporalCaptureOrigin
    let composition: CameraAspectRatio
    let shutterDate: Date
    let motion: TemporalMotionContext
    let microTimeSlice: MicroTimeSlice
    let subjectAnchor: TemporalSubjectAnchor?
    let visualContext: TemporalVisualContext
    let opticalContext: TemporalOpticalContext

    init(
        id: UUID = UUID(),
        photo: CapturedPhoto,
        origin: TemporalCaptureOrigin,
        composition: CameraAspectRatio,
        shutterDate: Date,
        motion: TemporalMotionContext,
        microTimeSlice: MicroTimeSlice = .unavailable,
        subjectAnchor: TemporalSubjectAnchor? = nil,
        visualContext: TemporalVisualContext = .unavailable,
        opticalContext: TemporalOpticalContext = .unavailable
    ) {
        self.id = id
        self.photo = photo
        self.origin = origin
        self.composition = composition
        self.shutterDate = shutterDate
        self.motion = motion
        self.microTimeSlice = microTimeSlice
        self.subjectAnchor = subjectAnchor
        self.visualContext = visualContext
        self.opticalContext = opticalContext
    }
}
