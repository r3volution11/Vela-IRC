// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaFoundation
import VelaStore

/// Google's Gemini API: `models/{model}:streamGenerateContent?alt=sse`.
/// The key goes in the `x-goog-api-key` header, never in the URL, so it
/// can't end up in a log of addresses. Models that think get a low
/// thinking level, and room in `maxOutputTokens` for it.
///
/// A blocked prompt (`promptFeedback.blockReason`) or a reply stopped by a
/// safety filter (`finishReason` `SAFETY`, `PROHIBITED_CONTENT` and the
/// like) is a decline. Parts marked `thought` are skipped.
nonisolated struct GeminiAPI: AIProviderAPI {
    let identity: AIProviderIdentity
    let client: AIHTTPClient
    let key: String
    var baseURL = AIProviderKind.gemini.defaultBaseURL!

    private var headers: [String: String] {
        ["x-goog-api-key": key]
    }

    /// `finishReason`s that mean the reply was stopped rather than done.
    static let declinedReasons: Set<String> = [
        "SAFETY", "RECITATION", "BLOCKLIST", "PROHIBITED_CONTENT", "SPII", "LANGUAGE", "IMAGE_SAFETY",
    ]

    func body(for call: AIModelCall) -> JSONValue {
        var generation: [String: JSONValue] = [
            "maxOutputTokens": .number(Double(call.maximumResponseTokens + AIModelCall.thinkingAllowance)),
        ]
        if call.model.thinkingControl == true {
            generation["thinkingConfig"] = .object(["thinkingLevel": "LOW"])
        }
        return .object([
            "systemInstruction": .object(["parts": .array([.object(["text": .string(call.instructions)])])]),
            "contents": .array([.object(["role": "user", "parts": .array([.object(["text": .string(call.prompt)])])])]),
            "generationConfig": .object(generation),
        ])
    }

    /// `…/models/{model}:streamGenerateContent?alt=sse`.
    func streamURL(model: String) -> URL? {
        guard let id = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))) else { return nil }
        return URL(string: baseURL.absoluteString + "/models/\(id):streamGenerateContent?alt=sse")
    }

    func stream(_ call: AIModelCall) -> AsyncThrowingStream<String, Error> {
        guard let url = streamURL(model: call.model.id) else {
            return AsyncThrowingStream { $0.finish(throwing: identity.failure(.modelNotFound, model: call.model.id)) }
        }
        let request = AIHTTPClient.request(url, method: "POST", headers: headers, body: body(for: call))
        let events = client.events(request, api: self, model: call.model.id)
        let identity = identity
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in events {
                        if event["promptFeedback"]?["blockReason"]?.stringValue != nil {
                            throw CatchUpModelError.declined
                        }
                        if let error = event["error"] {
                            throw identity.failure(.other(AIProviderFailure.trimmed(error["message"]?.stringValue ?? "The answer stopped.")))
                        }
                        guard let candidate = event["candidates"]?.arrayValue?.first else { continue }
                        for part in candidate["content"]?["parts"]?.arrayValue ?? [] where part["thought"]?.boolValue != true {
                            if let text = part["text"]?.stringValue, !text.isEmpty { continuation.yield(text) }
                        }
                        if let reason = candidate["finishReason"]?.stringValue, Self.declinedReasons.contains(reason) {
                            throw CatchUpModelError.declined
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Models

    /// `GET v1beta/models`, every page, keeping Gemini models that
    /// generate text (`generateContent`), with their input limits.
    func listModels() async throws -> [AIModelInfo] {
        var models: [AIModelInfo] = []
        var token: String?
        for _ in 0..<10 {
            var components = URLComponents(url: baseURL.appending(path: "models"), resolvingAgainstBaseURL: false)!
            var query = [URLQueryItem(name: "pageSize", value: "1000")]
            if let token { query.append(URLQueryItem(name: "pageToken", value: token)) }
            components.queryItems = query
            let page = try await client.json(AIHTTPClient.request(components.url!, headers: headers), api: self)
            for item in page["models"]?.arrayValue ?? [] {
                guard let name = item["name"]?.stringValue else { continue }
                let id = name.hasPrefix("models/") ? String(name.dropFirst("models/".count)) : name
                let methods = item["supportedGenerationMethods"]?.arrayValue?.compactMap(\.stringValue) ?? []
                guard methods.contains("generateContent") || methods.contains("streamGenerateContent"), Self.isTextModel(id) else { continue }
                models.append(AIModelInfo(
                    id: id,
                    name: item["displayName"]?.stringValue,
                    contextTokens: item["inputTokenLimit"]?.intValue,
                    thinkingControl: Self.takesThinkingLevel(id: id, thinks: item["thinking"]?.boolValue)
                ))
            }
            guard let next = page["nextPageToken"]?.stringValue, !next.isEmpty else { break }
            token = next
        }
        return Self.ordered(models, recommended: AIProviderKind.gemini.recommendedModels)
    }

    static func isTextModel(_ id: String) -> Bool {
        let lower = id.lowercased()
        return lower.hasPrefix("gemini")
            && !["embedding", "image", "tts", "audio", "live", "computer-use", "robotics", "veo"].contains { lower.contains($0) }
    }

    /// Thinking models from Gemini 3 on take a thinking level; Gemini 2.x
    /// took a budget instead, and rejects a level.
    static func takesThinkingLevel(id: String, thinks: Bool?) -> Bool? {
        guard let thinks else { return nil }
        guard thinks else { return false }
        return !id.lowercased().hasPrefix("gemini-2") && !id.lowercased().hasPrefix("gemini-1")
    }

    // MARK: Errors

    func failure(for error: AIHTTPError, model: String?) -> CatchUpModelError {
        let message = (error.message ?? "").lowercased()
        if error.detailReasons.contains("API_KEY_INVALID") || message.contains("api key not valid") || message.contains("api key expired") {
            return identity.failure(.badKey)
        }
        switch error.status {
        case 403 where message.contains("key"):
            return identity.failure(.badKey)
        case 429 where message.contains("per day") || message.contains("billing"):
            return identity.failure(.quota)
        case 404:
            return identity.failure(.modelNotFound, model: model)
        default:
            return standardFailure(for: error, model: model)
        }
    }
}
