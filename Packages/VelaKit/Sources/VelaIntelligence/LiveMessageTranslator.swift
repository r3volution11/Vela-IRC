// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Observation
@preconcurrency import Translation

/// Translates with Apple's Translation framework, on this Mac.
///
/// Pairs whose languages are installed run in a
/// `TranslationSession(installedSource:target:)`. Pairs that need a
/// download go to ``downloads``: the chat view's hidden `.translationTask`
/// opens a session for them, so macOS can ask to download the language,
/// and runs them there.
public final class LiveMessageTranslator: MessageTranslator {
    public let downloads = TranslationDownloads()

    public init() {}

    public func status(from source: Locale.Language, to target: Locale.Language) async -> TranslationPairStatus {
        switch await LanguageAvailability().status(from: source, to: target) {
        case .installed: .installed
        case .supported: .needsDownload
        case .unsupported: .unsupported
        @unknown default: .unsupported
        }
    }

    public func translate(_ texts: [String], from source: Locale.Language, to target: Locale.Language) async throws -> [String] {
        switch await status(from: source, to: target) {
        case .unsupported:
            throw TranslationFailure.unsupportedPair
        case .needsDownload:
            return try await downloads.translate(texts, pair: TranslationPair(source: source, target: target))
        case .installed:
            let session = TranslationSession(installedSource: source, target: target)
            do {
                return try await Self.translate(texts, in: session)
            } catch TranslationFailure.notDownloaded {
                // Removed since the status check: let macOS offer it again.
                return try await downloads.translate(texts, pair: TranslationPair(source: source, target: target))
            }
        }
    }

    public func supportedLanguages() async -> [Locale.Language] {
        await LanguageAvailability().supportedLanguages
    }

    /// Runs one batch in `session`, keeping the order of `texts`.
    /// Nonisolated: the session isn't Sendable and stays with this task.
    nonisolated static func translate(_ texts: [String], in session: TranslationSession) async throws -> [String] {
        let requests = texts.indices.map { TranslationSession.Request(sourceText: texts[$0], clientIdentifier: String($0)) }
        let responses: [TranslationSession.Response]
        do {
            responses = try await session.translations(from: requests)
        } catch {
            throw failure(from: error)
        }
        var results = [String?](repeating: nil, count: texts.count)
        for response in responses {
            guard let index = response.clientIdentifier.flatMap(Int.init), results.indices.contains(index) else { continue }
            results[index] = response.targetText
        }
        guard results.allSatisfy({ $0 != nil }) else {
            throw TranslationFailure.failed("The translation came back incomplete.")
        }
        return results.compactMap { $0 }
    }

    nonisolated static func failure(from error: any Error) -> TranslationFailure {
        if let failure = error as? TranslationFailure { return failure }
        if error is CancellationError { return .cancelled }
        switch error {
        case TranslationError.notInstalled:
            return .notDownloaded
        case TranslationError.unsupportedLanguagePairing,
             TranslationError.unsupportedSourceLanguage,
             TranslationError.unsupportedTargetLanguage,
             TranslationError.unableToIdentifyLanguage:
            return .unsupportedPair
        case TranslationError.alreadyCancelled:
            return .cancelled
        default:
            return .failed(error.localizedDescription)
        }
    }
}

/// Batches that need a language download first.
///
/// The Translation framework only offers a download from a session that a
/// view's `.translationTask` created. The chat view watches ``request``,
/// opens a session for that pair and hands it to ``run(in:)``, which asks
/// macOS to download the languages (`prepareTranslation()`) and then
/// translates every batch waiting for the pair. Pairs are handled one at a
/// time, so only one download prompt shows.
@Observable
public final class TranslationDownloads {
    /// The pair the chat view should open a translation session for; nil
    /// when nothing waits. Each new request has a new id, so asking again
    /// for the same pair (after a declined download) runs the task again.
    public private(set) var request: Request?

    nonisolated public struct Request: Equatable, Sendable {
        public let id: Int
        public let pair: TranslationPair
    }

    nonisolated private struct Job: Sendable {
        let pair: TranslationPair
        let texts: [String]
        let continuation: CheckedContinuation<[String], any Error>
    }

    @ObservationIgnored private var jobs: [Job] = []
    @ObservationIgnored private var nextRequestID = 0

    public init() {}

    /// Translates `texts` once the chat view has a session for `pair`.
    func translate(_ texts: [String], pair: TranslationPair) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            jobs.append(Job(pair: pair, texts: texts, continuation: continuation))
            if request == nil { advance() }
        }
    }

    /// Runs the waiting batches for ``request`` in `session`, a session the
    /// chat view's `.translationTask` made for that pair. Nonisolated, like
    /// the task: the session isn't Sendable and stays with it.
    nonisolated public func run(in session: TranslationSession) async {
        // The task also runs when the view reappears with an older
        // configuration; only a session for the requested pair will do.
        guard let pair = await requestedPair(),
              session.sourceLanguage.map({ $0.isSameTranslationLanguage(as: pair.source) }) == true,
              session.targetLanguage.map({ $0.isSameTranslationLanguage(as: pair.target) }) == true
        else { return }
        do {
            try await session.prepareTranslation()
        } catch {
            // Declined or failed: everything waiting for the pair fails.
            let failure = LiveMessageTranslator.failure(from: error)
            await fail(pair, with: failure == .cancelled ? .notDownloaded : failure)
            return
        }
        while let job = await takeJob(for: pair) {
            do {
                job.continuation.resume(returning: try await LiveMessageTranslator.translate(job.texts, in: session))
            } catch {
                job.continuation.resume(throwing: LiveMessageTranslator.failure(from: error))
            }
        }
        await advance()
    }

    private func requestedPair() -> TranslationPair? {
        request?.pair
    }

    private func takeJob(for pair: TranslationPair) -> Job? {
        guard let index = jobs.firstIndex(where: { $0.pair == pair }) else { return nil }
        return jobs.remove(at: index)
    }

    private func fail(_ pair: TranslationPair, with failure: TranslationFailure) {
        let matching = jobs.filter { $0.pair == pair }
        jobs.removeAll { $0.pair == pair }
        for job in matching { job.continuation.resume(throwing: failure) }
        advance()
    }

    /// Fails everything waiting, e.g. when no chat is on screen to ask from.
    public func cancelAll() {
        let waiting = jobs
        jobs.removeAll()
        for job in waiting { job.continuation.resume(throwing: TranslationFailure.cancelled) }
        request = nil
    }

    /// Requests the next waiting pair, or clears the request.
    private func advance() {
        guard let next = jobs.first?.pair else {
            request = nil
            return
        }
        nextRequestID += 1
        request = Request(id: nextRequestID, pair: next)
    }
}
