// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import FoundationModels
import VelaStore

/// Summarizes with Apple's Foundation Models (``CatchUpEngine`` over
/// ``FoundationModelsCatchUpModel``), on this Mac. With
/// `intelligence.privateCloudCompute` on, on macOS 27 or later, a stretch
/// too long for one on-device pass goes to Private Cloud Compute instead
/// (see ``CatchUpRouter``); everything else stays on the Mac. Private Cloud
/// Compute is in development builds only for now
/// (`PrivateCloudComputeAvailability`).
public final class FoundationModelSummarizer: ConversationSummarizer {
    private let availability: IntelligenceAvailability
    /// Whether long catch-ups may use Private Cloud Compute: the setting.
    private let usesPrivateCloudCompute: () -> Bool
    /// How Private Cloud Compute has done this session: how long it takes,
    /// and whether it failed lately.
    private let cloudTimings = CatchUpCloudTimings()

    /// - Parameters:
    ///   - usesPrivateCloudCompute: Read before each summary; true lets
    ///     a long one go to Private Cloud Compute (`intelligence.privateCloudCompute`).
    public init(availability: IntelligenceAvailability, usesPrivateCloudCompute: @escaping () -> Bool = { false }) {
        self.availability = availability
        self.usesPrivateCloudCompute = usesPrivateCloudCompute
    }

    public nonisolated func summarize(_ request: CatchUpRequest) -> AsyncThrowingStream<CatchUpSummary, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let router = try await self.router(checkingAvailability: true)
                    let summary = try await router.run(request) { continuation.yield($0) }
                    continuation.yield(summary)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public nonisolated func plan(_ request: CatchUpRequest) async -> CatchUpPlan {
        guard let router = try? await router(checkingAvailability: false) else {
            return CatchUpPlan(passes: 1, transcriptTokens: 0)
        }
        return await router.plan(request)
    }

    /// Where summaries go now: Private Cloud Compute is offered to the
    /// router only while the setting is on and the system has it.
    func router(checkingAvailability: Bool) throws -> CatchUpRouter {
        if checkingAvailability {
            availability.refresh()
            guard availability.status.isAvailable else { throw CatchUpError.unavailable(availability.status) }
        }
        return CatchUpRouter(
            onDevice: FoundationModelsCatchUpModel(),
            cloud: usesPrivateCloudCompute() ? Self.privateCloudCompute(timings: cloudTimings) : nil
        )
    }

    /// Private Cloud Compute, where the system has it (macOS 27+), in
    /// development builds only for now (`PrivateCloudComputeAvailability`):
    /// a release never sets up the cloud path.
    private nonisolated static func privateCloudCompute(timings: CatchUpCloudTimings) -> (any CatchUpCloud)? {
        guard PrivateCloudComputeAvailability.isBuiltIn else { return nil }
        if #available(macOS 27.0, *) {
            return PrivateCloudComputeCloud(timings: timings)
        }
        return nil
    }
}

/// ``CatchUpLanguageModel`` on the on-device `SystemLanguageModel`. Each
/// request gets a fresh session, so earlier chunks never crowd the context.
///
/// Replies are plain text (``CatchUpReply``), and the model's guardrails
/// are `.permissiveContentTransformations`: meant for transforming text
/// people wrote, such as summarizing it, and applied only to requests that
/// generate text. With guided generation (`@Generable`) the same guardrails
/// behave like `.default`, and a heated channel was declined whole.
nonisolated struct FoundationModelsCatchUpModel: CatchUpLanguageModel {
    /// Plan for at most this context, whatever the model offers (tests use
    /// 4,096 to act like macOS 26.0–26.3).
    var contextLimit: Int?
    /// Use the system's token counts where it has them (macOS 26.4+).
    var countsTokens = true
    /// `.permissiveContentTransformations`; tests compare `.default`.
    var permissiveGuardrails = true

    /// Low but not greedy: factual, without the repetition loops greedy
    /// decoding can fall into. The response stops after
    /// `maximumResponseTokens`, the room the engine left for it, so one
    /// that runs on is cut off there instead of filling the context window
    /// (minutes, on a Mac with a 4,096-token model).
    static func options(maximumResponseTokens: Int) -> GenerationOptions {
        GenerationOptions(temperature: 0.3, maximumResponseTokens: maximumResponseTokens)
    }

    /// The model requests go to.
    var model: SystemLanguageModel {
        SystemLanguageModel(guardrails: permissiveGuardrails ? .permissiveContentTransformations : .default)
    }

    func contextSize() async -> Int {
        min(SystemLanguageModel.default.contextSize, contextLimit ?? .max)
    }

    func tokenCount(_ text: String) async -> Int? {
        guard countsTokens, #available(macOS 26.4, *) else { return nil }
        return try? await SystemLanguageModel.default.tokenCount(for: text)
    }

    func digest(
        prompt: String,
        instructions: String,
        maximumResponseTokens: Int,
        until enough: @escaping @Sendable (String) -> Bool
    ) async throws -> String {
        try await Self.respond(
            in: LanguageModelSession(model: model, instructions: instructions),
            prompt: prompt,
            maximumResponseTokens: maximumResponseTokens,
            until: enough,
            classify: Self.classify
        )
    }

    func summarize(prompt: String, instructions: String, maximumResponseTokens: Int) -> AsyncThrowingStream<String, Error> {
        let model = model
        return Self.stream(
            in: { LanguageModelSession(model: model, instructions: instructions) },
            prompt: prompt,
            maximumResponseTokens: maximumResponseTokens,
            classify: Self.classify
        )
    }

    // MARK: Requests

    /// A reply from a fresh `session`, all at once: streamed, so it can
    /// stop as soon as it's `enough`. A reply cut off at the limit ends
    /// with what it has. Shared with ``PrivateCloudComputeCatchUpModel``.
    static func respond(
        in session: LanguageModelSession,
        prompt: String,
        maximumResponseTokens: Int,
        until enough: (String) -> Bool,
        classify: (Error) -> Error
    ) async throws -> String {
        do {
            var reply = ""
            for try await snapshot in session.streamResponse(to: prompt, options: options(maximumResponseTokens: maximumResponseTokens)) {
                reply = snapshot.content
                if enough(reply) { break }
            }
            return reply
        } catch {
            throw classify(error)
        }
    }

    /// A reply from a fresh session, streamed: each element is the reply
    /// so far. Shared with ``PrivateCloudComputeCatchUpModel``.
    static func stream(
        in makeSession: @escaping @Sendable () -> LanguageModelSession,
        prompt: String,
        maximumResponseTokens: Int,
        classify: @escaping @Sendable (Error) -> Error
    ) -> AsyncThrowingStream<String, Error> {
        let options = options(maximumResponseTokens: maximumResponseTokens)
        return AsyncThrowingStream { continuation in
            let task = Task {
                let session = makeSession()
                do {
                    for try await snapshot in session.streamResponse(to: prompt, options: options) {
                        continuation.yield(snapshot.content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: classify(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Foundation Models' errors as the engine's. macOS 27 reports
    /// `LanguageModelError`s; macOS 26 the older `GenerationError`s.
    @Sendable static func classify(_ error: Error) -> Error {
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
