import ActivityKit
import Foundation

protocol CameraLiveActivityService: Sendable {
    func trigger(with state: CameraLiveActivityAttributes.ContentState) async throws
    func update(with state: CameraLiveActivityAttributes.ContentState) async
    func finish(with state: CameraLiveActivityAttributes.ContentState) async
    func dismissAll() async
}

struct MockCameraLiveActivityService: CameraLiveActivityService {
    func trigger(with state: CameraLiveActivityAttributes.ContentState) async throws {}
    func update(with state: CameraLiveActivityAttributes.ContentState) async {}
    func finish(with state: CameraLiveActivityAttributes.ContentState) async {}
    func dismissAll() async {}
}

actor LiveCameraLiveActivityService: CameraLiveActivityService {
    private var activity: CameraActivityHandle?

    func trigger(with state: CameraLiveActivityAttributes.ContentState) async throws {
        let enabled = await MainActor.run {
            ActivityAuthorizationInfo().areActivitiesEnabled
        }
        guard enabled else {
            throw CameraLiveActivityError.disabled
        }

        await dismissAll()

        let attributes = CameraLiveActivityAttributes(cameraName: "FUMIRA")
        let content = ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(20 * 60)
        )

        // ActivityKit must start on the main actor; requesting off-main can
        // create an activity that never renders in the Dynamic Island.
        let requested = try await MainActor.run {
            CameraActivityHandle(
                try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
            )
        }
        activity = requested
    }

    func update(with state: CameraLiveActivityAttributes.ContentState) async {
        guard let current = currentActivity else { return }
        let content = ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(20 * 60)
        )
        await current.value.update(content)
    }

    func finish(with state: CameraLiveActivityAttributes.ContentState) async {
        guard let current = currentActivity else { return }
        let content = ActivityContent(state: state, staleDate: nil)
        let dismissalDelay: TimeInterval = switch state.phase {
        case .ready:
            45
        case .failed:
            8
        case .framing, .capturing, .captured,
             .understanding, .storyWriting, .generating:
            3
        }
        await current.value.end(
            content,
            dismissalPolicy: .after(Date().addingTimeInterval(dismissalDelay))
        )
        activity = nil
    }

    func dismissAll() async {
        let activities = await MainActor.run {
            Activity<CameraLiveActivityAttributes>.activities.map(CameraActivityHandle.init)
        }
        for current in activities {
            await current.value.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
    }

    private var currentActivity: CameraActivityHandle? {
        if let activity, activity.value.activityState == .active {
            return activity
        }
        return Activity<CameraLiveActivityAttributes>.activities.first {
            $0.activityState == .active
        }.map(CameraActivityHandle.init)
    }
}

/// ActivityKit's reference type doesn't currently declare `Sendable`, although
/// its async mutation API is designed to cross executors. Keep that unchecked
/// boundary private and immutable instead of weakening the service actor.
private final class CameraActivityHandle: @unchecked Sendable {
    let value: Activity<CameraLiveActivityAttributes>

    init(_ value: Activity<CameraLiveActivityAttributes>) {
        self.value = value
    }
}

enum CameraLiveActivityError: LocalizedError {
    case disabled
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .disabled:
            "请先在系统设置中允许 FUMIRA 显示实时活动。"
        case let .requestFailed(message):
            message
        }
    }
}
