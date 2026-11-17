// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Observation
import VelaCore
import VelaIRC
import VelaIntelligence

/// A line's translation, as the message list shows it.
enum LineTranslationState: Equatable {
    case translating(source: Locale.Language)
    case translated(text: String, source: Locale.Language)
    case failed(reason: String, source: Locale.Language)
    /// The reader hid it. Automatic translation leaves it hidden.
    case hidden

    var isShowing: Bool {
        switch self {
        case .translating, .translated, .failed: true
        case .hidden: false
        }
    }
}

/// Where a message list translates into, and whether it does so on its own.
/// Set by `translationHost(buffer:)` for the rows below it.
struct TranslationContext: Equatable {
    var target: Locale.Language
    /// The buffer (or its network) is in `translation.autoTranslate`.
    var isAutomatic: Bool
    /// Demo mode: canned translations, no Translation framework.
    var isDemo: Bool
}

/// Per-line translation state for the message lists (translating,
/// translated, failed, hidden). One per app, in the SwiftUI environment.
///
/// Rows ask for a line to be translated; requests go through a
/// `TranslationQueue` (batched per language, a few batches at a time) to a
/// `MessageTranslator`. Detected languages and finished translations are
/// cached by line id, so scrolling back or hiding and showing again never
/// translates twice. Everything is bounded: the oldest lines' state goes
/// first. A deleted (redacted) message's translation is dropped.
@Observable
final class TranslationStore {
    /// Lines with a translation shown, in progress, failed or hidden.
    private(set) var states: BoundedDictionary<UUID, LineTranslationState>

    /// Downloads waiting for the chat view's translation task (live
    /// translator only).
    private(set) var downloads: TranslationDownloads?

    @ObservationIgnored private var translator: (any MessageTranslator)?
    @ObservationIgnored private var queue: TranslationQueue?
    @ObservationIgnored private let detector = MessageLanguageDetector()
    @ObservationIgnored private let collectionDelay: Duration

    /// The language of each line looked at; nil when it isn't one to translate.
    @ObservationIgnored private var detections = BoundedDictionary<UUID, Locale.Language?>(limit: 20_000)
    /// Finished translations, kept when hidden.
    @ObservationIgnored private var translations = BoundedDictionary<UUID, Translation>(limit: 5_000)
    /// Text and source of each line asked for, to translate again into a new target.
    @ObservationIgnored private var sources = BoundedDictionary<UUID, Source>(limit: 5_000)
    /// The attempt each line waits for; results of older attempts are dropped.
    @ObservationIgnored private var attempts: [UUID: Attempt] = [:]
    @ObservationIgnored private var pairStatus: [TranslationPair: TranslationPairStatus] = [:]
    /// Pairs whose download the reader declined; automatic translation skips them.
    @ObservationIgnored private var declinedPairs: Set<TranslationPair> = []
    @ObservationIgnored private var supportedCodes: Set<String>?
    /// The target the lines on show were translated into.
    @ObservationIgnored private var currentTarget: Locale.Language?
    /// Message rows on screen (or about to be), as the list builds them.
    @ObservationIgnored private var onScreen: Set<UUID> = []
    /// Lines still showing a translation into a previous target; redone
    /// when their row next appears.
    @ObservationIgnored private var staleLines: Set<UUID> = []
    @ObservationIgnored private var supportedLanguagesCache: [Locale.Language]?

    private struct Translation {
        var text: String
        var source: Locale.Language
        var target: Locale.Language
    }

    private struct Source {
        var text: String
        var language: Locale.Language
    }

    private struct Attempt {
        var lineID: UUID
        var pair: TranslationPair
        var isAutomatic: Bool
    }

    /// - Parameters:
    ///   - translator: Fixed translator (tests). By default the store picks
    ///     the live one, or canned text in demo mode, on first use.
    ///   - stateLimit: How many lines' states to keep (tests use fewer).
    init(translator: (any MessageTranslator)? = nil, collectionDelay: Duration = .milliseconds(120), stateLimit: Int = 5_000) {
        self.translator = translator
        self.collectionDelay = collectionDelay
        self.states = BoundedDictionary(limit: stateLimit)
    }

    // MARK: Setup

    /// Picks the translator (live, or canned in demo mode) the first time.
    func prepare(isDemo: Bool) {
        guard queue == nil else { return }
        let translator: any MessageTranslator
        if let injected = self.translator {
            translator = injected
        } else if isDemo {
            translator = CannedTranslator.demo()
        } else {
            let live = LiveMessageTranslator()
            downloads = live.downloads
            translator = live
        }
        self.translator = translator
        let queue = TranslationQueue(translator: translator, collectionDelay: collectionDelay)
        queue.onResult = { [weak self] id, result in self?.finish(id, result) }
        self.queue = queue
        Task { [weak self] in
            let languages = await translator.supportedLanguages()
            self?.supportedLanguagesCache = languages
            self?.supportedCodes = Set(languages.compactMap { $0.languageCode?.identifier })
        }
    }

    /// The language to translate into: `translation.language`, or the Mac's
    /// language when that's empty (English in demo mode, whose lines are).
    static func target(setting: String, isDemo: Bool) -> Locale.Language {
        TranslationTarget.resolve(setting: setting, preferredLanguages: isDemo ? ["en"] : Locale.preferredLanguages)
    }

    /// The languages to offer in "Translate into".
    func supportedLanguages(isDemo: Bool) async -> [Locale.Language] {
        prepare(isDemo: isDemo)
        if let supportedLanguagesCache { return supportedLanguagesCache }
        guard let translator else { return [] }
        let languages = await translator.supportedLanguages()
        supportedLanguagesCache = languages
        return languages
    }

    // MARK: Reading

    func state(for lineID: UUID) -> LineTranslationState? {
        states[lineID]
    }

    /// The language to offer translating `line` from: when it's someone
    /// else's message, clearly in one language, not the target, and the
    /// pair can be translated. Nil otherwise.
    func offer(for line: ChatLine, in buffer: BufferModel, context: TranslationContext) -> Locale.Language? {
        guard line.kind.isConversation, !line.isSelf, !line.isRedacted,
              let source = detectedLanguage(of: line, in: buffer),
              !source.isSameTranslationLanguage(as: context.target)
        else { return nil }
        prepare(isDemo: context.isDemo)
        return canTranslate(TranslationPair(source: source, target: context.target)) ? source : nil
    }

    /// The line's language, detected once and cached.
    func detectedLanguage(of line: ChatLine, in buffer: BufferModel?) -> Locale.Language? {
        if let cached = detections[line.id] { return cached }
        let detected = detector.detect(line.text) { word in
            guard let buffer else { return false }
            return word.caseInsensitiveCompare(line.nick ?? "") == .orderedSame
                || buffer.member(named: String(word)) != nil
        }?.language
        detections[line.id] = .some(detected)
        return detected
    }

    // MARK: Actions

    /// Translates `line` from `source` into the context's target, from the
    /// cache when it's been translated before.
    func translate(_ line: ChatLine, from source: Locale.Language, context: TranslationContext, isAutomatic: Bool = false) {
        guard !line.isRedacted else {
            forget(line.id)
            return
        }
        let text = IRCFormatting.strip(line.text)
        sources[line.id] = Source(text: text, language: source)
        if currentTarget == nil { currentTarget = context.target }
        if let cached = translations[line.id], cached.target == context.target {
            states[line.id] = .translated(text: cached.text, source: cached.source)
            return
        }
        prepare(isDemo: context.isDemo)
        request(line.id, text: text, pair: TranslationPair(source: source, target: context.target), isAutomatic: isAutomatic)
    }

    /// Translates `line` if its buffer translates automatically and it's in
    /// another language. Lines already translated, failed or hidden are
    /// left alone, and so are pairs that can't be translated or whose
    /// download was declined.
    func autoTranslate(_ line: ChatLine, in buffer: BufferModel, context: TranslationContext) {
        guard context.isAutomatic, states[line.id] == nil,
              let source = offer(for: line, in: buffer, context: context)
        else { return }
        let pair = TranslationPair(source: source, target: context.target)
        guard !declinedPairs.contains(pair) else { return }
        translate(line, from: source, context: context, isAutomatic: true)
    }

    /// Hides the line's translation; Translate shows it again.
    func hide(_ lineID: UUID) {
        attempts = attempts.filter { $0.value.lineID != lineID }
        states[lineID] = .hidden
    }

    /// Translates the line again, skipping the cache.
    func translateAgain(_ line: ChatLine, in buffer: BufferModel, context: TranslationContext) {
        translations[line.id] = nil
        guard let source = sources[line.id]?.language ?? detectedLanguage(of: line, in: buffer) else { return }
        translate(line, from: source, context: context)
    }

    /// The target language changed: translations on screen are redone in
    /// it at once, the others when their rows next appear (see
    /// ``rowAppeared(_:context:)``), so a long scrollback isn't translated
    /// again all at once. Called whenever a chat appears or its target
    /// changes; does nothing while the target stays the same.
    func retarget(to target: Locale.Language, isDemo: Bool) {
        let previous = currentTarget
        currentTarget = target
        guard let previous, previous != target else { return }
        staleLines.removeAll()
        let showing = states.dictionary.compactMap { id, state in Self.followsTarget(state) ? id : nil }
        for id in showing {
            guard let source = sources[id] else { continue }
            if source.language.isSameTranslationLanguage(as: target) {
                states[id] = nil
                continue
            }
            if let cached = translations[id], cached.target == target {
                states[id] = .translated(text: cached.text, source: cached.source)
                continue
            }
            if onScreen.contains(id) {
                redo(id, source: source, target: target, isDemo: isDemo)
            } else {
                staleLines.insert(id)
            }
        }
    }

    // MARK: Rows

    /// A message row came on screen. A translation left in a previous
    /// target by ``retarget(to:isDemo:)`` is redone now; a deleted
    /// message's is dropped.
    func rowAppeared(_ line: ChatLine, context: TranslationContext?) {
        guard !line.isRedacted else {
            forget(line.id)
            return
        }
        onScreen.insert(line.id)
        guard staleLines.remove(line.id) != nil, let context, let source = sources[line.id],
              let state = states[line.id], Self.followsTarget(state)
        else { return }
        redo(line.id, source: source, target: context.target, isDemo: context.isDemo)
    }

    func rowDisappeared(_ lineID: UUID) {
        onScreen.remove(lineID)
    }

    /// Forgets the line's translation, its text and anything in flight:
    /// its message was deleted.
    func forget(_ lineID: UUID) {
        attempts = attempts.filter { $0.value.lineID != lineID }
        if states[lineID] != nil { states[lineID] = nil }
        translations[lineID] = nil
        sources[lineID] = nil
        staleLines.remove(lineID)
    }

    /// Translating or translated: redone when the target changes. (Failed
    /// and hidden lines show nothing in any target.)
    private static func followsTarget(_ state: LineTranslationState) -> Bool {
        switch state {
        case .translating, .translated: true
        case .failed, .hidden: false
        }
    }

    private func redo(_ lineID: UUID, source: Source, target: Locale.Language, isDemo: Bool) {
        prepare(isDemo: isDemo)
        request(lineID, text: source.text, pair: TranslationPair(source: source.language, target: target), isAutomatic: false)
    }

    // MARK: Queue

    private func request(_ lineID: UUID, text: String, pair: TranslationPair, isAutomatic: Bool) {
        guard let queue else { return }
        attempts = attempts.filter { $0.value.lineID != lineID }
        let attemptID = UUID()
        attempts[attemptID] = Attempt(lineID: lineID, pair: pair, isAutomatic: isAutomatic)
        states[lineID] = .translating(source: pair.source)
        queue.enqueue([TranslationQueue.Request(id: attemptID, text: text, pair: pair)])
    }

    private func finish(_ attemptID: UUID, _ result: Result<String, TranslationFailure>) {
        guard let attempt = attempts.removeValue(forKey: attemptID) else { return }
        let lineID = attempt.lineID
        let source = attempt.pair.source
        switch result {
        case .success(let text):
            translations[lineID] = Translation(text: text, source: source, target: attempt.pair.target)
            pairStatus[attempt.pair] = .installed
            // Downloaded after all (a later Translate): automatic translation
            // picks the pair up again.
            declinedPairs.remove(attempt.pair)
            states[lineID] = .translated(text: text, source: source)
        case .failure(.cancelled):
            states[lineID] = nil
        case .failure(.unsupportedPair):
            pairStatus[attempt.pair] = .unsupported
            states[lineID] = attempt.isAutomatic ? nil : .failed(reason: Self.reason(for: .unsupportedPair, pair: attempt.pair), source: source)
        case .failure(.notDownloaded):
            declinedPairs.insert(attempt.pair)
            states[lineID] = attempt.isAutomatic ? nil : .failed(reason: Self.reason(for: .notDownloaded, pair: attempt.pair), source: source)
        case .failure(let failure):
            states[lineID] = .failed(reason: Self.reason(for: failure, pair: attempt.pair), source: source)
        }
    }

    /// Whether `pair` is worth offering: not known to be unsupported, and
    /// both languages among the supported ones once those are known.
    private func canTranslate(_ pair: TranslationPair) -> Bool {
        if let status = pairStatus[pair] { return status != .unsupported }
        checkStatus(of: pair)
        guard let supportedCodes else { return true }
        return [pair.source, pair.target].allSatisfy { language in
            language.languageCode.map { supportedCodes.contains($0.identifier) } ?? false
        }
    }

    @ObservationIgnored private var checkingPairs: Set<TranslationPair> = []

    /// Asks the translator about `pair` once, for later offers.
    private func checkStatus(of pair: TranslationPair) {
        guard let translator, !checkingPairs.contains(pair) else { return }
        checkingPairs.insert(pair)
        Task { [weak self] in
            let status = await translator.status(from: pair.source, to: pair.target)
            self?.pairStatus[pair] = status
        }
    }

    static func reason(for failure: TranslationFailure, pair: TranslationPair) -> String {
        let source = pair.source.translationDisplayName()
        let target = pair.target.translationDisplayName()
        switch failure {
        case .unsupportedPair: return "Translating \(source) into \(target) isn't available on this Mac."
        case .notDownloaded: return "\(source) isn't downloaded on this Mac."
        case .cancelled: return "Translation was cancelled."
        case .failed(let message): return message
        }
    }
}

/// A dictionary that forgets its oldest entries past `limit`.
struct BoundedDictionary<Key: Hashable, Value> {
    let limit: Int
    private var storage: [Key: Value] = [:]
    private var order: [Key] = []

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    var count: Int { storage.count }

    /// The entries, in no order.
    var dictionary: [Key: Value] { storage }

    subscript(key: Key) -> Value? {
        get { storage[key] }
        set {
            guard let newValue else {
                storage[key] = nil
                return
            }
            if storage.updateValue(newValue, forKey: key) == nil { order.append(key) }
            trim()
        }
    }

    /// Drops the oldest fifth once over the limit, so trimming stays rare.
    private mutating func trim() {
        guard storage.count > limit else { return }
        order.removeAll { storage[$0] == nil }
        let excess = storage.count - limit + limit / 5
        for key in order.prefix(excess) { storage[key] = nil }
        order.removeFirst(min(excess, order.count))
    }
}
