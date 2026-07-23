import Foundation

enum AIModelRole: String, Codable, CaseIterable, Hashable, Sendable {
    case understanding
    case story
    case image

    var displayName: String {
        switch self {
        case .understanding:
            "图片理解"
        case .story:
            "故事编剧"
        case .image:
            "变迁生图"
        }
    }

    var shortDescription: String {
        switch self {
        case .understanding:
            "识别主体、空间与可能发生变化的线索"
        case .story:
            "把识图结果写成过去与未来的连续故事"
        case .image:
            "保持原图主体与构图，生成故事中的时间版本"
        }
    }
}

enum AIProviderKind: String, Codable, CaseIterable, Hashable, Sendable {
    case fumiraDemo
    case openAI
    case google
    case anthropic
    case blackForestLabs
    case stability

    var displayName: String {
        switch self {
        case .fumiraDemo:
            "FUMIRA Demo"
        case .openAI:
            "OpenAI"
        case .google:
            "Google"
        case .anthropic:
            "Anthropic"
        case .blackForestLabs:
            "Black Forest Labs"
        case .stability:
            "Stability AI"
        }
    }
}

enum AIModelAvailability: String, Codable, Hashable, Sendable {
    case ready
    case requiresBackend

    var label: String {
        switch self {
        case .ready:
            "可运行"
        case .requiresBackend:
            "待后台接入"
        }
    }
}

struct AIModelOption: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let role: AIModelRole
    let provider: AIProviderKind
    let modelID: String
    let displayName: String
    let detail: String
    let availability: AIModelAvailability
}

struct AIModelCatalog: Hashable, Codable, Sendable {
    let options: [AIModelOption]

    func options(for role: AIModelRole) -> [AIModelOption] {
        options.filter { $0.role == role }
    }

    func option(id: String) -> AIModelOption? {
        options.first { $0.id == id }
    }

    func isRunnable(_ configuration: AIModelConfiguration) -> Bool {
        AIModelRole.allCases.allSatisfy { role in
            guard let option = option(id: configuration.optionID(for: role)) else {
                return false
            }
            return option.availability == .ready
        }
    }

    static let bundled = AIModelCatalog(
        options: [
            AIModelOption(
                id: "demo.vision.context",
                role: .understanding,
                provider: .fumiraDemo,
                modelID: "fumira-vision-context-v1",
                displayName: "上下文识图 Demo",
                detail: "主体、空间、时代线索与变化驱动",
                availability: .ready
            ),
            AIModelOption(
                id: "openai.vision.server",
                role: .understanding,
                provider: .openAI,
                modelID: "backend/openai-vision",
                displayName: "OpenAI 视觉路由",
                detail: "由 FUMIRA 后台映射具体视觉模型",
                availability: .requiresBackend
            ),
            AIModelOption(
                id: "google.vision.server",
                role: .understanding,
                provider: .google,
                modelID: "backend/gemini-vision",
                displayName: "Gemini Vision 路由",
                detail: "由后台映射 Gemini 多模态模型",
                availability: .requiresBackend
            ),
            AIModelOption(
                id: "anthropic.vision.server",
                role: .understanding,
                provider: .anthropic,
                modelID: "backend/claude-vision",
                displayName: "Claude Vision 路由",
                detail: "由后台映射 Claude 视觉模型",
                availability: .requiresBackend
            ),
            AIModelOption(
                id: "demo.story.cinematic",
                role: .story,
                provider: .fumiraDemo,
                modelID: "fumira-story-cinematic-v1",
                displayName: "时间编剧 Demo",
                detail: "七个时间锚点与连续叙事提示词",
                availability: .ready
            ),
            AIModelOption(
                id: "openai.story.server",
                role: .story,
                provider: .openAI,
                modelID: "backend/openai-story",
                displayName: "ChatGPT 编剧路由",
                detail: "由后台映射 OpenAI 文本模型",
                availability: .requiresBackend
            ),
            AIModelOption(
                id: "google.story.server",
                role: .story,
                provider: .google,
                modelID: "backend/gemini-story",
                displayName: "Gemini 编剧路由",
                detail: "由后台映射 Gemini 文本模型",
                availability: .requiresBackend
            ),
            AIModelOption(
                id: "anthropic.story.server",
                role: .story,
                provider: .anthropic,
                modelID: "backend/claude-story",
                displayName: "Claude 编剧路由",
                detail: "由后台映射 Claude 文本模型",
                availability: .requiresBackend
            ),
            AIModelOption(
                id: "demo.image.identity",
                role: .image,
                provider: .fumiraDemo,
                modelID: "fumira-image-identity-v1",
                displayName: "主体一致性 Demo",
                detail: "用 SwiftUI 时间世界模拟基于原图的变迁",
                availability: .ready
            ),
            AIModelOption(
                id: "openai.image.server",
                role: .image,
                provider: .openAI,
                modelID: "backend/openai-image",
                displayName: "OpenAI Image 路由",
                detail: "由后台映射 OpenAI 图像生成模型",
                availability: .requiresBackend
            ),
            AIModelOption(
                id: "google.image.server",
                role: .image,
                provider: .google,
                modelID: "backend/imagen",
                displayName: "Imagen 路由",
                detail: "由后台映射 Google 图像生成模型",
                availability: .requiresBackend
            ),
            AIModelOption(
                id: "bfl.image.server",
                role: .image,
                provider: .blackForestLabs,
                modelID: "backend/flux",
                displayName: "FLUX 路由",
                detail: "由后台映射 FLUX 图像生成模型",
                availability: .requiresBackend
            ),
            AIModelOption(
                id: "stability.image.server",
                role: .image,
                provider: .stability,
                modelID: "backend/stable-image",
                displayName: "Stable Image 路由",
                detail: "由后台映射 Stability AI 图像模型",
                availability: .requiresBackend
            )
        ]
    )
}

struct AIModelConfiguration: Hashable, Codable, Sendable {
    var understandingOptionID: String
    var storyOptionID: String
    var imageOptionID: String

    func optionID(for role: AIModelRole) -> String {
        switch role {
        case .understanding:
            understandingOptionID
        case .story:
            storyOptionID
        case .image:
            imageOptionID
        }
    }

    mutating func select(optionID: String, for role: AIModelRole) {
        switch role {
        case .understanding:
            understandingOptionID = optionID
        case .story:
            storyOptionID = optionID
        case .image:
            imageOptionID = optionID
        }
    }

    static let demo = AIModelConfiguration(
        understandingOptionID: "demo.vision.context",
        storyOptionID: "demo.story.cinematic",
        imageOptionID: "demo.image.identity"
    )
}
