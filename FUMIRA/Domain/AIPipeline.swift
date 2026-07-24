import Foundation

enum PipelineStage: String, Codable, CaseIterable, Equatable, Sendable {
    case configuration
    case capture
    case understanding
    case story
    case imageGeneration

    var displayName: String {
        switch self {
        case .configuration:
            "模型配置"
        case .capture:
            "拍照"
        case .understanding:
            "图片理解"
        case .story:
            "时间故事"
        case .imageGeneration:
            "变迁图生成"
        }
    }
}

struct CapturedPhoto: Identifiable, Hashable, Sendable {
    let id: UUID
    let data: Data
    let capturedAt: Date
    let pixelWidth: Int
    let pixelHeight: Int

    init(
        id: UUID = UUID(),
        data: Data,
        capturedAt: Date = .now,
        pixelWidth: Int = 0,
        pixelHeight: Int = 0
    ) {
        self.id = id
        self.data = data
        self.capturedAt = capturedAt
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    /// Width divided by height after orientation normalisation and composition
    /// cropping. Every on-screen preview uses this value so a portrait,
    /// landscape, or square capture keeps the same frame throughout the
    /// pipeline.
    var displayAspectRatio: Double? {
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }
        return Double(pixelWidth) / Double(pixelHeight)
    }
}

private enum GeneratedCopyLimiter {
    static func limit(_ value: String, to maximum: Int) -> String {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
        guard normalized.count > maximum else { return normalized }
        guard maximum > 1 else { return String(normalized.prefix(maximum)) }
        return String(normalized.prefix(maximum - 1)) + "…"
    }
}

enum UnderstandingCopyPolicy {
    static let summary = 80
    static let locationType = 14
    static let visualMood = 40
    static let timeClue = 24
    static let changeDriver = 24
    static let subjectName = 18
    static let identityRule = 48

    static func limit(_ value: String, to maximum: Int) -> String {
        GeneratedCopyLimiter.limit(value, to: maximum)
    }
}

struct SceneSubject: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let name: String
    let confidence: Double
    let identityRule: String

    init(
        id: UUID = UUID(),
        name: String,
        confidence: Double,
        identityRule: String
    ) {
        self.id = id
        self.name = UnderstandingCopyPolicy.limit(name, to: UnderstandingCopyPolicy.subjectName)
        self.confidence = min(max(confidence, 0), 1)
        self.identityRule = UnderstandingCopyPolicy.limit(
            identityRule,
            to: UnderstandingCopyPolicy.identityRule
        )
    }
}

struct SceneUnderstanding: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let summary: String
    let locationType: String
    let visualMood: String
    let timeClues: [String]
    let changeDrivers: [String]
    let subjects: [SceneSubject]

    init(
        id: UUID = UUID(),
        summary: String,
        locationType: String,
        visualMood: String,
        timeClues: [String],
        changeDrivers: [String],
        subjects: [SceneSubject]
    ) {
        self.id = id
        self.summary = UnderstandingCopyPolicy.limit(summary, to: UnderstandingCopyPolicy.summary)
        self.locationType = UnderstandingCopyPolicy.limit(
            locationType,
            to: UnderstandingCopyPolicy.locationType
        )
        self.visualMood = UnderstandingCopyPolicy.limit(
            visualMood,
            to: UnderstandingCopyPolicy.visualMood
        )
        self.timeClues = timeClues
            .prefix(8)
            .map { UnderstandingCopyPolicy.limit($0, to: UnderstandingCopyPolicy.timeClue) }
            .filter { !$0.isEmpty }
        self.changeDrivers = changeDrivers
            .prefix(8)
            .map { UnderstandingCopyPolicy.limit($0, to: UnderstandingCopyPolicy.changeDriver) }
            .filter { !$0.isEmpty }
        self.subjects = Array(subjects.prefix(6))
    }

    static let parkReference = SceneUnderstanding(
        summary: "一座正在生长的城市公园：树木、草坡与中央步道共同指向远处的城市边界。",
        locationType: "城市公园",
        visualMood: "安静、开阔、带有向远处延伸的期待",
        timeClues: ["年轻树木", "新修步道", "远处城市轮廓"],
        changeDrivers: ["植被自然生长", "城市扩张", "公共空间更新", "气候变化"],
        subjects: [
            SceneSubject(
                name: "三棵公园树木",
                confidence: 0.97,
                identityRule: "保留树木的相对位置，让树龄随时间改变"
            ),
            SceneSubject(
                name: "中央步道",
                confidence: 0.94,
                identityRule: "保留步道的透视方向与画面中心线"
            ),
            SceneSubject(
                name: "草坡与天际线",
                confidence: 0.91,
                identityRule: "维持地平线高度，让城市密度随年代变化"
            )
        ]
    )
}

struct StoryBeat: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let anchorYears: Double
    let title: String
    let narrative: String
    let visualPrompt: String

    init(
        id: UUID = UUID(),
        anchorYears: Double,
        title: String,
        narrative: String,
        visualPrompt: String
    ) {
        self.id = id
        self.anchorYears = anchorYears
        self.title = StoryCopyPolicy.limit(title, to: StoryCopyPolicy.beatTitle)
        self.narrative = StoryCopyPolicy.limit(narrative, to: StoryCopyPolicy.beatNarrative)
        self.visualPrompt = StoryCopyPolicy.limit(visualPrompt, to: StoryCopyPolicy.visualPrompt)
    }
}

/// Display budgets shared with `/v1/stories`. The server uses these while
/// prompting MiniMax; these initializers are the final safety boundary for old
/// servers or alternate providers.
enum StoryCopyPolicy {
    static let title = 16
    static let logline = 56
    static let presentTruth = 72
    static let identityRule = 48
    static let beatTitle = 14
    static let beatNarrative = 72
    static let visualPrompt = 110

    static func limit(_ value: String, to maximum: Int) -> String {
        GeneratedCopyLimiter.limit(value, to: maximum)
    }
}

struct TemporalStory: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let title: String
    let logline: String
    let presentTruth: String
    let identityRules: [String]
    let beats: [StoryBeat]

    init(
        id: UUID = UUID(),
        title: String,
        logline: String,
        presentTruth: String,
        identityRules: [String],
        beats: [StoryBeat]
    ) {
        self.id = id
        self.title = StoryCopyPolicy.limit(title, to: StoryCopyPolicy.title)
        self.logline = StoryCopyPolicy.limit(logline, to: StoryCopyPolicy.logline)
        self.presentTruth = StoryCopyPolicy.limit(presentTruth, to: StoryCopyPolicy.presentTruth)
        self.identityRules = identityRules
            .prefix(8)
            .map { StoryCopyPolicy.limit($0, to: StoryCopyPolicy.identityRule) }
            .filter { !$0.isEmpty }
        self.beats = beats.sorted { $0.anchorYears < $1.anchorYears }
    }

    func beat(for time: TimePosition) -> StoryBeat? {
        beats.min {
            abs($0.anchorYears - time.offsetYears) <
                abs($1.anchorYears - time.offsetYears)
        }
    }

    func narrative(for time: TimePosition) -> String {
        guard abs(time.offsetYears) >= 0.5 else { return presentTruth }
        guard let beat = beat(for: time) else { return logline }
        return "\(time.compactLabel)，\(beat.narrative)"
    }

    func generationPrompt(
        for time: TimePosition,
        understanding: SceneUnderstanding
    ) -> String {
        let beat = beat(for: time)
        let identity = identityRules.joined(separator: "；")
        let subjects = understanding.subjects
            .map(\.identityRule)
            .joined(separator: "；")
        return """
        基于原始照片生成 \(time.compactLabel) 的同一地点。
        故事：\(beat?.narrative ?? logline)
        视觉变化：\(beat?.visualPrompt ?? "保持当下状态")
        场景理解：\(understanding.summary)
        主体连续性：\(subjects)
        叙事连续性：\(identity)
        保持原图构图、镜头位置和主要主体身份，不添加无关人物或文字。
        """
    }

    /// Offline/simulator fallback. Live runs receive every content field from
    /// `/v1/stories`; this factory avoids baking one park-specific story into
    /// the product while keeping previews and network-free development functional.
    static func fallback(
        understanding: SceneUnderstanding,
        targetTime: TimePosition
    ) -> TemporalStory {
        let location = understanding.locationType.isEmpty
            ? "这个地方"
            : understanding.locationType
        let drivers = understanding.changeDrivers.isEmpty
            ? ["时间自然变化"]
            : understanding.changeDrivers
        let identityRules = understanding.subjects.map(\.identityRule)
        let anchors = [-100.0, -30, -10, 0, 10, 30, 100]

        return TemporalStory(
            title: "\(location)的时间回声",
            logline: "\(understanding.summary) 目标抵达\(targetTime.compactLabel)。",
            presentTruth: understanding.summary,
            identityRules: identityRules.isEmpty
                ? ["保持原图主体、机位与构图关系"]
                : identityRules,
            beats: anchors.enumerated().map { index, anchor in
                let driver = drivers[index % drivers.count]
                return StoryBeat(
                    anchorYears: anchor,
                    title: anchor == 0
                        ? "今天的\(location)"
                        : (anchor < 0 ? "\(location)的旧日" : "\(location)的下一章"),
                    narrative: anchor == 0
                        ? understanding.summary
                        : "\(driver)继续改变\(location)的景象，主体与构图保持连续。",
                    visualPrompt: "\(understanding.visualMood)，\(driver)，保持原图主体、机位与构图"
                )
            }
        )
    }

    static let parkReference = fallback(
        understanding: .parkReference,
        targetTime: TimePosition(normalized: 0.35)
    )
}
