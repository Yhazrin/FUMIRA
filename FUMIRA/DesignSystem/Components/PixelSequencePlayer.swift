import SwiftUI
import UIKit

/// A portable multi-clip renderer for one-shot stories and indefinite pet loops.
///
/// Random loops always return to their base clip. Action clips are inserted
/// only after the configured number of base cycles, with weighted selection.
struct PixelSequencePlayer: View {
    let sequence: PixelSequence
    var bundle: Bundle = .main
    var isPlaying = true
    var contentMode: ContentMode = .fit

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var currentFrame: String?

    var body: some View {
        frameView(filename: currentFrame ?? fallbackFrame)
            .task(id: playbackTaskID) {
                await runPlayback()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(sequence.displayName)
            .accessibilityAddTraits(.isImage)
    }

    private var playbackTaskID: PlaybackTaskID {
        PlaybackTaskID(
            sequenceID: sequence.id,
            isPlaying: isPlaying,
            reduceMotion: reduceMotion
        )
    }

    private var fallbackFrame: String? {
        reduceMotion ? sequence.reduceMotionFrame : sequence.firstClip?.frames.first
    }

    @MainActor
    private func runPlayback() async {
        currentFrame = fallbackFrame
        guard isPlaying, !reduceMotion, var clip = sequence.firstClip else { return }

        var linearClipIndex = 0
        var completedBaseLoops = 0

        while !Task.isCancelled {
            for frame in clip.frames {
                currentFrame = frame
                do {
                    try await Task.sleep(for: clip.frameDuration)
                } catch {
                    return
                }
            }

            switch sequence.playbackMode {
            case .oneShot:
                linearClipIndex += 1
                guard sequence.clips.indices.contains(linearClipIndex) else { return }
                clip = sequence.clips[linearClipIndex]

            case .randomLoop:
                guard let baseClip = sequence.baseClip else { return }
                if clip.kind == .action {
                    clip = baseClip
                    completedBaseLoops = 0
                    continue
                }

                completedBaseLoops += 1
                let insertsAction = PixelSequencePlayback.shouldInsertAction(
                    probability: sequence.actionProbability,
                    completedBaseLoops: completedBaseLoops,
                    minimumBaseLoops: sequence.minimumBaseLoops,
                    randomUnit: Double.random(in: 0..<1)
                )
                if insertsAction,
                   let action = PixelSequencePlayback.weightedAction(
                    from: sequence.actionClips,
                    randomUnit: Double.random(in: 0..<1)
                   ) {
                    clip = action
                } else {
                    clip = baseClip
                }
            }
        }
    }

    @ViewBuilder
    private func frameView(filename: String?) -> some View {
        if let filename, let image = bundledImage(named: filename) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.none)
                .aspectRatio(contentMode: contentMode)
        } else {
            Color.clear
        }
    }

    private func bundledImage(named filename: String) -> UIImage? {
        UIImage(named: filename, in: bundle, compatibleWith: nil)
    }
}

private struct PlaybackTaskID: Hashable {
    let sequenceID: String
    let isPlaying: Bool
    let reduceMotion: Bool
}

/// A one-shot wrapper suitable for a launch or between-phase interstitial.
struct PixelSequenceSplashView<Background: View>: View {
    let sequence: PixelSequence
    let background: Background
    let onCompletion: @MainActor () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        sequence: PixelSequence,
        @ViewBuilder background: () -> Background,
        onCompletion: @escaping @MainActor () -> Void
    ) {
        self.sequence = sequence
        self.background = background()
        self.onCompletion = onCompletion
    }

    var body: some View {
        ZStack {
            background
            PixelSequencePlayer(sequence: sequence)
        }
        .task(id: sequence.id) {
            guard sequence.playbackMode == .oneShot else { return }
            if reduceMotion {
                onCompletion()
                return
            }
            try? await Task.sleep(for: .seconds(sequence.totalDuration))
            guard !Task.isCancelled else { return }
            onCompletion()
        }
    }
}

#if DEBUG
struct PixelSequenceShowcase: View {
    private let library = try? PixelSequenceLibrary.bundled()

    var body: some View {
        ScrollView {
            VStack(spacing: PosterSpacing.xl) {
                ForEach(library?.sequences ?? []) { sequence in
                    VStack(alignment: .leading, spacing: PosterSpacing.sm) {
                        Text(sequence.displayName)
                            .font(PosterTypography.sectionTitle)
                            .foregroundStyle(PosterPalette.ink)

                        PixelSequencePlayer(sequence: sequence)
                            .frame(maxWidth: .infinity)
                            .aspectRatio(1, contentMode: .fit)
                            .background(PosterPalette.cardLight)
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: PosterRadius.card,
                                    style: .continuous
                                )
                            )
                    }
                }
            }
            .padding(PosterSpacing.lg)
        }
        .background(PosterPalette.paper)
    }
}

#Preview {
    PixelSequenceShowcase()
}
#endif
