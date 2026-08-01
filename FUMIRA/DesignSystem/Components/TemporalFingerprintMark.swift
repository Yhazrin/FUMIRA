import SwiftUI

/// A reproducible 21-stroke signature derived from temporal story markers and
/// the selected time. It is a compact legend, not a score or confidence meter.
struct TemporalFingerprintMark: View {
    enum Size {
        case compact
        case poster

        fileprivate var artworkHeight: CGFloat {
            switch self {
            case .compact:
                PosterSpacing.xl
            case .poster:
                PosterSpacing.xl + PosterSpacing.lg
            }
        }

        fileprivate var minimumWidth: CGFloat {
            switch self {
            case .compact:
                PosterSpacing.xl * 3
            case .poster:
                PosterSpacing.xl * 5
            }
        }

        fileprivate var idealWidth: CGFloat {
            switch self {
            case .compact:
                PosterSpacing.xl * 4
            case .poster:
                PosterSpacing.xl * 7
            }
        }
    }

    let markers: [TemporalInterpretationMarker]
    let selectedTime: TimePosition
    var size: Size = .compact

    private let strokeCount = 21

    var body: some View {
        VStack(alignment: .leading, spacing: PosterSpacing.xs) {
            fingerprintCanvas
                .frame(height: size.artworkHeight)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: PosterSpacing.sm) {
                    legendTitle
                    Spacer(minLength: PosterSpacing.sm)
                    selectedLegend
                }

                VStack(alignment: .leading, spacing: PosterSpacing.xs) {
                    legendTitle
                    selectedLegend
                }
            }
        }
        .frame(
            minWidth: size.minimumWidth,
            idealWidth: size.idealWidth,
            alignment: .leading
        )
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("确定性时间指纹")
        .accessibilityValue(accessibilitySummary)
    }

    private var fingerprintCanvas: some View {
        Canvas { context, canvasSize in
            let horizontalInset = min(PosterSpacing.xs, canvasSize.width / 2)
            let usableWidth = max(canvasSize.width - horizontalInset * 2, 0)
            let centerY = canvasSize.height / 2
            let spacing = usableWidth / CGFloat(max(strokeCount - 1, 1))
            let lineWidth = min(
                PosterRadius.waveBar,
                max(PosterRadius.waveBar / 2, spacing * 0.22)
            )

            var baseline = Path()
            baseline.move(to: CGPoint(x: horizontalInset, y: centerY))
            baseline.addLine(to: CGPoint(x: canvasSize.width - horizontalInset, y: centerY))
            context.stroke(
                baseline,
                with: .color(PosterPalette.line),
                style: StrokeStyle(
                    lineWidth: PosterRadius.waveBar / 2,
                    lineCap: .round
                )
            )

            for index in 0..<strokeCount {
                let vector = fingerprintVector(at: index)
                let x = horizontalInset + CGFloat(index) * spacing
                let height = canvasSize.height * CGFloat(vector.heightRatio)
                let yInset = (canvasSize.height - height) / 2
                var stroke = Path()
                stroke.move(to: CGPoint(x: x, y: yInset))
                stroke.addLine(to: CGPoint(x: x, y: canvasSize.height - yInset))

                context.stroke(
                    stroke,
                    with: .color(
                        vector.isSelected
                            ? PosterPalette.actionBlue
                            : PosterPalette.ink
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
            }
        }
        .accessibilityHidden(true)
    }

    private var legendTitle: some View {
        Text("时间指纹 · 21 道")
            .font(PosterTypography.caption)
            .foregroundStyle(PosterPalette.mutedInk)
            .lineLimit(1)
    }

    private var selectedLegend: some View {
        HStack(spacing: PosterSpacing.xs) {
            Capsule(style: .continuous)
                .fill(PosterPalette.actionBlue)
                .frame(
                    width: PosterSpacing.md,
                    height: PosterRadius.waveBar
                )
                .accessibilityHidden(true)

            Text(selectedTime.compactLabel)
                .font(PosterTypography.caption)
                .foregroundStyle(PosterPalette.ink)
                .lineLimit(1)
        }
    }

    private var accessibilitySummary: String {
        var parts = [
            "由 21 道短线组成",
            "当前时间：\(selectedTime.compactLabel)"
        ]

        let titles = markers
            .compactMap { marker -> String? in
                let title = marker.title.trimmingCharacters(in: .whitespacesAndNewlines)
                return title.isEmpty ? nil : title
            }
            .prefix(3)
        if !titles.isEmpty {
            parts.append("解释转折：\(titles.joined(separator: "、"))")
        }

        return parts.joined(separator: "，")
    }

    private func fingerprintVector(at index: Int) -> FingerprintVector {
        let denominator = Double(max(strokeCount - 1, 1))
        let sample = -1 + 2 * Double(index) / denominator
        let selected = boundedNormalized(selectedTime.normalized)
        let selectedIndex = Int(
            (((selected + 1) / 2) * denominator).rounded()
        )

        let markerInfluence = markers.reduce(0.0) { strongest, marker in
            let markerPosition = boundedNormalized(marker.normalized)
            let distance = abs(sample - markerPosition)
            let reach = marker.isExactTarget ? 0.28 : 0.22
            let influence = max(0, 1 - distance / reach)
                * (marker.isExactTarget ? 1 : 0.78)
            return max(strongest, influence)
        }
        let selectedDistance = abs(sample - selected)
        let selectedInfluence = max(0, 1 - selectedDistance / 0.18)
        let heightRatio = min(
            0.92,
            0.28 + markerInfluence * 0.38 + selectedInfluence * 0.30
        )

        return FingerprintVector(
            heightRatio: heightRatio,
            isSelected: index == selectedIndex
        )
    }

    private func boundedNormalized(_ normalized: Double) -> Double {
        guard normalized.isFinite else { return 0 }
        return min(max(normalized, -1), 1)
    }
}

private struct FingerprintVector {
    let heightRatio: Double
    let isSelected: Bool
}

#Preview("Temporal fingerprint sizes") {
    let markers = [
        TemporalInterpretationMarker(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            normalized: -0.64,
            anchorYears: -34,
            title: "树苗形成",
            isExactTarget: false
        ),
        TemporalInterpretationMarker(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
            normalized: 0,
            anchorYears: 0,
            title: "现在",
            isExactTarget: false
        ),
        TemporalInterpretationMarker(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000013")!,
            normalized: 0.42,
            anchorYears: 12,
            title: "林荫形成",
            isExactTarget: true
        )
    ]

    VStack(alignment: .leading, spacing: PosterSpacing.xl) {
        TemporalFingerprintMark(
            markers: markers,
            selectedTime: TimePosition(normalized: 0.42)
        )

        TemporalFingerprintMark(
            markers: markers,
            selectedTime: TimePosition(normalized: 0.42),
            size: .poster
        )
    }
    .padding(PosterSpacing.lg)
    .background(PosterPalette.canvas)
}
