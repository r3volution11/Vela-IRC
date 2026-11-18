// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// What the user lets a site show inline.
public enum SiteAccess: String, Sendable, Hashable, CaseIterable, Codable {
    /// Everything: previews, images and players. Also bypasses the adult-site
    /// list and counts as "listed" when previews are restricted to listed sites.
    case allow
    /// Link cards without any image, favicon, thumbnail or player.
    case textOnly
    /// Nothing: Vela never contacts the site.
    case block

    /// Parses a settings value, tolerating case and separators
    /// (`textOnly`, `text-only`, `TEXT_ONLY`) and the UI's wording
    /// (`everything`, `nothing`).
    public init?(settingsValue: String) {
        let folded = settingsValue.lowercased().filter { $0.isLetter }
        switch folded {
        case "allow", "everything": self = .allow
        case "textonly", "text": self = .textOnly
        case "block", "nothing": self = .block
        default: return nil
        }
    }

    /// More restrictive values win when two entries collide.
    fileprivate var strictness: Int {
        switch self {
        case .allow: 0
        case .textOnly: 1
        case .block: 2
        }
    }
}

/// Per-site rules, keyed by normalized domain (`example.com`).
///
/// A rule covers the domain and its subdomains on label boundaries; the most
/// specific matching rule wins, so `img.example.com: allow` overrides
/// `example.com: block` for that one host.
public struct SiteRules: Sendable, Hashable {
    /// Normalized domain → access.
    public private(set) var entries: [String: SiteAccess] = [:]

    public init() {}

    /// Builds rules from the `media.siteRules` settings shape
    /// (`{"example.com": "block"}`). Domains are normalized (scheme, path,
    /// port, `*.` and case are dropped); unknown values and empty domains are
    /// skipped; when two entries normalize to the same domain the more
    /// restrictive one wins.
    public init(_ raw: [String: String]) {
        for (domain, value) in raw {
            guard let access = SiteAccess(settingsValue: value) else { continue }
            insert(access, for: domain)
        }
    }

    public init(entries: [String: SiteAccess]) {
        for (domain, access) in entries { insert(access, for: domain) }
    }

    public var isEmpty: Bool { entries.isEmpty }
    public var count: Int { entries.count }

    /// The rules in the settings shape, ready to be written back.
    public var settingsValue: [String: String] {
        entries.mapValues(\.rawValue)
    }

    /// The domains that have exactly `access`, sorted.
    public func domains(with access: SiteAccess) -> [String] {
        entries.filter { $0.value == access }.map(\.key).sorted()
    }

    /// The rule written for exactly `domain` (normalized), if any. Setting nil removes it.
    public subscript(domain: String) -> SiteAccess? {
        get { Self.normalizedDomain(domain).flatMap { entries[$0] } }
        set {
            guard let key = Self.normalizedDomain(domain) else { return }
            entries[key] = newValue
        }
    }

    private mutating func insert(_ access: SiteAccess, for domain: String) {
        guard let key = Self.normalizedDomain(domain) else { return }
        if let existing = entries[key], existing.strictness >= access.strictness { return }
        entries[key] = access
    }

    /// The most specific rule covering `host`, walking up its parent domains
    /// (`a.b.example.com`, `b.example.com`, `example.com`, `com`).
    /// IP literals only match a rule for the exact address.
    public func access(forHost host: String) -> (domain: String, access: SiteAccess)? {
        guard !entries.isEmpty, let host = Self.normalizedDomain(host) else { return nil }
        if Self.isIPLiteral(host) { return entries[host].map { (host, $0) } }
        for suffix in Self.domainSuffixes(of: host) {
            if let access = entries[suffix] { return (suffix, access) }
        }
        return nil
    }

    /// `access(forHost:)` for the URL's host.
    public func access(for url: URL) -> (domain: String, access: SiteAccess)? {
        Self.normalizedHost(url).flatMap { access(forHost: $0) }
    }

    // MARK: - Domains

    /// Reduces a user-entered domain to a bare lowercase host name:
    /// `https://*.Example.com:8443/path` → `example.com`. Nil when nothing is left.
    public static func normalizedDomain(_ entry: String) -> String? {
        var domain = entry.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let schemeEnd = domain.range(of: "://") { domain = String(domain[schemeEnd.upperBound...]) }
        if let slash = domain.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
            domain = String(domain[..<slash])
        }
        if let at = domain.lastIndex(of: "@") { domain = String(domain[domain.index(after: at)...]) }
        if domain.hasPrefix("[") {
            domain = String(domain.dropFirst().prefix { $0 != "]" })
        } else if let colon = domain.lastIndex(of: ":"), domain.filter({ $0 == ":" }).count == 1 {
            domain = String(domain[..<colon])
        }
        while domain.hasPrefix("*") || domain.hasPrefix(".") { domain.removeFirst() }
        while domain.hasSuffix(".") { domain.removeLast() }
        return domain.isEmpty ? nil : domain
    }

    /// The URL's host, lowercased, without brackets or a trailing dot.
    public static func normalizedHost(_ url: URL) -> String? {
        guard var host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        while host.hasSuffix(".") { host.removeLast() }
        return host.isEmpty ? nil : host
    }

    /// Which domain a "Block / Allow this site" action should write a rule for:
    /// the host without a leading `www.`, or the provider's main domain for
    /// video and GIF sites (so one rule covers `youtu.be` and `youtube.com`,
    /// or `media.tenor.com` and `tenor.com`).
    public static func suggestedRuleDomain(for url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        if case .embed(let info) = MediaClassifier.classify(url) { return info.provider.mainDomain }
        return normalizedHost(url).flatMap(suggestedRuleDomain(forHost:))
    }

    /// `suggestedRuleDomain(for:)` for a bare host.
    public static func suggestedRuleDomain(forHost host: String) -> String? {
        guard var domain = normalizedDomain(host) else { return nil }
        if let mainDomain = providerMainDomain(forHost: domain) { return mainDomain }
        if domain.hasPrefix("www."), domain.count > 4, domain.dropFirst(4).contains(".") { domain.removeFirst(4) }
        return domain
    }

    /// The main domain of the video or GIF site whose domains cover `host`
    /// (`youtu.be` → `youtube.com`, `gph.is` → `giphy.com`), if any.
    static func providerMainDomain(forHost host: String) -> String? {
        EmbedProvider.provider(forHost: host)?.mainDomain ?? GIFProvider.ruleProvider(forHost: host)?.mainDomain
    }

    /// Whether `host` is `domain` or one of its subdomains.
    static func host(_ host: String, isWithin domain: String) -> Bool {
        host == domain || (host.hasSuffix(domain) && host.dropLast(domain.count).hasSuffix("."))
    }

    /// `a.b.example.com` → `a.b.example.com`, `b.example.com`, `example.com`, `com`.
    static func domainSuffixes(of host: String) -> [String] {
        var suffixes = [host]
        var rest = Substring(host)
        while let dot = rest.firstIndex(of: ".") {
            rest = rest[rest.index(after: dot)...]
            if rest.isEmpty { break }
            suffixes.append(String(rest))
        }
        return suffixes
    }

    /// IPv4 dotted quads and anything with a colon (IPv6).
    static func isIPLiteral(_ host: String) -> Bool {
        if host.contains(":") { return true }
        return !host.isEmpty && host.allSatisfy { $0 == "." || $0.isASCIIDigit }
    }
}
