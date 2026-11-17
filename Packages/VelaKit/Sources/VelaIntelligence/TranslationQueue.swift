// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Collects translation requests for a moment, groups them by language
/// pair into batches and runs a few batches at a time.
///
/// Rows that appear together (opening an auto-translated channel, a burst
/// of new lines) arrive within one collection window and go out as one
/// batch per language instead of one request each.
public final class TranslationQueue {
    /// One line to translate.
    nonisolated public struct Request: Hashable, Sendable {
        public var id: UUID
        public var text: String
        public var pair: TranslationPair

        public init(id: UUID, text: String, pair: TranslationPair) {
            self.id = id
            self.text = text
            self.pair = pair
        }
    }

    /// Called once per request, on the main actor.
    public var onResult: ((UUID, Result<String, TranslationFailure>) -> Void)?

    public let maxBatchSize: Int
    public let maxConcurrentBatches: Int
    private let collectionDelay: Duration
    private let translator: any MessageTranslator

    /// Waiting, oldest first.
    private var pending: [Request] = []
    private var inFlight: Set<UUID> = []
    private var runningBatches = 0
    private var flushTask: Task<Void, Never>?

    public init(
        translator: any MessageTranslator,
        maxBatchSize: Int = 16,
        maxConcurrentBatches: Int = 2,
        collectionDelay: Duration = .milliseconds(120)
    ) {
        self.translator = translator
        self.maxBatchSize = max(1, maxBatchSize)
        self.maxConcurrentBatches = max(1, maxConcurrentBatches)
        self.collectionDelay = collectionDelay
    }

    /// Nothing waiting or running.
    public var isIdle: Bool { pending.isEmpty && runningBatches == 0 }

    /// Whether `id` is waiting or being translated.
    public func contains(_ id: UUID) -> Bool {
        inFlight.contains(id) || pending.contains { $0.id == id }
    }

    /// Queues `requests`; ones already queued or running are skipped.
    public func enqueue(_ requests: [Request]) {
        var queued = Set(pending.map(\.id)).union(inFlight)
        for request in requests where !queued.contains(request.id) {
            pending.append(request)
            queued.insert(request.id)
        }
        scheduleFlush()
    }

    /// Drops `id` if it's still waiting. A running batch finishes.
    public func cancel(_ id: UUID) {
        pending.removeAll { $0.id == id }
    }

    /// Starts batches now instead of after the collection window.
    public func flush() {
        flushTask?.cancel()
        flushTask = nil
        pump()
    }

    private func scheduleFlush() {
        guard flushTask == nil, !pending.isEmpty else { return }
        let delay = collectionDelay
        flushTask = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled, let self else { return }
            self.flushTask = nil
            self.pump()
        }
    }

    /// Starts batches while there's room: the oldest waiting request's pair
    /// first, up to ``maxBatchSize`` of that pair in their queued order.
    private func pump() {
        while runningBatches < maxConcurrentBatches, let first = pending.first {
            var batch: [Request] = []
            var rest: [Request] = []
            for request in pending {
                if request.pair == first.pair, batch.count < maxBatchSize {
                    batch.append(request)
                } else {
                    rest.append(request)
                }
            }
            pending = rest
            start(batch)
        }
    }

    private func start(_ batch: [Request]) {
        runningBatches += 1
        inFlight.formUnion(batch.map(\.id))
        Task { [weak self] in
            guard let self else { return }
            let results = await self.run(batch)
            self.runningBatches -= 1
            for (request, result) in zip(batch, results) {
                self.inFlight.remove(request.id)
                self.onResult?(request.id, result)
            }
            self.pump()
        }
    }

    /// Translates a batch. If a batch of several fails for an unexpected
    /// reason, each line is tried alone, so one line can't sink the others.
    private func run(_ batch: [Request]) async -> [Result<String, TranslationFailure>] {
        guard let pair = batch.first?.pair else { return [] }
        do {
            let texts = try await translator.translate(batch.map(\.text), from: pair.source, to: pair.target)
            guard texts.count == batch.count else {
                return batch.map { _ in .failure(.failed("The translation came back incomplete.")) }
            }
            return texts.map { .success($0) }
        } catch {
            let failure = Self.failure(from: error)
            guard batch.count > 1, case .failed = failure else {
                return batch.map { _ in .failure(failure) }
            }
            var results: [Result<String, TranslationFailure>] = []
            for request in batch {
                do {
                    let text = try await translator.translate([request.text], from: pair.source, to: pair.target)
                    results.append(text.first.map { .success($0) } ?? .failure(.failed("The translation came back empty.")))
                } catch {
                    results.append(.failure(Self.failure(from: error)))
                }
            }
            return results
        }
    }

    nonisolated static func failure(from error: any Error) -> TranslationFailure {
        if let failure = error as? TranslationFailure { return failure }
        if error is CancellationError { return .cancelled }
        return .failed(error.localizedDescription)
    }
}
