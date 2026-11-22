// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaFoundation
import VelaStore

/// A server that speaks OpenAI's Chat Completions API: Ollama, LM Studio,
/// llama.cpp's server, vLLM and the like, on this Mac, your network or
/// elsewhere. `POST {base}/chat/completions`, streamed; `GET {base}/models`
/// for the list. A key is optional (sent as a bearer token when there is
/// one).
///
/// Local models often write their thinking into the reply
/// (`<think>…</think>`) or a separate `reasoning_content`: both are left
/// out. A server that's not running is "couldn't connect", not offline.
nonisolated struct OpenAICompatibleAPI: AIProviderAPI {
    let identity: AIProviderIdentity
    let client: AIHTTPClient
    let key: String?
    let baseURL: URL

    /// Thinking room for local reasoning models: less than hosted ones get,
    /// since a slow Mac writes every token.
    static let thinkingAllowance = 2_048

    private var headers: [String: String] {
        guard let key, !key.isEmpty else { return [:] }
        return ["Authorization": "Bearer \(key)"]
    }

    func body(for call: AIModelCall) -> JSONValue {
        .object([
            "model": .string(call.model.id),
            "messages": .array([
                .object(["role": "system", "content": .string(call.instructions)]),
                .object(["role": "user", "content": .string(call.prompt)]),
            ]),
            "stream": true,
            "max_tokens": .number(Double(call.maximumResponseTokens + Self.thinkingAllowance)),
            // Low but not greedy, as with Apple's model.
            "temperature": 0.3,
        ])
    }

    func stream(_ call: AIModelCall) -> AsyncThrowingStream<String, Error> {
        let request = AIHTTPClient.request(baseURL.appending(path: "chat/completions"), method: "POST", headers: headers, body: body(for: call))
        let events = client.events(request, api: self, model: call.model.id)
        let identity = identity
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var filter = ThinkingFilter()
                    for try await event in events {
                        if let error = event["error"] {
                            let message = error.stringValue ?? error["message"]?.stringValue ?? "The answer stopped."
                            let http = AIHTTPError(status: 400, body: .object(["error": .object(["message": .string(message)])]), text: message)
                            if http.saysContextExceeded { throw CatchUpModelError.contextExceeded }
                            throw identity.failure(.other(AIProviderFailure.trimmed(message)))
                        }
                        guard let choice = event["choices"]?.arrayValue?.first else { continue }
                        if let content = choice["delta"]?["content"]?.stringValue {
                            let text = filter.text(from: content)
                            if !text.isEmpty { continuation.yield(text) }
                        }
                        if choice["finish_reason"]?.stringValue == "content_filter" {
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

    /// `GET {base}/models`, leaving out embedding models.
    func listModels() async throws -> [AIModelInfo] {
        let page = try await client.json(AIHTTPClient.request(baseURL.appending(path: "models"), headers: headers), api: self)
        return (page["data"]?.arrayValue ?? []).compactMap { item in
            guard let id = item["id"]?.stringValue, !id.lowercased().contains("embed") else { return nil }
            return AIModelInfo(id: id)
        }
    }

    func failure(for error: AIHTTPError, model: String?) -> CatchUpModelError {
        let message = (error.message ?? error.text).lowercased()
        // Ollama: `model "x" not found, try pulling it first`.
        if message.contains("not found"), message.contains("model") {
            return identity.failure(.modelNotFound, model: model)
        }
        return standardFailure(for: error, model: model)
    }
}
