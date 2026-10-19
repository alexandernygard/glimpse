import Foundation

enum CaptureKind: String, Codable {
    case screenshot
    case note
}

/// The fixed set of buckets a capture can land in. Order matters: it defines the ⌘1…⌘6 hotkeys.
enum Category: String, Codable, CaseIterable, Identifiable {
    case todo
    case followUp
    case important
    case thought
    case idea
    case reference

    var id: String { rawValue }

    var title: String {
        switch self {
        case .todo: return "To-do"
        case .followUp: return "Follow Up"
        case .important: return "Important"
        case .thought: return "Thought"
        case .idea: return "Idea"
        case .reference: return "Reference"
        }
    }

    var symbol: String {
        switch self {
        case .todo: return "checkmark.circle"
        case .followUp: return "arrow.uturn.forward.circle"
        case .important: return "exclamationmark.circle"
        case .thought: return "bubble.left"
        case .idea: return "lightbulb"
        case .reference: return "bookmark"
        }
    }

    /// 1-based number used for the ⌘N hotkey.
    var hotkeyNumber: Int { (Category.allCases.firstIndex(of: self) ?? 0) + 1 }

    /// Definition handed to Claude so its suggestions match how the user thinks about the buckets.
    var guidance: String {
        switch self {
        case .todo: return "a concrete task the user themselves must do"
        case .followUp: return "waiting on someone or something, or needs checking back on later"
        case .important: return "high-stakes information to keep front of mind: deadlines, decisions, key facts, warnings"
        case .thought: return "a reflection, observation, or musing with no action attached"
        case .idea: return "a new idea, project, feature, or thing to try"
        case .reference: return "material to look up or reuse later: articles, docs, code, products, quotes"
        }
    }

    static func from(hotkeyNumber n: Int) -> Category? {
        guard n >= 1, n <= allCases.count else { return nil }
        return allCases[n - 1]
    }
}

enum CategorySource: String, Codable {
    case manual
    case ai
}

enum AIStatus: Codable, Equatable {
    case pending
    case done
    case skipped
    case failed(String)
}

struct AIEnrichment: Codable, Equatable {
    var title: String
    var summary: String
    var suggestedCategory: Category
    var tags: [String]
    var extractedText: String
    var actionItems: [String]
}

struct Capture: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var kind: CaptureKind
    var text: String
    var imageFilename: String?
    var category: Category?
    var categorySource: CategorySource?
    var sourceApp: String?
    var ai: AIEnrichment?
    var aiStatus: AIStatus = .pending

    var displayTitle: String {
        if let t = ai?.title, !t.isEmpty { return t }
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        if !firstLine.isEmpty { return firstLine }
        return kind == .screenshot ? "Screenshot" : "Note"
    }

    var subtitle: String? {
        if let s = ai?.summary, !s.isEmpty { return s }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if ai?.title == nil {
            // Title already shows the first line; show the rest if any.
            let lines = trimmed.split(whereSeparator: \.isNewline).dropFirst()
            let rest = lines.joined(separator: " ")
            return rest.isEmpty ? nil : rest
        }
        return trimmed
    }

    func matches(search: String) -> Bool {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return true }
        var hay = [text, displayTitle, sourceApp ?? ""]
        if let ai {
            hay += [ai.summary, ai.extractedText]
            hay += ai.tags
            hay += ai.actionItems
        }
        return hay.contains { $0.lowercased().contains(q) }
    }
}
