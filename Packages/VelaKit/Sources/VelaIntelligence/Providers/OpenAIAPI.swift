// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaFoundation
import VelaStore

/// OpenAI's Responses API (`POST /v1/responses`), streamed: the API OpenAI
/// recommends for new work. The key is a bearer token. Requests aren't
/// stored (`store: false`). Reasoning models get a low effort and room in
/// `max_output_tokens` for their reasoning on top of the reply.
///
/// Read from the stream: `response.output_text.delta` (the text),
/// `response.refusal.*` (a decline), `response.incomplete` (a content
/// filter is a decline; the output limit just ends it), and
/// `response.failed` / `error`.
nonisolated struct OpenAIAPI: AIProviderAPI {
    let identity: AIProviderIdentity
    let client: AIHTTPClient
    let key: String
    var baseURL = AIProviderKind.openAI.defaultBaseURL!

    private var headers: [String: String] {
        ["Authorization": "Bearer \(key)"]
    }

    func body(for call: AIModelCall) -> JSONValue {
        var body: [String: JSONValue] = [
            "model": .string(call.model.id),
            "instructions": .string(call.instructions),
            "input": .string(call.prompt),
            "max_output_tokens": .number(Double(call.maximumResponseTokens + AIModelCall.thinkingAllowance)),
            "stream": true,
            "store": false,
        ]
        if call.model.thinkingControl == true {
            body["reasoning"] = .object(["effort": "low"])
        }
        return .object(body)
    }

    func stream(_ call: AIModelCall) -> AsyncThrowingStream<String, Error> {
        let request = AIHTTPClient.request(baseURL.appending(path: "responses"), method: "POST", headers: headers, body: body(for: call))
        let events = client.events(request, api: self, model: call.model.id)
        let identity = identity
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in events {
                        switch event["type"]?.stringValue {
                        case "response.output_text.delta":
                            if let text = event["delta"]?.stringValue { continuation.yield(text) }
                        case "response.refusal.delta", "response.refusal.done":
                            throw CatchUpModelError.declined
                        case "response.incomplete":
                            if event["response"]?["incomplete_details"]?["reason"]?.stringValue == "content_filter" {
                                throw CatchUpModelError.declined
                            }
                            continuation.finish()
                            return
                        case "response.failed":
                            throw Self.streamFailure(event["response"]?["error"], identity: identity)
                        case "error":
                            throw Self.streamFailure(event, identity: identity)
                        case "response.completed":
                            continuation.finish()
                            return
                        default:
                            continue
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

    /// `response.failed`'s error, or an `error` event: `code` and `message`.
    static func streamFailure(_ error: JSONValue?, identity: AIProviderIdentity) -> CatchUpModelError {
        let message = AIProviderFailure.trimmed(error?["message"]?.stringValue ?? "The answer stopped.")
        switch error?["code"]?.stringValue {
        case "rate_limit_exceeded": return identity.failure(.rateLimited)
        case "insufficient_quota": return identity.failure(.quota)
        case "server_error": return identity.failure(.overloaded)
        case "invalid_prompt": return .declined
        case "context_length_exceeded": return .contextExceeded
        default: return identity.failure(.other(message))
        }
    }

    // MARK: Models

    /// `GET /v1/models`, keeping the models that write text (GPT and the o
    /// series, not embeddings, speech, images or the like), newest first.
    func listModels() async throws -> [AIModelInfo] {
        let page = try await client.json(AIHTTPClient.request(baseURL.appending(path: "models"), headers: headers), api: self)
        let items = (page["data"]?.arrayValue ?? []).compactMap { item -> (id: String, created: Double)? in
            guard let id = item["id"]?.stringValue, Self.isTextModel(id) else { return nil }
            return (id, item["created"]?.doubleValue ?? 0)
        }
        let models = items
            .sorted { $0.created != $1.created ? $0.created > $1.created : $0.id < $1.id }
            .map { AIModelInfo(id: $0.id, contextTokens: Self.contextTokens($0.id), thinkingControl: Self.takesReasoningEffort($0.id)) }
        return Self.ordered(models, recommended: AIProviderKind.openAI.recommendedModels)
    }

    static let excludedWords = [
        "embedding", "tts", "whisper", "dall-e", "image", "audio", "realtime", "transcribe",
        "moderation", "search", "instruct", "davinci", "babbage", "computer-use", "codex", "sora",
    ]

    static func isTextModel(_ id: String) -> Bool {
        let lower = id.lowercased()
        let family = lower.hasPrefix("gpt-") || lower.hasPrefix("chatgpt-")
            || ["o1", "o3", "o4"].contains { lower == $0 || lower.hasPrefix($0 + "-") }
        return family && !excludedWords.contains { lower.contains($0) }
    }

    /// Reasoning models take `reasoning.effort`; older ones reject it.
    static func takesReasoningEffort(_ id: String) -> Bool? {
        let lower = id.lowercased()
        if ["gpt-5", "gpt-6", "gpt-7", "o1", "o3", "o4"].contains(where: { lower.hasPrefix($0) }) { return true }
        if lower.hasPrefix("gpt-4") || lower.hasPrefix("gpt-3") || lower.hasPrefix("chatgpt-") { return false }
        return nil
    }

    /// Input limits by family, as OpenAI publishes them; the list doesn't say.
    static func contextTokens(_ id: String) -> Int? {
        let lower = id.lowercased()
        if lower.hasPrefix("gpt-6") || lower.hasPrefix("gpt-4.1") { return 1_000_000 }
        if lower.hasPrefix("gpt-5") { return 272_000 }
        if lower.hasPrefix("o3") || lower.hasPrefix("o4") || lower.hasPrefix("o1") { return 200_000 }
        if lower.hasPrefix("gpt-4o") { return 128_000 }
        return nil
    }

    // MARK: Errors

    func failure(for error: AIHTTPError, model: String?) -> CatchUpModelError {
        if error.code == "insufficient_quota" || error.type == "insufficient_quota" {
            return identity.failure(.quota)
        }
        if error.code == "model_not_found" { return identity.failure(.modelNotFound, model: model) }
        if error.code == "invalid_api_key" { return identity.failure(.badKey) }
        return standardFailure(for: error, model: model)
    }
}
