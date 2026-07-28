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

/// Offline/mock fallback only. Live generation prompts are authored on the
/// server (`server/src/temporalImagePrompt.ts`). Keep this short and never treat
/// it as the product source of truth.
enum TemporalImagePrompt {
    static func make(for time: TimePosition) -> String {
        let direction: String
        if abs(time.offsetDays) < 1 {
            direction = "接近此刻，仅做必要时间一致性修正。"
        } else if time.offsetDays > 0 {
            direction = "未来方向，累积可解释的环境与使用变化。"
        } else {
            direction = "过去方向，保守逆推并避免时代错置。"
        }
        return """
        [mock-fallback] 将输入照片编辑为「\(time.compactLabel)」同一机位真实照片。\
        \(direction) 保持构图与空间锚点；只改变有依据的部分，但不能在改变一个主体后停止；\
        不添加无关、抢镜或缺乏时间因果依据的人物、车辆、建筑或设施。权威 Prompt 在 server。
        """
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
    static let identityRule = 80
    /// CameraLock fields (viewpoint / lensAndPerspective / horizon / depthStructure).
    static let cameraLockField = 80
    /// SpatialAnchor name.
    static let spatialAnchorName = 24
    /// SpatialAnchor depth label.
    static let spatialAnchorDepth = 16
    /// SpatialAnchor position string.
    static let spatialAnchorPosition = 96
    /// SpatialAnchor geometry / material / silhouette.
    static let spatialAnchorGeometry = 96
    /// SpatialAnchor identityLock.
    static let spatialAnchorIdentity = 96
    /// TemporalLayer.layer (one of the six required systems).
    static let temporalLayerName = 28
    /// TemporalLayer.visibleEvidence.
    static let temporalLayerEvidence = 96
    /// TemporalLayer.pastPotential / futurePotential.
    static let temporalLayerPotential = 96
    /// Scene Bible storySeeds (slightly looser than change drivers).
    static let storySeed = 56
    /// HardConstraint sentence.
    static let hardConstraint = 96

    static func limit(_ value: String, to maximum: Int) -> String {
        GeneratedCopyLimiter.limit(value, to: maximum)
    }

    /// Limit an optional field; returns nil if the source is nil or empty after trimming.
    static func limitOrNil(_ value: String?, to maximum: Int) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return limit(trimmed, to: maximum)
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

struct CameraLock: Hashable, Codable, Sendable {
    var viewpoint: String?
    var lensAndPerspective: String?
    var horizon: String?
    var depthStructure: String?

    init(
        viewpoint: String? = nil,
        lensAndPerspective: String? = nil,
        horizon: String? = nil,
        depthStructure: String? = nil
    ) {
        self.viewpoint = UnderstandingCopyPolicy.limitOrNil(viewpoint, to: UnderstandingCopyPolicy.cameraLockField)
        self.lensAndPerspective = UnderstandingCopyPolicy.limitOrNil(lensAndPerspective, to: UnderstandingCopyPolicy.cameraLockField)
        self.horizon = UnderstandingCopyPolicy.limitOrNil(horizon, to: UnderstandingCopyPolicy.cameraLockField)
        self.depthStructure = UnderstandingCopyPolicy.limitOrNil(depthStructure, to: UnderstandingCopyPolicy.cameraLockField)
    }
}

struct SpatialAnchor: Hashable, Codable, Sendable {
    var name: String
    var depth: String?
    var position: String?
    var geometry: String?
    var identityLock: String?

    init(
        name: String,
        depth: String? = nil,
        position: String? = nil,
        geometry: String? = nil,
        identityLock: String? = nil
    ) {
        self.name = UnderstandingCopyPolicy.limit(name, to: UnderstandingCopyPolicy.spatialAnchorName)
        self.depth = UnderstandingCopyPolicy.limitOrNil(depth, to: UnderstandingCopyPolicy.spatialAnchorDepth)
        self.position = UnderstandingCopyPolicy.limitOrNil(position, to: UnderstandingCopyPolicy.spatialAnchorPosition)
        self.geometry = UnderstandingCopyPolicy.limitOrNil(geometry, to: UnderstandingCopyPolicy.spatialAnchorGeometry)
        self.identityLock = UnderstandingCopyPolicy.limitOrNil(identityLock, to: UnderstandingCopyPolicy.spatialAnchorIdentity)
    }
}

struct TemporalLayer: Hashable, Codable, Sendable {
    var layer: String
    var visibleEvidence: String?
    var pastPotential: String?
    var futurePotential: String?
    var confidence: Double?

    init(
        layer: String,
        visibleEvidence: String? = nil,
        pastPotential: String? = nil,
        futurePotential: String? = nil,
        confidence: Double? = nil
    ) {
        self.layer = UnderstandingCopyPolicy.limit(layer, to: UnderstandingCopyPolicy.temporalLayerName)
        self.visibleEvidence = UnderstandingCopyPolicy.limitOrNil(visibleEvidence, to: UnderstandingCopyPolicy.temporalLayerEvidence)
        self.pastPotential = UnderstandingCopyPolicy.limitOrNil(pastPotential, to: UnderstandingCopyPolicy.temporalLayerPotential)
        self.futurePotential = UnderstandingCopyPolicy.limitOrNil(futurePotential, to: UnderstandingCopyPolicy.temporalLayerPotential)
        self.confidence = confidence
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
    /// Optional Scene Bible extensions from the relay (ignored when absent).
    var cameraLock: CameraLock?
    var spatialAnchors: [SpatialAnchor]?
    var temporalLayers: [TemporalLayer]?
    var storySeeds: [String]?
    var hardConstraints: [String]?

    init(
        id: UUID = UUID(),
        summary: String,
        locationType: String,
        visualMood: String,
        timeClues: [String],
        changeDrivers: [String],
        subjects: [SceneSubject],
        cameraLock: CameraLock? = nil,
        spatialAnchors: [SpatialAnchor]? = nil,
        temporalLayers: [TemporalLayer]? = nil,
        storySeeds: [String]? = nil,
        hardConstraints: [String]? = nil
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
        self.cameraLock = cameraLock
        self.spatialAnchors = spatialAnchors.map { Array($0.prefix(8)) }
        self.temporalLayers = temporalLayers.map { Array($0.prefix(8)) }
        self.storySeeds = storySeeds.map {
            Array(
                $0.prefix(8).map {
                    UnderstandingCopyPolicy.limit($0, to: UnderstandingCopyPolicy.storySeed)
                }.filter { !$0.isEmpty }
            )
        }
        self.hardConstraints = hardConstraints.map {
            Array(
                $0.prefix(8).map {
                    UnderstandingCopyPolicy.limit($0, to: UnderstandingCopyPolicy.hardConstraint)
                }.filter { !$0.isEmpty }
            )
        }
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
        ],
        cameraLock: CameraLock(
            viewpoint: "中景对称视角",
            lensAndPerspective: "中等焦段、轻微广角",
            horizon: "位于画面上三分之一",
            depthStructure: "前景树木、中景步道、背景城市轮廓"
        ),
        spatialAnchors: [
            SpatialAnchor(
                name: "三棵景观树",
                depth: "前景",
                position: "画面左侧 1/3 处",
                geometry: "三棵相互错开的高大乔木",
                identityLock: "保留三棵树的相对位置和树冠轮廓"
            ),
            SpatialAnchor(
                name: "中央步道",
                depth: "中景",
                position: "由近及远向画面中心延伸",
                geometry: "连续铺装面，与两侧草坡形成三段式深度",
                identityLock: "保留透视方向与中心轴"
            ),
            SpatialAnchor(
                name: "城市天际线",
                depth: "背景",
                position: "画面最上沿",
                geometry: "中等高度建筑群的连续轮廓",
                identityLock: "维持地平线高度，允许建筑密度随年代变化"
            )
        ],
        temporalLayers: [
            TemporalLayer(
                layer: "vegetation",
                visibleEvidence: "前景树木年轻、草坡平整",
                pastPotential: "树木更矮、草坡未铺设",
                futurePotential: "树木长大成荫、草坡自然起伏",
                confidence: 0.95
            ),
            TemporalLayer(
                layer: "infrastructure",
                visibleEvidence: "中央步道为新修铺装",
                pastPotential: "步道未铺设或为临时线",
                futurePotential: "铺装更新、增设座椅或路灯",
                confidence: 0.9
            ),
            TemporalLayer(
                layer: "architecture",
                visibleEvidence: "远处可见低层建筑群",
                pastPotential: "建筑稀疏或为低矮房屋",
                futurePotential: "建筑密度增高，可加一两座新楼",
                confidence: 0.8
            ),
            TemporalLayer(
                layer: "movableObjects",
                visibleEvidence: "原图未见显著动态主体",
                pastPotential: "无抢镜主体",
                futurePotential: "保持主体稳定即可",
                confidence: 0.6
            )
        ],
        storySeeds: [
            "同一片土地在世代之间被反复照料",
            "城市与公园的关系以密度变化呈现"
        ],
        hardConstraints: [
            "不得新增抢镜的行人或动物",
            "保持树木位置与步道轴线"
        ]
    )
}

struct StoryBeat: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let anchorYears: Double
    let title: String
    let narrative: String
    let visualPrompt: String
    var transitionCause: String?
    var unchangedAnchors: [String]?
    var foregroundDelta: String?
    var midgroundDelta: String?
    var backgroundDelta: String?
    var subjectDelta: String?
    var environmentDelta: String?

    init(
        id: UUID = UUID(),
        anchorYears: Double,
        title: String,
        narrative: String,
        visualPrompt: String,
        transitionCause: String? = nil,
        unchangedAnchors: [String]? = nil,
        foregroundDelta: String? = nil,
        midgroundDelta: String? = nil,
        backgroundDelta: String? = nil,
        subjectDelta: String? = nil,
        environmentDelta: String? = nil
    ) {
        self.id = id
        self.anchorYears = anchorYears
        self.title = StoryCopyPolicy.limit(title, to: StoryCopyPolicy.beatTitle)
        self.narrative = StoryCopyPolicy.limit(narrative, to: StoryCopyPolicy.beatNarrative)
        self.visualPrompt = StoryCopyPolicy.limit(visualPrompt, to: StoryCopyPolicy.visualPrompt)
        self.transitionCause = transitionCause.map {
            StoryCopyPolicy.limit($0, to: StoryCopyPolicy.beatNarrative)
        }
        self.unchangedAnchors = unchangedAnchors.map {
            Array(
                $0.prefix(6).map { StoryCopyPolicy.limit($0, to: 28) }.filter { !$0.isEmpty }
            )
        }
        self.foregroundDelta = foregroundDelta.map {
            StoryCopyPolicy.limit($0, to: StoryCopyPolicy.beatNarrative)
        }
        self.midgroundDelta = midgroundDelta.map {
            StoryCopyPolicy.limit($0, to: StoryCopyPolicy.beatNarrative)
        }
        self.backgroundDelta = backgroundDelta.map {
            StoryCopyPolicy.limit($0, to: StoryCopyPolicy.beatNarrative)
        }
        self.subjectDelta = subjectDelta.map {
            StoryCopyPolicy.limit($0, to: StoryCopyPolicy.beatNarrative)
        }
        self.environmentDelta = environmentDelta.map {
            StoryCopyPolicy.limit($0, to: StoryCopyPolicy.beatNarrative)
        }
    }
}

/// Display budgets shared with `/v1/stories`. The server uses these while
/// prompting MiniMax; these initializers are the final safety boundary for old
/// servers or alternate providers.
enum StoryCopyPolicy {
    static let title = 16
    static let logline = 56
    static let presentTruth = 72
    static let identityRule = 80
    static let beatTitle = 14
    static let beatNarrative = 72
    static let visualPrompt = 140

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
