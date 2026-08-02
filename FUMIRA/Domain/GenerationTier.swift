import Foundation

/// A single user-facing quality dial.
///
/// One choice resolves the image model, how many anchor frames the session
/// pre-generates, how much prompt detail survives compression, and how many
/// validate/repair rounds the server is allowed to spend. It mirrors
/// `server/src/tiers.ts` — the two must be changed together.
enum GenerationTier: String, Codable, CaseIterable, Hashable, Sendable {
    case swift
    case balanced
    case faithful
    case cinematic

    static let `default`: GenerationTier = .balanced

    /// Cheapest first, so pickers and comparison tables read in one direction.
    static let ordered: [GenerationTier] = [.swift, .balanced, .faithful, .cinematic]

    var displayName: String {
        switch self {
        case .swift: "极速"
        case .balanced: "标准"
        case .faithful: "高保真"
        case .cinematic: "电影级"
        }
    }

    var tagline: String {
        switch self {
        case .swift: "最快最省，先看到大概的样子"
        case .balanced: "速度与还原度的平衡点"
        case .faithful: "专用编辑模型，自动校验构图与年代"
        case .cinematic: "最强编辑模型，最密锚点与最多修复轮次"
        }
    }

    var symbolName: String {
        switch self {
        case .swift: "bolt"
        case .balanced: "circle.lefthalf.filled"
        case .faithful: "checkmark.seal"
        case .cinematic: "film"
        }
    }

    /// Image option resolved when the tier is selected. Must stay in sync with
    /// the server's `TIER_PROFILES[...].imageModel`.
    var imageOptionID: String {
        switch self {
        case .swift: "apimart.image.gemini-3.1-flash"
        case .balanced: "apimart.image.gpt-4o"
        case .faithful, .cinematic: "apimart.image.gpt-image-2"
        }
    }

    /// Odd count so NOW is always an anchor and the rail stays symmetric.
    var anchorCount: Int {
        switch self {
        case .swift: 3
        case .balanced: 5
        case .faithful: 7
        case .cinematic: 9
        }
    }

    var repairRounds: Int {
        switch self {
        case .swift, .balanced: 0
        case .faithful: 1
        case .cinematic: 2
        }
    }

    var relativeCost: Int {
        switch self {
        case .swift: 1
        case .balanced: 3
        case .faithful: 6
        case .cinematic: 12
        }
    }

    var estimatedSecondsPerFrame: Int {
        switch self {
        case .swift: 15
        case .balanced: 35
        case .faithful: 70
        case .cinematic: 150
        }
    }

    /// Rough wait for the full anchor set, which is what the user actually feels.
    var estimatedSessionSeconds: Int {
        estimatedSecondsPerFrame * anchorCount
    }

    var estimatedSessionLabel: String {
        let seconds = estimatedSessionSeconds
        if seconds < 90 {
            return "约 \(seconds) 秒"
        }
        return "约 \(Int((Double(seconds) / 60).rounded())) 分钟"
    }

    var costLabel: String {
        String(repeating: "¥", count: min(4, Int(log2(Double(relativeCost))) + 1))
    }

    var accessibilitySummary: String {
        "\(displayName)，\(tagline)，\(anchorCount) 个时间锚点，\(estimatedSessionLabel)"
    }

    static func resolve(_ rawValue: String?) -> GenerationTier {
        guard let rawValue, let tier = GenerationTier(rawValue: rawValue) else {
            return .default
        }
        return tier
    }
}
