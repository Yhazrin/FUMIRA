import SwiftUI

/// Poster hero lettering: ink / pine / leafGreen segments, hand-drawn underline,
/// and phase-based composition (center, not pinned top-leading).
enum PosterHeroMoment: Equatable {
    /// Connection invite — "给时间，一张照片"
    case invite
    /// Bluetooth / hardware connected — "把此刻，留给未来"
    case connecting
    /// Camera permission / about to shoot — "此刻，去拍下"
    case ready
    /// Generation — "时间正在生长"
    case growing
    /// Result — "未来的回信"
    case reply
}

struct PosterKeywordSegment: Identifiable {
    let id: Int
    let text: String
    let color: Color
    var underlined: Bool = false

    init(id: Int, _ text: String, color: Color, underlined: Bool = false) {
        self.id = id
        self.text = text
        self.color = color
        self.underlined = underlined
    }
}

enum PosterHeroSurface {
    case paper
    /// Pine / deep generation surfaces — light lettering for AA contrast.
    case dark
}

struct PosterKeywordHero: View {
    let moment: PosterHeroMoment
    var fontSize: CGFloat = 44
    var surface: PosterHeroSurface = .paper
    /// Permission and compact utility surfaces can keep the expressive keyword
    /// treatment without adding an unrelated English script label.
    var showsScriptLabel = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var inkTone: Color {
        surface == .dark ? PosterPalette.paperWhite : PosterPalette.ink
    }

    private var pineTone: Color {
        surface == .dark ? PosterPalette.grassLight : PosterPalette.skyDeep
    }

    private var accentTone: Color {
        PosterPalette.leafGreen
    }

    private var scriptTone: Color {
        surface == .dark ? PosterPalette.paperWhite.opacity(0.72) : PosterPalette.mutedInk
    }

    private var segments: [PosterKeywordSegment] {
        switch moment {
        case .invite:
            [
                PosterKeywordSegment(id: 0, "给", color: inkTone),
                PosterKeywordSegment(id: 1, "时间", color: pineTone, underlined: true),
                PosterKeywordSegment(id: 2, "一张", color: inkTone),
                PosterKeywordSegment(id: 3, "照片", color: accentTone, underlined: true)
            ]
        case .connecting:
            [
                PosterKeywordSegment(id: 0, "把", color: inkTone),
                PosterKeywordSegment(id: 1, "此刻", color: pineTone, underlined: true),
                PosterKeywordSegment(id: 2, "留给", color: inkTone),
                PosterKeywordSegment(id: 3, "未来", color: accentTone, underlined: true)
            ]
        case .ready:
            [
                PosterKeywordSegment(id: 0, "此刻", color: pineTone, underlined: true),
                PosterKeywordSegment(id: 1, "去", color: inkTone),
                PosterKeywordSegment(id: 2, "拍下", color: accentTone, underlined: true)
            ]
        case .growing:
            [
                PosterKeywordSegment(id: 0, "时间", color: pineTone, underlined: true),
                PosterKeywordSegment(id: 1, "正在", color: inkTone),
                PosterKeywordSegment(id: 2, "生长", color: accentTone, underlined: true)
            ]
        case .reply:
            [
                PosterKeywordSegment(id: 0, "未来", color: accentTone, underlined: true),
                PosterKeywordSegment(id: 1, "的", color: inkTone),
                PosterKeywordSegment(id: 2, "回信", color: pineTone, underlined: true)
            ]
        }
    }

    private var scriptLabel: String {
        switch moment {
        case .invite: "Future Camera"
        case .connecting: "Connected"
        case .ready: "Ready"
        case .growing: "Growing"
        case .reply: "A letter from time"
        }
    }

    private var alignment: Alignment {
        switch moment {
        case .invite: .trailing
        case .growing: .center
        case .connecting: .trailing
        case .ready, .reply: .leading
        }
    }

    private var stackAlignment: HorizontalAlignment {
        switch alignment {
        case .leading: .leading
        case .trailing: .trailing
        default: .center
        }
    }

    private var rotations: [Double] {
        reduceMotion ? [0, 0, 0, 0] : [-1.8, 2.4, -1.2, 1.6]
    }

    var body: some View {
        VStack(alignment: stackAlignment, spacing: PosterSpacing.sm) {
            keywordStack
            if moment != .invite, showsScriptLabel {
                HandDrawnUnderline()
                    .stroke(PosterPalette.leafGreen, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .frame(width: underlineWidth, height: 10)
                    .opacity(0.9)

                Text(scriptLabel)
                    .font(PosterTypography.script(22))
                    .foregroundStyle(scriptTone)
            } else {
                Text("FUMIRA  /  FUTURE CAMERA")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.7)
                    .foregroundStyle(PosterPalette.skyDeep.opacity(0.72))
                    .padding(.top, PosterSpacing.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(segments.map(\.text).joined())
    }

    @ViewBuilder
    private var keywordStack: some View {
        switch moment {
        case .invite:
            VStack(alignment: .trailing, spacing: 0) {
                HStack(alignment: .lastTextBaseline, spacing: PosterSpacing.sm) {
                    segmentView(segments[0], index: 0, size: fontSize * 0.78)
                    segmentView(segments[1], index: 1, size: fontSize * 1.18)
                }
                HStack(alignment: .lastTextBaseline, spacing: PosterSpacing.sm) {
                    segmentView(segments[2], index: 2, size: fontSize * 0.82)
                    segmentView(segments[3], index: 3, size: fontSize * 1.28)
                }
                .padding(.trailing, fontSize * 0.48)
            }
        case .growing:
            VStack(alignment: .center, spacing: PosterSpacing.xs) {
                HStack(spacing: PosterSpacing.sm) {
                    segmentView(segments[0], index: 0)
                    segmentView(segments[1], index: 1)
                }
                HStack(spacing: PosterSpacing.sm) {
                    ForEach(Array(segments.dropFirst(2).enumerated()), id: \.element.id) { offset, segment in
                        segmentView(segment, index: offset + 2)
                    }
                }
            }
        case .connecting:
            VStack(alignment: .trailing, spacing: PosterSpacing.xs) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    segmentView(segment, index: index)
                }
            }
        case .ready, .reply:
            VStack(alignment: .leading, spacing: PosterSpacing.xs) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    segmentView(segment, index: index)
                }
            }
        }
    }

    private func segmentView(
        _ segment: PosterKeywordSegment,
        index: Int,
        size: CGFloat? = nil
    ) -> some View {
        Text(segment.text)
            .font(PosterTypography.display(size ?? fontSize))
            .foregroundStyle(segment.color)
            .rotationEffect(.degrees(rotation(for: index)))
            .overlay(alignment: .bottom) {
                if segment.underlined {
                    HandDrawnUnderline()
                        .stroke(PosterPalette.leafGreen.opacity(0.85), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .frame(height: 6)
                        .offset(y: 4)
                        .padding(.horizontal, 2)
                }
            }
    }

    private func rotation(for index: Int) -> Double {
        guard index < rotations.count else { return 0 }
        return rotations[index]
    }

    private var underlineWidth: CGFloat {
        switch moment {
        case .invite, .growing: 168
        case .connecting: 140
        case .ready, .reply: 120
        }
    }
}

/// Soft irregular underline — hand-mark energy without continuous animation.
struct HandDrawnUnderline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let y = rect.midY
        path.move(to: CGPoint(x: rect.minX, y: y + 1.2))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX * 0.9, y: y - 1.4),
            control: CGPoint(x: rect.width * 0.28, y: y + 2.6)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: y + 0.6),
            control: CGPoint(x: rect.width * 0.72, y: y - 2.2)
        )
        return path
    }
}

#Preview("Invite") {
    ZStack {
        PosterPalette.canvas.ignoresSafeArea()
        PosterKeywordHero(moment: .invite)
            .padding()
    }
}
