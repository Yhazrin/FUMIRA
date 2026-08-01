import SwiftUI

/// A compact, flat presentation for comparing grounded alternatives at the
/// same future point. The host owns selection and optional shake detection.
struct TemporalFutureForkView: View {
    struct PresentationItem: Identifiable, Equatable, Sendable {
        let id: String
        let title: String
        let rationale: String
        let evidence: String

        init(
            id: String,
            title: String,
            rationale: String,
            evidence: String
        ) {
            self.id = id
            self.title = title
            self.rationale = rationale
            self.evidence = evidence
        }
    }

    let items: [PresentationItem]
    let selectedIndex: Int
    let reduceMotion: Bool
    let shakeFeedbackTrigger: Int?
    let onSelect: (Int) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        items: [PresentationItem],
        selectedIndex: Int,
        reduceMotion: Bool,
        shakeFeedbackTrigger: Int? = nil,
        onSelect: @escaping (Int) -> Void
    ) {
        self.items = items
        self.selectedIndex = selectedIndex
        self.reduceMotion = reduceMotion
        self.shakeFeedbackTrigger = shakeFeedbackTrigger
        self.onSelect = onSelect
    }

    private var presentation: TemporalFutureForkPresentation {
        .resolve(
            items: items,
            selectedIndex: selectedIndex,
            reduceMotion: reduceMotion,
            shakeFeedbackTrigger: shakeFeedbackTrigger
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PosterSpacing.sm) {
            header

            if presentation.items.isEmpty {
                emptyState
            } else {
                branchSelectors
                branchDetails
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, PosterSpacing.xs)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: PosterSpacing.sm) {
            Text("同一年，另一种可能")
                .font(PosterTypography.sectionTitle)
                .foregroundStyle(PosterPalette.ink)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: PosterSpacing.sm)

            if presentation.selectedIndex != nil {
                Text(presentation.branchCounter)
                    .font(PosterTypography.label)
                    .foregroundStyle(PosterPalette.mutedInk)
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("可选时间分支，同一年，另一种可能")
        .accessibilityValue(presentation.accessibilityStatus)
        .accessibilityAddTraits(
            presentation.shakeFeedbackText == nil ? [] : .updatesFrequently
        )
        .accessibilityIdentifier("result.future-fork")
    }

    @ViewBuilder
    private var branchSelectors: some View {
        if dynamicTypeSize.isAccessibilitySize {
            verticalBranchSelectors
        } else {
            ViewThatFits(in: .horizontal) {
                horizontalBranchSelectors
                verticalBranchSelectors
            }
        }
    }

    private var horizontalBranchSelectors: some View {
        HStack(alignment: .top, spacing: PosterSpacing.md) {
            ForEach(presentation.items.indices, id: \.self) { index in
                branchButton(
                    presentation.items[index],
                    index: index,
                    isSelected: presentation.selectedIndex == index,
                    expands: false
                )
            }
        }
    }

    private var verticalBranchSelectors: some View {
        VStack(alignment: .leading, spacing: PosterSpacing.xs) {
            ForEach(presentation.items.indices, id: \.self) { index in
                branchButton(
                    presentation.items[index],
                    index: index,
                    isSelected: presentation.selectedIndex == index,
                    expands: true
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func branchButton(
        _ item: PresentationItem,
        index: Int,
        isSelected: Bool,
        expands: Bool
    ) -> some View {
        Button {
            guard !isSelected else { return }
            onSelect(index)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: PosterSpacing.xs) {
                Text("\(index + 1)")
                    .font(PosterTypography.caption)
                    .foregroundStyle(
                        isSelected
                            ? PosterPalette.ink
                            : PosterPalette.mutedInk
                    )

                Text(item.title)
                    .font(PosterTypography.label)
                    .foregroundStyle(
                        isSelected
                            ? PosterPalette.ink
                            : PosterPalette.mutedInk
                    )
                    .lineLimit(expands ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(
                maxWidth: expands ? .infinity : nil,
                minHeight: 44,
                alignment: .leading
            )
            .padding(.horizontal, PosterSpacing.xs)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(
                        isSelected
                            ? PosterPalette.actionBlueDeep
                            : PosterPalette.line
                    )
                    .frame(height: PosterRadius.waveBar)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: !expands, vertical: false)
        .accessibilityLabel("切换到分支 \(index + 1)，\(item.title)")
        .accessibilityValue(isSelected ? "当前分支" : "未选中")
        .accessibilityHint(isSelected ? "当前正在查看此分支" : "双击查看这种可能")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("result.future-fork.branch.\(index)")
    }

    private func selectedBranch(
        _ item: PresentationItem,
        index: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: PosterSpacing.xs) {
            Text(item.rationale)
                .font(PosterTypography.supporting)
                .foregroundStyle(PosterPalette.ink)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: PosterSpacing.sm) {
                Text("依据")
                    .font(PosterTypography.caption)
                    .foregroundStyle(PosterPalette.mutedInk)
                    .layoutPriority(1)

                Text(item.evidence)
                    .font(PosterTypography.caption)
                    .foregroundStyle(PosterPalette.mutedInk)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, PosterSpacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("当前分支 \(index + 1)，\(item.title)")
        .accessibilityValue("可能性：\(item.rationale)，画面依据：\(item.evidence)")
        .accessibilityIdentifier("result.future-fork.current")
    }

    /// Keeps every branch in one fixed layout region so selection never
    /// animates the parent stack's height. Only the visible layer crossfades.
    private var branchDetails: some View {
        ZStack(alignment: .topLeading) {
            ForEach(presentation.items.indices, id: \.self) { index in
                let isSelected = presentation.selectedIndex == index

                selectedBranch(presentation.items[index], index: index)
                    .opacity(isSelected ? 1 : 0)
                    .allowsHitTesting(isSelected)
                    .accessibilityHidden(!isSelected)
                    .animation(
                        presentation.animatesSelectionContent
                            ? PosterMotion.interaction
                            : nil,
                        value: isSelected
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: PosterSpacing.xs) {
            Text("还没有足够的未来线索")
                .font(PosterTypography.sectionTitle)
                .foregroundStyle(PosterPalette.ink)

            Text("需要至少两条有画面依据的分支。")
                .font(PosterTypography.supporting)
                .foregroundStyle(PosterPalette.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("result.future-fork.empty")
    }
}

/// Pure display state used by previews and focused component tests.
struct TemporalFutureForkPresentation: Equatable {
    static let maximumBranches = 3

    let items: [TemporalFutureForkView.PresentationItem]
    let selectedIndex: Int?
    let selectedItem: TemporalFutureForkView.PresentationItem?
    let branchCounter: String
    let shakeFeedbackTrigger: Int?
    let shakeFeedbackText: String?
    let reduceMotion: Bool

    var animatesSelectionContent: Bool {
        !reduceMotion
    }

    var accessibilityStatus: String {
        if let shakeFeedbackText {
            return shakeFeedbackText
        }
        guard selectedIndex != nil else {
            return "尚无可比较分支"
        }
        return "当前分支 \(branchCounter)"
    }

    static func resolve(
        items: [TemporalFutureForkView.PresentationItem],
        selectedIndex: Int,
        reduceMotion: Bool,
        shakeFeedbackTrigger: Int?
    ) -> Self {
        let visibleItems = Array(items.prefix(maximumBranches))
        let normalizedIndex: Int?

        if visibleItems.isEmpty {
            normalizedIndex = nil
        } else {
            normalizedIndex = min(max(selectedIndex, 0), visibleItems.count - 1)
        }

        let selectedItem = normalizedIndex.map { visibleItems[$0] }
        let branchCounter = normalizedIndex.map {
            "\($0 + 1) / \(visibleItems.count)"
        } ?? "0 / 0"
        let shakeFeedbackText: String?

        if shakeFeedbackTrigger != nil, let normalizedIndex, let selectedItem {
            shakeFeedbackText = "摇动已切换到分支 \(normalizedIndex + 1)：\(selectedItem.title)"
        } else {
            shakeFeedbackText = nil
        }

        return Self(
            items: visibleItems,
            selectedIndex: normalizedIndex,
            selectedItem: selectedItem,
            branchCounter: branchCounter,
            shakeFeedbackTrigger: shakeFeedbackTrigger,
            shakeFeedbackText: shakeFeedbackText,
            reduceMotion: reduceMotion
        )
    }
}

#Preview("Future fork") {
    TemporalFutureForkView(
        items: .futureForkPreview,
        selectedIndex: 1,
        reduceMotion: false,
        onSelect: { _ in }
    )
    .padding(PosterSpacing.lg)
    .background(PosterPalette.canvas)
}

#Preview("Future fork — shake feedback") {
    TemporalFutureForkView(
        items: .futureForkPreview,
        selectedIndex: 2,
        reduceMotion: true,
        shakeFeedbackTrigger: 1,
        onSelect: { _ in }
    )
    .padding(PosterSpacing.lg)
    .background(PosterPalette.canvas)
}

#Preview("Future fork — large type") {
    TemporalFutureForkView(
        items: .futureForkPreview,
        selectedIndex: 0,
        reduceMotion: true,
        onSelect: { _ in }
    )
    .environment(\.dynamicTypeSize, .accessibility3)
    .padding(PosterSpacing.lg)
    .background(PosterPalette.canvas)
}

private extension Array where Element == TemporalFutureForkView.PresentationItem {
    static let futureForkPreview: [Element] = [
        Element(
            id: "shade-path",
            title: "树荫覆盖小路",
            rationale: "保留现有树阵，以慢生长让林冠在同一年里连成更完整的阴影。",
            evidence: "树干位置、枝叶朝向与步道轮廓。"
        ),
        Element(
            id: "open-path",
            title: "步道保持开阔",
            rationale: "如果持续修剪临路树冠，同一条路可能保留更多天空与视线。",
            evidence: "现在的透视消失点、路面宽度与树冠缺口。"
        ),
        Element(
            id: "garden-path",
            title: "边缘长成花园",
            rationale: "低矮植被可以在不改变主路的前提下，让路缘形成更有层次的生长带。",
            evidence: "路缘留白、现有草地分布与光照方向。"
        )
    ]
}
