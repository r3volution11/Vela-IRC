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

// MARK: - Helpers

extension SettingsMigration {
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
