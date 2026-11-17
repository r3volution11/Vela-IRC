// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaIntelligence

@Suite("Message language detection")
struct MessageLanguageDetectorTests {
    let detector = MessageLanguageDetector()

    private func code(_ text: String, nicks: Set<String> = []) -> String? {
        detector.detect(text) { nicks.contains($0.lowercased()) }?.language.languageCode?.identifier
    }

    // MARK: Languages

    @Test(arguments: [
        "is it just me or is everyone in #vela talking about themes today",
        "anyone else up late for the geomagnetic storm alerts?",
        "nice, chathistory + reactions are the big ones for me",
        "doug: can you review the sidebar rail PR when you get a sec?",
        "plays inline, and the facade means no web view until you click ▶",
        "pushed the fix, can someone test",
    ])
    func englishIsEnglish(_ line: String) {
        #expect(code(line) == "en")
    }

    /// English chat that isn't clear enough to call stays undetected rather
    /// than being taken for another language.
    @Test(arguments: [
        "sudo apt install neovim",
        "test test test",
        "kk sounds gud",
        "hmm idk tbh",
        "brb lunch",
    ])
    func unclearEnglishIsNotTakenForAnotherLanguage(_ line: String) {
        let detected = code(line)
        #expect(detected == nil || detected == "en", "\(line) → \(detected ?? "nil")")
    }

    @Test(arguments: [
        ("¡Qué envidia! Aquí en Madrid el cielo estaba despejado, pero no se veía nada.", "es"),
        ("vale, nos vemos mañana", "es"),
        ("gracias por todo", "es"),
        ("北海道でもオーロラが見えたらしいよ。写真を撮りに行けばよかったな。", "ja"),
        ("今日はとても寒いですね", "ja"),
        ("おつかれさまでした", "ja"),
        ("Bei uns in Hamburg war es leider die ganze Nacht bewölkt.", "de"),
        ("guten Morgen zusammen", "de"),
        ("das ist echt cool", "de"),
        ("bonjour tout le monde", "fr"),
        ("감사합니다 정말로", "ko"),
        ("привет всем, как дела?", "ru"),
    ])
    func otherLanguagesAreDetected(_ line: String, _ expected: String) {
        #expect(code(line) == expected)
    }

    @Test func chineseKeepsItsScript() {
        let detected = detector.detect("这个主题真好看，我很喜欢")
        #expect(detected?.language.languageCode?.identifier == "zh")
        #expect(detected?.language.script?.identifier == "Hans")
    }

    // MARK: Too little to go on

    @Test(arguments: ["ok", "lol", "brb", "danke!", "jaja sí", "merci", "すごい！", "o/", "xD", "👍"])
    func shortLinesAreSkipped(_ line: String) {
        #expect(detector.detect(line) == nil)
    }

    @Test(arguments: ["😂😂😂", "🎉 🎉 🎉 🙌", ":thumbsup: :tada: :heart_eyes:", "¯\\_(ツ)_/¯"])
    func emojiOnlyLinesAreSkipped(_ line: String) {
        #expect(detector.detect(line) == nil)
    }

    @Test(arguments: [
        "https://upload.wikimedia.org/wikipedia/commons/thumb/d/d3/Aurora_borealis_over_Eielson_Air_Force_Base.jpg",
        "https://www.youtube.com/watch?v=aqz-KE-bpKQ",
        "www.example.com/some/really/long/path/with/words",
        "github.com/r3volution11/Vela-IRC/pulls",
        "#vela #vela-offtopic #swift #macdev",
    ])
    func linksAndChannelsOnlyAreSkipped(_ line: String) {
        #expect(detector.detect(line) == nil)
    }

    @Test func nicksDontCount() {
        let nicks: Set<String> = ["marisol", "kenji", "priya", "wren"]
        // Enough letters only with the nicks.
        #expect(code("marisol kenji priya wren: hola", nicks: nicks) == nil)
        #expect(code("marisol: gracias por todo", nicks: nicks) == "es")
    }

    @Test func confidenceIsReported() throws {
        let detected = try #require(detector.detect("Bei uns in Hamburg war es leider die ganze Nacht bewölkt."))
        #expect(detected.confidence >= MessageLanguageDetector.minimumConfidence)
        #expect(detected.confidence <= 1)
    }

    // MARK: Cleaning

    @Test func cleaningDropsFormattingLinksChannelsEmojiCodesAndCode() {
        let raw = "\u{02}hola\u{02} https://example.com/path #vela :tada: `let x = 1` www.swift.org amigos"
        #expect(MessageLanguageDetector.cleaned(raw) == "hola amigos")
    }

    @Test func cleaningDropsNicksWithTheirPunctuation() {
        let cleaned = MessageLanguageDetector.cleaned("kenji: did you see that, priya?") { ["kenji", "priya"].contains($0) }
        #expect(cleaned == "did you see that,")
    }

    @Test func cleaningKeepsAbbreviationsAndSentences() {
        #expect(MessageLanguageDetector.cleaned("e.g. the U.S. version") == "e.g. the U.S. version")
    }

    @Test func cjkCharactersWeighMore() {
        #expect(MessageLanguageDetector.letterWeight("hola") == 4)
        #expect(MessageLanguageDetector.letterWeight("ありがとう") == 15)
        #expect(MessageLanguageDetector.letterWeight("안녕") == 6)
        #expect(MessageLanguageDetector.letterWeight("😂 42 !!") == 0)
    }
}
