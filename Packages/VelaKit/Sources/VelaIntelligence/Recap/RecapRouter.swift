// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Synchronization

/// Where each Recap is written, as ``CatchUpRouter`` decides for Catch me
/// up: on this Mac, unless it takes more than one pass there and Private
/// Cloud Compute is on (`intelligence.privateCloudCompute`) and ready, in
/// which case its larger context reads it in fewer parts. When Private
/// Cloud Compute fails, the Recap is written on this Mac instead, and says
/// why. More detail is always one short pass, on this Mac.
nonisolated struct RecapRouter: Sendable {
    let onDevice: any CatchUpLanguageModel
    let cloud: (any CatchUpCloud)?
    var timings = RecapTimings()
    /// Private Cloud Compute was chosen as the model: every Recap goes
    /// there (see ``CatchUpRouter/alwaysCloud``).
    var alwaysCloud = false

    func plan(_ input: RecapInput) async -> RecapPlan {
        let transcript = RecapTranscript(input)
        let device = RecapEngine(model: onDevice, timings: timings)
        let local = await device.measure(transcript)
        guard let cloud, !transcript.isEmpty, alwaysCloud || !local.fitsOnePass,
              case .ready(let model) = await cloud.prepare()
        else { return await device.plan(input, measured: local) }
        let engine = RecapEngine(model: model, venue: .privateCloudCompute, timings: timings)
        return await engine.plan(input, measured: await engine.measure(transcript))
    }

    func run(_ input: RecapInput, progress: @escaping @Sendable (RecapSummary) -> Void) async throws -> RecapSummary {
        let transcript = RecapTranscript(input)
        guard !transcript.isEmpty else { throw CatchUpError.nothingToSummarize }
        var device = RecapEngine(model: onDevice, timings: timings)
        let local = await device.measure(transcript)
        guard let cloud, alwaysCloud || !local.fitsOnePass else {
            return try await device.run(input, measured: local, progress: progress)
        }
        let fallback: CatchUpCloudFallback
        switch await cloud.prepare() {
        case .notReady(let reason):
            fallback = reason
        case .ready(let model):
            let engine = RecapEngine(model: model, venue: .privateCloudCompute, timings: timings)
            do {
                return try await engine.run(input, measured: await engine.measure(transcript), progress: progress)
            } catch CatchUpModelError.cloudUnavailable(let reason) {
                fallback = reason
                cloud.record(failure: reason)
            }
        }
        try Task.checkCancellation()
        device.cloudFallback = fallback
        return try await device.run(input, measured: local, progress: progress)
    }

    func detail(_ request: RecapDetailRequest, progress: @escaping @Sendable (RecapDetail) -> Void) async throws -> RecapDetail {
        try await RecapEngine(model: onDevice, timings: timings).detail(request, progress: progress)
    }
}

/// Lets one summary at a time use Apple Intelligence: Catch me up cards,
/// Recaps (several windows can be open) and More detail take turns, in
/// the order they asked, so a Mac with 8 GB of memory never runs two at
/// once. Cancelling a waiting turn takes it out of line.
nonisolated final class ModelLane: Sendable {
    private struct State {
        var isBusy = false
        var waiting: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []
    }

    private let state = Mutex(State())

    init() {}

    /// Runs `work` when it's this caller's turn. `waiting` is called first
    /// when someone else is using the model.
    func run<T: Sendable>(waiting: @Sendable () -> Void = {}, _ work: @Sendable () async throws -> T) async throws -> T {
        try await acquire(waiting: waiting)
        defer { release() }
        try Task.checkCancellation()
        return try await work()
    }

    private func acquire(waiting: @Sendable () -> Void) async throws {
        let id = UUID()
        let mustWait = state.withLock { state -> Bool in
            if !state.isBusy {
                state.isBusy = true
                return false
            }
            return true
        }
        guard mustWait else { return }
        waiting()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let resumeNow = state.withLock { state -> Bool in
                    if !state.isBusy {
                        state.isBusy = true
                        return true
                    }
                    state.waiting.append((id, continuation))
                    return false
                }
                if resumeNow { continuation.resume() }
            }
        } onCancel: {
            let cancelled = state.withLock { state -> CheckedContinuation<Void, Error>? in
                guard let index = state.waiting.firstIndex(where: { $0.id == id }) else { return nil }
                return state.waiting.remove(at: index).continuation
            }
            cancelled?.resume(throwing: CancellationError())
        }
    }

    private func release() {
        let next = state.withLock { state -> CheckedContinuation<Void, Error>? in
            guard !state.waiting.isEmpty else {
                state.isBusy = false
                return nil
            }
            return state.waiting.removeFirst().continuation
        }
        next?.resume()
    }
}
