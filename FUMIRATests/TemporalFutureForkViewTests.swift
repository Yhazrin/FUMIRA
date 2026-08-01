import XCTest
@testable import FUMIRA

final class TemporalFutureForkViewTests: XCTestCase {
    func testPresentationKeepsAtMostThreeBranchesAndClampsHighIndex() {
        let presentation = makePresentation(
            items: fixtures + [
                item(
                    id: "fourth",
                    title: "第四种可能",
                    rationale: "不应进入紧凑组件。",
                    evidence: "第四条画面线索。"
                )
            ],
            selectedIndex: 99
        )

        XCTAssertEqual(
            presentation.items.count,
            TemporalFutureForkPresentation.maximumBranches
        )
        XCTAssertEqual(presentation.selectedIndex, 2)
        XCTAssertEqual(presentation.selectedItem?.id, "garden-path")
        XCTAssertEqual(presentation.branchCounter, "3 / 3")
    }

    func testPresentationClampsNegativeIndexToFirstBranch() {
        let presentation = makePresentation(selectedIndex: -8)

        XCTAssertEqual(presentation.selectedIndex, 0)
        XCTAssertEqual(presentation.selectedItem?.id, "shade-path")
        XCTAssertEqual(presentation.branchCounter, "1 / 3")
    }

    func testSelectedBranchPreservesRationaleAndEvidence() {
        let presentation = makePresentation(selectedIndex: 1)

        XCTAssertEqual(presentation.selectedItem?.title, "步道保持开阔")
        XCTAssertEqual(
            presentation.selectedItem?.rationale,
            "持续修剪树冠，保留更多天空。"
        )
        XCTAssertEqual(
            presentation.selectedItem?.evidence,
            "透视消失点、路面宽度与树冠缺口。"
        )
    }

    func testEmptyPresentationHasNoSelectionOrShakeFeedback() {
        let presentation = makePresentation(
            items: [],
            selectedIndex: 2,
            shakeFeedbackTrigger: 7
        )

        XCTAssertTrue(presentation.items.isEmpty)
        XCTAssertNil(presentation.selectedIndex)
        XCTAssertNil(presentation.selectedItem)
        XCTAssertEqual(presentation.branchCounter, "0 / 0")
        XCTAssertNil(presentation.shakeFeedbackText)
        XCTAssertEqual(presentation.accessibilityStatus, "尚无可比较分支")
    }

    func testShakeFeedbackIsOptionalAndNamesCurrentBranch() {
        let quiet = makePresentation(selectedIndex: 1)
        let shaken = makePresentation(
            selectedIndex: 1,
            shakeFeedbackTrigger: 4
        )

        XCTAssertNil(quiet.shakeFeedbackText)
        XCTAssertEqual(shaken.shakeFeedbackTrigger, 4)
        XCTAssertEqual(
            shaken.shakeFeedbackText,
            "摇动已切换到分支 2：步道保持开阔"
        )
        XCTAssertEqual(quiet.accessibilityStatus, "当前分支 2 / 3")
        XCTAssertEqual(shaken.accessibilityStatus, shaken.shakeFeedbackText)
    }

    func testReduceMotionRemainsExplicitPresentationInput() {
        let standard = makePresentation(reduceMotion: false)
        let reduced = makePresentation(reduceMotion: true)

        XCTAssertFalse(standard.reduceMotion)
        XCTAssertTrue(reduced.reduceMotion)
        XCTAssertTrue(standard.animatesSelectionContent)
        XCTAssertFalse(reduced.animatesSelectionContent)
        XCTAssertEqual(standard.items, reduced.items)
        XCTAssertEqual(standard.selectedIndex, reduced.selectedIndex)
    }

    private var fixtures: [TemporalFutureForkView.PresentationItem] {
        [
            item(
                id: "shade-path",
                title: "树荫覆盖小路",
                rationale: "保留树阵，让林冠缓慢相接。",
                evidence: "树干位置、枝叶朝向与步道轮廓。"
            ),
            item(
                id: "open-path",
                title: "步道保持开阔",
                rationale: "持续修剪树冠，保留更多天空。",
                evidence: "透视消失点、路面宽度与树冠缺口。"
            ),
            item(
                id: "garden-path",
                title: "边缘长成花园",
                rationale: "低矮植被沿着道路边缘生长。",
                evidence: "路缘留白、草地分布与光照方向。"
            )
        ]
    }

    private func makePresentation(
        items: [TemporalFutureForkView.PresentationItem]? = nil,
        selectedIndex: Int = 0,
        reduceMotion: Bool = false,
        shakeFeedbackTrigger: Int? = nil
    ) -> TemporalFutureForkPresentation {
        TemporalFutureForkPresentation.resolve(
            items: items ?? fixtures,
            selectedIndex: selectedIndex,
            reduceMotion: reduceMotion,
            shakeFeedbackTrigger: shakeFeedbackTrigger
        )
    }

    private func item(
        id: String,
        title: String,
        rationale: String,
        evidence: String
    ) -> TemporalFutureForkView.PresentationItem {
        TemporalFutureForkView.PresentationItem(
            id: id,
            title: title,
            rationale: rationale,
            evidence: evidence
        )
    }
}
