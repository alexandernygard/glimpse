import Foundation
import AppKit
import Observation

struct DayGroup: Identifiable {
    let day: Date
    let items: [Capture]
    var id: Date { day }
}

@MainActor
@Observable
final class CaptureStore {
    static let shared = CaptureStore()

    private(set) var captures: [Capture] = []

    let rootURL: URL
    let imagesURL: URL
    let dbURL: URL

    @ObservationIgnored private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    @ObservationIgnored private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        rootURL = base.appendingPathComponent("Glimpse", isDirectory: true)
        imagesURL = rootURL.appendingPathComponent("Images", isDirectory: true)
        dbURL = rootURL.appendingPathComponent("captures.json")
        try? FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true)
        load()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: dbURL) else { return }
        if let decoded = try? decoder.decode([Capture].self, from: data) {
            captures = decoded.sorted { $0.createdAt > $1.createdAt }
        }
    }

    private func save() {
        do {
            let data = try encoder.encode(captures)
            try data.write(to: dbURL, options: .atomic)
        } catch {
            NSLog("Glimpse: failed to save captures: \(error)")
        }
    }

    // MARK: Images

    func storeImage(_ data: Data, id: UUID) -> String {
        let filename = "\(id.uuidString).png"
        let url = imagesURL.appendingPathComponent(filename)
        try? data.write(to: url, options: .atomic)
        return filename
    }

    func imageURL(filename: String) -> URL {
        imagesURL.appendingPathComponent(filename)
    }

    func imageData(filename: String) -> Data? {
        try? Data(contentsOf: imageURL(filename: filename))
    }

    // MARK: CRUD

    func capture(id: UUID) -> Capture? {
        captures.first { $0.id == id }
    }

    func add(_ capture: Capture) {
        captures.insert(capture, at: 0)
        captures.sort { $0.createdAt > $1.createdAt }
        save()
    }

    func update(_ capture: Capture) {
        guard let idx = captures.firstIndex(where: { $0.id == capture.id }) else { return }
        captures[idx] = capture
        save()
    }

    func delete(_ capture: Capture) {
        captures.removeAll { $0.id == capture.id }
        if let f = capture.imageFilename {
            try? FileManager.default.removeItem(at: imageURL(filename: f))
            ImageCache.shared.evict(filename: f)
        }
        save()
    }

    func setCategory(_ category: Category?, for id: UUID, source: CategorySource) {
        guard var c = capture(id: id) else { return }
        c.category = category
        c.categorySource = category == nil ? nil : source
        update(c)
    }

    func setTitle(_ title: String, for id: UUID) {
        guard var c = capture(id: id) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let new: String? = trimmed.isEmpty || trimmed == c.ai?.title ? nil : trimmed
        guard c.customTitle != new else { return }
        c.customTitle = new
        update(c)
    }

    func setText(_ text: String, for id: UUID) {
        guard var c = capture(id: id), c.text != text else { return }
        c.text = text
        update(c)
    }

    // MARK: Export

    /// Writes captures as a Markdown file plus a sibling folder of the referenced images.
    func exportMarkdown(_ items: [Capture], to url: URL) throws {
        let assetsName = url.deletingPathExtension().lastPathComponent + " images"
        let assetsURL = url.deletingLastPathComponent().appendingPathComponent(assetsName, isDirectory: true)
        let fm = FileManager.default
        if items.contains(where: { $0.imageFilename != nil }) {
            try fm.createDirectory(at: assetsURL, withIntermediateDirectories: true)
        }

        var md = "# Glimpse export\n\nExported \(Date().formatted(date: .long, time: .shortened)), \(items.count) captures.\n"
        for group in Self.groupByDay(items) {
            md += "\n## \(group.day.formatted(date: .complete, time: .omitted))\n"
            for c in group.items {
                md += "\n### \(c.displayTitle)\n\n"
                var meta = [c.createdAt.formatted(date: .omitted, time: .shortened)]
                if let cat = c.category { meta.append(cat.title) }
                if let app = c.sourceApp { meta.append(app) }
                if let tags = c.ai?.tags, !tags.isEmpty { meta.append(tags.map { "#\($0)" }.joined(separator: " ")) }
                md += "_\(meta.joined(separator: " · "))_\n"
                if let f = c.imageFilename {
                    let dest = assetsURL.appendingPathComponent(f)
                    if !fm.fileExists(atPath: dest.path) {
                        try? fm.copyItem(at: imageURL(filename: f), to: dest)
                    }
                    let rel = "\(assetsName)/\(f)".addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? f
                    md += "\n![](\(rel))\n"
                }
                let note = c.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !note.isEmpty { md += "\n\(note)\n" }
                if let ai = c.ai {
                    if !ai.summary.isEmpty { md += "\n> \(ai.summary)\n" }
                    if !ai.actionItems.isEmpty {
                        md += "\n" + ai.actionItems.map { "- [ ] \($0)" }.joined(separator: "\n") + "\n"
                    }
                    if !ai.extractedText.isEmpty {
                        md += "\n<details><summary>Text from screenshot</summary>\n\n```\n\(ai.extractedText)\n```\n</details>\n"
                    }
                }
            }
        }
        try md.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: Queries

    func captures(in category: Category) -> [Capture] {
        captures.filter { $0.category == category }
    }

    static func groupByDay(_ items: [Capture]) -> [DayGroup] {
        let cal = Calendar.current
        var buckets: [Date: [Capture]] = [:]
        for c in items {
            buckets[cal.startOfDay(for: c.createdAt), default: []].append(c)
        }
        return buckets.keys.sorted(by: >).map { day in
            DayGroup(day: day, items: buckets[day]!.sorted { $0.createdAt > $1.createdAt })
        }
    }
}

/// Small in-memory cache so list rows don't hit disk on every redraw.
@MainActor
final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, NSImage>()

    init() { cache.countLimit = 300 }

    func image(filename: String, from dir: URL) -> NSImage? {
        if let hit = cache.object(forKey: filename as NSString) { return hit }
        guard let img = NSImage(contentsOf: dir.appendingPathComponent(filename)) else { return nil }
        cache.setObject(img, forKey: filename as NSString)
        return img
    }

    func evict(filename: String) {
        cache.removeObject(forKey: filename as NSString)
    }
}
