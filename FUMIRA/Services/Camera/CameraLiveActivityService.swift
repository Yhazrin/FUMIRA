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
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw CameraLiveActivityError.disabled
        }

        await dismissAll()

        let attributes = CameraLiveActivityAttributes(cameraName: "FUMIRA")
        let content = ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(10 * 60)
        )

        if #available(iOS 18.0, *) {
            activity = CameraActivityHandle(
                try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil,
                    style: .transient
                )
            )
        } else {
            activity = CameraActivityHandle(
                try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
            )
        }
    }

    func update(with state: CameraLiveActivityAttributes.ContentState) async {
        guard let current = currentActivity else { return }
        let content = ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(10 * 60)
        )
        await current.value.update(content)
    }

    func finish(with state: CameraLiveActivityAttributes.ContentState) async {
        guard let current = currentActivity else { return }
        let content = ActivityContent(state: state, staleDate: nil)
        await current.value.end(
            content,
            dismissalPolicy: .after(Date().addingTimeInterval(1.2))
        )
        activity = nil
    }

    func dismissAll() async {
        for current in Activity<CameraLiveActivityAttributes>.activities {
            await current.end(nil, dismissalPolicy: .immediate)
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

    var errorDescription: String? {
        switch self {
        case .disabled:
            "请先在系统设置中允许 FUMIRA 显示实时活动。"
        }
    }
}
