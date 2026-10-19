import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(CaptureStore.self) private var store
    @State private var keyDraft: String = ""
    @State private var savedFlash = false

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Claude") {
                HStack {
                    SecureField("sk-ant-…", text: $keyDraft)
                        .textFieldStyle(.roundedBorder)
                    Button(savedFlash ? "Saved" : "Save") {
                        settings.saveAPIKey(keyDraft)
                        savedFlash = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.2))
                            savedFlash = false
                        }
                    }
                    .disabled(keyDraft.isEmpty && settings.apiKey == nil)
                }
                Text(keyStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Model", selection: $settings.model) {
                    ForEach(AppSettings.models) { m in
                        Text(m.name).tag(m.id)
                    }
                }
                if let m = AppSettings.models.first(where: { $0.id == settings.model }) {
                    Text(m.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Let Claude title, summarize, and categorize captures", isOn: $settings.enrichmentEnabled)
            }

            Section("General") {
                Toggle("Launch Glimpse at login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.setLaunchAtLogin($0) }
                ))
                if let err = settings.launchAtLoginError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Hotkeys") {
                LabeledContent("Capture screen region", value: "⌥ ⇧ S")
                LabeledContent("Quick note", value: "⌥ ⇧ N")
                LabeledContent("Set category while capturing", value: "⌘ 1 … ⌘ 6")
                LabeledContent("Clear category / let Claude pick", value: "⌘ 0")
                LabeledContent("Save / new line / cancel", value: "↩ / ⇧ ↩ / esc")
            }

            Section("Storage") {
                LabeledContent("Captures") {
                    HStack {
                        Text("\(store.captures.count)")
                        Button("Export as Markdown…") { Exporter.exportMarkdown(store.captures) }
                            .disabled(store.captures.isEmpty)
                    }
                }
                HStack {
                    Text(store.rootURL.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Reveal") {
                        NSWorkspace.shared.activateFileViewerSelecting([store.rootURL])
                    }
                }
            }

            Section("Permissions") {
                Text("The first screenshot will ask for Screen Recording permission. Grant it to Glimpse in System Settings → Privacy & Security → Screen Recording, then try again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .onAppear {
            if settings.apiKeySource == .keychain { keyDraft = settings.apiKey ?? "" }
            settings.refreshLaunchAtLogin()
        }
    }

    private var keyStatus: String {
        switch settings.apiKeySource {
        case .keychain: return "Key stored in your login Keychain."
        case .environment: return "Using ANTHROPIC_API_KEY from the environment. Save a key here to override."
        case .none: return "No key set. Captures are stored but not organized until you add one."
        }
    }
}
