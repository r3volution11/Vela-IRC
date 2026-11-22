// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Observation
import VelaCore
import VelaStore

/// One "Catch me up" card: the conversation it covers and how far
/// summarizing it has got. Observable on its own, so a streaming summary
/// redraws only its card.
@Observable
public final class CatchUpCard {
    public enum Phase: Equatable, Sendable {
        /// Summarizing; the summary so far once there is one.
        case running(CatchUpSummary?)
        case done(CatchUpSummary)
        case failed(CatchUpError)
    }

    public let bufferID: BufferID
    /// What's being summarized.
    public private(set) var request: CatchUpRequest
    /// The New marker the card was opened under (`BufferModel.unreadMarkerAfter`).
    /// The card stays there (see ``anchor``) after the live marker moves or
    /// goes, as it does when the window loses and regains focus.
    public private(set) var marker: Date?
    public internal(set) var phase: Phase
    /// While its summary waits its turn (summaries are written one at a
    /// time), how many are ahead of it, the one being written included.
    /// Nil once its own is being written, and for a finished card.
    public internal(set) var summariesAhead: Int?

    /// Where the card sits in the list: before the first line newer than
    /// this. Its own marker, or the start of the buffer when it was opened
    /// without one (it then covers everything loaded).
    public var anchor: Date { marker ?? .distantPast }

    @ObservationIgnored var key: CatchUpRangeKey
    /// The consent sheet was shown for this card's provider, so the card
    /// doesn't show it again each time it scrolls into view (its Review…
    /// button still does).
    @ObservationIgnored public var hasAskedForConsent = false

    init(request: CatchUpRequest, marker: Date?, phase: Phase) {
        self.bufferID = request.bufferID
        self.request = request
        self.marker = marker
        self.phase = phase
        self.key = CatchUpRangeKey(request)
    }

    func replace(with request: CatchUpRequest, marker: Date?) {
        if request.model != self.request.model { hasAskedForConsent = false }
        self.request = request
        self.marker = marker
        key = CatchUpRangeKey(request)
    }

    /// Lines in the stretch being summarized (the header's "N messages").
    public var messageCount: Int { request.lines.count }

    /// The time of the newest line in the stretch; nil for a card saying
    /// there's nothing new.
    public var coversThrough: Date? { request.lines.last?.time }

    /// The summary so far, complete or not.
    public var summary: CatchUpSummary? {
        switch phase {
        case .running(let partial): partial
        case .done(let summary): summary
        case .failed: nil
        }
    }

    public var isRunning: Bool {
        if case .running = phase { true } else { false }
    }

    /// Asked for with nothing new to summarize: the card says so.
    public var isNothingNew: Bool {
        phase == .failed(.nothingToSummarize)
    }
}

/// A stretch of one buffer's conversation, for caching: the buffer, its
/// newest line and how many lines lead up to it.
nonisolated struct CatchUpRangeKey: Hashable, Sendable {
    var bufferID: BufferID
    var newestLineID: UUID?
    var count: Int
    /// The model asked for: each model's summary is its own.
    var model: AIModelChoice?

    init(_ request: CatchUpRequest) {
        bufferID = request.bufferID
        newestLineID = request.lines.last?.id
        count = request.lines.count
        model = request.model
    }
}

/// A request to scroll a buffer's list to its Catch me up card. Each one
/// is distinct, so asking twice still scrolls.
nonisolated public struct CatchUpReveal: Equatable, Sendable {
    public let id = UUID()
    public let bufferID: BufferID
}

/// Catch me up summaries for the whole app: the open card per buffer and
/// finished summaries cached per buffer and range, shared by the cards and
/// the Siri / Shortcuts intent. One per app, owned by ``IntelligenceServices``.
///
/// A card stays open until it's dismissed, replaced by a newer stretch, its
/// buffer closes or Catch me up is turned off. Going to another buffer
/// leaves it, and its summary keeps being written. Each buffer's latest
/// stretch is also remembered for the session (see ``reopen(_:reveal:)``),
/// so its summary stays reachable after the buffer is read.
///
/// Summaries are written one at a time, in the order they're asked for:
/// several at once would be heavy on a Mac with 8 GB of memory. A card
/// whose summary is waiting says so (``CatchUpCard/summariesAhead``), and
/// closing it takes it out of the queue. Siri's request goes to the front,
/// since Siri is waiting for it.
@Observable
public final class CatchUpStore {
    /// Open cards, by buffer. Changes only when a card opens or closes;
    /// progress is observed on the card itself.
    public private(set) var cards: [BufferID: CatchUpCard] = [:]
    /// The latest request to scroll to a card.
    public private(set) var reveal: CatchUpReveal?

    @ObservationIgnored private let summarizer: any ConversationSummarizer
    @ObservationIgnored private var cache: [CatchUpRangeKey: CatchUpSummary] = [:]
    @ObservationIgnored private var cacheOrder: [CatchUpRangeKey] = []
    /// The job for each stretch being summarized or waiting its turn.
    @ObservationIgnored private var jobs: [CatchUpRangeKey: Job] = [:]
    /// Jobs waiting their turn, next first.
    @ObservationIgnored private var queue: [Job] = []
    /// The job being written now; at most one at a time.
    @ObservationIgnored private var running: Job?
    @ObservationIgnored private let cacheLimit: Int
    /// Each buffer's latest stretch, newest last; as many as the cache holds.
    @ObservationIgnored private var stretches: [BufferID: Stretch] = [:]
    @ObservationIgnored private var stretchOrder: [BufferID] = []

    /// A stretch a card was opened for: what to summarize and where it sat.
    private struct Stretch {
        let request: CatchUpRequest
        let marker: Date?
    }

    public init(summarizer: any ConversationSummarizer, cacheLimit: Int = 24) {
        self.summarizer = summarizer
        self.cacheLimit = cacheLimit
    }

    public func card(for bufferID: BufferID) -> CatchUpCard? {
        cards[bufferID]
    }

    /// The list scrolled to the card: forget the request.
    public func revealHandled(_ handled: CatchUpReveal) {
        if reveal == handled { reveal = nil }
    }

    // MARK: Cards

    /// Shows the card for `request`'s buffer and summarizes it, at once
    /// from the cache when this stretch was summarized before. A card
    /// that's already open for the same stretch is kept (and revealed).
    /// With no lines, the card says there's nothing new.
    ///
    /// - Parameters:
    ///   - marker: The buffer's New marker; see ``CatchUpCard/marker``.
    ///   - reveal: Ask the message list to scroll to the card.
    public func open(_ request: CatchUpRequest, marker: Date? = nil, reveal: Bool = true) {
        let key = CatchUpRangeKey(request)
        if let card = cards[request.bufferID], card.key == key, !isFailed(card) || card.isNothingNew {
            if reveal { self.reveal = CatchUpReveal(bufferID: request.bufferID) }
            return
        }
        if let old = cards[request.bufferID] { detach(old.key) }
        let card: CatchUpCard
        if request.lines.isEmpty {
            card = CatchUpCard(request: request, marker: marker, phase: .failed(.nothingToSummarize))
        } else {
            card = CatchUpCard(request: request, marker: marker, phase: .running(nil))
            remember(request, marker: marker)
        }
        cards[request.bufferID] = card
        if !request.lines.isEmpty { start(card) }
        if reveal { self.reveal = CatchUpReveal(bufferID: request.bufferID) }
    }

    /// Shows the buffer's card again, for when nothing is new: the open
    /// one (revealed), or one for the latest stretch summarized there this
    /// session, from the cache (or summarized again if it never finished).
    /// Returns false when there's neither.
    @discardableResult
    public func reopen(_ bufferID: BufferID, reveal: Bool = true) -> Bool {
        if let card = cards[bufferID], !card.isNothingNew {
            if reveal { self.reveal = CatchUpReveal(bufferID: bufferID) }
            return true
        }
        guard let stretch = stretches[bufferID] else { return false }
        open(stretch.request, marker: stretch.marker, reveal: reveal)
        return true
    }

    /// Whether ``reopen(_:reveal:)`` has a summary to show for the buffer.
    public func hasEarlierSummary(for bufferID: BufferID) -> Bool {
        if let card = cards[bufferID], !card.isNothingNew { return true }
        return stretches[bufferID] != nil
    }

    /// The latest stretch summarized in the buffer this session, for Siri
    /// when nothing in it is new any more.
    public func latestRequest(for bufferID: BufferID) -> CatchUpRequest? {
        stretches[bufferID]?.request
    }

    /// Summarizes again, ignoring the cache: `request` is usually the same
    /// buffer's conversation rebuilt, so it includes anything new. Also
    /// Try Again after a failure.
    public func regenerate(_ request: CatchUpRequest, marker: Date? = nil) {
        guard let card = cards[request.bufferID] else {
            forget(CatchUpRangeKey(request))
            open(request, marker: marker, reveal: false)
            return
        }
        detach(card.key)
        forget(card.key)
        card.replace(with: request, marker: marker)
        forget(card.key)
        guard !request.lines.isEmpty else {
            card.phase = .failed(.nothingToSummarize)
            return
        }
        remember(request, marker: marker)
        // Always a fresh job: one Siri is still waiting on keeps going for it.
        card.phase = .running(startJob(request, key: card.key).latest)
    }

    /// Summarizes the buffer's card's stretch again with `model`: the
    /// card's Change menu, and Try with Apple Intelligence. Nil follows
    /// the settings again. Later Regenerates keep the model.
    public func rerun(_ bufferID: BufferID, with model: AIModelChoice?) {
        guard let card = cards[bufferID] else { return }
        var request = card.request
        request.model = model
        regenerate(request, marker: card.marker)
    }

    /// Closes the buffer's card and stops its summary (unless Siri is
    /// waiting for the same one). A finished summary stays cached, and the
    /// stretch stays remembered. Called when the reader dismisses the card.
    public func dismiss(_ bufferID: BufferID) {
        guard let card = cards.removeValue(forKey: bufferID) else { return }
        detach(card.key)
    }

    /// The buffer on screen changed to `bufferID`. Cards elsewhere stay,
    /// and their summaries keep being written, except a "nothing new" card,
    /// which was an answer for the moment, and cards whose buffers are gone
    /// (`exists` says which still are).
    public func selectionChanged(to bufferID: BufferID?, exists: (BufferID) -> Bool) {
        for (id, card) in cards where id != bufferID && (card.isNothingNew || !exists(id)) {
            dismiss(id)
        }
        for id in stretches.keys where !exists(id) {
            stretches[id] = nil
            stretchOrder.removeAll { $0 == id }
        }
    }

    /// Closes every card and stops their summaries (unless Siri is waiting
    /// for one): Catch me up was turned off.
    public func closeAll() {
        for id in cards.keys { dismiss(id) }
    }

    // MARK: Siri and Shortcuts

    /// The finished summary of `request`, from the cache when possible.
    /// Shares the work with an open card summarizing the same stretch.
    /// Errors are ``CatchUpError``s (or `CancellationError`).
    ///
    /// - Parameter urgent: Someone is waiting on it (Siri): it goes to the
    ///   front of the queue, after the summary being written now.
    public func summary(for request: CatchUpRequest, urgent: Bool = false) async throws -> CatchUpSummary {
        guard let summary = try await summary(for: request, urgent: urgent, patience: nil) else {
            throw CancellationError()
        }
        return summary
    }

    /// As ``summary(for:urgent:)``, waiting at most `patience`. Returns nil
    /// when the summary isn't ready by then. It keeps being written, held
    /// for the caller, who either opens its card (``open(_:marker:reveal:)``
    /// with the same request, which takes it over) or lets go of it with
    /// ``release(_:)``. Siri uses this to hand a long wait over to the card.
    public func summary(for request: CatchUpRequest, urgent: Bool, patience: Duration?) async throws -> CatchUpSummary? {
        guard !request.lines.isEmpty else { throw CatchUpError.nothingToSummarize }
        let key = CatchUpRangeKey(request)
        if let cached = cache[key] {
            touch(key)
            return cached
        }
        let job: Job
        if let existing = jobs[key] {
            job = existing
            if urgent { moveToFront(job) }
        } else {
            job = startJob(request, key: key, urgent: urgent)
        }
        let token = UUID()
        let timer = patience.map { patience in
            Task { [weak self] in
                guard (try? await Task.sleep(for: patience)) != nil else { return }
                self?.expire(token, of: job)
            }
        }
        defer { timer?.cancel() }
        do {
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    if let result = job.result {
                        continuation.resume(with: result.map { Optional($0) })
                    } else {
                        job.waiters[token] = continuation
                    }
                }
            } onCancel: {
                Task { @MainActor [weak self] in
                    if let self {
                        self.stopWaiting(token, for: job)
                    } else {
                        job.waiters.removeValue(forKey: token)?.resume(throwing: CancellationError())
                    }
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Self.catchUpError(error)
        }
    }

    /// Lets go of a summary ``summary(for:urgent:patience:)`` held when its
    /// patience ran out. It stops, unless a card shows it or someone else
    /// is waiting for it.
    public func release(_ request: CatchUpRequest) {
        let key = CatchUpRangeKey(request)
        guard let job = jobs[key], job.holds > 0 else { return }
        job.holds -= 1
        if !job.isWanted, attachedCard(key) == nil { stop(job) }
    }

    /// The cached summary of `request`, if there is one.
    public func cachedSummary(for request: CatchUpRequest) -> CatchUpSummary? {
        cache[CatchUpRangeKey(request)]
    }

    /// How `request` would be summarized (see ``ConversationSummarizer/plan(_:)``).
    public func plan(for request: CatchUpRequest) async -> CatchUpPlan {
        await summarizer.plan(request)
    }

    // MARK: Jobs

    /// One summary being written, or waiting its turn. Summaries are
    /// written one at a time, in the order they were asked for (Siri's
    /// first), so a Mac with little memory never runs several at once.
    @MainActor
    private final class Job {
        enum Turn {
            /// In the queue.
            case waiting
            /// Its summary is being written (or about to be).
            case started
            /// Taken out of the queue before its turn.
            case withdrawn
        }

        let key: CatchUpRangeKey
        let request: CatchUpRequest
        /// Set right after init (the task refers back to its job).
        var task: Task<CatchUpSummary, Error>!
        var latest: CatchUpSummary?
        private(set) var turn = Turn.waiting
        /// The task, waiting for its turn.
        private var turnContinuation: CheckedContinuation<Snapshots, Error>?
        /// The summary started before the task got to wait for it.
        private var started: Snapshots?
        /// Callers of `summary(for:)` waiting for this job.
        var waiters: [UUID: CheckedContinuation<CatchUpSummary?, Error>] = [:]
        /// Siri gave up waiting and is handing the summary to its card.
        var holds = 0
        /// How it ended.
        private(set) var result: Result<CatchUpSummary, Error>?

        typealias Snapshots = AsyncThrowingStream<CatchUpSummary, Error>

        init(key: CatchUpRangeKey, request: CatchUpRequest) {
            self.key = key
            self.request = request
        }

        /// Someone besides a card wants it.
        var isWanted: Bool { !waiters.isEmpty || holds > 0 }

        /// The summary's snapshots, once the store starts this job; throws
        /// `CancellationError` if it's withdrawn (or its task cancelled)
        /// first.
        func waitForTurn() async throws -> Snapshots {
            switch turn {
            case .started: return try takeStarted()
            case .withdrawn: throw CancellationError()
            case .waiting: break
            }
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    switch turn {
                    case .started: continuation.resume(with: Result { try takeStarted() })
                    case .withdrawn: continuation.resume(throwing: CancellationError())
                    case .waiting: turnContinuation = continuation
                    }
                }
            } onCancel: {
                Task { @MainActor in self.withdraw() }
            }
        }

        /// Its turn: the summarizer has started on it, writing `snapshots`.
        /// Called the moment the turn comes, so the summary starts then.
        func start(_ snapshots: Snapshots) {
            guard turn == .waiting else { return }
            turn = .started
            if let turnContinuation {
                turnContinuation.resume(returning: snapshots)
                self.turnContinuation = nil
            } else {
                started = snapshots
            }
        }

        private func takeStarted() throws -> Snapshots {
            guard let snapshots = started else { throw CancellationError() }
            started = nil
            return snapshots
        }

        func withdraw() {
            guard turn == .waiting else { return }
            turn = .withdrawn
            turnContinuation?.resume(throwing: CancellationError())
            turnContinuation = nil
        }

        /// The job ended: everyone waiting gets the result.
        func finish(_ result: Result<CatchUpSummary, Error>) {
            self.result = result
            let waiting = Array(waiters.values)
            waiters.removeAll()
            for waiter in waiting { waiter.resume(with: result.map { Optional($0) }) }
        }
    }

    private func start(_ card: CatchUpCard) {
        if let cached = cache[card.key] {
            touch(card.key)
            card.phase = .done(cached)
            card.summariesAhead = nil
            return
        }
        let job = jobs[card.key] ?? startJob(card.request, key: card.key)
        card.phase = .running(job.latest)
        updatePlaces()
    }

    /// A new job for `request`, queued: at the end, or `urgent`ly at the
    /// front. It starts at once when nothing else is being summarized.
    private func startJob(_ request: CatchUpRequest, key: CatchUpRangeKey, urgent: Bool = false) -> Job {
        let job = Job(key: key, request: request)
        job.task = Task { [weak self] in
            do {
                let stream = try await job.waitForTurn()
                try Task.checkCancellation()
                var last: CatchUpSummary?
                for try await snapshot in stream {
                    try Task.checkCancellation()
                    last = snapshot
                    self?.progress(snapshot, of: job)
                }
                try Task.checkCancellation()
                guard var final = last else { throw CatchUpError.nothingToSummarize }
                final.isComplete = true
                final.isRevising = false
                final.progress = nil
                self?.complete(final, of: job)
                job.finish(.success(final))
                self?.ended(job)
                return final
            } catch {
                self?.fail(error, of: job)
                job.finish(.failure(error))
                self?.ended(job)
                throw error
            }
        }
        jobs[key] = job
        if urgent { queue.insert(job, at: 0) } else { queue.append(job) }
        startNext()
        return job
    }

    /// Starts the next job in the queue if none is being written, and
    /// tells queued cards their place.
    private func startNext() {
        while running == nil, !queue.isEmpty {
            let next = queue.removeFirst()
            guard next.turn == .waiting else { continue }
            running = next
            next.start(summarizer.summarize(next.request))
        }
        updatePlaces()
    }

    /// `job`'s task is over (done, failed or stopped): the next one's turn.
    private func ended(_ job: Job) {
        queue.removeAll { $0 === job }
        if running === job { running = nil }
        startNext()
    }

    /// Siri is waiting for a queued `job`: it goes next.
    private func moveToFront(_ job: Job) {
        guard let index = queue.firstIndex(where: { $0 === job }), index > 0 else { return }
        queue.remove(at: index)
        queue.insert(job, at: 0)
        updatePlaces()
    }

    /// Stops `job`: takes it out of the queue, or cancels it while it's
    /// being written (which then lets the next one start).
    private func stop(_ job: Job) {
        job.task.cancel()
        if jobs[job.key] === job { jobs[job.key] = nil }
        if let index = queue.firstIndex(where: { $0 === job }) {
            queue.remove(at: index)
            job.withdraw()
        }
        updatePlaces()
    }

    /// Each queued card's ``CatchUpCard/summariesAhead``. Cheap: one pass
    /// over a queue no longer than the open cards (and Siri's request).
    private func updatePlaces() {
        if let running, let card = attachedCard(of: running), card.summariesAhead != nil {
            card.summariesAhead = nil
        }
        // One that's been stopped is about to make way: don't count it.
        let ahead = running.map { $0.task.isCancelled ? 0 : 1 } ?? 0
        for (index, job) in queue.enumerated() {
            guard let card = attachedCard(of: job), card.summariesAhead != ahead + index else { continue }
            card.summariesAhead = ahead + index
        }
    }

    private func progress(_ snapshot: CatchUpSummary, of job: Job) {
        guard jobs[job.key] === job else { return }
        var snapshot = snapshot
        // Words never disappear: a snapshot without any keeps the ones
        // shown so far, dimmed, until the summarizer writes again.
        if !snapshot.hasText, let shown = job.latest, shown.hasText {
            var kept = shown
            kept.isRevising = true
            kept.progress = snapshot.progress
            kept.skippedMessages = snapshot.skippedMessages
            kept.venue = snapshot.venue
            kept.cloudFallback = snapshot.cloudFallback
            snapshot = kept
        }
        job.latest = snapshot
        if let card = attachedCard(job.key), card.isRunning { card.phase = .running(snapshot) }
    }

    private func complete(_ summary: CatchUpSummary, of job: Job) {
        guard jobs[job.key] === job else { return }
        jobs[job.key] = nil
        store(summary, for: job.key)
        attachedCard(job.key)?.phase = .done(summary)
    }

    private func fail(_ error: Error, of job: Job) {
        guard jobs[job.key] === job else { return }
        jobs[job.key] = nil
        guard !(error is CancellationError) else { return }
        attachedCard(job.key)?.phase = .failed(Self.catchUpError(error))
    }

    private func attachedCard(_ key: CatchUpRangeKey) -> CatchUpCard? {
        guard let card = cards[key.bufferID], card.key == key else { return nil }
        return card
    }

    /// The card showing `job`, while it's the job for the card's stretch.
    private func attachedCard(of job: Job) -> CatchUpCard? {
        guard jobs[job.key] === job else { return nil }
        return attachedCard(job.key)
    }

    /// The card showing `key` closed or moved on: stop its job, unless
    /// Siri is waiting for the same summary.
    private func detach(_ key: CatchUpRangeKey) {
        guard let job = jobs[key], !job.isWanted else { return }
        stop(job)
    }

    /// A caller of ``summary(for:urgent:patience:)`` stopped waiting
    /// (Siri gave up). Its job stops too, unless a card shows it or
    /// someone else still wants it.
    private func stopWaiting(_ token: UUID, for job: Job) {
        job.waiters.removeValue(forKey: token)?.resume(throwing: CancellationError())
        guard !job.isWanted else { return }
        if jobs[job.key] !== job || attachedCard(job.key) == nil { stop(job) }
    }

    /// `token`'s patience ran out: it stops waiting, and the job is held
    /// for it until it opens the card or lets go (``release(_:)``).
    private func expire(_ token: UUID, of job: Job) {
        guard let waiter = job.waiters.removeValue(forKey: token) else { return }
        job.holds += 1
        waiter.resume(returning: nil)
    }

    private func isFailed(_ card: CatchUpCard) -> Bool {
        if case .failed = card.phase { true } else { false }
    }

    static func catchUpError(_ error: Error) -> CatchUpError {
        if let error = error as? CatchUpError { return error }
        return .failed(error.localizedDescription)
    }

    // MARK: Cache

    /// Remembers `request` as its buffer's latest stretch, for the session.
    private func remember(_ request: CatchUpRequest, marker: Date?) {
        stretches[request.bufferID] = Stretch(request: request, marker: marker)
        stretchOrder.removeAll { $0 == request.bufferID }
        stretchOrder.append(request.bufferID)
        while stretchOrder.count > cacheLimit {
            stretches[stretchOrder.removeFirst()] = nil
        }
    }

    private func store(_ summary: CatchUpSummary, for key: CatchUpRangeKey) {
        cache[key] = summary
        touch(key)
        while cacheOrder.count > cacheLimit {
            cache[cacheOrder.removeFirst()] = nil
        }
    }

    private func touch(_ key: CatchUpRangeKey) {
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
    }

    private func forget(_ key: CatchUpRangeKey) {
        cache[key] = nil
        cacheOrder.removeAll { $0 == key }
    }
}
