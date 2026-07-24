import SwiftUI
import UIKit

struct ResultView: View {
    let model: AppModel
    var namespace: Namespace.ID

    private var generatedTime: TimePosition {
        model.generatedFrame?.time ?? model.generationTargetTime
    }

    private var generatedImage: UIImage? {
        model.generatedFrame?.imageData.flatMap(UIImage.init(data:))
    }

    private var photoAspectRatio: CGFloat {
        if let image = generatedImage, image.size.height > 0 {
            return image.size.width / image.size.height
        }
        return CGFloat(model.capturedPhoto?.displayAspectRatio ?? 3.0 / 4.0)
    }

    var body: some View {
        ZStack {
            ambientBackdrop
                .ignoresSafeArea()

            GeometryReader { proxy in
                let bottomReserve: CGFloat = 292
                let topReserve: CGFloat = 96
                let maxPhotoHeight = max(200, proxy.size.height - bottomReserve - topReserve)

                VStack(spacing: 0) {
                    header

                    heroPhoto(maxHeight: maxPhotoHeight)
                        .padding(.horizontal, PosterSpacing.lg)
                        .padding(.top, PosterSpacing.sm)

                    Spacer(minLength: PosterSpacing.sm)

                    bottomChrome
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: PosterSpacing.md) {
            PosterKeywordHero(moment: .reply, fontSize: 32)
            Spacer(minLength: 52)
        }
        .padding(.horizontal, PosterSpacing.lg)
        .padding(.top, PosterSpacing.sm)
    }

    private func heroPhoto(maxHeight: CGFloat) -> some View {
        PhotoAspectContainer(aspectRatio: photoAspectRatio, maximumHeight: maxHeight) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image = generatedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .accessibilityLabel("生成的时间场景")
                    } else {
                        TemporalParkScene(
                            time: model.selectedTime,
                            namespace: namespace,
                            cornerRadius: 0,
                            motionField: model.motionField
                        )
                        .accessibilityLabel("时间场景占位")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                Text("目标 · \(generatedTime.compactLabel)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(PosterPalette.paperWhite)
                    .padding(.horizontal, PosterSpacing.sm)
                    .padding(.vertical, PosterSpacing.xs)
                    .background(PosterPalette.ink.opacity(0.48))
                    .clipShape(Capsule())
                    .padding(PosterSpacing.md)
                    .accessibilityLabel("目标年份 \(generatedTime.compactLabel)")
            }
            .clipShape(RoundedRectangle(cornerRadius: PosterRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PosterRadius.card, style: .continuous)
                    .stroke(PosterPalette.paperWhite.opacity(0.55), lineWidth: 1)
            }
            .shadow(color: PosterPalette.ink.opacity(0.16), radius: 16, y: 8)
        }
        .flatParallax(model.motionField, depth: .back)
    }

    private var bottomChrome: some View {
        VStack(spacing: PosterSpacing.md) {
            narrativeStrip
                .padding(.horizontal, PosterSpacing.lg)

            TimeRail(
                value: model.selectedTime.normalized,
                onDetent: model.playTimeDetent
            ) { normalized in
                model.updateTime(normalized: normalized)
            }
            .padding(.horizontal, PosterSpacing.lg)

            HStack(spacing: PosterSpacing.md) {
                PosterCapsuleButton(
                    title: "保存海报",
                    accessibilityHint: "打开海报预览，可保存到相册或系统分享"
                ) {
                    model.openShare()
                }

                PosterCapsuleButton(
                    title: "重新生成",
                    style: .lime,
                    accessibilityHint: "用同一张原图重新生成拍摄时锁定的目标年份"
                ) {
                    Task { await model.regenerateResult() }
                }
            }
            .padding(.horizontal, PosterSpacing.lg)

            HStack(spacing: PosterSpacing.lg) {
                ResultTextAction(
                    title: "生成浏览年份",
                    systemImage: "clock.arrow.circlepath"
                ) {
                    Task { await model.generateAtStoryPreviewTime() }
                }
                ResultTextAction(title: "重拍", systemImage: "camera.rotate") {
                    model.retake()
                }
                if model.canUndoGeneration {
                    ResultTextAction(title: "撤销", systemImage: "arrow.uturn.backward") {
                        model.undoLastGeneration()
                    }
                }
            }
            .padding(.horizontal, PosterSpacing.lg)
        }
        .padding(.top, PosterSpacing.md)
        .padding(.bottom, PosterSpacing.lg)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: PosterRadius.card, style: .continuous)
                .fill(PosterPalette.canvas.opacity(0.94))
                .shadow(color: PosterPalette.ink.opacity(0.08), radius: 12, y: -2)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var narrativeStrip: some View {
        VStack(alignment: .leading, spacing: PosterSpacing.xs) {
            Text("故事浏览 · \(model.selectedTime.compactLabel)")
                .font(.caption.weight(.bold))
                .foregroundStyle(PosterPalette.skyDeep)
                .contentTransition(.numericText())

            Text(model.currentNarrative)
                .font(.footnote)
                .foregroundStyle(PosterPalette.ink)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, PosterSpacing.md)
        .padding(.vertical, PosterSpacing.sm)
        .background(PosterPalette.canvas)
        .clipShape(RoundedRectangle(cornerRadius: PosterRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PosterRadius.card, style: .continuous)
                .stroke(PosterPalette.line, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var ambientBackdrop: some View {
        if let image = generatedImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .blur(radius: 28)
                .scaleEffect(1.12)
                .overlay(PosterPalette.canvas.opacity(0.42))
                .overlay(PosterPalette.skySoft.opacity(0.22))
        } else {
            PosterPalette.skySoft
        }
    }
}

private struct ResultTextAction: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(PosterPalette.skyDeep)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PosterPressStyle())
        .accessibilityLabel(title)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @Namespace private var namespace

        var body: some View {
            ResultView(model: PreviewFixtures.model(phase: .result), namespace: namespace)
        }
    }
    return PreviewWrapper()
}
