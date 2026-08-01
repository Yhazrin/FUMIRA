import Foundation

enum TemporalFutureForkAvailability: Equatable, Sendable {
    case available
    case degradedInsufficientEvidence
    case insufficientEvidence
    case targetIsNotFuture
    case invalidTarget
}

enum TemporalFutureForkEvidenceSource: String, Hashable, Sendable {
    case temporalLayer
    case sceneRegion
    case changeDriver
}

/// Provenance carried into every interpretation. `observedEvidence` always
/// comes from SceneUnderstanding; `futurePotential` is explicitly hypothetical.
struct TemporalFutureForkEvidence: Hashable, Sendable {
    let source: TemporalFutureForkEvidenceSource
    let sourceKey: String
    let observedEvidence: String
    let futurePotential: String
    let confidence: Double?
}

enum TemporalFutureForkLens: String, Hashable, Sendable {
    case focusedContinuity
    case coupledChange
    case systemsView
}

enum TemporalFutureForkEffect: String, Hashable, Sendable {
    /// A read-only semantic alternative. It neither mutates time nor starts work.
    case interpretationOnly
}

/// Machine-readable safety contract for consumers in AppModel or generation.
struct TemporalFutureForkContract: Hashable, Sendable {
    let effect: TemporalFutureForkEffect
    let preservesTargetTime: Bool
    let startsGeneration: Bool
    let assertsFactualPrediction: Bool

    static let readOnlyInterpretation = TemporalFutureForkContract(
        effect: .interpretationOnly,
        preservesTargetTime: true,
        startsGeneration: false,
        assertsFactualPrediction: false
    )
}

struct TemporalFutureForkBranch: Identifiable, Hashable, Sendable {
    /// Stable across processes and launches for equal target + evidence input.
    let id: String
    let target: TimePosition
    let lens: TemporalFutureForkLens
    let title: String
    let interpretation: String
    let rationale: String
    let evidence: [TemporalFutureForkEvidence]
    /// Optional input for an existing generation request. This value never
    /// invokes a provider or creates a new target by itself.
    let generationDirective: String
    let contract: TemporalFutureForkContract

    /// Builds a branch-specific beat without changing generation.v3's target
    /// identity or render-plan safety fields. A mismatch returns nil instead of
    /// silently applying one target year's semantics to another.
    func applying(to beat: StoryBeat, target requestedTarget: TimePosition) -> StoryBeat? {
        guard contract == .readOnlyInterpretation,
              !evidence.isEmpty,
              TemporalFutureForkTarget.isSame(target, requestedTarget),
              TemporalFutureForkTarget.beat(beat, matches: requestedTarget)
        else {
            return nil
        }

        return StoryBeat(
            id: beat.id,
            anchorYears: beat.anchorYears,
            title: beat.title,
            narrative: Self.appending(
                interpretation,
                to: beat.narrative,
                maximum: StoryCopyPolicy.beatNarrative
            ),
            visualPrompt: Self.appending(
                generationDirective,
                to: beat.visualPrompt,
                maximum: StoryCopyPolicy.visualPrompt
            ),
            transitionCause: beat.transitionCause,
            unchangedAnchors: beat.unchangedAnchors,
            foregroundDelta: beat.foregroundDelta,
            midgroundDelta: beat.midgroundDelta,
            backgroundDelta: beat.backgroundDelta,
            subjectDelta: beat.subjectDelta,
            environmentDelta: beat.environmentDelta,
            exactTarget: beat.exactTarget,
            renderPlan: beat.renderPlan
        )
    }

    private static func appending(
        _ addition: String,
        to base: String,
        maximum: Int
    ) -> String {
        let separator = "；"
        let limitedAddition = TemporalFutureForkText.limit(addition, to: maximum)
        guard !base.isEmpty else { return limitedAddition }

        let baseBudget = maximum - limitedAddition.count - separator.count
        guard baseBudget > 0 else { return limitedAddition }
        let limitedBase = TemporalFutureForkText.limit(base, to: baseBudget)
        return limitedBase + separator + limitedAddition
    }
}

struct TemporalFutureForkResult: Hashable, Sendable {
    let target: TimePosition
    let availability: TemporalFutureForkAvailability
    let branches: [TemporalFutureForkBranch]
    let contract: TemporalFutureForkContract
}

/// Deterministic, offline interpretation engine for a selected future time.
///
/// It reads only already-available SceneUnderstanding fields. It never changes
/// the target, invokes generation, persists history, or presents a prediction as
/// fact. Rich input yields 2–3 branches; sparse input deliberately degrades to
/// one or zero instead of inventing unsupported detail.
enum TemporalFutureForkEngine {
    static func resolve(
        understanding: SceneUnderstanding?,
        target: TimePosition
    ) -> TemporalFutureForkResult {
        let contract = TemporalFutureForkContract.readOnlyInterpretation

        guard target.normalized.isFinite, target.offsetDays.isFinite else {
            return TemporalFutureForkResult(
                target: target,
                availability: .invalidTarget,
                branches: [],
                contract: contract
            )
        }
        guard target.offsetDays > 0 else {
            return TemporalFutureForkResult(
                target: target,
                availability: .targetIsNotFuture,
                branches: [],
                contract: contract
            )
        }
        guard let understanding else {
            return TemporalFutureForkResult(
                target: target,
                availability: .insufficientEvidence,
                branches: [],
                contract: contract
            )
        }

        let cues = Array(resolvedCues(from: understanding).prefix(3))
        let branches = cues.indices.map { index in
            makeBranch(
                lens: lens(for: index),
                cues: Array(cues.prefix(index + 1)),
                target: target,
                contract: contract
            )
        }

        let availability: TemporalFutureForkAvailability
        switch branches.count {
        case 2...:
            availability = .available
        case 1:
            availability = .degradedInsufficientEvidence
        default:
            availability = .insufficientEvidence
        }

        return TemporalFutureForkResult(
            target: target,
            availability: availability,
            branches: branches,
            contract: contract
        )
    }

    private static func resolvedCues(
        from understanding: SceneUnderstanding
    ) -> [TemporalFutureForkCue] {
        var cues: [TemporalFutureForkCue] = []
        var signatures = Set<String>()

        for (index, layer) in (understanding.temporalLayers ?? []).enumerated() {
            guard let layerName = TemporalFutureForkText.nonempty(layer.layer),
                  let observed = TemporalFutureForkText.nonempty(layer.visibleEvidence),
                  let potential = TemporalFutureForkText.nonempty(layer.futurePotential)
            else {
                continue
            }

            appendIfUnique(
                TemporalFutureForkCue(
                    source: .temporalLayer,
                    sourceKey: layerName,
                    label: layerName,
                    observedEvidence: observed,
                    futurePotential: potential,
                    confidence: boundedConfidence(layer.confidence),
                    sourcePriority: 0,
                    sourceIndex: index
                ),
                to: &cues,
                signatures: &signatures
            )
        }

        for (index, region) in (understanding.sceneGraph?.regions ?? []).enumerated() {
            guard let sourceKey = TemporalFutureForkText.nonempty(region.id),
                  let observed = TemporalFutureForkText.nonempty(region.currentCondition)
                    ?? TemporalFutureForkText.nonempty(region.description)
            else {
                continue
            }

            let label = TemporalFutureForkText.nonempty(region.description)
                ?? sourceKey
            appendIfUnique(
                TemporalFutureForkCue(
                    source: .sceneRegion,
                    sourceKey: sourceKey,
                    label: label,
                    observedEvidence: observed,
                    futurePotential: regionPotential(for: region),
                    confidence: combinedConfidence(
                        confidence: region.confidence,
                        salience: region.salience
                    ),
                    sourcePriority: 1,
                    sourceIndex: index
                ),
                to: &cues,
                signatures: &signatures
            )
        }

        let drivers = (understanding.sceneGraph?.globalDrivers ?? [])
            + understanding.changeDrivers
        for (index, driverValue) in drivers.enumerated() {
            guard let driver = TemporalFutureForkText.nonempty(driverValue) else {
                continue
            }
            appendIfUnique(
                TemporalFutureForkCue(
                    source: .changeDriver,
                    sourceKey: driver,
                    label: driver,
                    observedEvidence: "已识别的变化驱动：\(driver)",
                    futurePotential: "以“\(driver)”作为主要变化线索，其余未被证据支持的内容保持连续",
                    confidence: nil,
                    sourcePriority: 2,
                    sourceIndex: index
                ),
                to: &cues,
                signatures: &signatures
            )
        }

        return cues.sorted { lhs, rhs in
            if lhs.sourcePriority != rhs.sourcePriority {
                return lhs.sourcePriority < rhs.sourcePriority
            }
            let lhsConfidence = lhs.confidence ?? -1
            let rhsConfidence = rhs.confidence ?? -1
            if lhsConfidence != rhsConfidence {
                return lhsConfidence > rhsConfidence
            }
            let lhsKey = TemporalFutureForkText.canonical(lhs.sourceKey)
            let rhsKey = TemporalFutureForkText.canonical(rhs.sourceKey)
            if lhsKey != rhsKey {
                return lhsKey < rhsKey
            }
            return lhs.sourceIndex < rhs.sourceIndex
        }
    }

    private static func appendIfUnique(
        _ cue: TemporalFutureForkCue,
        to cues: inout [TemporalFutureForkCue],
        signatures: inout Set<String>
    ) {
        let signature = [
            cue.source.rawValue,
            TemporalFutureForkText.canonical(cue.sourceKey),
            TemporalFutureForkText.canonical(cue.futurePotential),
        ].joined(separator: "|")
        guard signatures.insert(signature).inserted else { return }
        cues.append(cue)
    }

    private static func boundedConfidence(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return min(max(value, 0), 1)
    }

    private static func combinedConfidence(
        confidence: Double,
        salience: Double
    ) -> Double? {
        guard confidence.isFinite, salience.isFinite else { return nil }
        return min(max((confidence + salience) / 2, 0), 1)
    }

    private static func regionPotential(for region: SceneRegion) -> String {
        let subject = TemporalFutureForkText.nonempty(region.description)
            ?? TemporalFutureForkText.nonempty(region.id)
            ?? "该区域"
        switch region.temporalPolicy {
        case .lockGeometry:
            return "保持\(subject)的几何与空间身份，仅呈现有依据的表面时间痕迹"
        case .ageInPlace:
            return "让\(subject)在原位呈现渐进老化，同时保持其空间锚点"
        case .evolve:
            return "让\(subject)沿当前形态渐进演化，不引入无关主体"
        case .replaceByEra:
            return "允许\(subject)出现时代性替换，同时保持同一区域与构图关系"
        case .mayDisappear:
            return "仅把\(subject)的消失作为一种可能解释，并保持场地连续性"
        case .transient:
            return "不把\(subject)这一瞬时状态外推为长期存在"
        }
    }

    private static func lens(for index: Int) -> TemporalFutureForkLens {
        switch index {
        case 0: .focusedContinuity
        case 1: .coupledChange
        default: .systemsView
        }
    }

    private static func makeBranch(
        lens: TemporalFutureForkLens,
        cues: [TemporalFutureForkCue],
        target: TimePosition,
        contract: TemporalFutureForkContract
    ) -> TemporalFutureForkBranch {
        let evidence = cues.map { cue in
            TemporalFutureForkEvidence(
                source: cue.source,
                sourceKey: cue.sourceKey,
                observedEvidence: cue.observedEvidence,
                futurePotential: cue.futurePotential,
                confidence: cue.confidence
            )
        }
        let interpretation = TemporalFutureForkText.limit(
            "可能解释：" + cues.map(\.futurePotential).joined(separator: "；"),
            to: StoryCopyPolicy.beatNarrative
        )
        let rationale = rationale(for: lens)
        let directive = TemporalFutureForkText.limit(
            "解释分支（非事实预测）：\(interpretation)。保持精确目标时间 \(target.compactLabel)，未列出的场景结构不变。",
            to: StoryCopyPolicy.visualPrompt
        )
        let title: String
        switch lens {
        case .focusedContinuity:
            title = "\(cues[0].label)延续"
        case .coupledChange:
            title = "双线并行"
        case .systemsView:
            title = "多层协同"
        }

        let stableSignature = ([
            "temporal-future-fork-v1",
            String(target.normalized.bitPattern, radix: 16),
            lens.rawValue,
        ] + evidence.flatMap {
            [
                $0.source.rawValue,
                TemporalFutureForkText.canonical($0.sourceKey),
                TemporalFutureForkText.canonical($0.observedEvidence),
                TemporalFutureForkText.canonical($0.futurePotential),
            ]
        }).joined(separator: "|")

        return TemporalFutureForkBranch(
            id: TemporalFutureForkStableID.make(from: stableSignature),
            target: target,
            lens: lens,
            title: TemporalFutureForkText.limit(title, to: StoryCopyPolicy.beatTitle),
            interpretation: interpretation,
            rationale: rationale,
            evidence: evidence,
            generationDirective: directive,
            contract: contract
        )
    }

    private static func rationale(for lens: TemporalFutureForkLens) -> String {
        switch lens {
        case .focusedContinuity:
            "仅沿最高排序的已见线索展开，未被证据支持的层保持连续。"
        case .coupledChange:
            "并置两条独立线索，表达同一目标时间下的一种组合解释。"
        case .systemsView:
            "组合三条已见线索形成系统解释，但不把组合结果声明为事实。"
        }
    }
}

private struct TemporalFutureForkCue: Sendable {
    let source: TemporalFutureForkEvidenceSource
    let sourceKey: String
    let label: String
    let observedEvidence: String
    let futurePotential: String
    let confidence: Double?
    let sourcePriority: Int
    let sourceIndex: Int
}

private enum TemporalFutureForkTarget {
    static func isSame(_ lhs: TimePosition, _ rhs: TimePosition) -> Bool {
        lhs.hasSameExactTimeIdentity(asOffsetDays: rhs.offsetDays)
    }

    static func beat(_ beat: StoryBeat, matches target: TimePosition) -> Bool {
        guard target.offsetDays.isFinite else { return false }
        let beatOffsetDays: Double
        if let exactTarget = beat.exactTarget {
            beatOffsetDays = exactTarget.offsetDays
        } else {
            beatOffsetDays = beat.anchorYears * 365.25
        }
        guard beatOffsetDays.isFinite else { return false }
        return target.hasSameExactTimeIdentity(asOffsetDays: beatOffsetDays)
    }
}

private enum TemporalFutureForkText {
    static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return normalized.isEmpty ? nil : normalized
    }

    static func canonical(_ value: String) -> String {
        nonempty(value)?.lowercased() ?? ""
    }

    static func limit(_ value: String, to maximum: Int) -> String {
        let normalized = nonempty(value) ?? ""
        guard normalized.count > maximum else { return normalized }
        guard maximum > 1 else { return String(normalized.prefix(maximum)) }
        return String(normalized.prefix(maximum - 1)) + "…"
    }
}

private enum TemporalFutureForkStableID {
    /// Fixed FNV-1a 64-bit hashing; unlike Swift.Hasher this is stable across runs.
    static func make(from value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return "future-fork-" + String(hash, radix: 16, uppercase: false)
    }
}
