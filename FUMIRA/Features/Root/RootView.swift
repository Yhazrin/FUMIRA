import SwiftUI

struct RootView: View {
    let model: AppModel

    @Namespace private var sceneNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch model.phase {
            case .connection:
                ConnectionView(model: model)
                    .transition(.posterPhase(reduceMotion: reduceMotion))

            case .bluetoothPermission:
                BluetoothPermissionView(model: model)
                    .transition(.posterPhase(reduceMotion: reduceMotion))

            case .connected:
                if let snapshot = model.hardwareSnapshot {
                    ConnectionFeedbackView(model: model, snapshot: snapshot)
                        .transition(.posterPhase(reduceMotion: reduceMotion))
                } else {
                    ConnectionView(model: model)
                }

            case .cameraPermission:
                CameraPermissionView(model: model)
                    .transition(.posterPhase(reduceMotion: reduceMotion))

            case .viewfinder:
                ViewfinderView(model: model, namespace: sceneNamespace)
                    .transition(.posterPhase(reduceMotion: reduceMotion))

            case .shuttered:
                ShutterFeedbackView(model: model, namespace: sceneNamespace)
                    .transition(.posterPhase(reduceMotion: reduceMotion))

            case .understanding:
                UnderstandingView(model: model)
                    .transition(.posterPhase(reduceMotion: reduceMotion))

            case .storyWriting:
                StoryWritingView(model: model)
                    .transition(.posterPhase(reduceMotion: reduceMotion))

            case .storyReady:
                StoryReadyView(model: model)
                    .transition(.posterPhase(reduceMotion: reduceMotion))

            case .generating:
                GenerationView(model: model, namespace: sceneNamespace)
                    .transition(.posterPhase(reduceMotion: reduceMotion))

            case .result:
                ResultView(model: model, namespace: sceneNamespace)
                    .transition(.posterPhase(reduceMotion: reduceMotion))

            case .share:
                SharePosterView(model: model)
                    .transition(.posterPhase(reduceMotion: reduceMotion))

            case .pipelineFailure:
                GenerationFailureView(model: model)
                    .transition(.posterPhase(reduceMotion: reduceMotion))

            case .disconnected:
                DisconnectedView(model: model)
                    .transition(.posterPhase(reduceMotion: reduceMotion))
            }
        }
        .overlay(alignment: .topTrailing) {
            if showsSettingsEntry {
                Button {
                    model.openSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(PosterPalette.ink.opacity(0.72))
                        .frame(width: 44, height: 44)
                        .background(PosterPalette.paperWhite.opacity(0.72))
                        .clipShape(Circle())
                }
                .padding(.trailing, PosterSpacing.lg)
                .padding(.top, PosterSpacing.sm)
                .accessibilityLabel("设置")
                .accessibilityHint("打开通用设置；模型路由在高级选项中")
            }
        }
        .sheet(isPresented: Bindable(model).isModelSettingsPresented) {
            SettingsView(model: model)
        }
        .animation(.posterPhaseChange(reduceMotion: reduceMotion), value: model.phase)
    }

    /// Low-disruption Settings entry on non-immersive phases only.
    /// Connection and camera/pipeline immersive phases never show this control.
    private var showsSettingsEntry: Bool {
        switch model.phase {
        case .connection,
             .viewfinder,
             .shuttered,
             .understanding,
             .storyWriting,
             .generating,
             .share:
            false
        case .bluetoothPermission,
             .connected,
             .cameraPermission,
             .storyReady,
             .result,
             .pipelineFailure,
             .disconnected:
            !model.isPipelineBusy
        }
    }
}

#Preview("Connection — 无设置入口") {
    RootView(model: PreviewFixtures.model(phase: .connection))
}

#Preview("Camera Permission — 有设置入口") {
    RootView(model: PreviewFixtures.model(phase: .cameraPermission))
}

#Preview("Viewfinder — 无全局设置") {
    RootView(model: PreviewFixtures.model(phase: .viewfinder))
}

#Preview("Result") {
    RootView(model: PreviewFixtures.model(phase: .result, time: 0.4))
}

#Preview("Share") {
    RootView(model: PreviewFixtures.model(phase: .share, time: -0.6))
}
