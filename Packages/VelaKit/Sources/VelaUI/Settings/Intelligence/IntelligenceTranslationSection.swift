// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaIntelligence
import VelaStore
import VelaTheme

/// Settings → Apple Intelligence → Translation.
struct IntelligenceTranslationSection: View {
    @Environment(AppModel.self) private var app
    @Environment(TranslationStore.self) private var store

    @State private var languages: [Locale.Language] = []

    var body: some View {
        @Bindable var settings = app.settings
        SettingsSection(
            "Translation",
            footer: "Translation runs on this Mac. macOS downloads each language once from Apple, the first time you translate from it."
        ) {
            SettingsMenuRow(
                title: "Translate into",
                detail: "Right-click a message in another language and choose Translate.",
                selection: $settings[.translationLanguage],
                options: Self.options(for: languages, current: settings[.translationLanguage], isDemo: app.isDemo)
            )
            let automatic = settings[.translationAutoTranslate]
            if !automatic.isEmpty {
                SettingsRow(
                    Self.automaticTitle(automatic),
                    detail: "Set from a channel's or network's right-click menu."
                ) {
                    Button("Clear") { settings[.translationAutoTranslate] = [] }
                        .buttonStyle(ThemedButtonStyle())
                        .accessibilityLabel("Stop translating these channels automatically")
                }
            }
        }
        .task {
            languages = await store.supportedLanguages(isDemo: app.isDemo)
        }
    }

    /// The Mac's language first, then every supported language by name. A
    /// hand-written code that isn't in the list stays selectable.
    static func options(for languages: [Locale.Language], current: String, isDemo: Bool) -> [(value: String, label: String)] {
        let mac = TranslationStore.target(setting: "", isDemo: isDemo).translationDisplayName()
        var seen: Set<String> = []
        var named: [(value: String, label: String)] = []
        for language in languages {
            let code = language.minimalIdentifier
            guard seen.insert(code).inserted else { continue }
            named.append((code, language.translationMenuName()))
        }
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, !seen.contains(trimmed) {
            named.append((current, Locale.Language(identifier: trimmed).translationMenuName()))
        }
        named.sort { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        return [("", "Same as Mac (\(mac))")] + named
    }

    /// "Translated automatically in 2 channels", counting whole networks
    /// (`"<uuid>/*"`) apart.
    static func automaticTitle(_ entries: [String]) -> String {
        let networks = entries.count(where: { $0.hasSuffix("/*") })
        let channels = entries.count - networks
        func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
        let parts = [channels > 0 ? count(channels, "channel") : nil, networks > 0 ? count(networks, "network") : nil]
        return "Translated automatically in " + parts.compactMap { $0 }.joined(separator: " and ")
    }
}
