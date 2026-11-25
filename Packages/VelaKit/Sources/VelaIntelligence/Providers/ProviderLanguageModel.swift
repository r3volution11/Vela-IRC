// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// One request to a provider's model: the same instructions and prompt the
/// engine gives Apple's model (``CatchUpPrompts``, ``RecapPrompts``), so
/// what's sent never names a channel, network or server.
nonisolated struct AIModelCall: Sendable, Hashable {
    var model: AIModelInfo
    var instructions: String
    var prompt: String
    /// The most the reply should write. A model that thinks first spends
    /// thinking tokens from the same limit, so requests leave room for
    /// that (``thinkingAllowance``) and the reply is cut off here instead
    /// (see ``ProviderLanguageModel``).
    var maximumResponseTokens: Int

    /// Room for a model's thinking on top of the reply, at the low effort
    /// Vela asks for.
    static let thinkingAllowance = 4_096
}

/// A provider's API: its model list, and a reply streamed as it's written.
nonisolated protocol AIProviderAPI: AIErrorClassifying {
    /// Each element is the next piece of the reply's text (thinking left
    /// out). Errors are ``CatchUpModelError``s: `.contextExceeded`,
    /// `.declined` (a refusal, or the provider's safety filters) or
    /// `.provider(…)`. Cancelling the consumer closes the connection.
    func stream(_ call: AIModelCall) -> AsyncThrowingStream<String, Error>
    /// The provider's text-generation models, recommended ones first.
    func listModels() async throws -> [AIModelInfo]
}

nonisolated extension AIProviderAPI {
    /// `models` with the kind's recommended ones first (in their order,
    /// with Vela's names where the provider has none), marked.
    static func ordered(_ models: [AIModelInfo], recommended: [AIModelInfo]) -> [AIModelInfo] {
        var byID: [String: AIModelInfo] = [:]
        var order: [String] = []
        for model in models where byID[model.id] == nil {
            byID[model.id] = model
            order.append(model.id)
        }
        var result: [AIModelInfo] = []
        for pick in recommended {
            guard var model = byID.removeValue(forKey: pick.id) else { continue }
            model.isRecommended = pick.isRecommended
            if model.name == model.id { model.name = pick.name }
            model.contextTokens = model.contextTokens ?? pick.contextTokens
            model.thinkingControl = model.thinkingControl ?? pick.thinkingControl
            result.append(model)
        }
        return result + order.compactMap { byID[$0] }
    }
}

/// ``CatchUpLanguageModel`` on one of your providers' models: Catch me up
/// and Recap run their engines on it as on Apple's model, with the
/// model's real context size, so a long stretch takes fewer passes
/// (usually one). The provider doesn't count tokens for free, so the
/// engine estimates, erring long.
///
/// Replies are cut off at the engine's limit on this side too, since a
/// model that thinks first is given more room than the reply needs.
nonisolated struct ProviderLanguageModel: CatchUpLanguageModel {
    let api: any AIProviderAPI
    let model: AIModelInfo
    /// The context the engine plans for.
    let context: Int

    func contextSize() async -> Int { context }

    func tokenCount(_ text: String) async -> Int? { nil }

    func digest(
        prompt: String,
        instructions: String,
        maximumResponseTokens: Int,
        until enough: @escaping @Sendable (String) -> Bool
    ) async throws -> String {
        let call = AIModelCall(model: model, instructions: instructions, prompt: prompt, maximumResponseTokens: maximumResponseTokens)
        var reply = ""
        for try await piece in api.stream(call) {
            reply += piece
            if enough(reply) || Self.isPastLimit(reply, maximumResponseTokens) { break }
        }
        try Task.checkCancellation()
        guard !reply.isEmpty else { throw api.identity.failure(.emptyResponse) }
        return reply
    }

    func summarize(prompt: String, instructions: String, maximumResponseTokens: Int) -> AsyncThrowingStream<String, Error> {
        let call = AIModelCall(model: model, instructions: instructions, prompt: prompt, maximumResponseTokens: maximumResponseTokens)
        let api = api
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var reply = ""
                    for try await piece in api.stream(call) {
                        guard !piece.isEmpty else { continue }
                        reply += piece
                        continuation.yield(reply)
                        if Self.isPastLimit(reply, maximumResponseTokens) { break }
                    }
                    try Task.checkCancellation()
                    if reply.isEmpty { throw api.identity.failure(.emptyResponse) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Written well past the reply's limit (by an estimate that errs
    /// long): stop reading.
    static func isPastLimit(_ reply: String, _ maximumResponseTokens: Int) -> Bool {
        CatchUpChunker.estimatedTokens(reply) > maximumResponseTokens * 3 / 2
    }
}

/// Leaves out a local model's thinking when it writes it into the reply
/// (`<think>…</think>` first, as some open models do).
nonisolated struct ThinkingFilter: Sendable {
    private var buffer = ""
    private var state = State.start

    private enum State {
        /// Nothing yet: it may open with `<think>`.
        case start
        case thinking
        case text
    }

    static let open = "<think>"
    static let close = "</think>"

    /// The part of `piece` that's reply text.
    mutating func text(from piece: String) -> String {
        switch state {
        case .text:
            return piece
        case .start:
            buffer += piece
            let trimmed = buffer.drop { $0.isWhitespace }
            if trimmed.hasPrefix(Self.open) {
                state = .thinking
                buffer = String(trimmed.dropFirst(Self.open.count))
                return text(from: "")
            }
            // Could still become "<think>": wait for more.
            if Self.open.hasPrefix(String(trimmed)) { return "" }
            state = .text
            defer { buffer = "" }
            return buffer
        case .thinking:
            buffer += piece
            guard let end = buffer.range(of: Self.close) else {
                // Keep only what could be the start of the closing tag.
                buffer = String(buffer.suffix(Self.close.count))
                return ""
            }
            let rest = buffer[end.upperBound...].drop { $0.isWhitespace }
            buffer = ""
            state = .text
            return String(rest)
        }
    }
}
