import Foundation

/// Runs Claude enrichment for captures in the background and writes results back into the store.
@MainActor
final class Enricher {
    static let shared = Enricher()
    private var inFlight: Set<UUID> = []

    func retryPending() {
        for c in CaptureStore.shared.captures where c.aiStatus == .pending {
            enrich(id: c.id)
        }
    }

    func enrich(id: UUID) {
        guard !inFlight.contains(id) else { return }
        let store = CaptureStore.shared
        let settings = AppSettings.shared
        guard var capture = store.capture(id: id) else { return }

        guard settings.enrichmentEnabled, let key = settings.apiKey, !key.isEmpty else {
            capture.aiStatus = .skipped
            store.update(capture)
            return
        }

        inFlight.insert(id)
        capture.aiStatus = .pending
        store.update(capture)

        let imageData = capture.imageFilename.flatMap { store.imageData(filename: $0) }
        let model = settings.model
        let snapshot = capture

        Task {
            defer { inFlight.remove(id) }
            do {
                let result = try await ClaudeService.enrich(capture: snapshot, imageData: imageData, apiKey: key, model: model)
                guard var c = store.capture(id: id) else { return }
                c.ai = result
                c.aiStatus = .done
                if c.category == nil {
                    c.category = result.suggestedCategory
                    c.categorySource = .ai
                }
                store.update(c)
            } catch {
                guard var c = store.capture(id: id) else { return }
                c.aiStatus = .failed(error.localizedDescription)
                store.update(c)
            }
        }
    }
}
