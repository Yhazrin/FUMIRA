import Foundation

/// Resolves the optional FUMIRA backend base URL used to switch generation
/// from the local mock to `RemoteGenerationProvider`.
///
/// Resolution order:
/// 1. Process environment `FUMIRA_API_BASE_URL` (scheme launch / CI)
/// 2. Info.plist `FUMIRA_API_BASE_URL` (optional build-time key)
///
/// Empty / missing → Mock path. Never holds vendor API keys.
enum FUMIRAAPIConfiguration {
    static var baseURL: URL? {
        if let env = ProcessInfo.processInfo.environment["FUMIRA_API_BASE_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty,
           let url = URL(string: env)
        {
            return url
        }

        if let plist = Bundle.main.object(forInfoDictionaryKey: "FUMIRA_API_BASE_URL") as? String {
            let trimmed = plist.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, let url = URL(string: trimmed) {
                return url
            }
        }

        return nil
    }

    static var usesRemoteGeneration: Bool {
        baseURL != nil
    }
}
