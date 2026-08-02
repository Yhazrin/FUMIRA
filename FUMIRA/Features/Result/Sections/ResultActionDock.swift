import SwiftUI

/// The bar of actions under the hero photo.
///
/// Owns no time state. Tilt is presented here as an explicit opt-in toggle so
/// the secondary interaction is discoverable instead of ambient.
struct ResultActionDock: View {
    let isBrowseTimeGenerated: Bool
    let isPreparingGeneration: Bool
    let canPresentComparison: Bool
    let canOfferTilt: Bool
    let isTiltActive: Bool
    let canUndo: Bool
    let browseLabel: String
    let revealProgress: CGFloat
    let reduceMotion: Bool
    let isDioramaEnabled: Bool
    let didSaveToLibrary: Bool

    let onGenerateBrowsedFrame: () -> Void
    let onSave: () -> Void
    let onPresentComparison: () -> Void
    let onToggleTilt: () -> Void
    let onRegenerate: () -> Void
    let onUndo: () -> Void
    let onOpenSettings: () -> Void
    let onRetake: () -> Void
    let onShowDiorama: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ClaySpacing.sm) {
            if !isBrowseTimeGenerated {
                generateBrowsedFrameButton
            }

            saveButton

            HStack(spacing: ClaySpacing.sm) {
                Spacer(minLength: ClaySpacing.sm)

                compactAction(title: "对准现实", systemImage: "viewfinder") {
                    onPresentComparison()
                }
                .opacity(canPresentComparison ? 1 : 0)
                .allowsHitTesting(canPresentComparison)
                .accessibilityHidden(!canPresentComparison)

                tiltAction
                    .opacity(canOfferTilt ? 1 : 0)
                    .allowsHitTesting(canOfferTilt)
                    .accessibilityHidden(!canOfferTilt)

                moreActionsMenu
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("result.action-dock")
    }

    // MARK: - Primary actions

    private var generateBrowsedFrameButton: some View {
        PosterCapsuleButton(
            title: isPreparingGeneration ? "正在对齐这一帧…" : "生成这一帧",
            accessibilityHint: "使用当前浏览的 \(browseLabel) 重新生成照片",
            action: onGenerateBrowsedFrame
        )
        .disabled(isPreparingGeneration)
        .accessibilityIdentifier("result.generate-browsed-frame")
    }

    private var saveButton: some View {
        TemporalSaveCapsule(
            title: "保存海报",
            revealProgress: revealProgress,
            reduceMotion: reduceMotion,
            action: onSave
        )
        .posterSensoryFeedback(trigger: didSaveToLibrary, .success)
    }

    // MARK: - Compact actions

    private func compactAction(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: ResultActionDock.compactSize, height: ResultActionDock.compactSize)
                .contentShape(Circle())
        }
        .clayButtonStyle(
            base: ClayPalette.warmWhite,
            rim: ClayPalette.warmWhiteRim,
            foreground: ClayPalette.orangeDepth,
            cornerRadius: ClayShape.pill,
            depth: 4
        )
        .accessibilityLabel(title)
    }

    private var tiltAction: some View {
        Button(action: onToggleTilt) {
            Image(systemName: isTiltActive ? "pause.circle" : "gyroscope")
                .font(.body.weight(.semibold))
                .frame(width: ResultActionDock.compactSize, height: ResultActionDock.compactSize)
                .contentShape(Circle())
        }
        .clayButtonStyle(
            base: isTiltActive ? ClayPalette.orange : ClayPalette.warmWhite,
            rim: isTiltActive ? ClayPalette.orangeDepth : ClayPalette.warmWhiteRim,
            foreground: isTiltActive ? ClayPalette.warmWhite : ClayPalette.orangeDepth,
            cornerRadius: ClayShape.pill,
            depth: 4
        )
        .disabled(isPreparingGeneration)
        .posterSensoryFeedback(trigger: isTiltActive, .selection)
        .accessibilityIdentifier("result.tilt-time")
        .accessibilityLabel(isTiltActive ? "停止倾斜穿越" : "开启倾斜穿越")
        .accessibilityValue(isTiltActive ? "已开启" : "已关闭")
        .accessibilityHint(
            isTiltActive
                ? "停止使用设备倾斜浏览时间"
                : "开启后，向左倾斜浏览过去，向右倾斜浏览未来，回正时停止"
        )
        .accessibilityAddTraits(isTiltActive ? .isSelected : [])
    }

    private var moreActionsMenu: some View {
        Menu {
            Button(action: onRegenerate) {
                Label("重新生成", systemImage: "sparkles")
            }

            if canUndo {
                Button(action: onUndo) {
                    Label("撤销", systemImage: "arrow.uturn.backward")
                }
            }

            Button(action: onOpenSettings) {
                Label("设置", systemImage: "gearshape")
            }

            Divider()

            Button(role: .destructive, action: onRetake) {
                Label("重拍", systemImage: "camera.rotate")
            }

            if isDioramaEnabled {
                Divider()

                Button(action: onShowDiorama) {
                    Label("3D 微缩场景", systemImage: "cube.transparent")
                }
            }
        } label: {
            ClayMoldedControl(
                base: ClayPalette.warmWhite,
                rim: ClayPalette.warmWhiteRim,
                foreground: ClayPalette.orangeDepth,
                cornerRadius: ClayShape.pill,
                depth: 4,
                isPressed: false
            ) {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .frame(
                        width: ResultActionDock.compactSize,
                        height: ResultActionDock.compactSize
                    )
            }
            // Match the flat, faint-contact-shadow read of its sibling
            // clayButtonStyle controls in this same row.
            .shadow(
                color: ClayShadow.buttonRest.color,
                radius: ClayShadow.buttonRest.radius,
                x: 0,
                y: ClayShadow.buttonRest.y
            )
            .contentShape(Circle())
        }
        .accessibilityIdentifier("result.more-actions")
        .accessibilityLabel("更多")
        .accessibilityHint("重新生成、撤销、设置和重拍")
    }

    private static let compactSize: CGFloat = 56
}
