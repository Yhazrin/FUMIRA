import SwiftUI

struct RootView: View {
    let model: AppModel

    @Namespace private var sceneNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var heroSlot: HeroSlotPreference?
    @State private var availableHeroSlots: [HeroSlotOwner: HeroSlotPreference] = [:]
    @State private var shutterFlash = 0.0

    var body: some View {
        // Full-bleed root geometry must match ViewfinderView's ignoresSafeArea
        // GeometryReader — otherwise preference frames and frost holes drift.
        GeometryReader { rootProxy in
            let rootSize = rootProxy.size
            let activeSlot = resolvedHeroSlot(in: rootSize)

            ZStack {
                // Permanent stage fill — phase views never fade this away.
                stageBackdrop
                    .ignoresSafeArea()
                    .animation(.posterPhaseChange(reduceMotion: reduceMotion), value: model.phase)

                // The persistent still-image hero begins after capture. The
                // live viewfinder owns its one full-screen preview independently.
                if let slot = activeSlot {
                    HeroPhotoSurface(model: model)
                        .frame(width: max(slot.frame.width, 1), height: max(slot.frame.height, 1))
                        .position(x: slot.frame.midX, y: slot.frame.midY)
                        .clipShape(
                            RoundedRectangle(cornerRadius: slot.cornerRadius, style: .continuous)
                        )
                        .shadow(
                            color: heroShadowColor,
                            radius: heroShadowRadius,
                            y: heroShadowY
                        )
                        .rotationEffect(.degrees(heroRotation))
                        .zIndex(20)
                        .allowsHitTesting(false)
                        .transition(.identity)
                        .animation(heroPlacementAnimation, value: slot.frame)
                        .animation(heroPlacementAnimation, value: slot.cornerRadius)
                        .animation(
                            .posterPhotoDrop(reduceMotion: reduceMotion),
                            value: heroRotation
                        )
                }

                // Page chrome above the hero (z > 20). Scope the phase
                // transaction here so camera/hero layers are not reanimated.
                phaseContent
                    .zIndex(30)
                    .animation(.posterPhaseChange(reduceMotion: reduceMotion), value: model.phase)

                // Viewfinder controls remain a sibling above the preview/shade.
                if model.phase == .viewfinder {
                    ViewfinderChromeOverlay(model: model)
                        .zIndex(50)
                        .transition(
                            .opacity.animation(
                                .posterPhaseChange(reduceMotion: reduceMotion)
                                    ?? .linear(duration: PosterMotion.reduced)
                            )
                        )
                }

                PosterEffects.cameraFlashWash
                    .opacity(shutterFlash)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .zIndex(60)
            }
            .frame(width: rootSize.width, height: rootSize.height)
            .coordinateSpace(name: HeroCoordinateSpace.name)
        }
        .ignoresSafeArea(
            .container,
            edges: usesFullBleedRoot ? .all : []
        )
        .statusBarHidden(model.phase == .viewfinder)
        .onPreferenceChange(HeroSlotPreferenceKey.self) { preferences in
            availableHeroSlots = preferences
            updateActiveHeroSlot(from: preferences)
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
                        .background(PosterPalette.canvas.opacity(0.88))
                        .clipShape(Circle())
                        .overlay {
                            Circle()
                                .stroke(PosterPalette.line, lineWidth: 1)
                        }
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
        .onAppear {
            syncMotionField()
        }
        .onDisappear {
            model.motionField.deactivate()
        }
        .onChange(of: model.phase) { _, phase in
            syncMotionField()
            if heroIsActive {
                updateActiveHeroSlot(from: availableHeroSlots)
            } else {
                heroSlot = nil
                availableHeroSlots = [:]
            }
        }
        .onChange(of: model.shutterFlashRequestID) { _, newID in
            guard newID != nil else { return }
            fireShutterFlash()
        }
        .onChange(of: reduceMotion) { _, _ in
            syncMotionField()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                syncMotionField()
            } else {
                model.motionField.deactivate()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .NSProcessInfoPowerStateDidChange
            )
        ) { _ in
            syncMotionField()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: ProcessInfo.thermalStateDidChangeNotification
            )
        ) { _ in
            syncMotionField()
        }
    }

    private func updateActiveHeroSlot(
        from preferences: [HeroSlotOwner: HeroSlotPreference]
    ) {
        guard
            !usesRootCompositionSlot,
            let owner = activeHeroSlotOwner,
            let preference = preferences[owner]
        else {
            return
        }

        // Phase transitions can publish both the outgoing and incoming slot in
        // the same render pass. Selecting by owner keeps the result image tied
        // to the result frame instead of whichever page reduced last.
        let isFirstPlacement = heroSlot == nil
        let apply = {
            heroSlot = preference
        }
        if reduceMotion || isFirstPlacement {
            apply()
        } else {
            withAnimation(.posterHeroMorph(reduceMotion: false)) {
                apply()
            }
        }
    }

    private var activeHeroSlotOwner: HeroSlotOwner? {
        switch model.phase {
        case .shuttered:
            .shuttered
        case .understanding:
            .understanding
        case .storyWriting:
            .storyWriting
        case .generating:
            .generating
        default:
            nil
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
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
                .transition(.cameraAperture(reduceMotion: reduceMotion))

        case .shuttered:
            ShutterFeedbackView(model: model, namespace: sceneNamespace)
                .transition(.photoDropAway(reduceMotion: reduceMotion))

        case .understanding:
            UnderstandingView(model: model, namespace: sceneNamespace)
                .transition(.photoDropIn(reduceMotion: reduceMotion))

        case .storyWriting:
            StoryWritingView(model: model)
                .transition(.posterPhase(reduceMotion: reduceMotion))

        case .generating:
            GenerationView(model: model, namespace: sceneNamespace)
                .transition(.posterPhase(reduceMotion: reduceMotion))

        case .result:
            ResultView(model: model, namespace: sceneNamespace)
                .transition(.generatedReveal(reduceMotion: reduceMotion))

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

    private var heroIsActive: Bool {
        switch model.phase {
        case .shuttered, .understanding, .storyWriting, .generating:
            true
        default:
            false
        }
    }

    /// Camera capture and the first paper landing share full-screen geometry.
    /// Utility/review pages keep system safe areas so compact titles never sit
    /// beneath status-bar or home-indicator content.
    private var usesFullBleedRoot: Bool {
        switch model.phase {
        case .viewfinder, .shuttered, .understanding:
            true
        default:
            false
        }
    }

    /// The shuttered stage begins at the exact viewfinder crop before later
    /// pipeline pages publish their own destination slots.
    private var usesRootCompositionSlot: Bool {
        switch model.phase {
        case .shuttered:
            true
        default:
            false
        }
    }

    private func resolvedHeroSlot(in rootSize: CGSize) -> HeroSlotPreference? {
        guard heroIsActive else { return nil }

        if usesRootCompositionSlot {
            let layout = CameraCompositionGeometry.layout(
                aspectRatio: model.cameraAspectRatio,
                in: rootSize
            )
            return HeroSlotPreference(
                frame: layout.heroFrame,
                cornerRadius: layout.cornerRadius
            )
        }

        return heroSlot
    }

    private var heroShadowColor: Color {
        switch model.phase {
        case .viewfinder:
            .clear
        case .understanding, .storyWriting, .generating:
            PosterEffects.photoPaperShadow
        case .shuttered:
            PosterPalette.ink.opacity(0.22)
        default:
            .clear
        }
    }

    private var heroShadowRadius: CGFloat {
        switch model.phase {
        case .viewfinder: 0
        case .shuttered: 18
        case .understanding: PosterEffects.photoPaperLandingShadowRadius
        default: 14
        }
    }

    private var heroShadowY: CGFloat {
        switch model.phase {
        case .viewfinder: 0
        case .shuttered: 10
        case .understanding: PosterEffects.photoPaperLandingShadowOffset
        default: 8
        }
    }

    private var heroRotation: Double {
        guard !reduceMotion else { return 0 }
        return switch model.phase {
        case .understanding: PosterMotion.photoPaperUnderstandingRotation
        case .storyWriting: PosterMotion.photoPaperStoryWritingRotation
        case .generating: PosterMotion.photoPaperGeneratingRotation
        default: 0
        }
    }

    private var heroPlacementAnimation: Animation? {
        if model.phase == .understanding {
            return .posterPhotoDrop(reduceMotion: reduceMotion)
        }
        return .posterHeroMorph(reduceMotion: reduceMotion)
    }

    /// Low-disruption Settings entry on non-immersive phases only.
    private var showsSettingsEntry: Bool {
        switch model.phase {
        case .connection,
             .bluetoothPermission,
             .connected,
             .cameraPermission,
             .viewfinder,
             .shuttered,
             .understanding,
             .storyWriting,
             .generating,
             .share:
            false
        case .result,
             .pipelineFailure,
             .disconnected:
            !model.isPipelineBusy
        }
    }

    /// Phase-aware fill so opacity transitions never reveal a black window.
    /// Result ambience lives here, below the persistent hero; placing it inside
    /// ResultView would cover the generated photo with an opaque page layer.
    @ViewBuilder
    private var stageBackdrop: some View {
        switch model.phase {
        case .viewfinder, .shuttered:
            PosterPalette.ink
        case .connection, .bluetoothPermission, .connected,
             .cameraPermission, .generating, .understanding,
             .storyWriting, .result, .share,
             .pipelineFailure, .disconnected:
            PosterPalette.canvas
        }
    }

    private func fireShutterFlash() {
        if reduceMotion {
            shutterFlash = 0.45
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                shutterFlash = 0
            }
            return
        }
        withAnimation(.linear(duration: PosterMotion.shutterFlashUp)) {
            shutterFlash = 0.78
        }
        withAnimation(
            .linear(duration: PosterMotion.shutterFlashDown)
                .delay(PosterMotion.shutterFlashUp)
        ) {
            shutterFlash = 0
        }
    }

    private func syncMotionField() {
        guard scenePhase == .active else {
            model.motionField.deactivate()
            return
        }
        model.syncMotionField(
            for: model.phase,
            reduceMotion: reduceMotion,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }
}

#Preview("Connection — 无设置入口") {
    RootView(model: PreviewFixtures.model(phase: .connection))
}

#Preview("Camera Permission — 无设置入口") {
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
