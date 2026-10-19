import SwiftUI
import AppKit

struct CaptureDetailView: View {
    @Environment(CaptureStore.self) private var store
    let capture: Capture
    @State private var noteDraft: String = ""
    @State private var titleDraft: String = ""
    @State private var pendingDelete: Capture?
    @FocusState private var titleFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let f = capture.imageFilename, let img = ImageCache.shared.image(filename: f, from: store.imagesURL) {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 440, alignment: .leading)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
                        .onTapGesture(count: 2) {
                            NSWorkspace.shared.open(store.imageURL(filename: f))
                        }
                        .help("Double-click to open in Preview")
                }

                VStack(alignment: .leading, spacing: 6) {
                    TextField("Title", text: $titleDraft, axis: .vertical)
                        .font(.title2.weight(.semibold))
                        .textFieldStyle(.plain)
                        .focused($titleFocused)
                        .onSubmit { commitTitle() }
                        .onChange(of: titleFocused) { _, focused in if !focused { commitTitle() } }
                        .help("Click to rename")
                    HStack(spacing: 6) {
                        Text(capture.createdAt.formatted(date: .complete, time: .shortened))
                        if let app = capture.sourceApp {
                            Text("·")
                            Text(app)
                        }
                        Text("·")
                        Text(capture.kind == .screenshot ? "Screenshot" : "Note")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }

                section("Category") {
                    HStack(spacing: 6) {
                        ForEach(Category.allCases) { cat in
                            CategoryChip(category: cat, selected: capture.category == cat) {
                                store.setCategory(capture.category == cat ? nil : cat, for: capture.id, source: .manual)
                            }
                        }
                    }
                    if capture.categorySource == .ai {
                        Text("Chosen by Claude. Click a chip to override.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else if let suggestion = capture.ai?.suggestedCategory,
                              capture.category != nil, capture.category != suggestion {
                        Text("Claude would have filed this under \(suggestion.title).")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                section("Note") {
                    TextEditor(text: $noteDraft)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 64, maxHeight: 180)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.35)))
                        .onChange(of: noteDraft) { _, new in
                            store.setText(new, for: capture.id)
                        }
                }

                AISection(capture: capture)

                HStack {
                    Button(role: .destructive) {
                        pendingDelete = capture
                    } label: {
                        Label("Delete…", systemImage: "trash")
                    }
                    Button {
                        capture.copyAsText()
                    } label: {
                        Label("Copy Text", systemImage: "doc.plaintext")
                    }
                    if let f = capture.imageFilename {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([store.imageURL(filename: f)])
                        } label: {
                            Label("Reveal in Finder", systemImage: "folder")
                        }
                        Button {
                            if let img = ImageCache.shared.image(filename: f, from: store.imagesURL) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.writeObjects([img])
                            }
                        } label: {
                            Label("Copy Image", systemImage: "doc.on.doc")
                        }
                    }
                }
                .padding(.top, 4)
            }
            .padding(20)
        }
        .onAppear {
            noteDraft = capture.text
            titleDraft = capture.displayTitle
        }
        .onChange(of: capture.displayTitle) { _, new in
            if !titleFocused { titleDraft = new }
        }
        .onDisappear { commitTitle() }
        .confirmDeleteCapture($pendingDelete)
    }

    private func commitTitle() {
        guard titleDraft != capture.displayTitle else { return }
        store.setTitle(titleDraft, for: capture.id)
        titleDraft = store.capture(id: capture.id)?.displayTitle ?? titleDraft
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }
}

struct AISection: View {
    @Environment(AppSettings.self) private var settings
    let capture: Capture

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Claude", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                statusLine
            }

            switch capture.aiStatus {
            case .pending:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Organizing…").foregroundStyle(.secondary)
                }
            case .skipped:
                Text(settings.apiKey == nil
                     ? "Not sent to Claude because no API key is set."
                     : "Not sent to Claude because organizing is turned off in Settings.")
                    .foregroundStyle(.secondary)
            case .failed(let msg):
                Text(msg)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            case .done:
                if let ai = capture.ai {
                    Text(ai.summary).textSelection(.enabled)

                    if !ai.tags.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(ai.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(.quaternary.opacity(0.6)))
                            }
                        }
                    }

                    if !ai.actionItems.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(ai.actionItems, id: \.self) { item in
                                Label(item, systemImage: "circle")
                                    .font(.callout)
                            }
                        }
                        .padding(.top, 2)
                    }

                    if !ai.extractedText.isEmpty {
                        DisclosureGroup("Text from screenshot") {
                            Text(ai.extractedText)
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.35)))
                        }
                        .font(.callout)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.2)))
    }

    @ViewBuilder
    private var statusLine: some View {
        switch capture.aiStatus {
        case .pending:
            EmptyView()
        default:
            Button {
                Enricher.shared.enrich(id: capture.id)
            } label: {
                Label(capture.aiStatus == .done ? "Re-run" : "Retry", systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
            .disabled(settings.apiKey == nil)
        }
    }
}
