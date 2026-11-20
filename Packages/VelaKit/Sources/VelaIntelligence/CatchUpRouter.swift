// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import FoundationModels
import Synchronization

/// Private Cloud Compute as ``CatchUpRouter`` sees it: a model to run the
/// engine on, when there is one, how long it takes, and how it went.
/// Tests use a fake.
nonisolated protocol CatchUpCloud: Sendable {
    /// A model ready for requests, or why there isn't one.
    func prepare() async -> CatchUpCloudReadiness
    /// Roughly how long `passes` parts take: measured this session, or
    /// estimated before there's a measurement.
    func estimatedSeconds(passes: Int) -> Double
    /// A one-pass summary took `duration`.
    func record(onePass duration: Duration)
    /// A summary had to fall back to the Mac, for `reason`.
    func record(failure reason: CatchUpCloudFallback)
}

/// What ``CatchUpCloud/prepare()`` found.
nonisolated enum CatchUpCloudReadiness: Sendable {
    case ready(any CatchUpLanguageModel)
    case notReady(CatchUpCloudFallback)
}

/// Where each summary is written. A stretch the on-device model reads in
/// one pass stays on this Mac. One that would take more passes goes to
/// Private Cloud Compute, when it's offered (`intelligence.privateCloudCompute`
/// on, macOS 27+): its larger context reads it in fewer parts, usually one.
/// When Private Cloud Compute isn't available, is over its daily limit or
/// fails, the stretch is summarized on this Mac instead, quietly; the
/// summary's ``CatchUpSummary/cloudFallback`` says why, for the card's
/// footer.
nonisolated struct CatchUpRouter: Sendable {
    let onDevice: any CatchUpLanguageModel
    /// Nil while Private Cloud Compute is off, or on a system without it.
    let cloud: (any CatchUpCloud)?

    /// Where and in how many passes `request` would be summarized. Counts
    /// tokens once (on the Mac's tokenizer); asks Private Cloud Compute
    /// only whether it's available, never sends it anything.
    func plan(_ request: CatchUpRequest) async -> CatchUpPlan {
        let transcript = CatchUpTranscript(request)
        let local = await CatchUpEngine(model: onDevice).measure(transcript)
        let onDevicePlan = CatchUpPlan(passes: local.passes, transcriptTokens: local.totalTokens)
        guard let cloud, !transcript.isEmpty, !local.fitsOnePass else { return onDevicePlan }
        switch await cloud.prepare() {
        case .notReady(let reason):
            var plan = onDevicePlan
            plan.cloudFallback = reason
            return plan
        case .ready(let model):
            let remote = await CatchUpEngine(model: model).measure(transcript)
            return CatchUpPlan(
                venue: .privateCloudCompute,
                passes: remote.passes,
                transcriptTokens: remote.totalTokens,
                estimatedSeconds: cloud.estimatedSeconds(passes: remote.passes)
            )
        }
    }

    /// Summarizes `request` where ``plan(_:)`` says, falling back to this
    /// Mac when Private Cloud Compute can't do it. Snapshots go to
    /// `progress`, as with ``CatchUpEngine/run(_:venue:cloudFallback:measured:progress:)``.
    func run(
        _ request: CatchUpRequest,
        progress: @escaping @Sendable (CatchUpSummary) -> Void = { _ in }
    ) async throws -> CatchUpSummary {
        let transcript = CatchUpTranscript(request)
        guard !transcript.isEmpty else { throw CatchUpError.nothingToSummarize }
        let device = CatchUpEngine(model: onDevice)
        let local = await device.measure(transcript)
        guard let cloud, !local.fitsOnePass else {
            return try await device.run(request, measured: local, progress: progress)
        }

        let fallback: CatchUpCloudFallback
        switch await cloud.prepare() {
        case .notReady(let reason):
            fallback = reason
        case .ready(let model):
            let engine = CatchUpEngine(model: model)
            let remote = await engine.measure(transcript)
            // Where it's going, before the first words.
            progress(CatchUpSummary(
                overview: "", topics: [], addressedToYou: [], messageCount: transcript.entries.count,
                isComplete: false, venue: .privateCloudCompute
            ))
            let clock = ContinuousClock()
            let start = clock.now
            do {
                let summary = try await engine.run(request, venue: .privateCloudCompute, measured: remote, progress: progress)
                if remote.fitsOnePass { cloud.record(onePass: clock.now - start) }
                return summary
            } catch CatchUpModelError.cloudUnavailable(let reason) {
                fallback = reason
                cloud.record(failure: reason)
            }
        }
        try Task.checkCancellation()
        return try await device.run(request, cloudFallback: fallback, measured: local, progress: progress)
    }
}

/// How Private Cloud Compute has done this session. How long a one-pass
/// summary takes (for Siri, which answers itself only when that's quick):
/// measured, or ``defaultOnePassSeconds`` before the first measurement.
/// And whether it failed lately: for ``cooldown`` after a failure it isn't
/// tried again, so plans don't count on it and each summary doesn't
/// first wait for it to fail.
nonisolated final class CatchUpCloudTimings: Sendable {
    /// The estimate before anything's measured: a server model reads a
    /// long transcript in a second or two, and writing the summary (750
    /// tokens at most) takes longer; with the round trip, about this.
    static let defaultOnePassSeconds = 12.0
    /// How long a failure keeps Private Cloud Compute out of the running.
    static let cooldown: Duration = .seconds(600)

    private struct State {
        var onePass: Double?
        var failure: (reason: CatchUpCloudFallback, at: ContinuousClock.Instant)?
    }

    private let state = Mutex(State())
    private let clock = ContinuousClock()

    /// A one-pass summary's seconds, measured or estimated.
    var onePassSeconds: Double {
        state.withLock { $0.onePass } ?? Self.defaultOnePassSeconds
    }

    /// Why Private Cloud Compute shouldn't be tried now: it failed within
    /// the ``cooldown``. Nil once that's over.
    var recentFailure: CatchUpCloudFallback? {
        let now = clock.now
        return state.withLock { state in
            guard let failure = state.failure, now - failure.at < Self.cooldown else { return nil }
            return failure.reason
        }
    }

    func record(failure reason: CatchUpCloudFallback) {
        let now = clock.now
        state.withLock { $0.failure = (reason, now) }
    }

    /// Several parts take one pass each, plus a merge.
    func estimatedSeconds(passes: Int) -> Double {
        onePassSeconds * Double(passes <= 1 ? 1 : passes + 1)
    }

    /// Averages in a new measurement, weighted toward the latest.
    func record(onePass duration: Duration) {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        state.withLock { state in
            state.onePass = state.onePass.map { ($0 + seconds) / 2 } ?? seconds
            // It worked: whatever failed before is over.
            state.failure = nil
        }
    }
}

// MARK: Private Cloud Compute

/// `PrivateCloudComputeLanguageModel`, checked before each summary: it must
/// be available, under its daily limit, able to generate the summary's
/// structure (guided generation) and to read the Mac's language, and not
/// have failed in the last few minutes. Its context size comes from the
/// system.
@available(macOS 27.0, *)
nonisolated struct PrivateCloudComputeCloud: CatchUpCloud {
    let timings: CatchUpCloudTimings

    func prepare() async -> CatchUpCloudReadiness {
        if let failure = timings.recentFailure { return .notReady(failure) }
        let model = PrivateCloudComputeLanguageModel()
        guard model.isAvailable else { return .notReady(.unavailable) }
        // The limit is per person and per day, and separate from
        // availability: the model can be available with the limit reached.
        guard !model.quotaUsage.isLimitReached else { return .notReady(.limitReached) }
        guard model.capabilities.contains(.guidedGeneration),
              (try? await model.supportsLocale()) == true,
              let context = try? await model.contextSize
        else { return .notReady(.unavailable) }
        return .ready(PrivateCloudComputeCatchUpModel(model: model, context: context))
    }

    func estimatedSeconds(passes: Int) -> Double {
        timings.estimatedSeconds(passes: passes)
    }

    func record(onePass duration: Duration) {
        timings.record(onePass: duration)
    }

    func record(failure reason: CatchUpCloudFallback) {
        timings.record(failure: reason)
    }
}

/// ``CatchUpLanguageModel`` on Private Cloud Compute: the same requests as
/// on the Mac (``FoundationModelsCatchUpModel``), in a session on
/// `PrivateCloudComputeLanguageModel`. The system counts tokens only for
/// the on-device model, so the engine estimates them here, erring long.
@available(macOS 27.0, *)
nonisolated struct PrivateCloudComputeCatchUpModel: CatchUpLanguageModel {
    let model: PrivateCloudComputeLanguageModel
    /// `PrivateCloudComputeLanguageModel.contextSize`.
    let context: Int

    func contextSize() async -> Int { context }

    func tokenCount(_ text: String) async -> Int? { nil }

    func schemaTokenCount(for pass: CatchUpPrompts.Pass) async -> Int? { nil }

    func digest(prompt: String, instructions: String, maximumResponseTokens: Int) async throws -> CatchUpDraft {
        try await FoundationModelsCatchUpModel.digest(
            in: LanguageModelSession(model: model, instructions: instructions),
            prompt: prompt,
            maximumResponseTokens: maximumResponseTokens,
            classify: Self.classify
        )
    }

    func summarize(prompt: String, instructions: String, maximumResponseTokens: Int) -> AsyncThrowingStream<CatchUpDraft, Error> {
        let model = model
        return FoundationModelsCatchUpModel.summarize(
            in: { LanguageModelSession(model: model, instructions: instructions) },
            prompt: prompt,
            maximumResponseTokens: maximumResponseTokens,
            classify: Self.classify
        )
    }

    /// What the engine handles itself (a part that's too long, or that's
    /// declined) stays as it is. Anything else, from an unreachable server
    /// or the daily limit to an app that isn't allowed to use Private
    /// Cloud Compute, means summarizing on the Mac instead.
    @Sendable static func classify(_ error: Error) -> Error {
        if error is CancellationError { return error }
        if let error = error as? PrivateCloudComputeLanguageModel.Error {
            if case .quotaLimitReached = error { return CatchUpModelError.cloudUnavailable(.limitReached) }
            return CatchUpModelError.cloudUnavailable(.unavailable)
        }
        switch FoundationModelsCatchUpModel.classify(error) {
        case let known as CatchUpModelError where known == .contextExceeded || known == .declined:
            return known
        case let known as CatchUpModelError:
            if case .cloudUnavailable = known { return known }
            return CatchUpModelError.cloudUnavailable(.unavailable)
        default:
            return CatchUpModelError.cloudUnavailable(.unavailable)
        }
    }
}
