// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import NaturalLanguage
import VelaIRC

/// The language a chat line is written in.
nonisolated public struct DetectedLanguage: Hashable, Sendable {
    public var language: Locale.Language
    /// NaturalLanguage's probability for it, 0–1.
    public var confidence: Double

    public init(language: Locale.Language, confidence: Double) {
        self.language = language
        self.confidence = confidence
    }
}

/// Finds the language of a chat line when it's clear enough to offer a
/// translation.
///
/// Chat lines are short and full of things that aren't words, so the text
/// is cleaned first (formatting, links, `#channels`, `:emoji:` codes,
/// `` `code` ``, nicks), then it must have enough letters and the
/// recognizer must be confident. Short replies like "ok", "lol" or "jaja sí"
/// stay untranslated; that's fine, they're easy to read anyway.
///
/// Keeps one `NLLanguageRecognizer`, so use an instance from one actor.
public final class MessageLanguageDetector {
    /// Letters a line needs after cleaning. Chinese, Japanese and Korean
    /// characters count three each (one carries about a word).
    public static let minimumLetters = 12
    /// NaturalLanguage's probability the top language needs.
    public static let minimumConfidence = 0.8

    private let recognizer = NLLanguageRecognizer()

    public init() {}

    /// The line's language, or nil when it's too short or too mixed to tell.
    /// - Parameters:
    ///   - text: The raw message text (IRC formatting allowed).
    ///   - isNick: Whether a word is a nick in the conversation; nicks are
    ///     names, not words, and would skew the result.
    public func detect(_ text: String, isNick: (Substring) -> Bool = { _ in false }) -> DetectedLanguage? {
        let cleaned = Self.cleaned(text, isNick: isNick)
        guard Self.letterWeight(cleaned) >= Self.minimumLetters else { return nil }
        recognizer.reset()
        recognizer.processString(cleaned)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).max(by: { $0.value < $1.value }),
              confidence >= Self.minimumConfidence,
              language != .undetermined
        else { return nil }
        return DetectedLanguage(language: Locale.Language(identifier: language.rawValue), confidence: confidence)
    }

    // MARK: Cleaning

    /// `text` without formatting, links, channel names, `:emoji:` codes,
    /// inline code and nicks, with spaces collapsed.
    nonisolated public static func cleaned(_ text: String, isNick: (Substring) -> Bool = { _ in false }) -> String {
        var plain = IRCFormatting.strip(text)
        plain = plain.replacing(inlineCode, with: " ")
        plain = plain.replacing(emojiCode, with: " ")
        var words: [Substring] = []
        for word in plain.split(whereSeparator: \.isWhitespace) {
            let core = word.trimmingCharacters(in: wordPunctuation)
            if core.isEmpty { continue }
            if isLink(core) || core.hasPrefix("#") || isNick(Substring(core)) { continue }
            words.append(word)
        }
        return words.joined(separator: " ")
    }

    /// Letters in `text`, Chinese, Japanese and Korean characters counting
    /// three.
    nonisolated public static func letterWeight(_ text: String) -> Int {
        var weight = 0
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            weight += isCJK(scalar) ? 3 : 1
        }
        return weight
    }

    // MARK: Helpers

    nonisolated(unsafe) private static let inlineCode = /`[^`]*`/
    nonisolated(unsafe) private static let emojiCode = /:[a-z0-9_+\-]+:/

    nonisolated private static let wordPunctuation = CharacterSet.punctuationCharacters
        .union(.symbols)
        .subtracting(CharacterSet(charactersIn: "#"))

    /// URLs (`https://…`, `www.…`) and bare domains or paths (`example.com/x`).
    nonisolated private static func isLink(_ word: String) -> Bool {
        let lower = word.lowercased()
        if lower.contains("://") || lower.hasPrefix("www.") || lower.hasPrefix("mailto:") { return true }
        // A dot between two letters, like a domain: "github.com", "foo.io/bar".
        guard let dot = lower.firstIndex(of: "."), dot != lower.startIndex else { return false }
        let after = lower[lower.index(after: dot)...]
        return after.first?.isLetter == true && after.prefix(while: \.isLetter).count >= 2
            && lower[..<dot].last?.isLetter == true
    }

    nonisolated private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF,   // Hiragana, Katakana
             0x3400...0x4DBF,   // CJK Extension A
             0x4E00...0x9FFF,   // CJK Unified Ideographs
             0xAC00...0xD7AF,   // Hangul syllables
             0x1100...0x11FF,   // Hangul Jamo
             0xF900...0xFAFF,   // CJK Compatibility Ideographs
             0xFF66...0xFF9F,   // Halfwidth Katakana
             0x20000...0x2FA1F: // CJK Extensions B–F, supplement
            true
        default:
            false
        }
    }
}
