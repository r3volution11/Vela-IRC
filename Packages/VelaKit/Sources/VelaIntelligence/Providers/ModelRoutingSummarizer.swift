// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaStore

/// Catch me up and Recap, each on the model it uses (``AIModels``): Apple's
/// (the summarizer this wraps, on this Mac or with Private Cloud Compute)
/// or one of your providers', running the same engines with the same
/// prompts, which carry only messages, nicks and your own nick. A
/// provider's model is used only once you've agreed to send it messages;
/// until then, and whenever it fails, the summary fails with a
/// ``CatchUpError/provider(_:)`` saying why. Nothing ever falls back to
/// another provider.
public final class ModelRoutingSummarizer: ConversationSummarizer, RecapSummarizer {
    let apple: any ConversationSummarizer & RecapSummarizer
    let models: AIModels
    /// How long a provider's Recap requests take, this session.
    let recapTimings = RecapTimings()

    public init(apple: any ConversationSummarizer & RecapSummarizer, models: AIModels) {
        self.apple = apple
        self.models = models
    }

    /// Roughly how long a provider takes per pass, for Siri's patience:
    /// a long transcript read and a short summary written.
    nonisolated static let providerSecondsPerPass = 8.0

    // MARK: Catch me up

    public nonisolated func summarize(_ request: CatchUpRequest) -> AsyncThrowingStream<CatchUpSummary, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    switch await self.models.route(for: .catchUp, override: request.model) {
                    case .apple(let model):
                        var forwarded = request
                        forwarded.model = .apple(model)
                        for try await snapshot in await self.apple.summarize(forwarded) { continuation.yield(snapshot) }
                    case .provider(let route):
                        continuation.yield(try await Self.summarize(request, on: route) { continuation.yield($0) })
                    case .unavailable(let failure):
                        throw CatchUpError.provider(failure)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public nonisolated func plan(_ request: CatchUpRequest) async -> CatchUpPlan {
        switch await models.route(for: .catchUp, override: request.model) {
        case .apple(let model):
            var forwarded = request
            forwarded.model = .apple(model)
            return await apple.plan(forwarded)
        case .provider(let route):
            guard let model = route.planningModel() else { return CatchUpPlan(passes: 1, transcriptTokens: 0) }
            let measured = await CatchUpEngine(model: model).measure(CatchUpTranscript(request))
            return CatchUpPlan(
                venue: .provider(route.label),
                passes: measured.passes,
                transcriptTokens: measured.totalTokens,
                estimatedSeconds: Self.providerSecondsPerPass * Double(measured.passes <= 1 ? 1 : measured.passes + 1)
            )
        case .unavailable:
            return CatchUpPlan(passes: 1, transcriptTokens: 0)
        }
    }

    /// A summary by a provider's model: its key read (off the main actor),
    /// where it's going said before the first words, then the engine.
    @concurrent
    nonisolated static func summarize(
        _ request: CatchUpRequest,
        on route: AIProviderRoute,
        progress: @escaping @Sendable (CatchUpSummary) -> Void
    ) async throws -> CatchUpSummary {
        let model: ProviderLanguageModel
        do {
            model = try route.languageModel()
        } catch let error as CatchUpModelError {
            throw error.catchUpError
        }
        let transcript = CatchUpTranscript(request)
        guard !transcript.isEmpty else { throw CatchUpError.nothingToSummarize }
        let venue = CatchUpVenue.provider(route.label)
        progress(CatchUpSummary(
            overview: "", topics: [], addressedToYou: [], messageCount: transcript.entries.count,
            isComplete: false, venue: venue
        ))
        do {
            return try await CatchUpEngine(model: model).run(request, venue: venue, progress: progress)
        } catch CatchUpError.declined {
            throw CatchUpError.provider(AIProviderFailure(providerID: route.entry.id, providerName: route.entry.name, reason: .declined))
        }
    }

    // MARK: Recap

    public nonisolated func plan(_ input: RecapInput) async -> RecapPlan {
        switch await models.route(for: .recap, override: input.model) {
        case .apple(let model):
            var forwarded = input
            forwarded.model = .apple(model)
            return await apple.plan(forwarded)
        case .provider(let route):
            guard let model = route.planningModel() else { return RecapPlan(passes: 1, transcriptTokens: 0, estimatedSeconds: 0) }
            let engine = RecapEngine(model: model, venue: .provider(route.label), timings: recapTimings)
            return await engine.plan(input)
        case .unavailable(let failure):
            return RecapPlan(passes: 1, transcriptTokens: 0, estimatedSeconds: 0, venue: .provider(AIModelLabel(
                providerID: failure.providerID, providerName: failure.providerName, modelID: failure.modelID ?? "", modelName: failure.modelID ?? ""
            )))
        }
    }

    public nonisolated func recap(_ input: RecapInput) -> AsyncThrowingStream<RecapSummary, Error> {
        AsyncThrowingStream { continuation in
            let task = Task(priority: .utility) {
                do {
                    switch await self.models.route(for: .recap, override: input.model) {
                    case .apple(let model):
                        var forwarded = input
                        forwarded.model = .apple(model)
                        for try await snapshot in await self.apple.recap(forwarded) { continuation.yield(snapshot) }
                    case .provider(let route):
                        let timings = self.recapTimings
                        continuation.yield(try await Self.recap(input, on: route, timings: timings) { continuation.yield($0) })
                    case .unavailable(let failure):
                        throw CatchUpError.provider(failure)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public nonisolated func detail(_ request: RecapDetailRequest) -> AsyncThrowingStream<RecapDetail, Error> {
        AsyncThrowingStream { continuation in
            let task = Task(priority: .utility) {
                do {
                    switch await self.models.route(for: .recap, override: request.model) {
                    case .apple(let model):
                        var forwarded = request
                        forwarded.model = .apple(model)
                        for try await detail in await self.apple.detail(forwarded) { continuation.yield(detail) }
                    case .provider(let route):
                        let timings = self.recapTimings
                        continuation.yield(try await Self.detail(request, on: route, timings: timings) { continuation.yield($0) })
                    case .unavailable(let failure):
                        throw CatchUpError.provider(failure)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    @concurrent
    nonisolated static func recap(
        _ input: RecapInput,
        on route: AIProviderRoute,
        timings: RecapTimings,
        progress: @escaping @Sendable (RecapSummary) -> Void
    ) async throws -> RecapSummary {
        let engine = RecapEngine(model: try languageModel(route), venue: .provider(route.label), timings: timings)
        do {
            return try await engine.run(input, progress: progress)
        } catch CatchUpError.declined {
            throw CatchUpError.provider(AIProviderFailure(providerID: route.entry.id, providerName: route.entry.name, reason: .declined))
        }
    }

    @concurrent
    nonisolated static func detail(
        _ request: RecapDetailRequest,
        on route: AIProviderRoute,
        timings: RecapTimings,
        progress: @escaping @Sendable (RecapDetail) -> Void
    ) async throws -> RecapDetail {
        let engine = RecapEngine(model: try languageModel(route), venue: .provider(route.label), timings: timings)
        do {
            return try await engine.detail(request, progress: progress)
        } catch CatchUpError.declined {
            throw CatchUpError.provider(AIProviderFailure(providerID: route.entry.id, providerName: route.entry.name, reason: .declined))
        }
    }

    /// The route's model with its key, failures as the reader sees them.
    private nonisolated static func languageModel(_ route: AIProviderRoute) throws -> ProviderLanguageModel {
        do {
            return try route.languageModel()
        } catch let error as CatchUpModelError {
            throw error.catchUpError
        }
    }
}
