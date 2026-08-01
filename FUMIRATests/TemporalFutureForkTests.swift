import XCTest
@testable import FUMIRA

final class TemporalFutureForkTests: XCTestCase {
    func testRichSceneBibleProducesThreeDeterministicEvidenceBranches() {
        let target = TimePosition(offsetDays: 30 * 365.25)
        let understanding = makeUnderstanding(
            temporalLayers: [
                TemporalLayer(
                    layer: "infrastructure",
                    visibleEvidence: "中央步道为新修铺装",
                    futurePotential: "铺装在原轴线上更新",
                    confidence: 0.82
                ),
                TemporalLayer(
                    layer: "vegetation",
                    visibleEvidence: "前景树木仍然年轻",
                    futurePotential: "树木长大成荫",
                    confidence: 0.96
                ),
                TemporalLayer(
                    layer: "architecture",
                    visibleEvidence: "远处为中等密度建筑群",
                    futurePotential: "背景建筑密度可能提高",
                    confidence: 0.75
                )
            ]
        )

        let first = TemporalFutureForkEngine.resolve(
            understanding: understanding,
            target: target
        )
        let second = TemporalFutureForkEngine.resolve(
            understanding: understanding,
            target: target
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.availability, .available)
        XCTAssertEqual(first.branches.count, 3)
        XCTAssertEqual(Set(first.branches.map(\.id)).count, 3)
        XCTAssertEqual(first.branches.map(\.evidence.count), [1, 2, 3])
        XCTAssertEqual(first.branches[0].evidence[0].sourceKey, "vegetation")

        for branch in first.branches {
            XCTAssertEqual(branch.target, target)
            XCTAssertFalse(branch.evidence.isEmpty)
            XCTAssertFalse(branch.rationale.isEmpty)
            XCTAssertFalse(branch.generationDirective.isEmpty)
            XCTAssertTrue(branch.interpretation.hasPrefix("可能解释："))
            XCTAssertEqual(branch.contract.effect, .interpretationOnly)
            XCTAssertTrue(branch.contract.preservesTargetTime)
            XCTAssertFalse(branch.contract.startsGeneration)
            XCTAssertFalse(branch.contract.assertsFactualPrediction)
        }
    }

    func testSparseEvidenceDegradesRatherThanInventingSecondBranch() {
        let understanding = makeUnderstanding(
            temporalLayers: [
                TemporalLayer(
                    layer: "vegetation",
                    visibleEvidence: "树木年轻",
                    futurePotential: "树冠逐渐扩展",
                    confidence: 0.8
                ),
                TemporalLayer(
                    layer: "unsupported",
                    visibleEvidence: nil,
                    futurePotential: "没有可见依据的变化",
                    confidence: 1
                )
            ]
        )

        let result = TemporalFutureForkEngine.resolve(
            understanding: understanding,
            target: TimePosition(offsetDays: 10 * 365.25)
        )

        XCTAssertEqual(result.availability, .degradedInsufficientEvidence)
        XCTAssertEqual(result.branches.count, 1)
        XCTAssertEqual(result.branches[0].evidence[0].sourceKey, "vegetation")
        XCTAssertFalse(
            result.branches[0].interpretation.contains("没有可见依据的变化")
        )
    }

    func testSceneGraphAndDriversProvideDeterministicFallbackEvidence() {
        let understanding = makeUnderstanding(
            temporalLayers: [],
            changeDrivers: ["公共空间维护"],
            sceneGraph: SceneGraph(
                baseline: SceneBaseline(
                    locationType: "公园",
                    broadCulturalContext: nil,
                    probableCaptureEra: nil,
                    season: nil,
                    timeOfDay: nil,
                    weather: nil
                ),
                cameraLock: CameraLock(viewpoint: "同一机位"),
                regions: [
                    SceneRegion(
                        id: "path",
                        depth: .midground,
                        category: .surface,
                        description: "中央步道",
                        spatialAnchor: "中央透视轴",
                        materials: ["铺装"],
                        currentCondition: "铺装较新",
                        confidence: 0.9,
                        salience: 0.8,
                        temporalPolicy: .ageInPlace
                    ),
                    SceneRegion(
                        id: "skyline",
                        depth: .background,
                        category: .architecture,
                        description: "城市天际线",
                        spatialAnchor: "背景地平线",
                        materials: ["建筑"],
                        currentCondition: "建筑密度中等",
                        confidence: 0.7,
                        salience: 0.7,
                        temporalPolicy: .replaceByEra
                    )
                ],
                globalDrivers: [],
                uncertainties: []
            )
        )

        let result = TemporalFutureForkEngine.resolve(
            understanding: understanding,
            target: TimePosition(offsetDays: 20 * 365.25)
        )

        XCTAssertEqual(result.availability, .available)
        XCTAssertEqual(result.branches.count, 3)
        XCTAssertEqual(result.branches[0].evidence[0].source, .sceneRegion)
        XCTAssertEqual(result.branches[1].evidence[1].source, .sceneRegion)
        XCTAssertEqual(result.branches[2].evidence[2].source, .changeDriver)
        XCTAssertTrue(result.branches[0].interpretation.contains("原位"))
    }

    func testMissingUnderstandingPastNowAndInvalidTargetsReturnNoBranches() {
        let future = TimePosition(offsetDays: 365.25)
        let missing = TemporalFutureForkEngine.resolve(
            understanding: nil,
            target: future
        )
        XCTAssertEqual(missing.availability, .insufficientEvidence)
        XCTAssertTrue(missing.branches.isEmpty)

        let past = TemporalFutureForkEngine.resolve(
            understanding: makeUnderstanding(),
            target: TimePosition(offsetDays: -365.25)
        )
        XCTAssertEqual(past.availability, .targetIsNotFuture)
        XCTAssertTrue(past.branches.isEmpty)

        let now = TemporalFutureForkEngine.resolve(
            understanding: makeUnderstanding(),
            target: .now
        )
        XCTAssertEqual(now.availability, .targetIsNotFuture)
        XCTAssertTrue(now.branches.isEmpty)

        let invalid = TemporalFutureForkEngine.resolve(
            understanding: makeUnderstanding(),
            target: TimePosition(normalized: .nan)
        )
        XCTAssertEqual(invalid.availability, .invalidTarget)
        XCTAssertTrue(invalid.branches.isEmpty)
    }

    func testApplyingBranchPreservesTargetAndCompleteRenderPlanContract() throws {
        let target = TimePosition(offsetDays: 10 * 365.25)
        let result = TemporalFutureForkEngine.resolve(
            understanding: makeUnderstanding(
                temporalLayers: [
                    TemporalLayer(
                        layer: "vegetation",
                        visibleEvidence: "前景树木年轻",
                        futurePotential: "树木沿原位置长大",
                        confidence: 0.9
                    ),
                    TemporalLayer(
                        layer: "surface",
                        visibleEvidence: "铺装较新",
                        futurePotential: "铺装在原轴线上老化",
                        confidence: 0.8
                    )
                ]
            ),
            target: target
        )
        let branch = try XCTUnwrap(result.branches.first)
        let renderPlan = makeRenderPlan(target: target)
        let beatID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let exactTarget = renderPlan.exactTarget
        let beat = StoryBeat(
            id: beatID,
            anchorYears: target.offsetYears,
            title: "十年以后",
            narrative: "场景保持连续",
            visualPrompt: "保持同一机位",
            transitionCause: "自然生长",
            unchangedAnchors: ["中央轴线"],
            foregroundDelta: "树木变化",
            midgroundDelta: "步道变化",
            backgroundDelta: "背景保持",
            subjectDelta: "主体连续",
            environmentDelta: "环境渐变",
            exactTarget: exactTarget,
            renderPlan: renderPlan
        )

        let applied = try XCTUnwrap(branch.applying(to: beat, target: target))

        XCTAssertEqual(applied.id, beat.id)
        XCTAssertEqual(applied.anchorYears, beat.anchorYears)
        XCTAssertEqual(applied.title, beat.title)
        XCTAssertEqual(applied.transitionCause, beat.transitionCause)
        XCTAssertEqual(applied.unchangedAnchors, beat.unchangedAnchors)
        XCTAssertEqual(applied.foregroundDelta, beat.foregroundDelta)
        XCTAssertEqual(applied.midgroundDelta, beat.midgroundDelta)
        XCTAssertEqual(applied.backgroundDelta, beat.backgroundDelta)
        XCTAssertEqual(applied.subjectDelta, beat.subjectDelta)
        XCTAssertEqual(applied.environmentDelta, beat.environmentDelta)
        XCTAssertEqual(applied.exactTarget, beat.exactTarget)
        XCTAssertEqual(applied.renderPlan, beat.renderPlan)
        XCTAssertEqual(applied.renderPlan?.coverage, renderPlan.coverage)
        XCTAssertEqual(applied.renderPlan?.mustPreserve, renderPlan.mustPreserve)
        XCTAssertEqual(applied.renderPlan?.prohibitedDrift, renderPlan.prohibitedDrift)
        XCTAssertNotEqual(applied.narrative, beat.narrative)
        XCTAssertNotEqual(applied.visualPrompt, beat.visualPrompt)
        XCTAssertTrue(applied.visualPrompt.contains("非事实预测"))

        let otherTarget = TimePosition(offsetDays: 11 * 365.25)
        XCTAssertNil(branch.applying(to: beat, target: otherTarget))

        let mismatchedBeat = StoryBeat(
            anchorYears: 20,
            title: "错误目标",
            narrative: "不应被覆盖",
            visualPrompt: "不应被覆盖",
            exactTarget: ExactTarget(
                offsetDays: 20 * 365.25,
                targetDateISO: "",
                compactLabel: "20 年"
            ),
            renderPlan: renderPlan
        )
        XCTAssertNil(branch.applying(to: mismatchedBeat, target: target))

        let oneHourMismatchedBeat = StoryBeat(
            anchorYears: target.offsetYears,
            title: "偏移一小时",
            narrative: "不应被覆盖",
            visualPrompt: "不应被覆盖",
            exactTarget: ExactTarget(
                offsetDays: target.offsetDays + 1.0 / 24.0,
                targetDateISO: "",
                compactLabel: target.compactLabel
            ),
            renderPlan: renderPlan
        )
        XCTAssertNil(branch.applying(to: oneHourMismatchedBeat, target: target))
    }

    func testStableIDChangesWhenTargetOrEvidenceChanges() throws {
        let understanding = makeUnderstanding(
            temporalLayers: [
                TemporalLayer(
                    layer: "vegetation",
                    visibleEvidence: "树木年轻",
                    futurePotential: "树木长大",
                    confidence: .nan
                )
            ]
        )
        let targetA = TimePosition(offsetDays: 5 * 365.25)
        let targetB = TimePosition(offsetDays: 6 * 365.25)
        let branchA = try XCTUnwrap(
            TemporalFutureForkEngine.resolve(
                understanding: understanding,
                target: targetA
            ).branches.first
        )
        let branchARepeat = try XCTUnwrap(
            TemporalFutureForkEngine.resolve(
                understanding: understanding,
                target: targetA
            ).branches.first
        )
        let branchB = try XCTUnwrap(
            TemporalFutureForkEngine.resolve(
                understanding: understanding,
                target: targetB
            ).branches.first
        )

        XCTAssertEqual(branchA.id, branchARepeat.id)
        XCTAssertNotEqual(branchA.id, branchB.id)
        XCTAssertNil(branchA.evidence[0].confidence)
    }

    private func makeUnderstanding(
        temporalLayers: [TemporalLayer] = [],
        changeDrivers: [String] = [],
        sceneGraph: SceneGraph? = nil
    ) -> SceneUnderstanding {
        SceneUnderstanding(
            summary: "一处保持同一视点的场景",
            locationType: "场景",
            visualMood: "安静",
            timeClues: [],
            changeDrivers: changeDrivers,
            subjects: [],
            temporalLayers: temporalLayers,
            sceneGraph: sceneGraph
        )
    }

    private func makeRenderPlan(target: TimePosition) -> TemporalRenderPlan {
        TemporalRenderPlan(
            exactTarget: ExactTarget(
                offsetDays: target.offsetDays,
                targetDateISO: "2040-01-01T00:00:00Z",
                compactLabel: target.compactLabel
            ),
            horizonBand: .decades,
            subjectContinuityMode: .siteOnly,
            globalEraState: "一种未来解释",
            regionChanges: [
                RegionTemporalChange(
                    regionId: "trees",
                    action: .grow,
                    magnitude: .moderate,
                    targetAppearance: "树冠扩大",
                    causalReason: "自然生长"
                )
            ],
            crossRegionCouplings: ["树荫影响步道"],
            mustPreserve: ["中央轴线", "地平线"],
            allowedEraAdditions: ["维护设施"],
            prohibitedDrift: ["改变机位", "新增抢镜人物"],
            coverage: RenderPlanCoverage(
                foreground: true,
                midground: true,
                background: true,
                builtEnvironment: true,
                naturalEnvironment: true,
                principalSubject: true
            )
        )
    }
}
