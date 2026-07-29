import SwiftUI

@main
@MainActor
struct FUMIRAApp: App {
    @State private var model: AppModel

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["FUMIRA_AUDIT_LIVE_ACTIVITY"] == "trigger" {
            let auditModel = AppModel(dependencies: .runtime)
            auditModel.phase = .viewfinder
            _model = State(initialValue: auditModel)
            return
        }

        if let phase = DebugAuditPhase.current {
            let auditModel = PreviewFixtures.model(
                phase: phase,
                time: 0.35,
                progress: 0.62,
                photoAspectRatio: DebugAuditAspectRatio.current,
                photoIsLandscape: DebugAuditPhotoOrientation.isLandscape
            )
            auditModel.isModelSettingsPresented =
                ProcessInfo.processInfo.environment["FUMIRA_AUDIT_SETTINGS"] == "1"
            _model = State(initialValue: auditModel)
            return
        }
        #endif
        _model = State(initialValue: AppModel(dependencies: .runtime))
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .preferredColorScheme(model.phase == .viewfinder ? .dark : .light)
                .task {
                    await model.prepare()
                    #if DEBUG
                    await runDebugAuditTransitionIfNeeded()
                    #endif
                }
                .onOpenURL { url in
                    model.handleDeepLink(url)
                }
        }
    }

    #if DEBUG
    private func runDebugAuditTransitionIfNeeded() async {
        let delay = auditTransitionDelay
        switch ProcessInfo.processInfo.environment["FUMIRA_AUDIT_TRANSITION"] {
        case "photoDrop":
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, model.phase == .shuttered else { return }
            model.phase = .generating
        case "result":
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, model.phase == .generating else { return }
            model.phase = .result
        case "capture":
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, model.phase == .shuttered else { return }
            model.phase = .understanding
        default:
            return
        }
    }

    private var auditTransitionDelay: Duration {
        let milliseconds = Int(
            ProcessInfo.processInfo.environment["FUMIRA_AUDIT_DELAY_MS"] ?? "900"
        ) ?? 900
        return .milliseconds(max(milliseconds, 0))
    }
    #endif
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
