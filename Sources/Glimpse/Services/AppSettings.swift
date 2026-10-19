import Foundation

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    struct ModelOption: Identifiable, Hashable {
        let id: String
        let name: String
    }

    static let models: [ModelOption] = [
        ModelOption(id: "claude-fable-5-1", name: "Claude Fable 5.1"),
        ModelOption(id: "claude-opus-5", name: "Claude Opus 5"),
        ModelOption(id: "claude-sonnet-5", name: "Claude Sonnet 5"),
        ModelOption(id: "claude-haiku-4-5", name: "Claude Haiku 4.5"),
    ]

    @Published var model: String {
        didSet { UserDefaults.standard.set(model, forKey: "model") }
    }

    @Published var enrichmentEnabled: Bool {
        didSet { UserDefaults.standard.set(enrichmentEnabled, forKey: "enrichmentEnabled") }
    }

    /// Resolved API key: Keychain first, then the ANTHROPIC_API_KEY environment variable.
    @Published private(set) var apiKey: String?
    private(set) var apiKeySource: String = "none"

    private init() {
        model = UserDefaults.standard.string(forKey: "model") ?? "claude-fable-5-1"
        enrichmentEnabled = (UserDefaults.standard.object(forKey: "enrichmentEnabled") as? Bool) ?? true
        if let k = Keychain.read(), !k.isEmpty {
            apiKey = k
            apiKeySource = "keychain"
        } else if let k = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !k.isEmpty {
            apiKey = k
            apiKeySource = "environment"
        }
    }

    func saveAPIKey(_ raw: String) {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty {
            Keychain.delete()
            if let env = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !env.isEmpty {
                apiKey = env
                apiKeySource = "environment"
            } else {
                apiKey = nil
                apiKeySource = "none"
            }
        } else {
            Keychain.save(key)
            apiKey = key
            apiKeySource = "keychain"
        }
    }
}
