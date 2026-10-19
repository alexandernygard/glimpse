import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var store: CaptureStore
    @State private var keyDraft: String = ""
    @State private var savedFlash = false

    var body: some View {
        Form {
            Section("Claude") {
                HStack {
                    SecureField("sk-ant-…", text: $keyDraft)
                        .textFieldStyle(.roundedBorder)
                    Button(savedFlash ? "Saved" : "Save") {
                        settings.saveAPIKey(keyDraft)
                        savedFlash = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { savedFlash = false }
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
                Toggle("Let Claude title, summarize, and categorize captures", isOn: $settings.enrichmentEnabled)
            }

            Section("Hotkeys") {
                LabeledContent("Capture screen region", value: "⌥ ⇧ S")
                LabeledContent("Quick note", value: "⌥ ⇧ N")
                LabeledContent("Set category while capturing", value: "⌘ 1 … ⌘ 6")
                LabeledContent("Clear category / let Claude pick", value: "⌘ 0")
                LabeledContent("Save / new line / cancel", value: "↩ / ⇧ ↩ / esc")
            }

            Section("Storage") {
                LabeledContent("Captures", value: "\(store.captures.count)")
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
            if settings.apiKeySource == "keychain" { keyDraft = settings.apiKey ?? "" }
        }
    }

    private var keyStatus: String {
        switch settings.apiKeySource {
        case "keychain": return "Key stored in your login Keychain."
        case "environment": return "Using ANTHROPIC_API_KEY from the environment. Save a key here to override."
        default: return "No key set. Captures are stored but not organized until you add one."
        }
    }
}
