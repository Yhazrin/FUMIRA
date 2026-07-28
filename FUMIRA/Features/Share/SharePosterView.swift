import SwiftUI
import UIKit

struct SharePosterView: View {
    let model: AppModel

    private var yearLabel: String {
        PosterComposer.yearLabel(for: model.selectedTime)
    }

    private var posterTitle: String {
        model.temporalStory?.title ?? model.currentStoryBeat?.title ?? "这一刻的时间故事"
    }

    private var sceneImage: UIImage? {
        model.generatedFrame?.imageData.flatMap(UIImage.init(data:))
    }

    var body: some View {
        PosterScreenContainer(background: PosterPalette.canvas) {
            VStack(spacing: PosterSpacing.lg) {
                PosterTitleView(
                    segments: ["带走", "这段", "时间"],
                    color: PosterPalette.sky,
                    fontSize: 36
                )

                PosterExportCard(
                    time: model.selectedTime,
                    yearLabel: yearLabel,
                    title: posterTitle,
                    narrative: model.currentNarrative,
                    sceneImage: sceneImage
                )
                .shadow(color: PosterEffects.floating, radius: 16, y: 8)
                .flatDecorationRotation(model.motionField)

                feedbackRow

                Spacer(minLength: PosterSpacing.sm)

                VStack(spacing: PosterSpacing.md) {
                    PosterCapsuleButton(
                        title: model.isSavingPoster ? "正在保存…" : "保存到相册",
                        accessibilityHint: "将合成海报写入系统相册"
                    ) {
                        Task { await model.savePosterToLibrary() }
                    }
                    .disabled(model.isSavingPoster || model.isPreparingPoster)
                    .opacity(model.isSavingPoster ? 0.72 : 1)

                    shareButton

                    PosterCapsuleButton(
                        title: "返回浏览",
                        style: .secondary,
                        accessibilityHint: "回到结果页继续调整时间"
                    ) {
                        model.returnToResult()
                    }
                }
            }
        }
        .task(id: shareTaskID) {
            if model.shareImageData == nil {
                await model.prepareSharePoster()
            }
        }
    }

    private var shareTaskID: String {
        "\(model.selectedTime.normalized)-\(model.generatedFrame?.id.uuidString ?? "none")"
    }

    @ViewBuilder
    private var feedbackRow: some View {
        if let message = model.shareFeedbackMessage {
            StatusPill(icon: "checkmark.circle.fill", label: message, isActive: true)
                .posterSymbolBounce(trigger: message)
                .accessibilityLabel(message)
        } else if let error = model.lastErrorMessage {
            StatusPill(icon: "exclamationmark.triangle.fill", label: error)
                .accessibilityLabel(error)
        } else if model.isPreparingPoster {
            StatusPill(icon: "hourglass", label: "正在合成海报…")
        }
    }

    @ViewBuilder
    private var shareButton: some View {
        if let poster = model.shareablePoster {
            ShareLink(
                item: poster,
                preview: SharePreview(
                    "FUMIRA 时间海报",
                    image: previewImage(for: poster.data)
                )
            ) {
                Text("分享海报")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(PosterPalette.ink)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 56)
                    .background(PosterPalette.canvas)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .stroke(PosterPalette.ink, lineWidth: 2)
                    }
            }
            .simultaneousGesture(TapGesture().onEnded {
                model.playShareHaptic()
            })
            .accessibilityLabel("分享海报")
            .accessibilityHint("打开系统分享菜单")
        } else {
            PosterCapsuleButton(
                title: model.isPreparingPoster ? "正在合成…" : "分享海报",
                style: .secondary,
                accessibilityHint: "海报准备好后可打开系统分享"
            ) {
                Task { await model.prepareSharePoster() }
            }
            .disabled(model.isPreparingPoster)
        }
    }

    private func previewImage(for data: Data) -> Image {
        if let uiImage = UIImage(data: data) {
            return Image(uiImage: uiImage)
        }
        return Image(systemName: "photo")
    }
}

#Preview("Share poster") {
    SharePosterView(model: PreviewFixtures.model(phase: .share, time: 0.35))
}

#Preview("Share poster · NOW") {
    SharePosterView(model: PreviewFixtures.model(phase: .share, time: 0))
}
