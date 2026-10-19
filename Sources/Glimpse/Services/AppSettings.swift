import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    struct ModelOption: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let detail: String
    }

    static let defaultModel = "claude-sonnet-5-5"

    static let models: [ModelOption] = [
        ModelOption(id: "claude-sonnet-5-5", name: "Claude Sonnet 5.5", detail: "Balanced speed and quality (default)"),
        ModelOption(id: "claude-haiku-5-5", name: "Claude Haiku 5.5", detail: "Fastest and cheapest"),
        ModelOption(id: "claude-opus-5-5", name: "Claude Opus 5.5", detail: "Most careful reading of dense screenshots"),
    ]

    var model: String {
        didSet { UserDefaults.standard.set(model, forKey: Keys.model) }
    }

    var enrichmentEnabled: Bool {
        didSet { UserDefaults.standard.set(enrichmentEnabled, forKey: Keys.enrichmentEnabled) }
    }

    /// Resolved API key: Keychain first, then the ANTHROPIC_API_KEY environment variable.
    private(set) var apiKey: String?
    private(set) var apiKeySource: KeySource = .none

    enum KeySource { case keychain, environment, none }

    /// Mirrors the system's login item state rather than storing our own flag.
    private(set) var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    private(set) var launchAtLoginError: String?

    private enum Keys {
        static let model = "model"
        static let enrichmentEnabled = "enrichmentEnabled"
    }

    private init() {
        model = Self.validatedModel(UserDefaults.standard.string(forKey: Keys.model))
        enrichmentEnabled = (UserDefaults.standard.object(forKey: Keys.enrichmentEnabled) as? Bool) ?? true
        // Persist the migration so a retired model id never lingers in defaults.
        UserDefaults.standard.set(model, forKey: Keys.model)
        resolveAPIKey()
    }

    /// Falls back to the default when the stored id is missing or no longer offered (e.g. a retired model).
    static func validatedModel(_ stored: String?) -> String {
        guard let stored, models.contains(where: { $0.id == stored }) else { return defaultModel }
        return stored
    }

    func saveAPIKey(_ raw: String) {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty {
            Keychain.delete()
        } else {
            Keychain.save(key)
        }
        resolveAPIKey()
    }

    private func resolveAPIKey() {
        if let k = Keychain.read(), !k.isEmpty {
            apiKey = k
            apiKeySource = .keychain
        } else if let k = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !k.isEmpty {
            apiKey = k
            apiKeySource = .environment
        } else {
            apiKey = nil
            apiKeySource = .none
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        refreshLaunchAtLogin()
    }

    func refreshLaunchAtLogin() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        if status == .requiresApproval {
            launchAtLoginError = "Approve Glimpse in System Settings → General → Login Items."
        }
    }
}
