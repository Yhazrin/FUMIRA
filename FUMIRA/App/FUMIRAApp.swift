import SwiftUI

@main
@MainActor
struct FUMIRAApp: App {
    @State private var model: AppModel

    init() {
        #if DEBUG
        if let phase = DebugAuditPhase.current {
            _model = State(initialValue: PreviewFixtures.model(
                phase: phase,
                time: 0.35,
                progress: 0.62,
                photoAspectRatio: DebugAuditAspectRatio.current,
                photoIsLandscape: DebugAuditPhotoOrientation.isLandscape
            ))
            return
        }
        #endif
        _model = State(initialValue: AppModel(dependencies: .runtime))
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .preferredColorScheme(.light)
                .task {
                    await model.prepare()
                }
                .onOpenURL { url in
                    model.handleDeepLink(url)
                }
        }
    }
}

#if DEBUG
private enum DebugAuditPhase {
    static var current: AppPhase? {
        guard let value = ProcessInfo.processInfo.environment["FUMIRA_AUDIT_PHASE"] else {
            return nil
        }

        return switch value {
        case "connection": .connection
        case "bluetoothPermission": .bluetoothPermission
        case "connected": .connected
        case "cameraPermission": .cameraPermission
        case "viewfinder": .viewfinder
        case "shuttered": .shuttered
        case "understanding": .understanding
        case "storyWriting": .storyWriting
        case "storyReady": .storyReady
        case "generating": .generating
        case "result": .result
        case "share": .share
        case "pipelineFailure": .pipelineFailure
        case "disconnected": .disconnected
        default: nil
        }
    }
}

private enum DebugAuditAspectRatio {
    static var current: CameraAspectRatio {
        switch ProcessInfo.processInfo.environment["FUMIRA_AUDIT_ASPECT"] {
        case "fullscreen": .fullScreen
        case "16:9": .widescreen
        case "1:1": .square
        default: .classic
        }
    }
}

private enum DebugAuditPhotoOrientation {
    static var isLandscape: Bool {
        ProcessInfo.processInfo.environment["FUMIRA_AUDIT_PHOTO_ORIENTATION"] == "landscape"
    }
}
#endif
