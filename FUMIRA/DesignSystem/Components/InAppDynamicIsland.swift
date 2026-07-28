import SwiftUI

/// In-app Dynamic Island: a small, status-bar-friendly capsule that mimics the
/// iPhone 14 Pro+ hardware island. Native SwiftUI only — we don't reach into
/// ActivityKit. Use it for app-level status that the user might want at a
/// glance from the camera page (selected time, capture liveness, camera
/// controls).
///
/// Three states:
/// - ``IslandState/collapsed``: a short black pill with the app mark + a
///   short live caption ("25 年后").
/// - ``IslandState/expanded``: a wider black pill that surfaces camera
///   controls (aspect ratio, flip, flash, grid). Tap the collapsed form
///   to expand; tap the background scrim to dismiss.
/// - ``IslandState/recording``: a slightly wider pill with a pulsing red dot
///   — fires when the camera is in the middle of an actual capture / regenerate
///   cycle.
enum IslandState: Equatable {
    case collapsed
    case expanded
    case recording
}

/// iPhone 14 Pro+'s actual Dynamic Island is drawn as a rounded-rectangle with
/// a small corner radius (~20pt on a 1170×2532 panel) — not a full capsule.
/// ``IslandShape`` reproduces that exact look so the in-app island reads as
/// the same hardware.
struct IslandShape: Shape {
    var cornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(cornerRadius, cornerRadius) }
        set { cornerRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: rect)
    }
}

@available(iOS 17.0, *)
struct InAppDynamicIsland: View {
    @Binding var state: IslandState
    /// Captured by the host page — usually `selectedTime.compactLabel`.
    let timeCaption: String
    /// Tapping the expanded form's primary action triggers this. Hook to
    /// whatever the page thinks is "now".
    let primaryActionTitle: String
    let primaryAction: () -> Void
    /// Optional width hint used only when the island is ``expanded``. Pass a
    /// larger value to make the merged form span the whole top chrome
    /// (left capsule + center island + right capsule visually combine into
    /// a single continuous pill).
    var expandedMaxWidth: CGFloat? = nil
    /// Optional row of camera controls rendered inside the expanded form.
    /// The host page passes buttons for aspect ratio, flip, flash, grid —
    /// the same controls the chrome used to expose before.
    var controls: [IslandControl] = []

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Compact form width.
    private let collapsedWidth: CGFloat = 116
    private let collapsedHeight: CGFloat = 36
    private let expandedHeight: CGFloat = 88
    private let recordingWidth: CGFloat = 132

    /// Corner radius that matches the iPhone's hardware Dynamic Island.
    private let cornerRadius: CGFloat = 20

    private var targetWidth: CGFloat {
        switch state {
        case .collapsed: collapsedWidth
        case .expanded: expandedMaxWidth ?? 320
        case .recording: recordingWidth
        }
    }

    private var targetHeight: CGFloat {
        switch state {
        case .collapsed, .recording: collapsedHeight
        case .expanded: expandedHeight
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            if state == .expanded {
                PosterPalette.ink.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withIslandAnimation(.easeInOut(duration: 0.22)) {
                            state = .collapsed
                        }
                    }
            }

            islandBody
                .frame(width: targetWidth, height: targetHeight)
                .background(islandBackground)
                .clipShape(IslandShape(cornerRadius: cornerRadius))
                .animation(
                    reduceMotion
                        ? .linear(duration: PosterMotion.reduced)
                        : .spring(response: 0.36, dampingFraction: 0.84),
                    value: state
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    handleTap()
                }
                .gesture(
                    LongPressGesture(minimumDuration: 0.4)
                        .onEnded { _ in
                            guard state == .collapsed else { return }
                            withIslandAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                                state = .expanded
                            }
                        }
                )
        }
    }

    @ViewBuilder
    private var islandBody: some View {
        switch state {
        case .collapsed:
            collapsedContent
        case .expanded:
            expandedContent
        case .recording:
            recordingContent
        }
    }

    private var collapsedContent: some View {
        HStack(spacing: 6) {
            Image(systemName: "camera.aperture")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PosterPalette.paperWhite)
            Text(timeCaption)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(PosterPalette.paperWhite)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 14)
    }

    private var expandedContent: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PosterPalette.paperWhite)
                Text(timeCaption)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(PosterPalette.paperWhite)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                ForEach(controls.indices, id: \.self) { index in
                    IslandControlButton(
                        control: controls[index],
                        isLast: index == controls.count - 1
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private var recordingContent: some View {
        HStack(spacing: 8) {
            recordingDot
            Text("正在捕捉 · \(timeCaption)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(PosterPalette.paperWhite)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 14)
    }

    private var recordingDot: some View {
        Circle()
            .fill(PosterPalette.errorCoral)
            .frame(width: 8, height: 8)
            .posterPulse(period: 0.9)
    }

    @ViewBuilder
    private var islandBackground: some View {
        // Pure black, no gradient, no border — matches the real iPhone
        // Dynamic Island. Using ``Color.black`` (not ``PosterPalette.ink``)
        // so the merged form reads as one continuous black surface that the
        // side capsules dissolve into.
        IslandShape(cornerRadius: cornerRadius)
            .fill(Color.black)
    }

    private func handleTap() {
        switch state {
        case .collapsed:
            withIslandAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                state = .expanded
            }
        case .expanded:
            break
        case .recording:
            withIslandAnimation(.easeInOut(duration: 0.20)) {
                state = .collapsed
            }
        }
    }

    private func withIslandAnimation(_ animation: Animation, _ block: () -> Void) {
        if reduceMotion {
            block()
        } else {
            withAnimation(animation, block)
        }
    }
}

// MARK: - Controls

/// Compact circular control rendered inside the expanded Dynamic Island.
struct IslandControl: Identifiable {
    let id: String
    let systemImage: String
    let label: String
    let isEnabled: Bool
    let action: () -> Void
}

@available(iOS 17.0, *)
private struct IslandControlButton: View {
    let control: IslandControl
    let isLast: Bool

    var body: some View {
        Button {
            control.action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: control.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(
                        control.isEnabled
                            ? PosterPalette.paperWhite
                            : PosterPalette.paperWhite.opacity(0.35)
                    )
                    .frame(width: 40, height: 40)
                    .background(
                        (control.isEnabled
                            ? Color.white.opacity(0.10)
                            : Color.white.opacity(0.04))
                    )
                    .clipShape(Circle())
                Text(control.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(
                        control.isEnabled
                            ? PosterPalette.paperWhite.opacity(0.85)
                            : PosterPalette.paperWhite.opacity(0.30)
                    )
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!control.isEnabled)
        .accessibilityLabel(control.label)
    }
}

@available(iOS 17.0, *)
#Preview("Collapsed") {
    @Previewable @State var state: IslandState = .collapsed
    return ZStack {
        PosterPalette.skyDeep.ignoresSafeArea()
        InAppDynamicIsland(
            state: $state,
            timeCaption: "25 年后",
            primaryActionTitle: "取景",
            primaryAction: {}
        )
    }
}

@available(iOS 17.0, *)
#Preview("Expanded · controls") {
    @Previewable @State var state: IslandState = .expanded
    let controls: [IslandControl] = [
        .init(id: "a", systemImage: "arrow.triangle.2.circlepath", label: "翻转", isEnabled: true, action: {}),
        .init(id: "b", systemImage: "bolt.badge.automatic.fill", label: "闪光", isEnabled: true, action: {}),
        .init(id: "c", systemImage: "3.4.5.rectangle", label: "画幅", isEnabled: true, action: {}),
        .init(id: "d", systemImage: "grid", label: "网格", isEnabled: true, action: {})
    ]
    return ZStack {
        PosterPalette.skyDeep.ignoresSafeArea()
        InAppDynamicIsland(
            state: $state,
            timeCaption: "30 年后",
            primaryActionTitle: "取景",
            primaryAction: {},
            expandedMaxWidth: 360,
            controls: controls
        )
    }
}

@available(iOS 17.0, *)
#Preview("Recording") {
    @Previewable @State var state: IslandState = .recording
    return ZStack {
        PosterPalette.skyDeep.ignoresSafeArea()
        InAppDynamicIsland(
            state: $state,
            timeCaption: "目标",
            primaryActionTitle: "取景",
            primaryAction: {}
        )
    }
}
