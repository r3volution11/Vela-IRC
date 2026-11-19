// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaCore
import VelaIntelligence
@testable import VelaUI

/// Translates by upper-casing and counts calls. Spanish and Japanese into
/// English only; anything else is unsupported.
private final class FakeTranslator: MessageTranslator {
    var calls: [[String]] = []
    var failure: TranslationFailure?

    func status(from source: Locale.Language, to target: Locale.Language) async -> TranslationPairStatus {
        ["es", "ja"].contains(source.languageCode?.identifier ?? "") ? .installed : .unsupported
    }

    func translate(_ texts: [String], from source: Locale.Language, to target: Locale.Language) async throws -> [String] {
        calls.append(texts)
        if let failure { throw failure }
        guard await status(from: source, to: target) == .installed else { throw TranslationFailure.unsupportedPair }
        return texts.map { "[\(target.minimalIdentifier)] " + $0.uppercased() }
    }

    func supportedLanguages() async -> [Locale.Language] {
        ["en", "es", "ja", "fr"].map { Locale.Language(identifier: $0) }
    }
}

@MainActor
private func eventually(_ condition: () -> Bool) async {
    for _ in 0..<400 where !condition() {
        try? await Task.sleep(for: .milliseconds(5))
    }
}

@MainActor
@Suite("Translation store")
struct TranslationStoreTests {
    let buffer = BufferModel(id: BufferID(networkID: UUID(), foldedName: "#vela-offtopic"), name: "#vela-offtopic", kind: .channel)
    let english = Locale.Language(identifier: "en")
    let spanish = Locale.Language(identifier: "es")

    private let spanishLine = ChatLine(kind: .message, nick: "marisol", text: "¡Qué envidia! Aquí en Madrid el cielo estaba despejado.")
    private let japaneseLine = ChatLine(kind: .message, nick: "kenji", text: "北海道でもオーロラが見えたらしいよ。")
    private let englishLine = ChatLine(kind: .message, nick: "wren", text: "is it just me or is everyone talking about themes today")
    private let frenchLine = ChatLine(kind: .message, nick: "théo", text: "c'est vraiment génial, bonjour tout le monde")

    private func context(automatic: Bool = false, target: String = "en") -> TranslationContext {
        TranslationContext(target: Locale.Language(identifier: target), isAutomatic: automatic, isDemo: false)
    }

    private func makeStore(_ translator: FakeTranslator, stateLimit: Int = 5_000) -> TranslationStore {
        let store = TranslationStore(translator: translator, collectionDelay: .zero, stateLimit: stateLimit)
        store.prepare(isDemo: false)
        return store
    }

    // MARK: Offering

    @Test func offersOnlyOtherPeoplesLinesInAnotherLanguage() {
        let store = makeStore(FakeTranslator())
        #expect(store.offer(for: spanishLine, in: buffer, context: context()) == spanish)
        #expect(store.offer(for: englishLine, in: buffer, context: context()) == nil)
        #expect(store.offer(for: ChatLine(kind: .message, nick: "wren", text: "jaja sí"), in: buffer, context: context()) == nil)

        var mine = spanishLine
        mine.isSelf = true
        #expect(store.offer(for: mine, in: buffer, context: context()) == nil)
        var deleted = spanishLine
        deleted.isRedacted = true
        #expect(store.offer(for: deleted, in: buffer, context: context()) == nil)
        let event = ChatLine(kind: .join, nick: "marisol", text: spanishLine.text)
        #expect(store.offer(for: event, in: buffer, context: context()) == nil)
    }

    @Test func linesInTheTargetLanguageAreNotOffered() {
        let store = makeStore(FakeTranslator())
        #expect(store.offer(for: spanishLine, in: buffer, context: context(target: "es-MX")) == nil)
        #expect(store.offer(for: englishLine, in: buffer, context: context(target: "es")) != nil)
    }

    /// VoiceOver's actions never detect a language: unknown until something
    /// else (a menu, automatic translation, the action itself) looks.
    @Test func knownOffersNeverDetect() {
        let store = makeStore(FakeTranslator())
        #expect(store.knownOffer(for: spanishLine, context: context()) == .unknown)
        #expect(store.knownOffer(for: englishLine, context: context()) == .unknown)
        var mine = spanishLine
        mine.isSelf = true
        #expect(store.knownOffer(for: mine, context: context()) == .none)
        #expect(store.knownOffer(for: ChatLine(kind: .join, nick: "marisol", text: spanishLine.text), context: context()) == .none)

        _ = store.detectedLanguage(of: spanishLine, in: buffer)
        _ = store.detectedLanguage(of: englishLine, in: buffer)
        #expect(store.knownOffer(for: spanishLine, context: context()) == .translate(from: spanish))
        #expect(store.knownOffer(for: englishLine, context: context()) == .none)
        #expect(store.knownOffer(for: spanishLine, context: context()) == store.offer(for: spanishLine, in: buffer, context: context()).map { .translate(from: $0) })
    }

    @Test func unsupportedPairsStopBeingOffered() async {
        let store = makeStore(FakeTranslator())
        // Not known yet: offered, and the pair gets checked.
        _ = store.offer(for: frenchLine, in: buffer, context: context())
        await eventually { store.offer(for: frenchLine, in: buffer, context: context()) == nil }
        #expect(store.offer(for: frenchLine, in: buffer, context: context()) == nil)
        #expect(store.offer(for: spanishLine, in: buffer, context: context()) == spanish)
    }

    // MARK: States

    @Test func translatingThenTranslated() async {
        let translator = FakeTranslator()
        let store = makeStore(translator)
        store.translate(spanishLine, from: spanish, context: context())
        #expect(store.state(for: spanishLine.id) == .translating(source: spanish))
        await eventually { store.state(for: spanishLine.id) != .translating(source: spanish) }
        #expect(store.state(for: spanishLine.id) == .translated(text: "[en] " + spanishLine.text.uppercased(), source: spanish))
        #expect(translator.calls.count == 1)
    }

    @Test func hidingKeepsTheTranslationForNextTime() async {
        let translator = FakeTranslator()
        let store = makeStore(translator)
        store.translate(spanishLine, from: spanish, context: context())
        await eventually { store.state(for: spanishLine.id)?.isTranslated == true }

        store.hide(spanishLine.id)
        #expect(store.state(for: spanishLine.id) == .hidden)
        #expect(store.state(for: spanishLine.id)?.isShowing == false)

        // Shown again from the cache, without translating.
        store.translate(spanishLine, from: spanish, context: context())
        #expect(store.state(for: spanishLine.id)?.isTranslated == true)
        #expect(translator.calls.count == 1)
    }

    @Test func translateAgainSkipsTheCache() async {
        let translator = FakeTranslator()
        let store = makeStore(translator)
        store.translate(spanishLine, from: spanish, context: context())
        await eventually { store.state(for: spanishLine.id)?.isTranslated == true }
        store.translateAgain(spanishLine, in: buffer, context: context())
        #expect(store.state(for: spanishLine.id) == .translating(source: spanish))
        await eventually { translator.calls.count == 2 && store.state(for: spanishLine.id)?.isTranslated == true }
        #expect(translator.calls.count == 2)
    }

    @Test func hidingWhileTranslatingDropsTheResult() async {
        let translator = FakeTranslator()
        let store = makeStore(translator)
        store.translate(spanishLine, from: spanish, context: context())
        store.hide(spanishLine.id)
        await eventually { translator.calls.count == 1 }
        try? await Task.sleep(for: .milliseconds(30))
        #expect(store.state(for: spanishLine.id) == .hidden)
    }

    @Test func failuresSayWhy() async {
        let translator = FakeTranslator()
        translator.failure = .failed("The service is busy.")
        let store = makeStore(translator)
        store.translate(spanishLine, from: spanish, context: context())
        await eventually { store.state(for: spanishLine.id) != .translating(source: spanish) }
        #expect(store.state(for: spanishLine.id) == .failed(reason: "The service is busy.", source: spanish))
        #expect(store.state(for: spanishLine.id)?.isShowing == true)

        translator.failure = nil
        store.translateAgain(spanishLine, in: buffer, context: context())
        await eventually { store.state(for: spanishLine.id)?.isTranslated == true }
        #expect(store.state(for: spanishLine.id)?.isTranslated == true)
    }

    @Test func aDeclinedDownloadFailsManualTranslationsOnly() async {
        let translator = FakeTranslator()
        translator.failure = .notDownloaded
        let store = makeStore(translator)
        store.translate(spanishLine, from: spanish, context: context())
        await eventually { store.state(for: spanishLine.id) != .translating(source: spanish) }
        guard case .failed(let reason, _) = store.state(for: spanishLine.id) else {
            Issue.record("Expected a failure")
            return
        }
        #expect(reason.contains("Spanish"))

        // Automatic translation leaves that pair alone from now on.
        let another = ChatLine(kind: .message, nick: "marisol", text: "vale, nos vemos mañana en la reunión")
        store.autoTranslate(another, in: buffer, context: context(automatic: true))
        #expect(store.state(for: another.id) == nil)
    }

    @Test func aLaterDownloadBringsAutomaticTranslationBack() async {
        let translator = FakeTranslator()
        translator.failure = .notDownloaded
        let store = makeStore(translator)
        store.translate(spanishLine, from: spanish, context: context())
        await eventually { store.state(for: spanishLine.id) != .translating(source: spanish) }

        // The reader downloads Spanish when asked the next time.
        translator.failure = nil
        store.translateAgain(spanishLine, in: buffer, context: context())
        await eventually { store.state(for: spanishLine.id)?.isTranslated == true }

        let another = ChatLine(kind: .message, nick: "marisol", text: "vale, nos vemos mañana en la reunión")
        store.autoTranslate(another, in: buffer, context: context(automatic: true))
        #expect(store.state(for: another.id) == .translating(source: spanish))
        await eventually { store.state(for: another.id)?.isTranslated == true }
        #expect(store.state(for: another.id)?.isTranslated == true)
    }

    // MARK: Automatic

    @Test func automaticTranslationNeedsAnAutomaticBuffer() async {
        let translator = FakeTranslator()
        let store = makeStore(translator)
        store.autoTranslate(spanishLine, in: buffer, context: context(automatic: false))
        #expect(store.state(for: spanishLine.id) == nil)

        store.autoTranslate(spanishLine, in: buffer, context: context(automatic: true))
        store.autoTranslate(japaneseLine, in: buffer, context: context(automatic: true))
        store.autoTranslate(englishLine, in: buffer, context: context(automatic: true))
        #expect(store.state(for: englishLine.id) == nil)
        await eventually { store.state(for: japaneseLine.id)?.isTranslated == true && store.state(for: spanishLine.id)?.isTranslated == true }
        // One batch per language.
        #expect(translator.calls.count == 2)
    }

    @Test func automaticTranslationLeavesHiddenLinesHidden() async {
        let translator = FakeTranslator()
        let store = makeStore(translator)
        store.hide(spanishLine.id)
        store.autoTranslate(spanishLine, in: buffer, context: context(automatic: true))
        #expect(store.state(for: spanishLine.id) == .hidden)
        #expect(translator.calls.isEmpty)
    }

    @Test func automaticFailuresForUnsupportedPairsStayQuiet() async {
        let translator = FakeTranslator()
        let store = makeStore(translator)
        store.autoTranslate(frenchLine, in: buffer, context: context(automatic: true))
        await eventually { store.state(for: frenchLine.id) == nil }
        #expect(store.state(for: frenchLine.id) == nil)
    }

    @Test func aNewTargetRetranslatesWhatsShowing() async {
        let translator = FakeTranslator()
        let store = makeStore(translator)
        store.translate(spanishLine, from: spanish, context: context())
        store.rowAppeared(spanishLine, context: context())
        await eventually { store.state(for: spanishLine.id)?.isTranslated == true }

        store.retarget(to: Locale.Language(identifier: "ja"), isDemo: false)
        await eventually { translator.calls.count == 2 && store.state(for: spanishLine.id)?.isTranslated == true }
        #expect(store.state(for: spanishLine.id) == .translated(text: "[ja] " + spanishLine.text.uppercased(), source: spanish))

        // Into the line's own language: nothing to show.
        store.retarget(to: Locale.Language(identifier: "es"), isDemo: false)
        #expect(store.state(for: spanishLine.id) == nil)
    }

    @Test func aNewTargetWaitsForRowsOffScreen() async {
        let translator = FakeTranslator()
        let store = makeStore(translator)
        let japanese = Locale.Language(identifier: "ja")
        let other = ChatLine(kind: .message, nick: "marisol", text: "vale, nos vemos mañana en la reunión")
        store.translate(spanishLine, from: spanish, context: context())
        store.translate(other, from: spanish, context: context())
        store.rowAppeared(spanishLine, context: context())
        await eventually { store.state(for: other.id)?.isTranslated == true && store.state(for: spanishLine.id)?.isTranslated == true }
        let calls = translator.calls.flatMap { $0 }.count

        // Only the row on screen is translated again now.
        store.retarget(to: japanese, isDemo: false)
        await eventually { store.state(for: spanishLine.id) == .translated(text: "[ja] " + spanishLine.text.uppercased(), source: spanish) }
        #expect(translator.calls.flatMap { $0 }.count == calls + 1)
        #expect(store.state(for: other.id) == .translated(text: "[en] " + other.text.uppercased(), source: spanish))

        // The other when it comes on screen.
        store.rowAppeared(other, context: context(target: "ja"))
        await eventually { store.state(for: other.id) == .translated(text: "[ja] " + other.text.uppercased(), source: spanish) }
        #expect(translator.calls.flatMap { $0 }.count == calls + 2)

        // Back to English: the row still on screen is redone; the one that
        // scrolled away waits.
        store.rowDisappeared(spanishLine.id)
        store.retarget(to: english, isDemo: false)
        await eventually { store.state(for: other.id) == .translated(text: "[en] " + other.text.uppercased(), source: spanish) }
        #expect(store.state(for: other.id) == .translated(text: "[en] " + other.text.uppercased(), source: spanish))
        #expect(store.state(for: spanishLine.id) == .translated(text: "[ja] " + spanishLine.text.uppercased(), source: spanish))
        #expect(translator.calls.flatMap { $0 }.count == calls + 3)
    }

    @Test func statesAreBounded() {
        let store = makeStore(FakeTranslator(), stateLimit: 10)
        let lines = (0..<50).map { ChatLine(kind: .message, nick: "marisol", text: "línea \($0)") }
        for line in lines { store.hide(line.id) }
        #expect(store.states.count <= 10)
        // The newest are kept.
        #expect(store.state(for: lines[49].id) == .hidden)
        #expect(store.state(for: lines[0].id) == nil)
    }

    // MARK: Deleted messages

    @Test func aDeletedMessageLosesItsTranslation() async {
        let translator = FakeTranslator()
        let store = makeStore(translator)
        store.translate(spanishLine, from: spanish, context: context())
        store.rowAppeared(spanishLine, context: context())
        await eventually { store.state(for: spanishLine.id)?.isTranslated == true }

        var deleted = spanishLine
        deleted.isRedacted = true
        store.rowAppeared(deleted, context: context())
        #expect(store.state(for: spanishLine.id) == nil)
        // Not even from the cache, and not into a new target.
        store.translate(deleted, from: spanish, context: context())
        #expect(store.state(for: spanishLine.id) == nil)
        store.retarget(to: Locale.Language(identifier: "ja"), isDemo: false)
        #expect(store.state(for: spanishLine.id) == nil)
        store.autoTranslate(deleted, in: buffer, context: context(automatic: true))
        #expect(store.state(for: spanishLine.id) == nil)
        #expect(translator.calls.count == 1)
    }

    @Test func deletingWhileTranslatingDropsTheResult() async {
        let translator = FakeTranslator()
        let store = makeStore(translator)
        store.translate(spanishLine, from: spanish, context: context())
        store.forget(spanishLine.id)
        await eventually { translator.calls.count == 1 }
        try? await Task.sleep(for: .milliseconds(30))
        #expect(store.state(for: spanishLine.id) == nil)
    }

    // MARK: Settings, menus and palette

    @Test func demoTranslatesIntoEnglish() {
        #expect(TranslationStore.target(setting: "", isDemo: true).languageCode?.identifier == "en")
        #expect(TranslationStore.target(setting: "fr", isDemo: true).languageCode?.identifier == "fr")
    }

    @Test func automaticTitleCountsChannelsAndNetworks() {
        let network = UUID().uuidString
        #expect(IntelligenceTranslationSection.automaticTitle(["\(network)/#a"]) == "Translated automatically in 1 channel")
        #expect(IntelligenceTranslationSection.automaticTitle(["\(network)/#a", "\(network)/#b", "\(network)/*"])
            == "Translated automatically in 2 channels and 1 network")
    }

    @Test func languageOptionsStartWithTheMac() {
        let languages = ["ja", "de", "pt-PT", "de"].map { Locale.Language(identifier: $0) }
        let options = IntelligenceTranslationSection.options(for: languages, current: "", isDemo: true)
        #expect(options.first?.value == "")
        #expect(options.first?.label.hasPrefix("Same as Mac") == true)
        #expect(options.map(\.value).filter { $0 == "de" }.count == 1)
        // A hand-written code stays selectable.
        let custom = IntelligenceTranslationSection.options(for: languages, current: "uk", isDemo: true)
        #expect(custom.contains { $0.value == "uk" })
    }

    @Test func paletteAndMenuToggleAutomaticTranslation() {
        let app = AppModel.demo()
        app.settings[.translationAutoTranslate] = []
        let network = UUID()
        let channel = BufferID(networkID: network, foldedName: "#vela")
        let command = VelaCommandCatalog.autoTranslateCommand(app: app, bufferID: channel)
        #expect(command.paletteTitle == "Buffer: Translate Messages Automatically")
        #expect(command.isChecked == false)
        command.perform()
        #expect(app.isAutoTranslated(channel))
        #expect(VelaCommandCatalog.autoTranslateCommand(app: app, bufferID: channel).isChecked == true)

        // The whole network: checked and fixed for its channels.
        VelaCommandCatalog.networkAutoTranslateCommand(app: app, networkID: network).perform()
        let other = VelaCommandCatalog.autoTranslateCommand(app: app, bufferID: BufferID(networkID: network, foldedName: "#other"))
        #expect(other.isChecked == true)
        #expect(!other.isEnabled)
        #expect(VelaCommandCatalog.networkAutoTranslateCommand(app: app, networkID: network).isChecked == true)
    }

    @Test func demoTranslatesVelaOfftopic() throws {
        let app = AppModel.demo()
        let libera = try #require(app.sessions.first)
        let offtopic = try #require(libera.buffer(named: "#vela-offtopic"))
        #expect(app.isAutoTranslated(offtopic.id))

        // Every line the demo would translate has a canned translation.
        let store = TranslationStore()
        let context = TranslationContext(target: english, isAutomatic: true, isDemo: true)
        let offered = offtopic.lines.filter { store.offer(for: $0, in: offtopic, context: context) != nil }
        #expect(offered.count == 3)
        for line in offered {
            #expect(CannedTranslator.demoTranslations[line.text] != nil, "\(line.text)")
        }
    }
}

private extension LineTranslationState {
    var isTranslated: Bool {
        if case .translated = self { true } else { false }
    }
}
