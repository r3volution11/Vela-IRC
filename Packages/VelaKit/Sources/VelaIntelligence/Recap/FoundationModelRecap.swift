// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaStore

/// Recaps with Apple's Foundation Models: the ``RecapEngine`` on the same
/// on-device model as Catch me up (and Private Cloud Compute for long ones,
/// while `intelligence.privateCloudCompute` is on), at a low priority, one
/// summary at a time (``ModelLane``).
extension FoundationModelSummarizer: RecapSummarizer {
    public nonisolated func plan(_ input: RecapInput) async -> RecapPlan {
        guard let router = try? await recapRouter(checkingAvailability: false, model: Self.appleModel(input.model)) else {
            return RecapPlan(passes: 1, transcriptTokens: 0, estimatedSeconds: 0)
        }
        return await router.plan(input)
    }

    public nonisolated func recap(_ input: RecapInput) -> AsyncThrowingStream<RecapSummary, Error> {
        AsyncThrowingStream { continuation in
            let task = Task(priority: .utility) {
                do {
                    let router = try await self.recapRouter(checkingAvailability: true, model: Self.appleModel(input.model))
                    let total = min(input.lineCount, RecapLimits.summaryLines)
                    let summary = try await self.lane.run(waiting: {
                        continuation.yield(RecapSummary(progress: RecapProgress(messagesRead: 0, messagesTotal: total, isWaiting: true)))
                    }) {
                        try await router.run(input) { continuation.yield($0) }
                    }
                    continuation.yield(summary)
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
                    let router = try await self.recapRouter(checkingAvailability: true)
                    let detail = try await self.lane.run {
                        try await router.detail(request) { continuation.yield($0) }
                    }
                    continuation.yield(detail)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The Catch me up router's models, with this session's Recap timings.
    func recapRouter(checkingAvailability: Bool, model: AppleModel = .automatic) throws -> RecapRouter {
        let catchUp = try router(checkingAvailability: checkingAvailability, model: model)
        var router = RecapRouter(onDevice: catchUp.onDevice, cloud: catchUp.cloud, timings: recapTimings)
        router.alwaysCloud = catchUp.alwaysCloud
        return router
    }
}
