import ActivityKit
import SwiftUI
import WidgetKit

struct CameraLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CameraLiveActivityAttributes.self) { context in
            lockScreenView(context.state)
                .activityBackgroundTint(CameraActivityStyle.islandBlack)
                .activitySystemActionForegroundColor(CameraActivityStyle.paperWhite)
                .widgetURL(CameraActivityLink.openCamera)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    shutterMark
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.zoomLabel)
                        .font(.system(.body, design: .rounded, weight: .bold))
                        .foregroundStyle(CameraActivityStyle.paperWhite)
                        .monospacedDigit()
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
                    expandedControls(context.state)
                }
            } compactLeading: {
                shutterMark
            } compactTrailing: {
                compactTrailing(context.state)
            } minimal: {
                Image(systemName: "camera.aperture")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CameraActivityStyle.blue)
            }
            .keylineTint(CameraActivityStyle.blue)
            .widgetURL(CameraActivityLink.openCamera)
        }
    }

    private func lockScreenView(
        _ state: CameraLiveActivityAttributes.ContentState
    ) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                shutterMark

                VStack(alignment: .leading, spacing: 2) {
                    Text("FUMIRA 时间相机")
                        .font(.headline)
                        .foregroundStyle(CameraActivityStyle.paperWhite)
                    Text(statusText(for: state))
                        .font(.caption)
                        .foregroundStyle(CameraActivityStyle.secondaryText)
                }

                Spacer(minLength: 8)

                Text(state.zoomLabel)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(CameraActivityStyle.paperWhite)
                    .monospacedDigit()
            }

            expandedControls(state)
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
        }
    }

    private var shutterMark: some View {
        ZStack {
            Circle()
                .fill(CameraActivityStyle.blue)
            Circle()
                .fill(CameraActivityStyle.paperWhite)
                .padding(4)
            Circle()
                .fill(CameraActivityStyle.blue)
                .frame(width: 4, height: 4)
        }
        .frame(width: 24, height: 24)
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
            "已捕捉"
        }
    }
}

private enum CameraActivityLink {
    static let openCamera = URL(string: "fumira://camera")!
    static let flash = URL(string: "fumira://camera/flash")!
    static let lens = URL(string: "fumira://camera/lens")!
    static let grid = URL(string: "fumira://camera/grid")!
    static let aspect = URL(string: "fumira://camera/aspect")!
}

private enum CameraActivityStyle {
    static let blue = Color(red: 30 / 255, green: 156 / 255, blue: 224 / 255)
    static let paperWhite = Color(red: 250 / 255, green: 247 / 255, blue: 239 / 255)
    static let islandBlack = Color.black.opacity(0.96)
    static let secondaryText = paperWhite.opacity(0.68)
    static let controlFill = paperWhite.opacity(0.12)
    static let activeControl = blue.opacity(0.34)
}
