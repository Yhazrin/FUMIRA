import SwiftUI
import UIKit

enum HeroPhotoMetrics {
    static let understandingMaximumHeight: CGFloat = 360
    static let understandingHorizontalInset = PosterSpacing.xl + PosterSpacing.md
    // A slight downward landing preserves the paper-drop direction without
    // stranding the sealed target beneath a large empty band.
    static let understandingVerticalOffset = PosterSpacing.xl

    static func understandingFrame(
        aspectRatio: CGFloat,
        in size: CGSize
    ) -> CGRect {
        let ratio = max(aspectRatio, 0.01)
        let availableWidth = max(size.width - understandingHorizontalInset * 2, 1)
        let height = min(understandingMaximumHeight, availableWidth / ratio)
        let width = height * ratio
        return CGRect(
            x: (size.width - width) / 2,
            y: (size.height - height) / 2 + understandingVerticalOffset,
            width: width,
            height: height
        )
    }
}

/// Persistent photo host owned by ``RootView``. Survives phase swaps so the
/// capture never remounts, jumps, or fades with page opacity transitions.
struct HeroPhotoSurface: View {
    let model: AppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scanPosition = -0.8
    @State private var generatedLayerOpacity = 0.0

    private var showsUnderstandingOverlay: Bool {
        model.phase == .understanding
    }

    private var showsGeneratingOverlay: Bool {
        model.phase == .generating
    }

    private var showsSealedTarget: Bool {
        model.decodedGeneratedImage != nil
            && (model.phase == .understanding || model.phase == .storyWriting)
    }

    private var usesPhotoPaper: Bool {
        switch model.phase {
        case .understanding, .storyWriting, .generating:
            true
        default:
            false
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let paperInset: CGFloat = usesPhotoPaper ? 8 : 0
            let paperFooter: CGFloat = usesPhotoPaper ? 24 : 0
            let photoWidth = max(proxy.size.width - paperInset * 2, 1)
            let photoHeight = max(proxy.size.height - paperInset - paperFooter, 1)

            ZStack {
                if usesPhotoPaper {
                    PhotoPaperBacking()
                        .transition(.opacity)
                }

                photoContent(width: photoWidth, height: photoHeight)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: usesPhotoPaper ? PosterRadius.photoPaper * 0.5 : 0,
                            style: .continuous
                        )
                    )
                    .position(
                        x: paperInset + photoWidth / 2,
                        y: paperInset + photoHeight / 2
                    )
            }
            .animation(.posterPhotoDrop(reduceMotion: reduceMotion), value: usesPhotoPaper)
        }
        .clipped()
        .onAppear {
            syncLayerOpacities(animated: false)
            startScanIfNeeded()
        }
        .onChange(of: model.decodedGeneratedImage != nil) { _, hasGenerated in
            if hasGenerated {
                crossfadeToGenerated()
            } else {
                generatedLayerOpacity = 0
            }
        }
        .onChange(of: model.phase) { _, phase in
            syncLayerOpacities(animated: true)
            if phase == .understanding {
                startScanIfNeeded()
            }
        }
    }

    private func photoContent(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            PosterPalette.ink.opacity(0.12)

            if let image = model.decodedCapturedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipped()
                    .accessibilityLabel("刚刚拍下的原始照片")
            } else if model.capturedPhoto != nil {
                PosterPalette.ink.opacity(0.2)
            }

            if let image = model.decodedGeneratedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipped()
                    .opacity(generatedLayerOpacity)
                    .accessibilityLabel("生成的时间场景")
            }

            if showsSealedTarget {
                sealedTargetOverlay
            }

            if showsUnderstandingOverlay {
                understandingOverlay
            }

            if showsGeneratingOverlay {
                generatingOverlay
            }
        }
        .frame(width: width, height: height)
        .clipped()
    }

    private var understandingOverlay: some View {
        ZStack {
            GeometryReader { proxy in
                Rectangle()
                    .fill(PosterPalette.actionBlue)
                    .frame(height: 4)
                    .shadow(color: PosterPalette.actionBlue, radius: 10)
                    .offset(y: proxy.size.height * scanPosition)
            }
            .opacity(reduceMotion ? 0 : 0.9)

            VStack {
                Spacer()
                HStack {
                    Label(
                        model.modelOption(for: .understanding)?.displayName ?? "图片理解",
                        systemImage: "viewfinder"
                    )
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PosterPalette.paperWhite)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(PosterPalette.actionBlue)
                    .clipShape(Capsule())
                    Spacer()
                }
                .padding(PosterSpacing.md)
            }
        }
        .allowsHitTesting(false)
    }

    private var sealedTargetOverlay: some View {
        ZStack {
            PosterPalette.canvas

            Canvas { context, size in
                let spacing: CGFloat = 22
                var x = -size.height
                while x < size.width {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: size.height))
                    path.addLine(to: CGPoint(x: x + size.height, y: 0))
                    context.stroke(
                        path,
                        with: .color(PosterPalette.actionBlue.opacity(0.08)),
                        lineWidth: 9
                    )
                    x += spacing
                }
            }

            VStack(spacing: PosterSpacing.sm) {
                Image(systemName: "photo.badge.checkmark")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(PosterPalette.actionBlue)
                Text("目标画面已封存")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PosterPalette.actionBlueDeep)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: PosterRadius.photoPaper * 0.5, style: .continuous)
                .stroke(PosterPalette.actionBlue.opacity(0.28), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityLabel("目标画面已生成，完成故事后揭晓")
    }

    private var generatingOverlay: some View {
        TemporalParkScene(
            time: model.selectedTime,
            cornerRadius: 0,
            motionField: model.motionField
        )
        .opacity(0.15 + model.generationProgress * 0.55)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func crossfadeToGenerated() {
        guard model.phase == .result || model.phase == .share else { return }
        if reduceMotion {
            generatedLayerOpacity = 1
            return
        }
        withAnimation(.easeInOut(duration: PosterMotion.heroGeneratedCrossfade)) {
            generatedLayerOpacity = 1
        }
    }

    private func syncLayerOpacities(animated: Bool) {
        let generatedTarget: Double = {
            switch model.phase {
            case .result, .share:
                return model.decodedGeneratedImage == nil ? 0 : 1
            default:
                return 0
            }
        }()

        let apply = {
            generatedLayerOpacity = generatedTarget
        }
        if animated, !reduceMotion {
            withAnimation(.easeInOut(duration: PosterMotion.heroGeneratedCrossfade)) {
                apply()
            }
        } else {
            apply()
        }
    }

    private func startScanIfNeeded() {
        guard showsUnderstandingOverlay, !reduceMotion else { return }
        scanPosition = -0.8
        withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: true)) {
            scanPosition = 0.8
        }
    }
}

private struct PhotoPaperBacking: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            PosterPalette.paperWhite

            Canvas { context, size in
                let lineCount = 18
                for index in 0..<lineCount {
                    let y = size.height * CGFloat(index + 1) / CGFloat(lineCount + 1)
                    var path = Path()
                    let stagger = CGFloat((index * 13) % 17)
                    path.move(to: CGPoint(x: stagger, y: y))
                    path.addLine(to: CGPoint(x: max(size.width - 8 - stagger * 0.25, 0), y: y))
                    context.stroke(
                        path,
                        with: .color(PosterEffects.photoPaperFiber),
                        lineWidth: index.isMultiple(of: 3) ? 0.7 : 0.35
                    )
                }
            }
            .allowsHitTesting(false)

            HStack(spacing: 5) {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 8, weight: .semibold))
                Rectangle()
                    .frame(width: 18, height: 1)
            }
            .foregroundStyle(PosterEffects.photoPaperFooterMark)
            .frame(height: 22)
        }
        .overlay {
            RoundedRectangle(cornerRadius: PosterRadius.photoPaper, style: .continuous)
                .stroke(PosterEffects.photoPaperStroke, lineWidth: 1)
        }
        .clipShape(
            RoundedRectangle(cornerRadius: PosterRadius.photoPaper, style: .continuous)
        )
        .accessibilityHidden(true)
    }
}
