import SwiftUI
import AppKit

extension Category {
    var color: Color {
        switch self {
        case .todo: return .blue
        case .followUp: return .orange
        case .important: return .red
        case .thought: return .purple
        case .idea: return .yellow
        case .reference: return .teal
        }
    }
}

struct CategoryChip: View {
    let category: Category
    let selected: Bool
    var showHotkey: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: category.symbol)
                Text(category.title)
                if showHotkey {
                    Text("⌘\(category.hotkeyNumber)")
                        .font(.caption2.monospaced())
                        .opacity(0.7)
                }
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(selected ? category.color.opacity(0.9) : Color.primary.opacity(0.06))
            )
            .foregroundStyle(selected ? .white : .primary)
            .overlay(Capsule().strokeBorder(selected ? .clear : category.color.opacity(0.35)))
        }
        .buttonStyle(.plain)
        .help(category.guidance)
    }
}

struct CategoryBadge: View {
    let category: Category
    var dimmed: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: category.symbol)
            Text(category.title)
        }
        .font(.caption2.weight(.medium))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(category.color.opacity(dimmed ? 0.15 : 0.25)))
        .foregroundStyle(category.color)
    }
}

struct AIStatusIndicator: View {
    let status: AIStatus

    var body: some View {
        switch status {
        case .pending:
            ProgressView().controlSize(.mini).help("Claude is organizing this capture")
        case .done:
            Image(systemName: "sparkles").foregroundStyle(.secondary).help("Organized by Claude")
        case .skipped:
            Image(systemName: "sparkles.slash").foregroundStyle(.tertiary).help("Not sent to Claude (no API key or disabled)")
        case .failed(let msg):
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange).help(msg)
        }
    }
}

struct Thumbnail: View {
    @Environment(CaptureStore.self) private var store
    let capture: Capture

    var body: some View {
        Group {
            if let f = capture.imageFilename, let img = ImageCache.shared.image(filename: f, from: store.imagesURL) {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(.quaternary.opacity(0.5))
                    Image(systemName: "text.alignleft").foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 64, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
    }
}

enum DayFormat {
    static func label(for day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    static func detail(for day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) || cal.isDateInYesterday(day) {
            return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        }
        if cal.component(.year, from: day) != cal.component(.year, from: Date()) {
            return day.formatted(.dateTime.year())
        }
        return ""
    }
}

extension Capture {
    /// Plain-text rendering for the pasteboard: title, note, summary, action items, extracted text.
    var plainText: String {
        var parts = [displayTitle]
        let note = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { parts.append(note) }
        if let ai {
            if !ai.summary.isEmpty { parts.append(ai.summary) }
            if !ai.actionItems.isEmpty { parts.append(ai.actionItems.map { "- \($0)" }.joined(separator: "\n")) }
            if !ai.extractedText.isEmpty { parts.append(ai.extractedText) }
        }
        return parts.joined(separator: "\n\n")
    }

    @MainActor
    func copyAsText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(plainText, forType: .string)
    }
}

private struct ConfirmDeleteCapture: ViewModifier {
    @Environment(CaptureStore.self) private var store
    @Binding var capture: Capture?
    var onDelete: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Delete \u{201C}\(capture?.displayTitle ?? "")\u{201D}?",
            isPresented: Binding(get: { capture != nil }, set: { if !$0 { capture = nil } }),
            presenting: capture
        ) { c in
            Button("Delete", role: .destructive) {
                store.delete(c)
                onDelete()
            }
        } message: { c in
            Text(c.imageFilename == nil ? "This can't be undone." : "The screenshot file is deleted too. This can't be undone.")
        }
    }
}

extension View {
    func confirmDeleteCapture(_ capture: Binding<Capture?>, onDelete: @escaping () -> Void = {}) -> some View {
        modifier(ConfirmDeleteCapture(capture: capture, onDelete: onDelete))
    }
}
