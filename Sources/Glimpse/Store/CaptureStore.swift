import Foundation
import AppKit

struct DayGroup: Identifiable {
    let day: Date
    let items: [Capture]
    var id: Date { day }
}

@MainActor
final class CaptureStore: ObservableObject {
    static let shared = CaptureStore()

    @Published private(set) var captures: [Capture] = []

    let rootURL: URL
    let imagesURL: URL
    let dbURL: URL

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private let decoder: JSONDecoder = {
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

    func setText(_ text: String, for id: UUID) {
        guard var c = capture(id: id), c.text != text else { return }
        c.text = text
        update(c)
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
final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, NSImage>()
    private let queue = DispatchQueue(label: "glimpse.imagecache")

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
