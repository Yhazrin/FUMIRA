import ActivityKit
import SwiftUI
import WidgetKit

struct CameraLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CameraLiveActivityAttributes.self) { context in
            lockScreenView(context.state)
                .activityBackgroundTint(CameraActivityStyle.islandBlack)
                .activitySystemActionForegroundColor(CameraActivityStyle.paperWhite)
                .widgetURL(activityURL(for: context.state))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    activityMark(context.state)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    trailingValue(context.state)
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 1) {
                        Text("FUMIRA")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(CameraActivityStyle.blue)
                        Text(statusText(for: context.state))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CameraActivityStyle.paperWhite)
                            .contentTransition(.numericText())
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    expandedContent(context.state)
                }
            } compactLeading: {
                activityMark(context.state)
            } compactTrailing: {
                compactTrailing(context.state)
            } minimal: {
                Image(systemName: phaseSymbol(for: context.state.phase))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CameraActivityStyle.blue)
                    .contentTransition(.symbolEffect(.replace))
            }
            .keylineTint(CameraActivityStyle.blue)
            .widgetURL(activityURL(for: context.state))
        }
    }

    private func lockScreenView(
        _ state: CameraLiveActivityAttributes.ContentState
    ) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                activityMark(state)

                VStack(alignment: .leading, spacing: 2) {
                    Text("FUMIRA 时间相机")
                        .font(.headline)
                        .foregroundStyle(CameraActivityStyle.paperWhite)
                    Text(statusText(for: state))
                        .font(.caption)
                        .foregroundStyle(CameraActivityStyle.secondaryText)
                }

                Spacer(minLength: 8)

                trailingValue(state)
            }

            expandedContent(state)
        }
        .padding(16)
    }

    @ViewBuilder
    private func compactTrailing(
        _ state: CameraLiveActivityAttributes.ContentState
    ) -> some View {
        switch state.phase {
        case .framing:
            Text(state.zoomLabel)
                .font(.caption.weight(.bold))
                .foregroundStyle(CameraActivityStyle.paperWhite)
                .monospacedDigit()
        case .capturing:
            Image(systemName: "camera.shutter.button.fill")
                .foregroundStyle(CameraActivityStyle.paperWhite)
        case .captured:
            Image(systemName: "checkmark")
                .font(.caption.weight(.black))
                .foregroundStyle(CameraActivityStyle.paperWhite)
        case .understanding, .storyWriting, .generating:
            Text(state.normalizedProgress, format: .percent.precision(.fractionLength(0)))
                .font(.caption2.weight(.black))
                .foregroundStyle(CameraActivityStyle.paperWhite)
                .monospacedDigit()
                .contentTransition(.numericText())
        case .ready:
            Image(systemName: "sparkles")
                .font(.caption.weight(.black))
                .foregroundStyle(CameraActivityStyle.yellow)
                .contentTransition(.symbolEffect(.replace))
        case .failed:
            Image(systemName: "exclamationmark")
                .font(.caption.weight(.black))
                .foregroundStyle(CameraActivityStyle.coral)
        }
    }

    private func activityMark(
        _ state: CameraLiveActivityAttributes.ContentState
    ) -> some View {
        ZStack {
            Circle()
                .fill(CameraActivityStyle.blue)

            if state.isCameraPhase {
                Circle()
                    .fill(CameraActivityStyle.paperWhite)
                    .padding(4)
                Circle()
                    .fill(CameraActivityStyle.blue)
                    .frame(width: 4, height: 4)
            } else {
                Image(systemName: phaseSymbol(for: state.phase))
                    .font(.caption2.weight(.black))
                    .foregroundStyle(
                        state.phase == .ready
                            ? CameraActivityStyle.yellow
                            : CameraActivityStyle.paperWhite
                    )
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .frame(width: 24, height: 24)
    }

    @ViewBuilder
    private func expandedContent(
        _ state: CameraLiveActivityAttributes.ContentState
    ) -> some View {
        if state.isCameraPhase {
            expandedControls(state)
        } else if state.isProcessing {
            processingProgress(state)
        } else if state.phase == .ready {
            Link(destination: CameraActivityLink.result) {
                Label("打开时间照片", systemImage: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CameraActivityStyle.islandBlack)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(CameraActivityStyle.yellow, in: Capsule())
            }
        } else {
            Label("轻点返回 FUMIRA", systemImage: "arrow.clockwise")
                .font(.caption.weight(.semibold))
                .foregroundStyle(CameraActivityStyle.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 36)
        }
    }

    private func expandedControls(
        _ state: CameraLiveActivityAttributes.ContentState
    ) -> some View {
        HStack(spacing: 14) {
            activityControl(
                destination: CameraActivityLink.flash,
                systemImage: state.flashSymbol,
                label: "闪光"
            )
            activityControl(
                destination: CameraActivityLink.lens,
                systemImage: state.lensSymbol,
                label: "镜头"
            )
            activityControl(
                destination: CameraActivityLink.grid,
                systemImage: state.isGridEnabled ? "square.grid.3x3.fill" : "square.grid.3x3",
                label: "网格",
                isActive: state.isGridEnabled
            )
            activityControl(
                destination: CameraActivityLink.aspect,
                text: state.aspectRatioLabel,
                label: "画幅"
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private func processingProgress(
        _ state: CameraLiveActivityAttributes.ContentState
    ) -> some View {
        VStack(spacing: 6) {
            ProgressView(value: state.normalizedProgress)
                .tint(CameraActivityStyle.yellow)

            HStack {
                Spacer()
                Text(state.targetLabel)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(CameraActivityStyle.secondaryText)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func trailingValue(
        _ state: CameraLiveActivityAttributes.ContentState
    ) -> some View {
        if state.isCameraPhase {
            Text(state.zoomLabel)
                .font(.system(.body, design: .rounded, weight: .bold))
                .foregroundStyle(CameraActivityStyle.paperWhite)
                .monospacedDigit()
        } else if state.isProcessing {
            Text(state.normalizedProgress, format: .percent.precision(.fractionLength(0)))
                .font(.system(.body, design: .rounded, weight: .bold))
                .foregroundStyle(CameraActivityStyle.paperWhite)
                .monospacedDigit()
                .contentTransition(.numericText())
        } else {
            Image(systemName: state.phase == .ready ? "checkmark" : "exclamationmark")
                .font(.body.weight(.black))
                .foregroundStyle(
                    state.phase == .ready
                        ? CameraActivityStyle.yellow
                        : CameraActivityStyle.coral
                )
        }
    }

    private func activityControl(
        destination: URL,
        systemImage: String? = nil,
        text: String? = nil,
        label: String,
        isActive: Bool = false
    ) -> some View {
        Link(destination: destination) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(
                            isActive
                                ? CameraActivityStyle.activeControl
                                : CameraActivityStyle.controlFill
                        )

                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.caption.weight(.bold))
                    } else if let text {
                        Text(text)
                            .font(.caption2.weight(.black))
                    }
                }
                .frame(width: 36, height: 36)

                Text(label)
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(CameraActivityStyle.paperWhite)
        }
    }

    private func statusText(
        for state: CameraLiveActivityAttributes.ContentState
    ) -> String {
        switch state.phase {
        case .framing:
            "\(state.targetLabel) · \(state.aspectRatioLabel)"
        case .capturing:
            "正在捕捉"
        case .captured:
            "现实已定锚"
        case .understanding:
            "正在拆开现实层"
        case .storyWriting:
            "正在寻找时间因果"
        case .generating:
            "正在聚合\(state.targetLabel)"
        case .ready:
            "\(state.targetLabel)已经抵达"
        case .failed:
            "时间生成需要处理"
        }
    }

    private func phaseSymbol(
        for phase: CameraLiveActivityAttributes.ContentState.Phase
    ) -> String {
        switch phase {
        case .framing:
            "camera.aperture"
        case .capturing:
            "camera.shutter.button.fill"
        case .captured:
            "scope"
        case .understanding:
            "viewfinder"
        case .storyWriting:
            "point.3.connected.trianglepath.dotted"
        case .generating:
            "square.3.layers.3d"
        case .ready:
            "sparkles"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private func activityURL(
        for state: CameraLiveActivityAttributes.ContentState
    ) -> URL {
        switch state.phase {
        case .framing, .capturing, .captured:
            CameraActivityLink.openCamera
        case .understanding, .storyWriting, .generating, .failed:
            CameraActivityLink.progress
        case .ready:
            CameraActivityLink.result
        }
    }
}

private enum CameraActivityLink {
    static let openCamera = URL(string: "fumira://camera")!
    static let progress = URL(string: "fumira://progress")!
    static let result = URL(string: "fumira://result")!
    static let flash = URL(string: "fumira://camera/flash")!
    static let lens = URL(string: "fumira://camera/lens")!
    static let grid = URL(string: "fumira://camera/grid")!
    static let aspect = URL(string: "fumira://camera/aspect")!
}

private enum CameraActivityStyle {
    static let blue = Color(red: 30 / 255, green: 156 / 255, blue: 224 / 255)
    static let paperWhite = Color(red: 250 / 255, green: 247 / 255, blue: 239 / 255)
    static let islandBlack = Color.black.opacity(0.96)
    static let yellow = Color(red: 255 / 255, green: 211 / 255, blue: 58 / 255)
    static let coral = Color(red: 233 / 255, green: 94 / 255, blue: 82 / 255)
    static let secondaryText = paperWhite.opacity(0.68)
    static let controlFill = paperWhite.opacity(0.12)
    static let activeControl = blue.opacity(0.34)
}
