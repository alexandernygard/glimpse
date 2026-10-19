import SwiftUI
import AppKit

struct CaptureView: View {
    @ObservedObject var draft: CaptureDraft
    var onSubmit: () -> Void
    var onCancel: () -> Void

    private var placeholder: String {
        draft.kind == .screenshot
            ? "Add a note about this screenshot (optional)…"
            : "What's on your mind?"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: draft.kind == .screenshot ? "camera.viewfinder" : "square.and.pencil")
                    .foregroundStyle(.secondary)
                Text(draft.kind == .screenshot ? "Screenshot" : "Quick note")
                    .font(.headline)
                Spacer()
                if let app = draft.sourceApp {
                    Text("from \(app)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let image = draft.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
            }

            ZStack(alignment: .topLeading) {
                NoteTextView(text: $draft.text, onSubmit: onSubmit, onCancel: onCancel)
                    .frame(height: draft.image == nil ? 96 : 64)
                if draft.text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 7)
                        .padding(.leading, 9)
                        .allowsHitTesting(false)
                }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.35)))

            HStack(spacing: 6) {
                ForEach(Category.allCases) { cat in
                    CategoryChip(category: cat, selected: draft.category == cat, showHotkey: true) {
                        draft.category = draft.category == cat ? nil : cat
                    }
                }
            }

            HStack(spacing: 14) {
                hint("↩", "save")
                hint("⇧↩", "new line")
                hint("⌘0", draft.category == nil ? "let Claude pick" : "clear category")
                Spacer()
                hint("esc", "cancel")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.12)))
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.caption.monospaced())
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary))
            Text(label)
        }
    }
}

/// NSTextView wrapper so Return submits, Shift-Return inserts a newline, and Escape cancels.
struct NoteTextView: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = false

        let tv = scroll.documentView as! NSTextView
        tv.delegate = context.coordinator
        tv.font = .systemFont(ofSize: 15)
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 5, height: 6)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.string = text

        DispatchQueue.main.async {
            tv.window?.makeFirstResponder(tv)
        }
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        let tv = nsView.documentView as! NSTextView
        if tv.string != text { tv.string = text }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteTextView
        init(_ parent: NoteTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                } else {
                    parent.onSubmit()
                }
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            default:
                return false
            }
        }
    }
}
