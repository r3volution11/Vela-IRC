// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// The language messages are translated into (`translation.language`).
nonisolated public enum TranslationTarget {
    /// The language for `setting`: a language code such as `"ja"` or
    /// `"pt-BR"`, or empty for the Mac's first preferred language (English
    /// if there's none).
    public static func resolve(setting: String, preferredLanguages: [String] = Locale.preferredLanguages) -> Locale.Language {
        let trimmed = setting.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return Locale.Language(identifier: trimmed) }
        return Locale.Language(identifier: preferredLanguages.first ?? "en")
    }
}

extension Locale.Language {
    /// Whether text in `self` needs no translation into `other`: the same
    /// language and script. Regions don't matter (English stays English in
    /// the UK), scripts do (Simplified and Traditional Chinese differ).
    nonisolated public func isSameTranslationLanguage(as other: Locale.Language) -> Bool {
        guard let code = languageCode, code == other.languageCode else { return false }
        let script = Locale.Language(identifier: maximalIdentifier).script
        let otherScript = Locale.Language(identifier: other.maximalIdentifier).script
        return script == nil || otherScript == nil || script == otherScript
    }

    /// The language's name in the reader's language, e.g. "Japanese" or
    /// "Chinese, Simplified", without a region.
    nonisolated public func translationDisplayName(in locale: Locale = .current) -> String {
        let code = languageCode?.identifier ?? minimalIdentifier
        if code == "zh", let script, let name = locale.localizedString(forIdentifier: "zh-\(script.identifier)") {
            return name
        }
        return locale.localizedString(forLanguageCode: code) ?? minimalIdentifier
    }

    /// The name with its region, for pickers that list regional variants,
    /// e.g. "Portuguese (Portugal)".
    nonisolated public func translationMenuName(in locale: Locale = .current) -> String {
        locale.localizedString(forIdentifier: minimalIdentifier) ?? translationDisplayName(in: locale)
    }
}
