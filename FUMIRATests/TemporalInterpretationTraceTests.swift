import XCTest
@testable import FUMIRA

final class TemporalInterpretationTraceTests: XCTestCase {
    func testResolveUsesNearestCanonicalBeatAndExplicitExplanation() {
        let nowBeat = makeBeat(
            id: uuid(1),
            anchorYears: 0,
            title: "此刻",
            narrative: "此刻仍保持原貌。"
        )
        let futureBeat = makeBeat(
            id: uuid(2),
            anchorYears: 10,
            title: "林荫形成",
            narrative: "树冠逐渐覆盖步道。",
            transitionCause: "树木持续生长",
            unchangedAnchors: ["中央步道", "地平线", "主体位置", "远处塔楼"]
        )
        let story = makeStory(
            identityRules: ["备用主体规则"],
            beats: [nowBeat, futureBeat]
        )
        let understanding = makeUnderstanding(changeDrivers: ["公共空间维护"])
        let selectedTime = TimePosition(offsetDays: 8 * 365.25)

        let trace = TemporalInterpretationTrace.resolve(
            story: story,
            understanding: understanding,
            at: selectedTime
        )

        XCTAssertEqual(trace.selectedTime, selectedTime)
        XCTAssertEqual(trace.activeBeatID, futureBeat.id)
        XCTAssertEqual(trace.activeBeatTitle, futureBeat.title)
        XCTAssertEqual(trace.narrative, futureBeat.narrative)
        XCTAssertEqual(trace.changeTrace, "树木持续生长")
        XCTAssertEqual(trace.continuityAnchors, ["中央步道", "地平线", "主体位置"])
        XCTAssertTrue(trace.interpretationLabel.hasPrefix("一种可能的"))
    }

    func testResolveFallsBackToSceneDriverAndStoryIdentityRules() {
        let beat = makeBeat(
            id: uuid(3),
            anchorYears: 0,
            title: "此刻",
            narrative: "同一机位下的此刻。",
            transitionCause: "  ",
            unchangedAnchors: ["", "\n"]
        )
        let story = makeStory(
            identityRules: ["保留主体", "保留中心轴", "保留地平线", "第四条不展示"],
            beats: [beat]
        )

        let trace = TemporalInterpretationTrace.resolve(
            story: story,
            understanding: makeUnderstanding(
                changeDrivers: ["材料自然老化", "后续驱动"]
            ),
            at: .now
        )

        XCTAssertEqual(trace.changeTrace, "材料自然老化")
        XCTAssertEqual(trace.continuityAnchors, ["保留主体", "保留中心轴", "保留地平线"])
    }

    func testMarkersAreMonotonicAndBoundedInRailSpace() {
        let story = makeStory(
            beats: [
                makeBeat(id: uuid(4), anchorYears: 150, title: "远未来"),
                makeBeat(id: uuid(5), anchorYears: -150, title: "远过去"),
                makeBeat(id: uuid(6), anchorYears: 0, title: "此刻"),
                makeBeat(id: uuid(7), anchorYears: 25, title: "未来"),
                makeBeat(id: uuid(8), anchorYears: -25, title: "过去")
            ]
        )

        let markers = TemporalInterpretationTrace.resolve(
            story: story,
            understanding: makeUnderstanding(),
            at: .now
        ).markers

        XCTAssertEqual(markers.map(\.anchorYears), [-150, -25, 0, 25, 150])
        XCTAssertTrue(markers.allSatisfy { (-1 ... 1).contains($0.normalized) })
        for (lhs, rhs) in zip(markers, markers.dropFirst()) {
            XCTAssertLessThanOrEqual(lhs.normalized, rhs.normalized)
        }
        XCTAssertEqual(markers.first?.normalized, -1)
        XCTAssertEqual(markers.last?.normalized, 1)
    }

    func testDistinctExactTargetIsAddedAsOneMarker() {
        let exactBeat = makeBeat(
            id: uuid(9),
            anchorYears: 12.5,
            title: "精确目标",
            exactTarget: makeExactTarget(anchorYears: 12.5)
        )
        let story = makeStory(
            beats: [
                makeBeat(id: uuid(10), anchorYears: 0, title: "此刻"),
                makeBeat(id: uuid(11), anchorYears: 10, title: "十年")
            ],
            targetBeat: exactBeat
        )

        let markers = TemporalInterpretationTrace.resolve(
            story: story,
            understanding: makeUnderstanding(),
            at: TimePosition(offsetDays: 11 * 365.25)
        ).markers

        XCTAssertEqual(markers.count, 3)
        XCTAssertEqual(markers.filter(\.isExactTarget).map(\.id), [exactBeat.id])
        XCTAssertEqual(markers.map(\.anchorYears), [0, 10, 12.5])
    }

    func testMatchingExactTargetDrivesTheActiveExplanation() {
        let canonicalBeat = makeBeat(
            id: uuid(16),
            anchorYears: 10,
            title: "十年锚点",
            narrative: "标准锚点叙事。"
        )
        let exactBeat = makeBeat(
            id: uuid(17),
            anchorYears: 12.5,
            title: "十二年半目标",
            narrative: "这条叙事精确对应已生成的十二年半。",
            transitionCause: "精确时间累积",
            unchangedAnchors: ["同一主体"],
            exactTarget: makeExactTarget(anchorYears: 12.5)
        )
        let story = makeStory(beats: [canonicalBeat], targetBeat: exactBeat)

        let trace = TemporalInterpretationTrace.resolve(
            story: story,
            understanding: makeUnderstanding(changeDrivers: ["备用驱动"]),
            at: TimePosition(offsetDays: 12.5 * 365.25)
        )

        XCTAssertEqual(trace.activeBeatID, exactBeat.id)
        XCTAssertEqual(trace.activeBeatTitle, exactBeat.title)
        XCTAssertEqual(trace.narrative, exactBeat.narrative)
        XCTAssertEqual(trace.changeTrace, "精确时间累积")
        XCTAssertEqual(trace.continuityAnchors, ["同一主体"])
    }

    func testExactTargetAtCanonicalAnchorIsDeduplicated() {
        let canonicalBeat = makeBeat(
            id: uuid(12),
            anchorYears: 10,
            title: "十年"
        )
        let exactBeat = makeBeat(
            id: uuid(13),
            anchorYears: 10.001,
            title: "精确十年",
            exactTarget: makeExactTarget(anchorYears: 10.001)
        )
        let story = makeStory(beats: [canonicalBeat], targetBeat: exactBeat)

        let markers = TemporalInterpretationTrace.resolve(
            story: story,
            understanding: makeUnderstanding(),
            at: TimePosition(offsetDays: 10 * 365.25)
        ).markers

        XCTAssertEqual(markers.count, 1)
        XCTAssertEqual(markers.first?.id, canonicalBeat.id)
        XCTAssertEqual(markers.first?.isExactTarget, true)
        XCTAssertFalse(markers.contains { $0.id == exactBeat.id })
    }

    func testResolveDoesNotSnapSelectionOrModifyPipelineInputs() {
        let canonicalBeat = makeBeat(
            id: uuid(14),
            anchorYears: 10,
            title: "十年"
        )
        let exactBeat = makeBeat(
            id: uuid(15),
            anchorYears: 13,
            title: "精确十三年",
            exactTarget: makeExactTarget(anchorYears: 13)
        )
        let story = makeStory(beats: [canonicalBeat], targetBeat: exactBeat)
        let understanding = makeUnderstanding(changeDrivers: ["植被生长"])
        let selectedTime = TimePosition(offsetDays: 7.25 * 365.25)
        let originalStory = story
        let originalUnderstanding = understanding

        let trace = TemporalInterpretationTrace.resolve(
            story: story,
            understanding: understanding,
            at: selectedTime
        )

        XCTAssertEqual(trace.selectedTime, selectedTime)
        XCTAssertEqual(trace.selectedTime.normalized, selectedTime.normalized, accuracy: 0)
        XCTAssertNotEqual(trace.selectedTime, TimePosition(offsetDays: canonicalBeat.anchorYears * 365.25))
        XCTAssertNotEqual(trace.selectedTime, TimePosition(offsetDays: exactBeat.anchorYears * 365.25))
        XCTAssertEqual(story, originalStory)
        XCTAssertEqual(understanding, originalUnderstanding)
        XCTAssertEqual(story.targetBeat, exactBeat)
    }

    func testEmptyInputsProduceAQuietSafeTrace() {
        let selectedTime = TimePosition(normalized: 0.37)

        let trace = TemporalInterpretationTrace.resolve(
            story: nil,
            understanding: nil,
            at: selectedTime
        )

        XCTAssertEqual(trace.selectedTime, selectedTime)
        XCTAssertNil(trace.activeBeatID)
        XCTAssertNil(trace.activeBeatTitle)
        XCTAssertEqual(trace.narrative, "暂无足够线索形成时间解释。")
        XCTAssertNil(trace.changeTrace)
        XCTAssertTrue(trace.continuityAnchors.isEmpty)
        XCTAssertTrue(trace.markers.isEmpty)
        XCTAssertEqual(
            trace.interpretationLabel,
            "一种可能的时间解释 · \(selectedTime.compactLabel)"
        )
    }

    private func makeStory(
        title: String = "同一地点",
        logline: String = "时间改变外观，机位保持连续。",
        presentTruth: String = "这是当前可观察到的场景。",
        identityRules: [String] = ["保留主体与构图"],
        beats: [StoryBeat],
        targetBeat: StoryBeat? = nil
    ) -> TemporalStory {
        TemporalStory(
            title: title,
            logline: logline,
            presentTruth: presentTruth,
            identityRules: identityRules,
            beats: beats,
            targetBeat: targetBeat
        )
    }

    private func makeUnderstanding(
        summary: String = "一处保持同一视点的场景。",
        changeDrivers: [String] = []
    ) -> SceneUnderstanding {
        SceneUnderstanding(
            summary: summary,
            locationType: "场景",
            visualMood: "安静",
            timeClues: [],
            changeDrivers: changeDrivers,
            subjects: []
        )
    }

    private func makeBeat(
        id: UUID,
        anchorYears: Double,
        title: String,
        narrative: String = "一种可能的场景变化。",
        transitionCause: String? = nil,
        unchangedAnchors: [String]? = nil,
        exactTarget: ExactTarget? = nil
    ) -> StoryBeat {
        StoryBeat(
            id: id,
            anchorYears: anchorYears,
            title: title,
            narrative: narrative,
            visualPrompt: "保持同一机位",
            transitionCause: transitionCause,
            unchangedAnchors: unchangedAnchors,
            exactTarget: exactTarget
        )
    }

    private func makeExactTarget(anchorYears: Double) -> ExactTarget {
        ExactTarget(
            offsetDays: anchorYears * 365.25,
            targetDateISO: "",
            compactLabel: "\(anchorYears) 年"
        )
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}
