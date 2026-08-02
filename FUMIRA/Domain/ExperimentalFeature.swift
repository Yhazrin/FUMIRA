import Foundation
import Observation

/// Interactions kept in the build but off the main path.
///
/// Seven parallel time interactions shipped during exploration. Only two stay
/// on the main path: the time rail you can see, and tilt browsing you
/// deliberately turn on. Each case below is a complete, tested implementation
/// that lost the convergence decision — not dead code. Gating them here keeps
/// the result screen legible while preserving the ability to evaluate any of
/// them later.
enum ExperimentalFeature: String, CaseIterable, Identifiable, Hashable, Sendable {
    case blowReveal
    case shakeToFork
    case futureFork
    case diorama

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blowReveal: "吹气显影"
        case .shakeToFork: "摇一摇换分支"
        case .futureFork: "未来分支"
        case .diorama: "3D 微缩场景"
        }
    }

    var detail: String {
        switch self {
        case .blowReveal: "结果页用麦克风吹气揭开照片，关闭后直接显示"
        case .shakeToFork: "摇动设备切换下一个未来分支"
        case .futureFork: "结果页下方展示多种未来可能并可分别生成"
        case .diorama: "把场景渲染成可旋转的 3D 微缩模型"
        }
    }

    /// Everything defaults off. The converged flow is rail + opt-in tilt.
    var defaultsEnabled: Bool { false }

    var storageKey: String { "fumira.experimental.\(rawValue)" }
}

/// UserDefaults-backed switches for the demoted interactions.
@MainActor
@Observable
final class ExperimentalFeatureStore {
    private let defaults: UserDefaults
    private var enabled: Set<ExperimentalFeature>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var restored: Set<ExperimentalFeature> = []
        for feature in ExperimentalFeature.allCases {
            let isOn = defaults.object(forKey: feature.storageKey) as? Bool
                ?? feature.defaultsEnabled
            if isOn { restored.insert(feature) }
        }
        #if DEBUG
        // UI audits need the demoted interactions on stage without a human
        // walking the settings list first.
        restored.formUnion(Self.auditOverrides)
        #endif
        self.enabled = restored
    }

    #if DEBUG
    /// `FUMIRA_EXPERIMENTS=blowReveal,futureFork` or `all`.
    private static var auditOverrides: Set<ExperimentalFeature> {
        guard let raw = ProcessInfo.processInfo.environment["FUMIRA_EXPERIMENTS"] else {
            return []
        }
        if raw == "all" { return Set(ExperimentalFeature.allCases) }
        return Set(
            raw.split(separator: ",")
                .compactMap { ExperimentalFeature(rawValue: String($0).trimmingCharacters(in: .whitespaces)) }
        )
    }
    #endif

    func isEnabled(_ feature: ExperimentalFeature) -> Bool {
        enabled.contains(feature)
    }

    func setEnabled(_ isEnabled: Bool, for feature: ExperimentalFeature) {
        if isEnabled {
            enabled.insert(feature)
        } else {
            enabled.remove(feature)
        }
        defaults.set(isEnabled, forKey: feature.storageKey)
    }
}
