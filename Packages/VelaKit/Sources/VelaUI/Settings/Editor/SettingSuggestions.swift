// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Foundation
import Observation
import VelaCore
import VelaIntelligence
import VelaMedia
import VelaStore
import VelaTheme

/// Suggestions for the settings editor's token fields, by
/// ``SettingSuggestionSource``: fonts, themes, channels, sites, languages,
/// timestamp patterns and theme tokens.
///
/// One per editor. Lists that cost something to build (sites seen in chat,
/// translation languages) are built once and kept.
@Observable
final class SettingSuggestionProvider {
    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private let themeStore: ThemeStore
    @ObservationIgnored private let translations: TranslationStore?

    /// Loaded on first use (asking the translation framework is async).
    private(set) var languages: [Locale.Language] = []
    @ObservationIgnored private var languagesRequested = false
    @ObservationIgnored private var domainCache: [String]?

    init(app: AppModel, themeStore: ThemeStore, translations: TranslationStore?) {
        self.app = app
        self.themeStore = themeStore
        self.translations = translations
    }

    // MARK: Suggestions

    func suggestions(for source: SettingSuggestionSource) -> [TokenSuggestion] {
        switch source {
        case .fontFamilies:
            FontCatalog.families.map { TokenSuggestion(value: $0, previewFontFamily: $0) }
        case .monospacedFontFamilies:
            FontCatalog.monospacedFamilies.map { TokenSuggestion(value: $0, previewFontFamily: $0) }
        case .themes:
            themeStore.themes.map { info in
                TokenSuggestion(value: info.name, detail: info.kind == .dark ? "Dark" : "Light")
            }
        case .timestampPatterns:
            SettingsMetadata.timestampPatterns.map { pattern in
                TokenSuggestion(value: pattern, detail: Self.timestampPreview(pattern))
            }
        case .languages:
            languageSuggestions
        case .buffers:
            Self.bufferSuggestions(networks: networkSnapshot)
        case .domains:
            domains.map { TokenSuggestion(value: $0) }
        case .themeTokens:
            Self.themeTokenSuggestions(themeNames: themeStore.themes.map(\.name))
        }
    }

    /// The chip text for a stored value.
    func label(for value: String, source: SettingSuggestionSource?) -> String {
        switch source {
        case .buffers:
            Self.bufferLabel(value, networks: networkSnapshot)
        case .languages:
            value.isEmpty ? "" : Locale.Language(identifier: value).translationMenuName()
        default:
            value
        }
    }

    /// Secondary chip text: a timestamp pattern's preview, a language code.
    func detail(for value: String, source: SettingSuggestionSource?) -> String? {
        switch source {
        case .timestampPatterns: value.isEmpty ? nil : Self.timestampPreview(value)
        case .languages: value.isEmpty ? nil : value
        default: nil
        }
    }

    /// Turns typed text into a value to store, or nil to refuse it.
    /// Suggestions matching the text exactly are handled by the token field.
    func resolve(_ text: String, source: SettingSuggestionSource?) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        switch source {
        case .buffers:
            return Self.resolveBuffer(trimmed, suggestions: Self.bufferSuggestions(networks: networkSnapshot))
        case .domains:
            return SiteRulesEditor.ruleDomain(trimmed)
        case .languages:
            // A language code, or a name in the list ("Japanese").
            if let match = languageSuggestions.first(where: { $0.label.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                return match.value
            }
            return trimmed.contains(where: \.isWhitespace) ? nil : trimmed
        default:
            return trimmed
        }
    }

    /// What an empty single-value field means, as its placeholder.
    static func emptyPlaceholder(for key: String, source: SettingSuggestionSource?) -> String {
        switch source {
        case .fontFamilies: "System font"
        case .monospacedFontFamilies: "System monospace font"
        case .languages: "Same as Mac"
        case .timestampPatterns: "From Clock and Seconds"
        case .themes: "Choose a theme"
        default: "Empty"
        }
    }

    /// Asks the translation framework for its languages, once.
    func loadLanguagesIfNeeded() async {
        guard !languagesRequested, let translations else { return }
        languagesRequested = true
        languages = await translations.supportedLanguages(isDemo: app.isDemo)
    }

    private var languageSuggestions: [TokenSuggestion] {
        var seen: Set<String> = []
        var result: [TokenSuggestion] = []
        for language in languages {
            let code = language.minimalIdentifier
            guard seen.insert(code).inserted else { continue }
            result.append(TokenSuggestion(value: code, label: language.translationMenuName(), detail: code))
        }
        return result.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    // MARK: Buffers

    /// A network with its channels and conversations, for buffer labels.
    nonisolated struct NetworkBuffers: Sendable {
        let id: UUID
        let name: String
        /// Folded name → name as shown (`"#vela"`).
        let buffers: [(foldedName: String, name: String)]
    }

    private var networkSnapshot: [NetworkBuffers] {
        var result: [NetworkBuffers] = []
        var seen: Set<UUID> = []
        for session in app.sessions where !session.isBouncerControl {
            seen.insert(session.id)
            let buffers = session.buffers
                .filter { $0.kind != .server }
                .map { (foldedName: $0.id.foldedName, name: $0.name) }
            result.append(NetworkBuffers(id: session.id, name: session.displayName, buffers: buffers))
        }
        // Saved networks that haven't started yet still name their entries.
        for config in app.networkStore.networks where !seen.contains(config.id) {
            result.append(NetworkBuffers(id: config.id, name: config.name.isEmpty ? config.host : config.name, buffers: []))
        }
        return result
    }

    /// `"<uuid>/#vela"` → `"#vela · Libera.Chat"`; `"<uuid>/*"` →
    /// `"All of Libera.Chat"`. Entries for networks Vela doesn't have, and
    /// anything that doesn't parse, are shown as they are.
    nonisolated static func bufferLabel(_ entry: String, networks: [NetworkBuffers]) -> String {
        guard let slash = entry.firstIndex(of: "/"),
              let networkID = UUID(uuidString: String(entry[..<slash])),
              let network = networks.first(where: { $0.id == networkID })
        else { return entry }
        let folded = String(entry[entry.index(after: slash)...])
        if folded == "*" { return "All of \(network.name)" }
        guard !folded.isEmpty else { return entry }
        let name = network.buffers.first { $0.foldedName == folded }?.name ?? folded
        return "\(name) · \(network.name)"
    }

    /// Every network ("All of …") and each of its channels and
    /// conversations, networks first.
    nonisolated static func bufferSuggestions(networks: [NetworkBuffers]) -> [TokenSuggestion] {
        var result: [TokenSuggestion] = []
        for network in networks {
            result.append(TokenSuggestion(
                value: BufferScopeList.networkEntry(for: network.id),
                label: "All of \(network.name)",
                detail: "Network"
            ))
        }
        for network in networks {
            for buffer in network.buffers {
                result.append(TokenSuggestion(
                    value: "\(network.id.uuidString)/\(buffer.foldedName)",
                    label: "\(buffer.name) · \(network.name)"
                ))
            }
        }
        return result
    }

    /// Typed text for a buffer list: a channel name that only one network
    /// has (`"#vela"`), a network's name (`"Libera.Chat"`, the whole
    /// network), or a raw `"<uuid>/<name>"` entry.
    nonisolated static func resolveBuffer(_ text: String, suggestions: [TokenSuggestion]) -> String? {
        let channelMatches = suggestions.filter { suggestion in
            guard let separator = suggestion.label.range(of: " · ") else { return false }
            return suggestion.label[..<separator.lowerBound].caseInsensitiveCompare(text) == .orderedSame
        }
        if channelMatches.count == 1 { return channelMatches[0].value }
        if let network = suggestions.first(where: { $0.label.caseInsensitiveCompare("All of \(text)") == .orderedSame }) {
            return network.value
        }
        if let slash = text.firstIndex(of: "/"), UUID(uuidString: String(text[..<slash])) != nil,
           text.index(after: slash) < text.endIndex {
            return text
        }
        return nil
    }

    // MARK: Domains

    /// Sites with rules, then sites linked in loaded messages (most linked
    /// first), at most `maximumDomains`.
    private var domains: [String] {
        if let domainCache { return domainCache }
        var counts: [String: Int] = [:]
        for buffer in app.orderedBuffers {
            for line in buffer.lines.suffix(Self.linesScannedPerBuffer) {
                for link in LinkDetector.links(in: line.text) {
                    if let domain = SiteRules.suggestedRuleDomain(for: link.url) {
                        counts[domain, default: 0] += 1
                    }
                }
            }
        }
        let ruled = app.siteRules.entries.keys.sorted()
        let linked = counts
            .filter { !ruled.contains($0.key) }
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .map(\.key)
        let result = Array((ruled + linked).prefix(Self.maximumDomains))
        domainCache = result
        return result
    }

    static let linesScannedPerBuffer = 400
    static let maximumDomains = 150

    // MARK: Theme tokens

    /// Every theme color token, the special keys, and a `"[Theme]"` scope
    /// per installed theme.
    nonisolated static func themeTokenSuggestions(themeNames: [String], includeScopes: Bool = true) -> [TokenSuggestion] {
        var result = ThemeRegistry.tokens.map { token in
            TokenSuggestion(value: token.key, detail: ThemeRegistry.groups.first { $0.id == token.group }?.title)
        }
        result.append(TokenSuggestion(value: "vibrancy", detail: "none, sidebar or window"))
        if includeScopes {
            result += themeNames.map { TokenSuggestion(value: "[\($0)]", detail: "Only for \($0)") }
        }
        return result
    }

    // MARK: Timestamps

    private static let previewDate: Date = {
        Calendar.current.date(bySettingHour: 14, minute: 5, second: 9, of: Date()) ?? Date()
    }()

    /// How `pattern` shows 14:05:09 today, e.g. `"2:05 PM"`.
    static func timestampPreview(_ pattern: String) -> String {
        let formatter = TimestampFormat.formatter(pattern: pattern, locale: .current)
        let text = formatter.string(from: previewDate)
        return text.isEmpty ? "(empty)" : text
    }
}
