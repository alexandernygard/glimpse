import Foundation

/// Uses the system `screencapture` tool so the selection UI is the exact one users already know.
enum ScreenshotService {
    static func captureInteractive() async -> Data? {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("glimpse-\(UUID().uuidString).png")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -i interactive, -s selection only, -x no sound, -t png
        process.arguments = ["-i", "-s", "-x", "-t", "png", tmp.path]

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                NSLog("Glimpse: could not launch screencapture: \(error)")
                continuation.resume()
            }
        }

        defer { try? FileManager.default.removeItem(at: tmp) }
        guard let data = try? Data(contentsOf: tmp), !data.isEmpty else { return nil }
        return data
    }
}
