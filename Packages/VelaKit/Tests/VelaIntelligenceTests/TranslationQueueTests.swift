// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaIntelligence

/// Records every batch, translates by upper-casing, and can hold batches
/// until released to check how many run at once.
final class RecordingTranslator: MessageTranslator {
    struct Batch: Equatable {
        var texts: [String]
        var source: String
        var target: String
    }

    var batches: [Batch] = []
    var running = 0
    var maxRunning = 0
    var holdsBatches = false
    var failingTexts: Set<String> = []
    var failure: TranslationFailure = .failed("Nope")
    private var held: [CheckedContinuation<Void, Never>] = []

    func status(from source: Locale.Language, to target: Locale.Language) async -> TranslationPairStatus {
        .installed
    }

    func translate(_ texts: [String], from source: Locale.Language, to target: Locale.Language) async throws -> [String] {
        batches.append(Batch(texts: texts, source: source.minimalIdentifier, target: target.minimalIdentifier))
        running += 1
        maxRunning = max(maxRunning, running)
        defer { running -= 1 }
        if holdsBatches { await withCheckedContinuation { held.append($0) } }
        if texts.contains(where: failingTexts.contains) { throw failure }
        return texts.map { $0.uppercased() }
    }

    func supportedLanguages() async -> [Locale.Language] { [] }

    var heldCount: Int { held.count }

    func releaseAll() {
        let waiting = held
        held.removeAll()
        waiting.forEach { $0.resume() }
    }
}

/// Waits (briefly) for `condition`, letting queued tasks run.
@MainActor
func eventually(_ condition: () -> Bool) async {
    for _ in 0..<400 where !condition() {
        try? await Task.sleep(for: .milliseconds(5))
    }
}

@MainActor
@Suite("Translation queue")
struct TranslationQueueTests {
    let ja = Locale.Language(identifier: "ja")
    let es = Locale.Language(identifier: "es")
    let en = Locale.Language(identifier: "en")

    private func request(_ text: String, from source: Locale.Language) -> TranslationQueue.Request {
        TranslationQueue.Request(id: UUID(), text: text, pair: TranslationPair(source: source, target: en))
    }

    private func makeQueue(
        _ translator: RecordingTranslator,
        batchSize: Int = 16,
        concurrent: Int = 2
    ) -> (TranslationQueue, Results) {
        let queue = TranslationQueue(
            translator: translator,
            maxBatchSize: batchSize,
            maxConcurrentBatches: concurrent,
            collectionDelay: .milliseconds(20)
        )
        let results = Results()
        queue.onResult = { id, result in results.values[id] = result }
        return (queue, results)
    }

    final class Results {
        var values: [UUID: Result<String, TranslationFailure>] = [:]
    }

    @Test func requestsArrivingTogetherBatchPerLanguage() async throws {
        let translator = RecordingTranslator()
        let (queue, results) = makeQueue(translator)
        let requests = [
            request("hola", from: es), request("konnichiwa", from: ja),
            request("adiós", from: es), request("sayonara", from: ja), request("gracias", from: es),
        ]
        queue.enqueue(Array(requests.prefix(2)))
        queue.enqueue(Array(requests.dropFirst(2)))
        await eventually { results.values.count == requests.count }

        #expect(translator.batches == [
            .init(texts: ["hola", "adiós", "gracias"], source: "es", target: "en"),
            .init(texts: ["konnichiwa", "sayonara"], source: "ja", target: "en"),
        ])
        for request in requests {
            #expect(try results.values[request.id]?.get() == request.text.uppercased())
        }
        #expect(queue.isIdle)
    }

    @Test func largeGroupsSplitIntoBatches() async {
        let translator = RecordingTranslator()
        let (queue, results) = makeQueue(translator, batchSize: 3)
        let requests = (1...7).map { request("línea \($0)", from: es) }
        queue.enqueue(requests)
        await eventually { results.values.count == 7 }
        #expect(translator.batches.map(\.texts.count) == [3, 3, 1])
        #expect(translator.batches.flatMap(\.texts) == requests.map(\.text))
    }

    @Test func onlyAFewBatchesRunAtOnce() async {
        let translator = RecordingTranslator()
        translator.holdsBatches = true
        let (queue, results) = makeQueue(translator, batchSize: 1, concurrent: 2)
        let requests = (1...5).map { request("frase \($0)", from: es) }
        queue.enqueue(requests)
        await eventually { translator.heldCount == 2 }
        #expect(translator.running == 2)
        #expect(results.values.isEmpty)

        // Each release lets the next ones start, never more than two.
        while results.values.count < 5 {
            translator.releaseAll()
            await eventually { translator.heldCount > 0 || results.values.count == 5 }
        }
        #expect(translator.maxRunning == 2)
        #expect(translator.batches.count == 5)
    }

    @Test func duplicatesAreSkippedWhileQueuedOrRunning() async {
        let translator = RecordingTranslator()
        translator.holdsBatches = true
        let (queue, results) = makeQueue(translator)
        let line = request("hola amigos", from: es)
        queue.enqueue([line])
        queue.enqueue([line])
        #expect(queue.contains(line.id))
        await eventually { translator.heldCount == 1 }
        queue.enqueue([line])
        translator.releaseAll()
        await eventually { results.values.count == 1 }
        try? await Task.sleep(for: .milliseconds(60))
        #expect(translator.batches.count == 1)
        #expect(translator.batches.first?.texts == ["hola amigos"])
    }

    @Test func cancelledRequestsNeverRun() async {
        let translator = RecordingTranslator()
        let (queue, results) = makeQueue(translator)
        let keep = request("hola", from: es)
        let drop = request("adiós", from: es)
        queue.enqueue([keep, drop])
        queue.cancel(drop.id)
        await eventually { results.values.count == 1 }
        try? await Task.sleep(for: .milliseconds(60))
        #expect(translator.batches.flatMap(\.texts) == ["hola"])
        #expect(results.values[drop.id] == nil)
    }

    @Test func oneBadLineDoesntSinkItsBatch() async throws {
        let translator = RecordingTranslator()
        translator.failingTexts = ["roto"]
        let (queue, results) = makeQueue(translator)
        let good = request("bien", from: es)
        let bad = request("roto", from: es)
        queue.enqueue([good, bad])
        await eventually { results.values.count == 2 }
        #expect(try results.values[good.id]?.get() == "BIEN")
        #expect(results.values[bad.id] == .failure(.failed("Nope")))
        // The batch, then each line alone.
        #expect(translator.batches.map(\.texts) == [["bien", "roto"], ["bien"], ["roto"]])
    }

    @Test func unsupportedPairsFailTheWholeBatchAtOnce() async {
        let translator = RecordingTranslator()
        translator.failingTexts = ["uno", "dos"]
        translator.failure = .unsupportedPair
        let (queue, results) = makeQueue(translator)
        let requests = [request("uno", from: es), request("dos", from: es)]
        queue.enqueue(requests)
        await eventually { results.values.count == 2 }
        #expect(requests.allSatisfy { results.values[$0.id] == .failure(.unsupportedPair) })
        #expect(translator.batches.count == 1)
    }

    @Test func flushStartsWithoutWaiting() async {
        let translator = RecordingTranslator()
        let queue = TranslationQueue(translator: translator, collectionDelay: .seconds(60))
        let results = Results()
        queue.onResult = { id, result in results.values[id] = result }
        queue.enqueue([request("hola", from: es)])
        queue.flush()
        await eventually { results.values.count == 1 }
        #expect(results.values.count == 1)
    }
}

@Suite("Canned translator")
struct CannedTranslatorTests {
    @Test func translatesWhatItKnowsAndFailsTheRest() async throws {
        let translator = CannedTranslator(translations: ["hola": "hello"])
        let es = Locale.Language(identifier: "es")
        let en = Locale.Language(identifier: "en")
        #expect(try await translator.translate(["hola"], from: es, to: en) == ["hello"])
        await #expect(throws: TranslationFailure.self) {
            try await translator.translate(["adiós"], from: es, to: en)
        }
        #expect(await translator.status(from: es, to: en) == .installed)
        #expect(await translator.status(from: en, to: Locale.Language(identifier: "en-GB")) == .unsupported)
    }

    @Test func demoTranslationsAreForeignAndEnglish() {
        let detector = MessageLanguageDetector()
        let languages = Set(CannedTranslator.demoTranslations.keys.compactMap {
            detector.detect($0)?.language.languageCode?.identifier
        })
        #expect(languages == ["es", "ja", "de"])
        for translation in CannedTranslator.demoTranslations.values {
            #expect(detector.detect(translation)?.language.languageCode?.identifier == "en")
        }
    }
}
