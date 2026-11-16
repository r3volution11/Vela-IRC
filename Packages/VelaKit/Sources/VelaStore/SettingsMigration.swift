// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaFoundation

/// One change a migration makes to settings.json.
public enum SettingsChange: Sendable, Hashable, CustomStringConvertible {
    case set(key: String, value: JSONValue)
    case remove(key: String)

    public var key: String {
        switch self {
        case .set(let key, _), .remove(let key): key
        }
    }

    /// The new value, or nil when the key is removed.
    public var value: JSONValue? {
        switch self {
        case .set(_, let value): value
        case .remove: nil
        }
    }

    public var description: String {
        switch self {
        case .set(let key, let value): "set \(key) = \(value)"
        case .remove(let key): "remove \(key)"
        }
    }
}

/// Upgrades settings.json written by older versions of Vela.
///
/// Each ``Rule`` rewrites the raw key/value dictionary and must be idempotent:
/// running it on its own output changes nothing, so the whole migration can
/// run on every launch (``SettingsStore/applyMigrations(_:)``). A file that
/// needs no migration is never rewritten.
///
/// To add a rule: write a `Rule` in the extension below, keep any key names
/// that no longer have a ``SettingKey`` as constants in ``LegacyKey``, and
/// append the rule to ``rules``. Rules run in that order; each one sees the
/// values left by the ones before it.
public enum SettingsMigration {
    /// One migration step.
    public struct Rule: Sendable, Identifiable {
        /// A short name for logs and tests.
        public let id: String
        private let body: @Sendable (inout [String: JSONValue]) -> Void

        public init(id: String, _ body: @escaping @Sendable (inout [String: JSONValue]) -> Void) {
            self.id = id
            self.body = body
        }

        public func apply(to values: inout [String: JSONValue]) {
            body(&values)
        }
    }

    /// Every rule, in the order it runs.
    public static let rules: [Rule] = [
        .mergeDomainListsIntoSiteRules,
        .splitMediaPresentation,
    ]

    /// `values` with `rules` applied.
    public static func migrated(_ values: [String: JSONValue], rules: [Rule] = rules) -> [String: JSONValue] {
        var migrated = values
        for rule in rules { rule.apply(to: &migrated) }
        return migrated
    }

    /// The changes that bring `values` up to date, sorted by key; empty when
    /// nothing needs migrating.
    public static func changes(for values: [String: JSONValue], rules: [Rule] = rules) -> [SettingsChange] {
        let migrated = migrated(values, rules: rules)
        guard migrated != values else { return [] }
        return Set(values.keys).union(migrated.keys).sorted().compactMap { key in
            let new = migrated[key]
            guard new != values[key] else { return nil }
            return new.map { .set(key: key, value: $0) } ?? .remove(key: key)
        }
    }

    /// Keys older versions of Vela wrote that no longer exist.
    enum LegacyKey {
        /// `[String]`: never load media from these domains (and subdomains).
        static let blockedDomains = "media.blockedDomains"
        /// `[String]`: with `media.restrictToAllowed`, the only domains media may load from.
        static let allowedDomains = "media.allowedDomains"
        /// `"full"` (default) or `"compact"`: the size of every inline preview.
        static let mediaPresentation = "media.presentation"
        /// `Bool`, default true: show embedded players for video links.
        static let mediaLoadVideoEmbeds = "media.loadVideoEmbeds"

        /// Defaults of the keys above that presets set, for matching ``LegacyPreset``.
        static let defaults: [String: JSONValue] = [
            mediaPresentation: "full",
            mediaLoadVideoEmbeds: true,
        ]
    }

    /// Presets as older versions of Vela defined them, so a migration can
    /// tell which preset a user had chosen and keep them on it.
    enum LegacyPreset {
        /// Before `media.presentation` and `media.loadVideoEmbeds` were split
        /// into `media.linkPreviewSize`, `media.videos` and `media.imageSize`.
        /// Modern and Tabbed are left out: they used the old defaults, which
        /// map to their new values without help.
        static let beforePreviewSizes: [(id: String, values: [String: JSONValue])] = [
            ("classic", [
                "navigation.style": "sidebar",
                "chat.layout": "classic",
                "chat.monospace": true,
                "chat.fontSize": 12,
                "chat.lineSpacing": 1,
                "chat.messageSpacing": 2,
                "chat.showAvatars": false,
                "chat.showJoinPart": "show",
                "chat.showTimestamps": true,
                "sidebar.rowHeight": 20,
                "sidebar.fontSize": 12,
                "memberList.visible": true,
                "media.presentation": "compact",
                "media.loadVideoEmbeds": false,
            ]),
            ("focus", [
                "navigation.style": "tabs",
                "tabs.placement": "titleBar",
                "tabs.roundness": 1,
                "tabs.serverRow": "auto",
                "chat.layout": "columns",
                "chat.monospace": false,
                "chat.fontSize": 13,
                "chat.lineSpacing": 2,
                "chat.messageSpacing": 3,
                "chat.showAvatars": false,
                "chat.showJoinPart": "hide",
                "memberList.visible": false,
                "media.presentation": "compact",
                "media.loadVideoEmbeds": true,
            ]),
        ]

        /// The current preset whose old version (from `legacy`) `values`
        /// matched, the way ``SettingsStore/matchingPreset()`` matches:
        /// missing keys count as their defaults.
        static func matching(
            _ values: [String: JSONValue],
            in legacy: [(id: String, values: [String: JSONValue])]
        ) -> SettingsPreset? {
            let old = legacy.first { preset in
                SettingsPreset.valuesMatch(preset.values) { key in
                    values[key] ?? LegacyKey.defaults[key] ?? SettingsCatalog.descriptor(forKey: key)?.defaultValue
                }
            }
            return old.flatMap { old in SettingsPreset.all.first { $0.id == old.id } }
        }
    }
}

// MARK: - Rules

extension SettingsMigration.Rule {
    /// `media.blockedDomains` and `media.allowedDomains` become `"block"` and
    /// `"allow"` entries in `media.siteRules`, and the lists are removed.
    ///
    /// - A domain in both lists is blocked.
    /// - An existing `media.siteRules` entry for the same domain is kept.
    /// - Domains are normalized loosely (case, whitespace, scheme, path,
    ///   port, a leading `*.`); VelaMedia normalizes them again when reading.
    /// - An allow rule also lets the site past the adult-site filter, which
    ///   the old allowed list did not do.
    public static let mergeDomainListsIntoSiteRules = Self(id: "media.domainListsToSiteRules") { values in
        typealias Legacy = SettingsMigration.LegacyKey
        let blocked = values[Legacy.blockedDomains]
        let allowed = values[Legacy.allowedDomains]
        guard blocked != nil || allowed != nil else { return }

        let rulesKey = SettingKey<[String: JSONValue]>.mediaSiteRules.key
        let original = values[rulesKey]?.objectValue
        var rules = original ?? [:]
        var covered = Set(rules.keys.compactMap(SettingsMigration.normalizedDomain))
        // Blocked first, so a domain in both lists ends up blocked.
        for (list, access) in [(blocked, "block"), (allowed, "allow")] {
            for entry in list?.arrayValue ?? [] {
                guard let domain = entry.stringValue.flatMap(SettingsMigration.normalizedDomain),
                      covered.insert(domain).inserted
                else { continue }
                rules[domain] = .string(access)
            }
        }
        // A malformed media.siteRules (not an object) reads as empty, so it is
        // replaced only when the lists add something.
        if rules != original ?? [:] {
            values[rulesKey] = .object(rules)
        }
        values.removeValue(forKey: Legacy.blockedDomains)
        values.removeValue(forKey: Legacy.allowedDomains)
    }
}

extension SettingsMigration.Rule {
    /// `media.presentation` and `media.loadVideoEmbeds` become
    /// `media.linkPreviewSize`, `media.videos` and `media.imageSize`, and are
    /// removed.
    ///
    /// - `compact` becomes minimal link previews, compact videos and
    ///   thumbnail images; `full` leaves the new defaults.
    /// - `media.loadVideoEmbeds: false` becomes `media.videos: off`, over the
    ///   compact mapping.
    /// - Settings that matched an old preset get that preset's new values
    ///   instead, so Settings still shows the preset rather than Custom:
    ///   old Classic keeps compact videos (not off), and old Focus gets
    ///   players.
    /// - A new key that already holds a valid value is kept, and defaults
    ///   aren't written.
    public static let splitMediaPresentation = Self(id: "media.presentationToPreviewSizes") { values in
        typealias Legacy = SettingsMigration.LegacyKey
        let presentation = values[Legacy.mediaPresentation]
        let loadVideoEmbeds = values[Legacy.mediaLoadVideoEmbeds]
        guard presentation != nil || loadVideoEmbeds != nil else { return }

        var linkSize: LinkPreviewSize?
        var videos: VideoEmbedStyle?
        var imageSize: InlineImageSize?
        if let preset = SettingsMigration.LegacyPreset.matching(values, in: SettingsMigration.LegacyPreset.beforePreviewSizes) {
            func presetValue<Value: SettingValueConvertible>(_ key: SettingKey<Value>) -> Value? {
                preset.values[key.key].flatMap(Value.init(settingJSON:))
            }
            linkSize = presetValue(.mediaLinkPreviewSize)
            videos = presetValue(.mediaVideos)
            imageSize = presetValue(.mediaImageSize)
        } else {
            if presentation?.stringValue == "compact" {
                linkSize = .minimal
                videos = .compact
                imageSize = .thumbnail
            }
            if loadVideoEmbeds?.boolValue == false { videos = .off }
        }
        SettingsMigration.fill(.mediaLinkPreviewSize, with: linkSize, in: &values)
        SettingsMigration.fill(.mediaVideos, with: videos, in: &values)
        SettingsMigration.fill(.mediaImageSize, with: imageSize, in: &values)
        values.removeValue(forKey: Legacy.mediaPresentation)
        values.removeValue(forKey: Legacy.mediaLoadVideoEmbeds)
    }
}

// MARK: - Helpers

extension SettingsMigration {
    /// Writes `value` to `key`, unless it's nil or the default, or the key
    /// already holds a valid value (an invalid one reads as the default, so
    /// it's replaced).
    static func fill<Value: SettingValueConvertible & Equatable>(
        _ key: SettingKey<Value>,
        with value: Value?,
        in values: inout [String: JSONValue]
    ) {
        guard let value, value != key.defaultValue,
              values[key.key].flatMap(Value.init(settingJSON:)) == nil
        else { return }
        values[key.key] = key.jsonValue(for: value)
    }

    /// A user-entered domain reduced to a bare lowercase host name:
    /// `https://*.Example.com:8443/path` → `example.com`. Nil when nothing is left.
    static func normalizedDomain(_ entry: String) -> String? {
        var domain = entry.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let schemeEnd = domain.range(of: "://") { domain = String(domain[schemeEnd.upperBound...]) }
        if let end = domain.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
            domain = String(domain[..<end])
        }
        if let at = domain.lastIndex(of: "@") { domain = String(domain[domain.index(after: at)...]) }
        if domain.hasPrefix("[") {
            domain = String(domain.dropFirst().prefix { $0 != "]" })
        } else if domain.filter({ $0 == ":" }).count == 1, let colon = domain.firstIndex(of: ":") {
            domain = String(domain[..<colon])
        }
        while domain.hasPrefix("*") || domain.hasPrefix(".") { domain.removeFirst() }
        while domain.hasSuffix(".") { domain.removeLast() }
        return domain.isEmpty ? nil : domain
    }
}
