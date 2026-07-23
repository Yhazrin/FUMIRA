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
        self.name = name
        self.confidence = min(max(confidence, 0), 1)
        self.identityRule = identityRule
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
        self.summary = summary
        self.locationType = locationType
        self.visualMood = visualMood
        self.timeClues = timeClues
        self.changeDrivers = changeDrivers
        self.subjects = subjects
    }

    static let demoPark = SceneUnderstanding(
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
        self.title = title
        self.narrative = narrative
        self.visualPrompt = visualPrompt
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
        self.title = title
        self.logline = logline
        self.presentTruth = presentTruth
        self.identityRules = identityRules
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

    static let demoPark = TemporalStory(
        title: "一条路，记住一百年",
        logline: "同一条公园步道，在城市与树木共同生长时，保存了每一代人的远方。",
        presentTruth: "今天，年轻的树刚刚遮住一点阳光，步道仍把视线送向城市边缘。",
        identityRules: [
            "镜头始终位于同一高度与方向",
            "中央步道始终是时间线",
            "三棵树保持相对位置并自然改变树龄"
        ],
        beats: [
            StoryBeat(
                anchorYears: -100,
                title: "这里还没有公园",
                narrative: "这里是一片靠近旧城的开阔土地，土路替代了今天的步道，远处只有低矮屋顶。",
                visualPrompt: "稀疏植被、泥土小径、低矮旧城、温暖褪色的日光"
            ),
            StoryBeat(
                anchorYears: -30,
                title: "第一批树苗",
                narrative: "公园刚被规划，细小树苗沿着新铺的道路站成一列，城市轮廓还很克制。",
                visualPrompt: "新栽树苗、较新的步道、较低城市密度、清爽纪实感"
            ),
            StoryBeat(
                anchorYears: -10,
                title: "公园开始被记住",
                narrative: "树冠尚未连成阴影，人们第一次把这条路当作每天经过的风景。",
                visualPrompt: "较年轻树冠、略有使用痕迹的步道、保持原图透视"
            ),
            StoryBeat(
                anchorYears: 0,
                title: "今天的这里",
                narrative: "年轻的树、开阔的草坡和一条通向城市的路，共同构成了今天。",
                visualPrompt: "忠实保持原始照片"
            ),
            StoryBeat(
                anchorYears: 10,
                title: "树荫连在一起",
                narrative: "树冠扩大，步道两侧出现更连续的绿荫，远处城市也向公园靠近了一些。",
                visualPrompt: "成熟树冠、连续树荫、适度增加的城市边界、真实自然"
            ),
            StoryBeat(
                anchorYears: 30,
                title: "公园成为城市的肺",
                narrative: "这片绿地被更密集的城市包围，却因为被持续照料而显得更加丰盛。",
                visualPrompt: "高大成熟树木、丰盛植被、远处高密城市、生态更新设施"
            ),
            StoryBeat(
                anchorYears: 100,
                title: "路还指向远方",
                narrative: "城市形态已经改变，老树成为地标；中央步道仍保留原来的方向，像一条可见的时间线。",
                visualPrompt: "百年老树、未来城市地标、生态基础设施、保持步道与构图连续"
            )
        ]
    )
}
