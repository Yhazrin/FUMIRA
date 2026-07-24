import Foundation

protocol AIModelConfigurationStore: Sendable {
    func load() async -> AIModelConfiguration
    func save(_ configuration: AIModelConfiguration) async throws
}

actor UserDefaultsAIModelConfigurationStore: AIModelConfigurationStore {
    private let defaults: UserDefaults
    private let key = "fumira.ai-model-configuration.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() async -> AIModelConfiguration {
        guard
            let data = defaults.data(forKey: key),
            let value = try? JSONDecoder().decode(AIModelConfiguration.self, from: data)
        else {
            return .standard
        }
        return value
    }

    func save(_ configuration: AIModelConfiguration) async throws {
        defaults.set(try JSONEncoder().encode(configuration), forKey: key)
    }
}

actor InMemoryAIModelConfigurationStore: AIModelConfigurationStore {
    private var configuration: AIModelConfiguration

    init(configuration: AIModelConfiguration = .standard) {
        self.configuration = configuration
    }

    func load() async -> AIModelConfiguration {
        configuration
    }

    func save(_ configuration: AIModelConfiguration) async throws {
        self.configuration = configuration
    }
}
