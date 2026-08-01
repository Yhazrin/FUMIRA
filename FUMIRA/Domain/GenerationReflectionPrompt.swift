import Foundation

/// A small, local reflection for the otherwise silent generation interval.
/// It deliberately does not mutate an already-submitted generation request;
/// its role is to help the person stay with the captured moment while the
/// image pipeline works in the background.
struct GenerationReflectionPrompt: Equatable, Sendable {
    enum InteractionKind: Equatable, Sendable {
        case choices
        case stamps
        case note
    }

    struct Choice: Identifiable, Equatable, Sendable {
        let id: String
        let title: String
        let acknowledgement: String
    }

    let question: String
    let interactionKind: InteractionKind
    let choices: [Choice]
    let notePlaceholder: String?
    let noteAcknowledgement: String?

    static func make(for time: TimePosition) -> GenerationReflectionPrompt {
        if time.offsetDays > 1.0 / 48.0 {
            return GenerationReflectionPrompt(
                question: "你觉得这里到了未来，最可能多出什么？",
                interactionKind: .choices,
                choices: [
                    Choice(
                        id: "future-shade",
                        title: "更多树影",
                        acknowledgement: "这句猜想被留在这一帧背面。"
                    ),
                    Choice(
                        id: "future-encounter",
                        title: "一次新的相遇",
                        acknowledgement: "未来的相遇，已经被你记下。"
                    ),
                    Choice(
                        id: "future-sound",
                        title: "完全不同的声音",
                        acknowledgement: "这段声音，被留给未来想象。"
                    ),
                ],
                notePlaceholder: nil,
                noteAcknowledgement: nil
            )
        }

        if time.offsetDays < -1.0 / 48.0 {
            return GenerationReflectionPrompt(
                question: "如果回到这里，你想从哪一道痕迹读懂当时？",
                interactionKind: .stamps,
                choices: [
                    Choice(
                        id: "past-hope",
                        title: "一段声音",
                        acknowledgement: "这段声音，替你留在了过去。"
                    ),
                    Choice(
                        id: "past-treasure",
                        title: "一处光影",
                        acknowledgement: "这处光影，被你带回了现在。"
                    ),
                    Choice(
                        id: "past-constant",
                        title: "一个习惯",
                        acknowledgement: "这个习惯，成了时间的线索。"
                    ),
                ],
                notePlaceholder: nil,
                noteAcknowledgement: nil
            )
        }

        return GenerationReflectionPrompt(
            question: "留一句话，让未来的人读到这一刻。",
            interactionKind: .note,
            choices: [],
            notePlaceholder: "写给未来的这里…",
            noteAcknowledgement: "这句留言，已经留在照片背面。"
        )
    }
}
