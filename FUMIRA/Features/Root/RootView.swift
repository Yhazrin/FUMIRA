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
            if !model.isPipelineBusy && model.phase != .share {
                Button {
                    model.isModelSettingsPresented = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.headline)
                        .foregroundStyle(PosterPalette.ink)
                        .frame(width: 44, height: 44)
                        .background(PosterPalette.paperWhite.opacity(0.9))
                        .clipShape(Circle())
                        .shadow(color: PosterEffects.floating, radius: 8, y: 4)
                }
                .padding(.trailing, PosterSpacing.lg)
                .padding(.top, PosterSpacing.sm)
                .accessibilityLabel("模型后台")
                .accessibilityHint("查看和选择识图、故事与生图模型路由")
            }
        }
        .sheet(isPresented: Bindable(model).isModelSettingsPresented) {
            ModelSettingsView(model: model)
        }
        .animation(.posterPhaseChange(reduceMotion: reduceMotion), value: model.phase)
    }
}

#Preview("Connection") {
    RootView(model: PreviewFixtures.model(phase: .connection))
}

#Preview("Viewfinder") {
    RootView(model: PreviewFixtures.model(phase: .viewfinder))
}

#Preview("Result") {
    RootView(model: PreviewFixtures.model(phase: .result, time: 0.4))
}

#Preview("Share") {
    RootView(model: PreviewFixtures.model(phase: .share, time: -0.6))
}
