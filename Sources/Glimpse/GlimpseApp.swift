import SwiftUI
import AppKit
import Carbon.HIToolbox

@main
struct GlimpseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = CaptureStore.shared
    @State private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup("Glimpse", id: "main") {
            MainView()
                .environment(store)
                .environment(settings)
                .frame(minWidth: 900, minHeight: 540)
        }
        .defaultSize(width: 1120, height: 720)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Capture Screen Region") { CaptureFlow.startScreenshot() }
                    .keyboardShortcut("s", modifiers: [.option, .shift])
                Button("Quick Note") { CaptureFlow.startNote() }
                    .keyboardShortcut("n", modifiers: [.option, .shift])
                Divider()
                Button("Export All as Markdown…") { Exporter.exportMarkdown(store.captures) }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(store.captures.isEmpty)
            }
            CommandMenu("Claude") {
                Button("Retry Failed Captures") { Enricher.shared.retryUnfinished() }
                    .disabled(settings.apiKey == nil || !store.captures.contains { $0.aiStatus.isUnfinished })
            }
        }

        MenuBarExtra("Glimpse", systemImage: "camera.viewfinder") {
            MenuBarMenu()
                .environment(store)
        }

        Settings {
            SettingsView()
                .environment(settings)
                .environment(store)
        }
    }
}

struct MenuBarMenu: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(CaptureStore.self) private var store

    var body: some View {
        Button("Capture Screen Region   ⌥⇧S") { CaptureFlow.startScreenshot() }
        Button("Quick Note   ⌥⇧N") { CaptureFlow.startNote() }
        Divider()
        Button("Open Glimpse (\(store.captures.count) captures)") {
            openWindow(id: "main")
            NSApp.activate()
        }
        SettingsLink { Text("Settings…") }
        Divider()
        Button("Quit Glimpse") { NSApp.terminate(nil) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let mods = UInt32(optionKey | shiftKey)
        HotkeyManager.shared.register(id: 1, keyCode: UInt32(kVK_ANSI_S), modifiers: mods) {
            CaptureFlow.startScreenshot()
        }
        HotkeyManager.shared.register(id: 2, keyCode: UInt32(kVK_ANSI_N), modifiers: mods) {
            CaptureFlow.startNote()
        }
        Enricher.shared.retryPending()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@MainActor
enum Exporter {
    static func exportMarkdown(_ items: [Capture]) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "Glimpse \(Date().formatted(.iso8601.year().month().day())).md"
        panel.message = "Screenshots are copied into a folder next to the Markdown file."
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try CaptureStore.shared.exportMarkdown(items, to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Export failed"
            alert.runModal()
        }
    }
}
