import SwiftUI

struct RootView: View {
    let model: AppModel

    @Namespace private var sceneNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var heroSlot: HeroSlotPreference?
    /// The shutter view uses a root-computed crop instead of publishing a
    /// preference. Cache that exact rect so the first developing frame can
    /// continue from it while the incoming destination preference resolves.
    @State private var shutteredHeroSlot: HeroSlotPreference?
    @State private var availableHeroSlots: [HeroSlotOwner: HeroSlotPreference] = [:]
    @State private var shutterFlash = 0.0
    @State private var cameraEntryProgress: CGFloat = 0
    @State private var captureProgress: CGFloat = 0
    @State private var spatialTimelineID = UUID()
    @State private var isEnteringCamera = false

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
                    if heroHandManipulationEnabled {
                        HeroPhotoSurface(
                            model: model,
                            spatialProgress: photoSpatialProgress,
                            timeRevealProgress: model.resultRevealProgress,
                            handManipulationEnabled: true
                        )
                            .frame(width: max(slot.frame.width, 1), height: max(slot.frame.height, 1))
                            .position(x: slot.frame.midX, y: slot.frame.midY)
                            .shadow(
                                color: heroShadowColor,
                                radius: heroShadowRadius,
                                y: heroShadowY
                            )
                            // The hand-held print sits above the clear stage
                            // reporter, but below non-photo controls.
                            .zIndex(31)
                            .transition(.identity)
                    } else {
                        HeroPhotoSurface(
                            model: model,
                            spatialProgress: photoSpatialProgress,
                            timeRevealProgress: model.resultRevealProgress
                        )
                            .frame(width: max(slot.frame.width, 1), height: max(slot.frame.height, 1))
                            .position(x: slot.frame.midX, y: slot.frame.midY)
                            .clipShape(heroClipShape(for: slot))
                            .shadow(
                                color: heroShadowColor,
                                radius: heroShadowRadius,
                                y: heroShadowY
                            )
                            .zIndex(20)
                            .allowsHitTesting(false)
                            .transition(.identity)
                    }
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
                } else if model.phase == .shuttered {
                    CameraCaptureDepartureChrome(
                        progress: captureProgress,
                        reduceMotion: reduceMotion,
                        aspectRatio: model.cameraAspectRatio,
                        selectedTimeNormalized: model.selectedTime.normalized
                    )
                    .zIndex(50)
                }

                PosterEffects.cameraFlashWash
                    .opacity(shutterFlash)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .zIndex(60)

                if cameraEntryProgress > 0.001 || isEnteringCamera {
                    CameraEntryPortal(
                        progress: cameraEntryProgress,
                        reduceMotion: reduceMotion
                    )
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .zIndex(100)
                }
            }
            .frame(width: rootSize.width, height: rootSize.height)
            .coordinateSpace(name: HeroCoordinateSpace.name)
            .onChange(of: activeSlot, initial: true) { _, slot in
                if model.phase == .shuttered, let slot {
                    shutteredHeroSlot = slot
                }
            }
        }
        .ignoresSafeArea(
            .container,
            edges: usesFullBleedRoot ? .all : []
        )
        // Keep the system status region alive in the viewfinder. The real
        // ActivityKit Dynamic Island needs that system-owned geometry; the
        // camera preview itself still extends full-bleed underneath it.
        .statusBarHidden(false)
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
                    .background(PosterPalette.cardLight)
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .stroke(PosterPalette.line, lineWidth: 1)
                    }
            }
            .posterZoomSource(
                namespace: sceneNamespace,
                id: PosterZoomID.settingsCog,
                cornerRadius: PosterRadius.control
            )
            .padding(.trailing, PosterSpacing.lg)
            .padding(.top, PosterSpacing.sm)
            .accessibilityLabel("设置")
            .accessibilityHint("打开通用设置；模型路由在高级选项中")
        }
    }
    .sheet(isPresented: Bindable(model).isModelSettingsPresented) {
        SettingsView(model: model)
            .posterZoomDestination(
                namespace: sceneNamespace,
                id: PosterZoomID.settingsCog
            )
        }
        .onAppear {
            syncMotionField()
            resetSpatialTimelinesForCurrentPhase()
        }
        #if DEBUG
        .task {
            await runCameraEntryAuditIfNeeded()
        }
        #endif
        .onDisappear {
            resetSpatialTimelines()
            model.motionField.deactivate()
            model.captureMotion.deactivate()
        }
        .onChange(of: model.phase) { previous, phase in
            syncMotionField()
            syncSpatialTimeline(from: previous, to: phase)
            if previous == .shuttered,
               phase == .understanding,
               heroSlot == nil {
                heroSlot = shutteredHeroSlot
            }
            if heroIsActive {
                updateActiveHeroSlot(from: availableHeroSlots)
            } else {
                heroSlot = nil
                shutteredHeroSlot = nil
                availableHeroSlots = [:]
            }
        }
        .onChange(of: model.shutterFlashRequestID) { _, newID in
            guard newID != nil else { return }
            fireShutterFlash()
        }
        .onChange(of: reduceMotion) { _, _ in
            syncMotionField()
            resetSpatialTimelinesForCurrentPhase()
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
        case .result:
            .result
        default:
            nil
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch model.phase {
        case .connection:
            ConnectionView(
                model: model,
                entryProgress: cameraEntryProgress,
                onLaunchCamera: beginCameraEntry
            )
                .transition(.posterPhase(reduceMotion: reduceMotion))

        case .bluetoothPermission:
            BluetoothPermissionView(model: model)
                .transition(.posterPhase(reduceMotion: reduceMotion))

        case .connected:
            if let snapshot = model.hardwareSnapshot {
                ConnectionFeedbackView(model: model, snapshot: snapshot)
                    .transition(.posterPhase(reduceMotion: reduceMotion))
            } else {
                ConnectionView(model: model, onLaunchCamera: beginCameraEntry)
            }

        case .cameraPermission:
            CameraPermissionView(
                model: model,
                onLaunchViewfinder: beginViewfinderEntry
            )
                .transition(.posterPhase(reduceMotion: reduceMotion))

        case .viewfinder:
            ViewfinderView(model: model, namespace: sceneNamespace)
                .transition(.cameraAperture(reduceMotion: reduceMotion))

        case .shuttered:
            ShutterFeedbackView(model: model, namespace: sceneNamespace)
                .transition(.photoDropAway(reduceMotion: reduceMotion))

        case .understanding, .storyWriting, .generating:
            RealityDevelopingView(model: model)
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
        case .shuttered, .understanding, .storyWriting, .generating, .result:
            true
        default:
            false
        }
    }

    /// Direct manipulation begins only after the physical capture has landed.
    /// The result screen keeps its own time-door and panel gestures, while the
    /// developing stages turn the shared print into an object users can hold.
    private var heroHandManipulationEnabled: Bool {
        guard !reduceMotion else { return false }
        return switch model.phase {
        case .understanding, .storyWriting, .generating:
            true
        default:
            false
        }
    }

    private func beginCameraEntry() {
        guard !isEnteringCamera else { return }
        guard !reduceMotion else {
            model.beginPhoneOnlyPath()
            return
        }

        isEnteringCamera = true
        let timelineID = UUID()
        spatialTimelineID = timelineID
        withAnimation(PosterMotion.cameraEntry) {
            cameraEntryProgress = 1
        } completion: {
            guard spatialTimelineID == timelineID else { return }
            isEnteringCamera = false
            cameraEntryProgress = 0
        }

        // Navigation is an immediate response to the user's tap. The portal
        // is only a transient acknowledgement layer; it must never own the
        // permission flow or hold the app on the connection screen if an
        // animation completion is interrupted by a system permission sheet.
        model.beginPhoneOnlyPath()
    }

    /// Reuses the same lens portal after the permission page. The permission
    /// request is asynchronous, but the visual transform remains one
    /// interruptible progress value rather than a delayed page swap.
    private func beginViewfinderEntry() {
        Task { await model.grantCameraAccess() }
    }

    #if DEBUG
    private func runCameraEntryAuditIfNeeded() async {
        guard
            ProcessInfo.processInfo.environment["FUMIRA_AUDIT_CAMERA_ENTRY"] == "1",
            model.phase == .connection
        else {
            return
        }

        let milliseconds = Int(
            ProcessInfo.processInfo.environment["FUMIRA_AUDIT_DELAY_MS"] ?? "700"
        ) ?? 700
        try? await Task<Never, Never>.sleep(for: .milliseconds(max(milliseconds, 0)))
        guard !Task.isCancelled, model.phase == .connection else { return }
        beginCameraEntry()
    }
    #endif

    /// Camera capture and the first paper landing share full-screen geometry.
    /// Utility/review pages keep system safe areas so compact titles never sit
    /// beneath status-bar or home-indicator content.
    private var usesFullBleedRoot: Bool {
        switch model.phase {
        case .connection, .cameraPermission, .viewfinder, .shuttered, .understanding,
             .storyWriting, .generating:
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

        if model.phase == .understanding {
            let source = shutteredHeroSlot ?? HeroSlotPreference(
                frame: CameraCompositionGeometry.layout(
                    aspectRatio: model.cameraAspectRatio,
                    in: rootSize
                ).heroFrame,
                cornerRadius: CameraCompositionGeometry.layout(
                    aspectRatio: model.cameraAspectRatio,
                    in: rootSize
                ).cornerRadius
            )
            let destination = HeroSlotPreference(
                frame: RealityDevelopingGeometry.photoFrame(
                    in: rootSize,
                    aspectRatio: CGFloat(
                        model.capturedPhoto?.displayAspectRatio ?? 3.0 / 4.0
                    )
                ),
                cornerRadius: PosterRadius.photoPaper
            )
            return source.interpolated(
                to: destination,
                progress: developingLandingProgress
            )
        }
        return heroSlot
    }

    private var developingLandingProgress: CGFloat {
        FUMIRASpatialMotion.map(
            captureProgress,
            from: 0.72...1,
            to: 0...1
        )
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
        case .shuttered: 18 * captureLiftProgress
        case .understanding: PosterEffects.photoPaperLandingShadowRadius
        default: 14
        }
    }

    private var heroShadowY: CGFloat {
        switch model.phase {
        case .viewfinder: 0
        case .shuttered: 10 * captureLiftProgress
        case .understanding: PosterEffects.photoPaperLandingShadowOffset
        default: 8
        }
    }

    private var captureLiftProgress: CGFloat {
        min(max(captureProgress / 0.72, 0), 1)
    }

    private func heroClipShape(for slot: HeroSlotPreference) -> AnyShape {
        switch model.phase {
        case .shuttered:
            return AnyShape(
                UnevenRoundedRectangle(
                    cornerRadii: RectangleCornerRadii(
                        topLeading: 0,
                        bottomLeading: slot.cornerRadius,
                        bottomTrailing: slot.cornerRadius,
                        topTrailing: 0
                    ),
                    style: .continuous
                )
            )
        case .understanding:
            let topRadius = slot.cornerRadius * developingLandingProgress
            return AnyShape(
                UnevenRoundedRectangle(
                    cornerRadii: RectangleCornerRadii(
                        topLeading: topRadius,
                        bottomLeading: slot.cornerRadius,
                        bottomTrailing: slot.cornerRadius,
                        topTrailing: topRadius
                    ),
                    style: .continuous
                )
            )
        default:
            return AnyShape(
                RoundedRectangle(
                    cornerRadius: slot.cornerRadius,
                    style: .continuous
                )
            )
        }
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
            !model.isPipelineBusy && !model.isRealityAlignmentPresented
        }
    }

    /// Phase-aware fill so opacity transitions never reveal a black window.
    /// Result ambience lives here, below the persistent hero; placing it inside
    /// ResultView would cover the generated photo with an opaque page layer.
    @ViewBuilder
    private var stageBackdrop: some View {
        switch model.phase {
        case .viewfinder, .shuttered:
            PosterPalette.cameraBody
        case .understanding, .storyWriting, .generating:
            FrozenRealityBackdrop(
                image: model.decodedCapturedImage,
                motion: model.captureMotion
            )
        case .connection, .bluetoothPermission, .connected,
             .cameraPermission, .result, .share,
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

    /// RootView owns the three semantic spatial tracks: phase views publish
    /// chrome and destination geometry only, while these values remain
    /// continuous through the phase boundary.
    private var photoSpatialProgress: CGFloat {
        switch model.phase {
        case .shuttered, .understanding:
            FUMIRASpatialMotion.spatialPulse(captureProgress)
        case .result:
            FUMIRASpatialMotion.spatialPulse(model.resultRevealProgress)
        default:
            0
        }
    }

    private func resetSpatialTimelines() {
        spatialTimelineID = UUID()
        cameraEntryProgress = 0
        captureProgress = 0
        isEnteringCamera = false
    }

    private func resetSpatialTimelinesForCurrentPhase() {
        resetSpatialTimelines()
        if model.phase == .understanding {
            captureProgress = 1
        }
    }

    private func syncSpatialTimeline(from previous: AppPhase, to phase: AppPhase) {
        // The phase switch to the permission page happens at the portal's
        // aperture apex. Preserve the in-flight identity so its resolve leg
        // can complete instead of being cancelled by the business phase.
        if isEnteringCamera,
           (MotionTimeline.transition(from: previous, to: phase) == .cameraEntry
                || (previous == .cameraPermission && phase == .viewfinder)) {
            return
        }
        let timelineID = UUID()
        spatialTimelineID = timelineID

        guard !reduceMotion else {
            if phase == .understanding { captureProgress = 1 }
            return
        }

        switch MotionTimeline.transition(from: previous, to: phase) {
        case .capture where phase == .shuttered:
            captureProgress = 0
            withAnimation(PosterMotion.captureLift) {
                captureProgress = 0.72
            }
        case .capture where phase == .understanding:
            withAnimation(PosterMotion.captureSettle) {
                captureProgress = 1
            }
        case .timeReveal:
            return
        case .none, .cameraEntry, .capture:
            if phase != .shuttered && phase != .understanding {
                captureProgress = 0
            }
        }
    }

    private func syncMotionField() {
        guard scenePhase == .active else {
            model.motionField.deactivate()
            model.captureMotion.deactivate()
            return
        }
        model.syncMotionField(
            for: model.phase,
            reduceMotion: reduceMotion,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
        model.syncCaptureMotion(for: model.phase, sceneIsActive: true)
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
