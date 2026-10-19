import AppKit

/// Entry points for the two capture gestures. Called from hotkeys, menus, and toolbar buttons.
@MainActor
enum CaptureFlow {
    private static var frontmostAppName: String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        if app.bundleIdentifier == Bundle.main.bundleIdentifier { return nil }
        return app.localizedName
    }

    static func startScreenshot() {
        let sourceApp = frontmostAppName
        Task {
            guard let data = await ScreenshotService.captureInteractive(),
                  let image = NSImage(data: data) else { return }
            CapturePanelController.shared.present(kind: .screenshot, image: image, imageData: data, sourceApp: sourceApp)
        }
    }

    static func startNote() {
        let sourceApp = frontmostAppName
        CapturePanelController.shared.present(kind: .note, image: nil, imageData: nil, sourceApp: sourceApp)
    }
}
