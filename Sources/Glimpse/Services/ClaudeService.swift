import Foundation
import AppKit

enum ClaudeError: LocalizedError {
    case invalidKey
    case rateLimited
    case overloaded
    case offline
    case http(Int, String)
    case refusal(String)
    case truncated
    case noText
    case badJSON(String)

    var errorDescription: String? {
        switch self {
        case .invalidKey: return "Your Anthropic API key was rejected. Check it in Settings."
        case .rateLimited: return "Rate limited by the Anthropic API. Try again in a minute."
        case .overloaded: return "The Anthropic API is busy right now. Try again shortly."
        case .offline: return "Couldn't reach the Anthropic API. Check your internet connection."
        case .http(let code, let msg): return "API error \(code): \(msg)"
        case .refusal(let why): return "Claude declined this request: \(why)"
        case .truncated: return "Claude's response was cut off before it finished."
        case .noText: return "Claude returned no text."
        case .badJSON(let raw): return "Could not parse Claude's response: \(raw.prefix(200))"
        }
    }
}

/// Raw Messages API client. Anthropic has no official Swift SDK, so this talks HTTP directly.
enum ClaudeService {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let fallbackBeta = "server-side-fallback-2026-07-01"

    static func enrich(capture: Capture, imageData: Data?, apiKey: String, model: String) async throws -> AIEnrichment {
        var content: [[String: Any]] = []
        if let imageData, let jpeg = ImageUtil.jpegForUpload(imageData) {
            content.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": jpeg.base64EncodedString(),
                ],
            ])
        }
        content.append(["type": "text", "text": userPrompt(for: capture)])

        var body: [String: Any] = [
            "model": model,
            // Thinking is adaptive (on by default) on all offered models and counts toward this cap.
            "max_tokens": 16000,
            "system": systemPrompt,
            "messages": [["role": "user", "content": content]],
            "output_config": outputConfig,
        ]
        var headers = [
            "content-type": "application/json",
            "x-api-key": apiKey,
            "anthropic-version": "2023-06-01",
        ]

        // Sonnet 5.5 and Opus 5.5 can decline via safety classifiers; server-side fallback reruns
        // eligible declines on another model. Haiku 5.5 has no server-side fallback.
        let useFallback = !model.contains("haiku")
        if useFallback {
            body["fallbacks"] = "default"
            headers["anthropic-beta"] = fallbackBeta
        }

        do {
            return try await send(body: body, headers: headers)
        } catch ClaudeError.http(400, let msg) where useFallback && msg.localizedCaseInsensitiveContains("fallback") {
            body.removeValue(forKey: "fallbacks")
            headers.removeValue(forKey: "anthropic-beta")
            return try await send(body: body, headers: headers)
        }
    }

    private static func send(body: [String: Any], headers: [String: String]) async throws -> AIEnrichment {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
                                            .cannotConnectToHost, .timedOut, .dnsLookupFailed].contains(error.code) {
            throw ClaudeError.offline
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]

        guard (200..<300).contains(status) else {
            switch status {
            case 401, 403: throw ClaudeError.invalidKey
            case 429: throw ClaudeError.rateLimited
            case 500, 503, 529: throw ClaudeError.overloaded
            default:
                let msg = ((json["error"] as? [String: Any])?["message"] as? String)
                    ?? String(data: data, encoding: .utf8)
                    ?? "Unknown error"
                throw ClaudeError.http(status, msg)
            }
        }

        switch json["stop_reason"] as? String {
        case "refusal":
            let why = ((json["stop_details"] as? [String: Any])?["explanation"] as? String) ?? "no explanation given"
            throw ClaudeError.refusal(why)
        case "max_tokens":
            throw ClaudeError.truncated
        default:
            break
        }

        // Responses may start with thinking blocks; the structured output is in the text block.
        guard let blocks = json["content"] as? [[String: Any]],
              let text = blocks.first(where: { $0["type"] as? String == "text" })?["text"] as? String
        else { throw ClaudeError.noText }

        do {
            return try JSONDecoder().decode(AIEnrichment.self, from: Data(text.utf8))
        } catch {
            throw ClaudeError.badJSON(text)
        }
    }

    // MARK: Prompt

    private static let systemPrompt: String = {
        let cats = Category.allCases.map { "- \($0.rawValue): \($0.guidance)" }.joined(separator: "\n")
        return """
        You organize a personal capture inbox for one person. Throughout the day they grab two kinds of things on their Mac: \
        a screenshot of a region of the screen, or a short typed note. Your job is to make each capture instantly \
        recognizable and findable later.

        For each capture return:
        - title: at most 8 words, specific, no trailing period. Name the actual thing (a person, product, error, article), not the medium.
        - summary: one or two sentences on what this is and why the person likely captured it. Do not start with "This is a screenshot".
        - suggestedCategory: the single best bucket from the list below.
        - tags: up to 5 short lowercase tags that would help search later (people, projects, tools, topics). No duplicates of the category name.
        - extractedText: the meaningful text visible in the screenshot, transcribed faithfully and trimmed to what matters (drop menus, chrome, boilerplate). Empty string for notes or images with no useful text.
        - actionItems: concrete next actions implied by the capture, phrased as imperatives. Empty array if none.

        Categories:
        \(cats)

        If the person already chose a category, still return your own honest suggestion. Be concise and never invent details that are not in the capture.
        """
    }()

    private static func userPrompt(for capture: Capture) -> String {
        var lines: [String] = []
        lines.append("Captured: \(capture.createdAt.formatted(date: .complete, time: .shortened))")
        lines.append("Kind: \(capture.kind == .screenshot ? "screenshot (image attached)" : "typed note")")
        if let app = capture.sourceApp { lines.append("Frontmost app at capture time: \(app)") }
        let note = capture.text.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append(note.isEmpty ? "User's note: (none)" : "User's note:\n\"\"\"\n\(note)\n\"\"\"")
        if let cat = capture.category, capture.categorySource == .manual {
            lines.append("User's manual category: \(cat.rawValue)")
        } else {
            lines.append("User's manual category: none, please choose")
        }
        return lines.joined(separator: "\n")
    }

    private static var outputConfig: [String: Any] {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "title": ["type": "string"],
                "summary": ["type": "string"],
                "suggestedCategory": ["type": "string", "enum": Category.allCases.map(\.rawValue)],
                "tags": ["type": "array", "items": ["type": "string"]],
                "extractedText": ["type": "string"],
                "actionItems": ["type": "array", "items": ["type": "string"]],
            ],
            "required": ["title", "summary", "suggestedCategory", "tags", "extractedText", "actionItems"],
            "additionalProperties": false,
        ]
        // Low effort keeps captures snappy; all offered models support it and think less at this level.
        return ["format": ["type": "json_schema", "schema": schema], "effort": "low"]
    }
}

enum ImageUtil {
    /// Downscales to Anthropic's recommended max edge and re-encodes as JPEG to keep uploads small.
    static func jpegForUpload(_ data: Data, maxDimension: CGFloat = 1568) -> Data? {
        guard let image = NSImage(data: data),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let scale = min(1, maxDimension / max(w, h))
        let newW = max(1, Int(w * scale)), newH = max(1, Int(h * scale))
        guard let ctx = CGContext(data: nil, width: newW, height: newH, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        // Flatten transparency onto white so JPEG doesn't go black.
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: newW, height: newH))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        guard let out = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: out).representation(using: .jpeg, properties: [.compressionFactor: 0.82])
    }
}
