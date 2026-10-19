import SwiftUI
import AppKit
import Carbon.HIToolbox

@main
struct GlimpseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = CaptureStore.shared
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup("Glimpse", id: "main") {
            MainView()
                .environmentObject(store)
                .environmentObject(settings)
                .frame(minWidth: 900, minHeight: 540)
        }
        .defaultSize(width: 1120, height: 720)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Capture Screen Region") { CaptureFlow.startScreenshot() }
                    .keyboardShortcut("s", modifiers: [.option, .shift])
                Button("Quick Note") { CaptureFlow.startNote() }
                    .keyboardShortcut("n", modifiers: [.option, .shift])
            }
        }

        MenuBarExtra("Glimpse", systemImage: "camera.viewfinder") {
            MenuBarMenu()
                .environmentObject(store)
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(store)
        }
    }
}

struct MenuBarMenu: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject var store: CaptureStore

    var body: some View {
        Button("Capture Screen Region   ⌥⇧S") { CaptureFlow.startScreenshot() }
        Button("Quick Note   ⌥⇧N") { CaptureFlow.startNote() }
        Divider()
        Button("Open Glimpse (\(store.captures.count) captures)") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
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
            Task { @MainActor in CaptureFlow.startScreenshot() }
        }
        HotkeyManager.shared.register(id: 2, keyCode: UInt32(kVK_ANSI_N), modifiers: mods) {
            Task { @MainActor in CaptureFlow.startNote() }
        }
        Task { @MainActor in Enricher.shared.retryPending() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
