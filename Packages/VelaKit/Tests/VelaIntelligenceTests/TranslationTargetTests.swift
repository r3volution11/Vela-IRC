// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaIntelligence

@Suite("Translation target language")
struct TranslationTargetTests {
    @Test func emptySettingUsesTheMacsFirstLanguage() {
        let target = TranslationTarget.resolve(setting: "", preferredLanguages: ["fr-CA", "en-US"])
        #expect(target.minimalIdentifier == Locale.Language(identifier: "fr-CA").minimalIdentifier)
        #expect(TranslationTarget.resolve(setting: "   ", preferredLanguages: ["ja-JP"]).languageCode?.identifier == "ja")
    }

    @Test func noPreferredLanguageFallsBackToEnglish() {
        #expect(TranslationTarget.resolve(setting: "", preferredLanguages: []).languageCode?.identifier == "en")
    }

    @Test func aSetLanguageWins() {
        let target = TranslationTarget.resolve(setting: "pt-BR", preferredLanguages: ["en-US"])
        #expect(target.languageCode?.identifier == "pt")
        #expect(target.region?.identifier == "BR")
        #expect(TranslationTarget.resolve(setting: " ja ", preferredLanguages: ["en-US"]).languageCode?.identifier == "ja")
    }

    @Test func regionsDontMakeADifferentLanguage() {
        let english = Locale.Language(identifier: "en")
        #expect(english.isSameTranslationLanguage(as: Locale.Language(identifier: "en-GB")))
        #expect(Locale.Language(identifier: "en-US").isSameTranslationLanguage(as: english))
        #expect(Locale.Language(identifier: "pt-PT").isSameTranslationLanguage(as: Locale.Language(identifier: "pt-BR")))
        #expect(!english.isSameTranslationLanguage(as: Locale.Language(identifier: "es")))
    }

    @Test func scriptsDo() {
        let simplified = Locale.Language(identifier: "zh-Hans")
        #expect(!simplified.isSameTranslationLanguage(as: Locale.Language(identifier: "zh-Hant")))
        #expect(simplified.isSameTranslationLanguage(as: Locale.Language(identifier: "zh")))
        #expect(!Locale.Language(identifier: "zh-TW").isSameTranslationLanguage(as: Locale.Language(identifier: "zh-CN")))
    }

    @Test func namesForCaptionsAndMenus() {
        let english = Locale(identifier: "en")
        #expect(Locale.Language(identifier: "ja").translationDisplayName(in: english) == "Japanese")
        #expect(Locale.Language(identifier: "de-AT").translationDisplayName(in: english) == "German")
        #expect(Locale.Language(identifier: "zh-Hant").translationDisplayName(in: english).contains("Traditional"))
        #expect(Locale.Language(identifier: "pt-PT").translationMenuName(in: english) == "Portuguese (Portugal)")
        #expect(Locale.Language(identifier: "es").translationDisplayName(in: Locale(identifier: "de")) == "Spanisch")
    }
}
