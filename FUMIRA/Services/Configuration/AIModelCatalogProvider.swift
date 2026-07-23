import Foundation

protocol AIModelCatalogProvider: Sendable {
    func catalog() async throws -> AIModelCatalog
}

struct BundledAIModelCatalogProvider: AIModelCatalogProvider {
    func catalog() async throws -> AIModelCatalog {
        .bundled
    }
}
