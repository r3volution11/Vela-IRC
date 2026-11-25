// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Observation
import VelaCore
import VelaStore

/// One Recap window's report: reading the messages for its scope, the
/// summary as it's written, and More detail on its topics and notes.
/// Lives only as long as its window: nothing is saved, and closing the
/// window (``close()``) stops whatever is running.
///
/// Reading the messages:
///
///     gathering ──▶ ready
///               ├─▶ needsSpan   nothing unread: asks how far back
///               └─▶ empty       nothing in the scope and span
///
/// The summary, once there are messages and the output is Summary:
///
///     idle ──▶ estimating ──▶ running ──▶ done
///                   │            ├─▶ stopped (Stop; what was written stays)
///                   │            └─▶ failed
///                   └─▶ confirming (a long one: "About 2 minutes · Start")
///
/// and `unavailable` while Apple Intelligence can't run. A log needs
/// none of it.
@Observable
public final class RecapSession {
    public enum Phase: Equatable, Sendable {
        case gathering
        case ready
        /// "Since your first unread", with nothing unread: pick a span.
        case needsSpan
        /// Nothing matches the scope.
        case empty
    }

    public enum SummaryPhase: Equatable, Sendable {
        case idle
        case unavailable(IntelligenceStatus)
        case estimating
        /// Long enough to ask before starting.
        case confirming(RecapPlan)
        case running
        case done
        /// Stopped before it finished; what was written so far stays.
        case stopped
        case failed(CatchUpError)
    }

    /// More detail on one item.
    public enum DetailState: Equatable, Sendable {
        /// Waiting its turn, or being written (with what's written so far).
        case loading(RecapDetail?)
        case done(RecapDetail)
        case failed(String)

        public var detail: RecapDetail? {
            switch self {
            case .loading(let detail): detail
            case .done(let detail): detail
            case .failed: nil
            }
        }
    }

    public private(set) var scope: RecapScope
    public private(set) var phase: Phase = .gathering
    public private(set) var summaryPhase: SummaryPhase = .idle
    public private(set) var input: RecapInput?
    public private(set) var findings = RecapFindings()
    public private(set) var summary: RecapSummary?
    /// More detail, by item id (a topic's, a note's or a "for you" line's).
    public private(set) var details: [String: DetailState] = [:]
    /// The model asked for in this window (its Change menu, "Recap
    /// With…"); nil follows Recap's setting.
    public private(set) var model: AIModelChoice?

    @ObservationIgnored private let gatherer: @MainActor (RecapScope) async -> RecapInput
    @ObservationIgnored private let summarizer: any RecapSummarizer
    @ObservationIgnored private let status: @MainActor () -> IntelligenceStatus
    @ObservationIgnored private let linkTitles: @Sendable ([URL]) async -> [URL: String]
    @ObservationIgnored private var gatherTask: Task<Void, Never>?
    @ObservationIgnored private var summaryTask: Task<Void, Never>?
    @ObservationIgnored private var detailTasks: [String: Task<Void, Never>] = [:]
    /// Bumped whenever the scope's messages are read again, so a late
    /// result from before is ignored.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isClosed = false

    /// - Parameters:
    ///   - gather: Reads the scope's messages (``RecapGatherer/gather(_:now:)``).
    ///   - status: Whether the summary can be written now: Apple
    ///     Intelligence's status, or available when Recap uses one of
    ///     your providers' models.
    ///   - linkTitles: Titles of link previews already in memory.
    ///   - model: The model to write with; nil follows Recap's setting.
    public init(
        scope: RecapScope,
        gather: @escaping @MainActor (RecapScope) async -> RecapInput,
        summarizer: any RecapSummarizer,
        status: @escaping @MainActor () -> IntelligenceStatus,
        linkTitles: @escaping @Sendable ([URL]) async -> [URL: String] = { _ in [:] },
        model: AIModelChoice? = nil
    ) {
        self.scope = scope
        self.gatherer = gather
        self.summarizer = summarizer
        self.status = status
        self.linkTitles = linkTitles
        self.model = model
    }

    // MARK: Asking

    /// Reads the scope's messages and, for a summary, starts on it (or asks
    /// first, when it's long).
    public func start() {
        load(scope)
    }

    /// Changes what the Recap covers. A new Who, Where or When reads the
    /// messages again; a new output just switches between the summary and
    /// the log (starting the summary the first time it's shown).
    public func update(_ newScope: RecapScope) {
        guard !isClosed, newScope != scope else { return }
        let onlyOutput = RecapScope(place: newScope.place, person: newScope.person, span: newScope.span, output: scope.output) == scope
        scope = newScope
        guard onlyOutput, phase == .ready, let input else {
            load(newScope)
            return
        }
        if newScope.output == .summary, summaryPhase == .idle || isUnavailable { beginSummary(input) }
    }

    /// Starts a long summary after its estimate.
    public func confirm() {
        guard case .confirming = summaryPhase, var input else { return }
        input.model = model
        summarize(input)
    }

    /// Stops the summary being written. What it wrote stays.
    public func stop() {
        guard summaryPhase == .running || summaryPhase == .estimating else { return }
        summaryTask?.cancel()
        summaryTask = nil
        summary?.progress = nil
        summaryPhase = .stopped
    }

    /// Reads the messages again (anything new included) and writes a new
    /// summary. Also Try Again.
    public func regenerate() {
        load(scope)
    }

    /// Writes the summary again with `model` (the Change menu, Try with
    /// Apple Intelligence); nil follows Recap's setting again. Shows the
    /// summary if the log was showing.
    public func rerun(with model: AIModelChoice?) {
        guard !isClosed else { return }
        self.model = model
        if scope.output != .summary { scope.output = .summary }
        load(scope)
    }

    /// More detail on a topic: its messages, read again on their own.
    public func moreDetail(on topic: RecapTopic) {
        guard let conversation = topic.start?.conversation ?? input?.line(topic.lineIDs.first ?? UUID())?.conversation.id else { return }
        var lines = lines(topic.lineIDs, in: conversation)
        // A long topic in a busy channel: the people in it.
        if lines.count > 160, !topic.participants.isEmpty {
            let people = Set(topic.participants.map { $0.lowercased() })
            let focused = lines.filter { line in
                people.contains(line.nick.lowercased())
                    || people.contains { CatchUpTranscript.containsWord($0, in: line.text.lowercased()) }
            }
            if focused.count >= 8 { lines = focused }
        }
        detail(id: topic.id, lines: lines, conversation: conversation, focus: topic.title)
    }

    /// More detail on a decision, question or follow-up: the messages around it.
    public func moreDetail(on note: RecapNote) {
        guard let reference = note.reference else { return }
        let focus = note.owner.map { "\($0): \(note.text)" } ?? note.text
        detail(id: note.id, lines: context(around: reference), conversation: reference.conversation, focus: focus)
    }

    /// Closes More detail on an item (or stops it).
    public func clearDetail(_ id: String) {
        detailTasks.removeValue(forKey: id)?.cancel()
        details[id] = nil
    }

    /// The window closed: stop everything, and forget the report.
    public func close() {
        isClosed = true
        gatherTask?.cancel()
        summaryTask?.cancel()
        for task in detailTasks.values { task.cancel() }
        detailTasks = [:]
        gatherTask = nil
        summaryTask = nil
    }

    // MARK: Reading

    private func load(_ scope: RecapScope) {
        guard !isClosed else { return }
        gatherTask?.cancel()
        summaryTask?.cancel()
        for task in detailTasks.values { task.cancel() }
        detailTasks = [:]
        details = [:]
        summary = nil
        summaryPhase = .idle
        generation += 1
        let generation = generation
        phase = .gathering
        gatherTask = Task { [weak self] in
            guard let self else { return }
            let input = await self.gatherer(scope)
            guard self.generation == generation, !Task.isCancelled else { return }
            self.input = input
            guard !input.isEmpty else {
                self.findings = RecapFindings()
                self.phase = scope.span == .sinceUnread ? .needsSpan : .empty
                return
            }
            var findings = await Self.findings(for: input)
            findings.applyTitles(await self.linkTitles(findings.linkURLs))
            guard self.generation == generation, !Task.isCancelled else { return }
            self.findings = findings
            self.phase = .ready
            if self.scope.output == .summary { self.beginSummary(input) }
        }
    }

    @concurrent
    private nonisolated static func findings(for input: RecapInput) async -> RecapFindings {
        RecapFindings(input)
    }

    // MARK: Summarizing

    private var isUnavailable: Bool {
        if case .unavailable = summaryPhase { true } else { false }
    }



    private func beginSummary(_ gathered: RecapInput) {
        var asked = gathered
        asked.model = model
        let input = asked
        // A provider's model asked for here doesn't need Apple Intelligence.
        let current = model.map { $0.isApple ? status() : .available } ?? status()
        guard current.isAvailable else {
            summaryPhase = .unavailable(current)
            return
        }
        summaryPhase = .estimating
        let generation = generation
        summaryTask = Task { [weak self] in
            guard let self else { return }
            let plan = await self.summarizer.plan(input)
            guard self.generation == generation, !Task.isCancelled, self.summaryPhase == .estimating else { return }
            if plan.asksFirst {
                self.summaryPhase = .confirming(plan)
            } else {
                self.summarize(input)
            }
        }
    }

    private func summarize(_ input: RecapInput) {
        summaryTask?.cancel()
        summaryPhase = .running
        let generation = generation
        let stream = summarizer.recap(input)
        summaryTask = Task { [weak self] in
            do {
                for try await snapshot in stream {
                    guard let self, self.generation == generation, !Task.isCancelled else { return }
                    self.show(snapshot)
                }
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                self.summary?.isComplete = true
                self.summary?.progress = nil
                self.summaryPhase = .done
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                self.summary?.progress = nil
                self.summaryPhase = .failed(CatchUpStore.catchUpError(error))
            }
        }
    }

    /// A snapshot as shown: words that have appeared stay until new ones
    /// take their place (a progress-only snapshot keeps them).
    private func show(_ snapshot: RecapSummary) {
        guard var shown = summary, !snapshot.hasContent else {
            summary = snapshot
            return
        }
        shown.progress = snapshot.progress
        shown.skippedMessages = snapshot.skippedMessages
        shown.venue = snapshot.venue
        shown.cloudFallback = snapshot.cloudFallback
        if !snapshot.notesForYou.isEmpty { shown.notesForYou = snapshot.notesForYou }
        summary = shown
    }

    // MARK: More detail

    private func detail(id: String, lines: [RecapLine], conversation: BufferID, focus: String) {
        guard !isClosed, !lines.isEmpty, summaryPhase != .running else { return }
        if case .loading = details[id] { return }
        detailTasks.removeValue(forKey: id)?.cancel()
        details[id] = .loading(nil)
        let ownNick = input?.conversation(conversation)?.ownNick ?? ""
        let stream = summarizer.detail(RecapDetailRequest(lines: lines, ownNick: ownNick, focus: focus, model: detailModel))
        let generation = generation
        detailTasks[id] = Task { [weak self] in
            do {
                var last: RecapDetail?
                for try await detail in stream {
                    guard let self, self.generation == generation, !Task.isCancelled else { return }
                    last = detail
                    self.details[id] = .loading(detail)
                }
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                var final = last ?? RecapDetail()
                final.isComplete = true
                self.details[id] = final.points.isEmpty ? .failed("Apple Intelligence didn't add anything.") : .done(final)
                self.detailTasks[id] = nil
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                self.details[id] = .failed(CatchUpStore.catchUpError(error).errorDescription ?? "Apple Intelligence couldn't look closer.")
                self.detailTasks[id] = nil
            }
        }
    }

    /// More detail asks the model that wrote the summary: the provider's,
    /// or Apple's on this Mac (More detail is always one short pass).
    private var detailModel: AIModelChoice? {
        switch summary?.venue {
        case .provider(let label): label.choice
        case .onDevice, .privateCloudCompute: .apple(.automatic)
        case nil: model
        }
    }

    /// The lines with `ids` in `conversation`, oldest first.
    private func lines(_ ids: [UUID], in conversation: BufferID) -> [RecapLine] {
        guard let lines = input?.conversation(conversation)?.lines else { return [] }
        let wanted = Set(ids)
        return lines.filter { wanted.contains($0.id) }
    }

    /// A note's message with what led up to it and what followed.
    private func context(around reference: RecapReference, before: Int = 12, after: Int = 30) -> [RecapLine] {
        guard let lines = input?.conversation(reference.conversation)?.lines,
              let index = lines.firstIndex(where: { $0.id == reference.lineID })
        else { return [] }
        return Array(lines[max(0, index - before)..<min(lines.count, index + after + 1)])
    }
}
