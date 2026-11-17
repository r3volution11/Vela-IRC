// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import FoundationModels

/// Summarizes with Apple's on-device Foundation Models (``CatchUpEngine``
/// over ``FoundationModelsCatchUpModel``). Nothing leaves the Mac.
public final class FoundationModelSummarizer: ConversationSummarizer {
    private let availability: IntelligenceAvailability

    public init(availability: IntelligenceAvailability) {
        self.availability = availability
    }

    public nonisolated func summarize(_ request: CatchUpRequest) -> AsyncThrowingStream<CatchUpSummary, Error> {
        let availability = availability
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let status = await MainActor.run {
                        availability.refresh()
                        return availability.status
                    }
                    guard status.isAvailable else { throw CatchUpError.unavailable(status) }
                    let engine = CatchUpEngine(model: FoundationModelsCatchUpModel())
                    let summary = try await engine.run(request) { continuation.yield($0) }
                    continuation.yield(summary)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// ``CatchUpLanguageModel`` on `SystemLanguageModel.default`. Each request
/// gets a fresh session, so earlier chunks never crowd the context.
nonisolated struct FoundationModelsCatchUpModel: CatchUpLanguageModel {
    /// Plan for at most this context, whatever the model offers (tests use
    /// 4,096 to act like macOS 26.0–26.3).
    var contextLimit: Int?
    /// Use the system's token counts where it has them (macOS 26.4+).
    var countsTokens = true

    /// Low but not greedy: factual, without the repetition loops greedy
    /// decoding can fall into.
    private var options: GenerationOptions { GenerationOptions(temperature: 0.3) }

    func contextSize() async -> Int {
        min(SystemLanguageModel.default.contextSize, contextLimit ?? .max)
    }

    func tokenCount(_ text: String) async -> Int? {
        guard countsTokens, #available(macOS 26.4, *) else { return nil }
        return try? await SystemLanguageModel.default.tokenCount(for: text)
    }

    func schemaTokenCount(for pass: CatchUpPrompts.Pass) async -> Int? {
        guard countsTokens, #available(macOS 26.4, *) else { return nil }
        let schema = switch pass {
        case .single, .merge: GeneratedCatchUp.generationSchema
        case .digest: ChunkDigest.generationSchema
        }
        return try? await SystemLanguageModel.default.tokenCount(for: schema)
    }

    func digest(prompt: String, instructions: String) async throws -> CatchUpDraft {
        let session = LanguageModelSession(model: .default, instructions: instructions)
        do {
            let response = try await session.respond(to: prompt, generating: ChunkDigest.self, options: options)
            return CatchUpDraft(response.content)
        } catch {
            throw Self.classify(error)
        }
    }

    func summarize(prompt: String, instructions: String) -> AsyncThrowingStream<CatchUpDraft, Error> {
        let options = options
        return AsyncThrowingStream { continuation in
            let task = Task {
                let session = LanguageModelSession(model: .default, instructions: instructions)
                do {
                    let stream = session.streamResponse(to: prompt, generating: GeneratedCatchUp.self, options: options)
                    for try await snapshot in stream {
                        continuation.yield(CatchUpDraft(snapshot.content))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.classify(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Foundation Models' errors as the engine's. macOS 27 reports
    /// `LanguageModelError`s; macOS 26 the older `GenerationError`s.
    static func classify(_ error: Error) -> Error {
        if error is CancellationError || error is CatchUpModelError { return error }
        if #available(macOS 27.0, *) {
            if let error = error as? LanguageModelError {
                switch error {
                case .contextSizeExceeded: return CatchUpModelError.contextExceeded
                case .rateLimited: return CatchUpModelError.rateLimited
                case .guardrailViolation, .refusal: return CatchUpModelError.declined
                case .unsupportedLanguageOrLocale: return CatchUpModelError.unsupportedLanguage
                default: return CatchUpModelError.failed(error.localizedDescription)
                }
            }
            if error is SystemLanguageModel.Error { return CatchUpModelError.unavailable }
        }
        if let error = error as? LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize: return CatchUpModelError.contextExceeded
            case .rateLimited: return CatchUpModelError.rateLimited
            case .guardrailViolation, .refusal: return CatchUpModelError.declined
            case .unsupportedLanguageOrLocale: return CatchUpModelError.unsupportedLanguage
            case .assetsUnavailable: return CatchUpModelError.unavailable
            default: return CatchUpModelError.failed(error.localizedDescription)
            }
        }
        return CatchUpModelError.failed(error.localizedDescription)
    }
}
