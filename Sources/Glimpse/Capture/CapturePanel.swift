import AppKit
import SwiftUI
import Observation

@MainActor
@Observable
final class CaptureDraft {
    let kind: CaptureKind
    let image: NSImage?
    let imageData: Data?
    let sourceApp: String?
    var text: String = ""
    var category: Category?

    init(kind: CaptureKind, image: NSImage?, imageData: Data?, sourceApp: String?) {
        self.kind = kind
        self.image = image
        self.imageData = imageData
        self.sourceApp = sourceApp
    }
}

/// Borderless floating panel that can take keyboard focus without activating the app.
final class CapturePanel: NSPanel {
    var onCategoryKey: ((Int) -> Void)?
    var onCancel: (() -> Void)?
    var onSubmit: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command {
            if let chars = event.charactersIgnoringModifiers, let n = Int(chars), (0...9).contains(n) {
                onCategoryKey?(n)
                return true
            }
            if event.keyCode == 36 { // return
                onSubmit?()
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

@MainActor
final class CapturePanelController {
    static let shared = CapturePanelController()

    private var panel: CapturePanel?
    private var draft: CaptureDraft?

    func present(kind: CaptureKind, image: NSImage?, imageData: Data?, sourceApp: String?) {
        dismiss()

        let draft = CaptureDraft(kind: kind, image: image, imageData: imageData, sourceApp: sourceApp)
        self.draft = draft

        let view = CaptureView(
            draft: draft,
            onSubmit: { [weak self] in self?.submit() },
            onCancel: { [weak self] in self?.dismiss() }
        )
        let hosting = NSHostingView(rootView: view)
        var size = hosting.fittingSize
        if size.width < 100 || size.height < 100 { size = NSSize(width: 560, height: image == nil ? 260 : 520) }

        let panel = CapturePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = hosting

        panel.onCategoryKey = { n in
            draft.category = n == 0 ? nil : Category.from(hotkeyNumber: n)
        }
        panel.onCancel = { [weak self] in self?.dismiss() }
        panel.onSubmit = { [weak self] in self?.submit() }

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let f = screen?.visibleFrame {
            let origin = NSPoint(x: f.midX - size.width / 2, y: f.maxY - size.height - f.height * 0.16)
            panel.setFrameOrigin(origin)
        }

        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
    }

    func submit() {
        guard let draft else { dismiss(); return }
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || draft.imageData != nil else { dismiss(); return }

        var capture = Capture(kind: draft.kind, text: text)
        capture.sourceApp = draft.sourceApp
        if let cat = draft.category {
            capture.category = cat
            capture.categorySource = .manual
        }
        if let data = draft.imageData {
            capture.imageFilename = CaptureStore.shared.storeImage(data, id: capture.id)
        }
        CaptureStore.shared.add(capture)
        dismiss()
        Enricher.shared.enrich(id: capture.id)
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        draft = nil
    }
}
