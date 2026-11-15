// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// The user's inline media settings.
///
/// `LinkPreviewService` enforces `allows(_:)` (including on redirects) and
/// `maxImageBytes`. The boolean switches are for callers deciding what to
/// fetch and render automatically; `permitsAutomaticPreview(of:)` combines them.
public struct MediaPolicy: Sendable, Codable, Hashable {
    /// Fetch previews without the user clicking first.
    public var autoLoad: Bool = true
    /// Show link cards for ordinary pages.
    public var showLinkCards: Bool = true
    /// Show YouTube/Vimeo/Twitch/Streamable facades.
    public var loadVideoEmbeds: Bool = true
    /// Never fetch from these domains (and their subdomains).
    public var blockedDomains: [String] = []
    /// Domains used when `restrictToAllowedDomains` is on.
    public var allowedDomains: [String] = []
    public var restrictToAllowedDomains: Bool = false
    public var maxImageBytes: Int = 10 * 1024 * 1024
    /// Allow fetching from `localhost`, private/link-local IP literals and
    /// single-label or `.local` hosts. Off by default so a link pasted in a
    /// channel cannot make Vela send requests into the user's LAN.
    public var allowPrivateNetworkHosts: Bool = false

    public init(
        autoLoad: Bool = true,
        showLinkCards: Bool = true,
        loadVideoEmbeds: Bool = true,
        blockedDomains: [String] = [],
        allowedDomains: [String] = [],
        restrictToAllowedDomains: Bool = false,
        maxImageBytes: Int = 10 * 1024 * 1024,
        allowPrivateNetworkHosts: Bool = false
    ) {
        self.autoLoad = autoLoad
        self.showLinkCards = showLinkCards
        self.loadVideoEmbeds = loadVideoEmbeds
        self.blockedDomains = blockedDomains
        self.allowedDomains = allowedDomains
        self.restrictToAllowedDomains = restrictToAllowedDomains
        self.maxImageBytes = maxImageBytes
        self.allowPrivateNetworkHosts = allowPrivateNetworkHosts
    }

    /// Whether Vela may contact `url` at all.
    ///
    /// Only `http`/`https`. Domain entries match the host itself and its
    /// subdomains on label boundaries: `example.com` covers `img.example.com`
    /// but not `badexample.com`. Entries may be written as `*.example.com`,
    /// `.example.com` or even `https://example.com/`. Blocking wins over allowing.
    public func allows(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = Self.normalizedHost(url)
        else { return false }

        if !allowPrivateNetworkHosts, Self.isPrivateNetworkHost(host) { return false }
        if blockedDomains.contains(where: { Self.host(host, matches: $0) }) { return false }
        if restrictToAllowedDomains {
            return allowedDomains.contains { Self.host(host, matches: $0) }
        }
        return true
    }

    /// Whether a preview for `url` should be fetched and shown without a click.
    public func permitsAutomaticPreview(of url: URL) -> Bool {
        guard autoLoad, allows(url) else { return false }
        switch MediaClassifier.classify(url) {
        case .image, .video: return true
        case .embed: return loadVideoEmbeds
        case .page: return showLinkCards
        }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case autoLoad, showLinkCards, loadVideoEmbeds, blockedDomains, allowedDomains
        case restrictToAllowedDomains, maxImageBytes, allowPrivateNetworkHosts
    }

    /// Missing keys fall back to defaults so older settings files keep loading.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = MediaPolicy()
        autoLoad = try container.decodeIfPresent(Bool.self, forKey: .autoLoad) ?? defaults.autoLoad
        showLinkCards = try container.decodeIfPresent(Bool.self, forKey: .showLinkCards) ?? defaults.showLinkCards
        loadVideoEmbeds = try container.decodeIfPresent(Bool.self, forKey: .loadVideoEmbeds)
            ?? defaults.loadVideoEmbeds
        blockedDomains = try container.decodeIfPresent([String].self, forKey: .blockedDomains)
            ?? defaults.blockedDomains
        allowedDomains = try container.decodeIfPresent([String].self, forKey: .allowedDomains)
            ?? defaults.allowedDomains
        restrictToAllowedDomains = try container.decodeIfPresent(Bool.self, forKey: .restrictToAllowedDomains)
            ?? defaults.restrictToAllowedDomains
        maxImageBytes = try container.decodeIfPresent(Int.self, forKey: .maxImageBytes) ?? defaults.maxImageBytes
        allowPrivateNetworkHosts = try container.decodeIfPresent(Bool.self, forKey: .allowPrivateNetworkHosts)
            ?? defaults.allowPrivateNetworkHosts
    }

    // MARK: - Matching

    static func normalizedHost(_ url: URL) -> String? {
        guard var host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        while host.hasSuffix(".") { host.removeLast() }
        return host.isEmpty ? nil : host
    }

    /// Reduces a user-entered domain to a bare lowercase host name.
    static func normalizedDomain(_ entry: String) -> String? {
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

    static func host(_ host: String, matches entry: String) -> Bool {
        guard let domain = normalizedDomain(entry) else { return false }
        return host == domain || host.hasSuffix("." + domain)
    }

    /// Loopback, private, link-local and CGNAT IP literals, plus names that
    /// only resolve on a local network. Hostnames that *resolve* to private
    /// addresses are not caught here.
    static func isPrivateNetworkHost(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local")
            || host.hasSuffix(".internal") || host.hasSuffix(".lan") || host.hasSuffix(".home.arpa") {
            return true
        }
        if let octets = ipv4Octets(host) {
            let (a, b) = (octets[0], octets[1])
            return a == 0 || a == 10 || a == 127
                || (a == 169 && b == 254)
                || (a == 172 && (16...31).contains(b))
                || (a == 192 && b == 168)
                || (a == 100 && (64...127).contains(b))
                || a >= 224
        }
        if host.contains(":") {
            let lower = host.lowercased()
            if lower == "::1" || lower == "::" { return true }
            if lower.hasPrefix("fe8") || lower.hasPrefix("fe9") || lower.hasPrefix("fea") || lower.hasPrefix("feb") {
                return true   // fe80::/10 link-local
            }
            if lower.hasPrefix("fc") || lower.hasPrefix("fd") { return true }   // fc00::/7 unique local
            if lower.hasPrefix("::ffff:") {
                return isPrivateNetworkHost(String(lower.dropFirst("::ffff:".count)))
            }
            return false
        }
        // Single-label names ("router", "nas") only resolve via local search domains.
        return !host.contains(".")
    }

    private static func ipv4Octets(_ host: String) -> [Int]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var octets: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.count <= 3, part.allSatisfy(\.isASCIIDigit), let value = Int(part),
                  value <= 255
            else { return nil }
            octets.append(value)
        }
        return octets
    }
}
