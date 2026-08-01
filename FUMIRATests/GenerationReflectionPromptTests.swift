import XCTest
@testable import FUMIRA

final class GenerationReflectionPromptTests: XCTestCase {
    func testFuturePromptInvitesAConcreteFutureGuess() {
        let prompt = GenerationReflectionPrompt.make(
            for: TimePosition(offsetDays: 365.25)
        )

        XCTAssertEqual(prompt.question, "你觉得这里到了未来，最可能多出什么？")
        XCTAssertEqual(prompt.interactionKind, .choices)
        XCTAssertEqual(prompt.choices.count, 3)
        XCTAssertTrue(prompt.choices.contains { $0.id == "future-encounter" })
    }

    func testPastPromptIsDistinctFromFuturePrompt() {
        let prompt = GenerationReflectionPrompt.make(
            for: TimePosition(offsetDays: -365.25)
        )

        XCTAssertEqual(prompt.question, "如果回到这里，你想从哪一道痕迹读懂当时？")
        XCTAssertEqual(prompt.interactionKind, .stamps)
        XCTAssertTrue(prompt.choices.contains { $0.id == "past-constant" })
    }

    func testNowPromptKeepsTheMomentPersonal() {
        let prompt = GenerationReflectionPrompt.make(for: .now)

        XCTAssertEqual(prompt.question, "留一句话，让未来的人读到这一刻。")
        XCTAssertEqual(prompt.interactionKind, .note)
        XCTAssertEqual(prompt.notePlaceholder, "写给未来的这里…")
    }
}
