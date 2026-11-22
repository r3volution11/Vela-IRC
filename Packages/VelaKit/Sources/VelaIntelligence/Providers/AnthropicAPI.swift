// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaFoundation
import VelaStore

/// Anthropic's Messages API (`POST /v1/messages`), streamed.
///
/// - The key goes in `x-api-key`, with `anthropic-version`.
/// - The instructions are the `system` prompt and the transcript is the
///   one user message; nothing is prefilled for the assistant.
/// - No sampling parameters: this API version rejects them.
/// - Current models think before they answer, and thinking can't be
///   turned off on all of them, so Vela asks for low effort
///   (`output_config.effort`) where the model takes it, and gives
///   `max_tokens` room for the thinking on top of the reply.
/// - Only `text_delta`s are read; thinking blocks are skipped.
/// - `stop_reason: "refusal"` is a decline, which the engine handles like
///   Apple's guardrails (the part is left out).
nonisolated struct AnthropicAPI: AIProviderAPI {
    let identity: AIProviderIdentity
    let client: AIHTTPClient
    let key: String
    var baseURL = AIProviderKind.anthropic.defaultBaseURL!

    static let version = "2026-10-21"

    private var headers: [String: String] {
        ["x-api-key": key, "anthropic-version": Self.version]
    }

    func body(for call: AIModelCall) -> JSONValue {
        var body: [String: JSONValue] = [
            "model": .string(call.model.id),
            "max_tokens": .number(Double(call.maximumResponseTokens + AIModelCall.thinkingAllowance)),
            "stream": true,
            "system": .string(call.instructions),
            "messages": .array([.object(["role": "user", "content": .string(call.prompt)])]),
        ]
        if call.model.thinkingControl == true {
            body["output_config"] = .object(["effort": "low"])
        }
        return .object(body)
    }

    func stream(_ call: AIModelCall) -> AsyncThrowingStream<String, Error> {
        let request = AIHTTPClient.request(baseURL.appending(path: "messages"), method: "POST", headers: headers, body: body(for: call))
        let events = client.events(request, api: self, model: call.model.id)
        let identity = identity
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in events {
                        switch event["type"]?.stringValue {
                        case "content_block_delta":
                            if event["delta"]?["type"]?.stringValue == "text_delta", let text = event["delta"]?["text"]?.stringValue {
                                continuation.yield(text)
                            }
                        case "message_delta":
                            if event["delta"]?["stop_reason"]?.stringValue == "refusal" {
                                throw CatchUpModelError.declined
                            }
                        case "error":
                            throw Self.streamFailure(event["error"], identity: identity)
                        case "message_stop":
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

    /// An `error` event in the middle of a stream.
    static func streamFailure(_ error: JSONValue?, identity: AIProviderIdentity) -> CatchUpModelError {
        let message = AIProviderFailure.trimmed(error?["message"]?.stringValue ?? "The answer stopped.")
        switch error?["type"]?.stringValue {
        case "overloaded_error", "api_error": return identity.failure(.overloaded)
        case "rate_limit_error": return identity.failure(.rateLimited)
        default: return identity.failure(.other(message))
        }
    }

    // MARK: Models

    /// `GET /v1/models`, every page: Claude models are all text models.
    /// Each has its display name, its input limit (`max_input_tokens`) and
    /// whether it takes an effort.
    func listModels() async throws -> [AIModelInfo] {
        var models: [AIModelInfo] = []
        var after: String?
        for _ in 0..<10 {
            var components = URLComponents(url: baseURL.appending(path: "models"), resolvingAgainstBaseURL: false)!
            var query = [URLQueryItem(name: "limit", value: "1000")]
            if let after { query.append(URLQueryItem(name: "after_id", value: after)) }
            components.queryItems = query
            let page = try await client.json(AIHTTPClient.request(components.url!, headers: headers), api: self)
            for item in page["data"]?.arrayValue ?? [] {
                guard let id = item["id"]?.stringValue, item["type"]?.stringValue ?? "model" == "model" else { continue }
                let effort = item["capabilities"]?["effort"]
                let takesEffort = effort?["low"]?["supported"]?.boolValue ?? effort?["supported"]?.boolValue
                models.append(AIModelInfo(
                    id: id,
                    name: item["display_name"]?.stringValue,
                    contextTokens: item["max_input_tokens"]?.intValue,
                    thinkingControl: takesEffort
                ))
            }
            guard page["has_more"]?.boolValue == true, let last = page["last_id"]?.stringValue else { break }
            after = last
        }
        return Self.ordered(models, recommended: AIProviderKind.anthropic.recommendedModels)
    }

    // MARK: Errors

    func failure(for error: AIHTTPError, model: String?) -> CatchUpModelError {
        // A monthly spend cap: a 429 that waiting doesn't fix.
        if error.status == 429, error.body?["error"]?["details"]?["error_code"]?.stringValue == "enforced_spend_limit_reached" {
            return identity.failure(.quota)
        }
        switch error.type {
        case "authentication_error": return identity.failure(.badKey)
        case "billing_error": return identity.failure(.quota)
        case "not_found_error": return identity.failure(.modelNotFound, model: model)
        case "overloaded_error": return identity.failure(.overloaded)
        default: return standardFailure(for: error, model: model)
        }
    }
}
