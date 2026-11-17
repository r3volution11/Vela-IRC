// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Fixed translations, for demo mode, screenshots and tests. Works offline
/// on any Mac. Text it has no translation for fails to translate.
public final class CannedTranslator: MessageTranslator {
    /// Translations by original text.
    public var translations: [String: String]
    /// How long each batch takes, so the "Translating…" state shows.
    public var delay: Duration
    /// The languages it claims to support.
    public var languages: [Locale.Language]

    public init(
        translations: [String: String],
        delay: Duration = .zero,
        languages: [Locale.Language] = CannedTranslator.commonLanguages
    ) {
        self.translations = translations
        self.delay = delay
        self.languages = languages
    }

    /// The demo's foreign-language lines (#vela-offtopic), in English.
    public static func demo() -> CannedTranslator {
        CannedTranslator(translations: demoTranslations, delay: .milliseconds(250))
    }

    public static let demoTranslations: [String: String] = [
        "¡Qué envidia! Aquí en Madrid el cielo estaba despejado, pero no se veía nada.":
            "So jealous! Here in Madrid the sky was clear, but you couldn't see a thing.",
        "北海道でもオーロラが見えたらしいよ。写真を撮りに行けばよかったな。":
            "Apparently you could see the aurora in Hokkaido too. I should have gone out to take photos.",
        "Bei uns in Hamburg war es leider die ganze Nacht bewölkt.":
            "Unfortunately it was cloudy all night here in Hamburg.",
    ]

    public static let commonLanguages: [Locale.Language] = [
        "ar", "de", "en", "en-GB", "es", "fr", "hi", "id", "it", "ja", "ko", "nl", "pl",
        "pt", "pt-PT", "ru", "th", "tr", "uk", "vi", "zh", "zh-TW",
    ].map { Locale.Language(identifier: $0) }

    public func status(from source: Locale.Language, to target: Locale.Language) async -> TranslationPairStatus {
        source.isSameTranslationLanguage(as: target) ? .unsupported : .installed
    }

    public func translate(_ texts: [String], from source: Locale.Language, to target: Locale.Language) async throws -> [String] {
        if delay > .zero { try? await Task.sleep(for: delay) }
        return try texts.map { text in
            guard let translation = translations[text] else {
                throw TranslationFailure.failed("There's no demo translation for this message.")
            }
            return translation
        }
    }

    public func supportedLanguages() async -> [Locale.Language] {
        languages
    }
}
