// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Why a site's previews are blocked.
public enum BlockReason: String, Sendable, Hashable, Codable {
    /// The host is on the bundled adult-site list (or an adult-only TLD).
    case adultSite
    /// The page labels itself adult (RTA label, `rating` meta, `Rating` header).
    case adultPage
    /// The user has a "Nothing" rule for the site.
    case userBlocked
    /// Previews are restricted to listed sites and this one isn't listed.
    case notAllowed
}

/// A blocked site and why. `domain` is what a "Show once" / "Always allow" /
/// "Unblock" action should act on: the rule's own domain for `userBlocked`,
/// the listed domain for `adultSite`, the suggested rule domain otherwise.
public struct SiteBlock: Sendable, Hashable, Codable {
    public var reason: BlockReason
    public var domain: String

    public init(reason: BlockReason, domain: String) {
        self.reason = reason
        self.domain = domain
    }
}

/// What a `MediaPolicy` lets a URL do.
public enum SiteVerdict: Sendable, Hashable {
    /// Previews, images, thumbnails and players.
    case everything
    /// Pages and oEmbed may be fetched for a text card; no images of any kind.
    case textOnly
    /// Nothing may be fetched; the UI shows a chip saying why.
    case blocked(SiteBlock)
    /// Never contacted and never offered: not `http(s)`, or a private-network host.
    case forbidden

    public var block: SiteBlock? {
        if case .blocked(let block) = self { return block }
        return nil
    }
}

/// The user's inline media settings, as they apply to one buffer (or, from
/// `PreviewDecider`, to one link).
///
/// `verdict(for:)` decides per URL, in this order:
/// 1. forbidden: a non-`http(s)` scheme or a private-network host;
/// 2. allowed once (`allowedOnce`, from "Show once"): everything;
/// 3. the most specific site rule (always beats the adult list);
/// 4. the adult-site list (bundled plus `extraAdultDomains`), when `filterAdultSites`;
/// 5. `restrictToAllowedDomains`: blocked unless an allow/textOnly rule matched;
/// 6. everything.
///
/// `imagesAllowed == false` turns "everything" into "text only".
/// `allows(_:)` gates page, oEmbed and redirect requests; `allowsImage(_:)`
/// gates every image, thumbnail, favicon, poster and direct-media load.
public struct MediaPolicy: Sendable, Hashable {
    /// Fetch previews without the user clicking first.
    public var autoLoad: Bool = true
    /// Show link cards for ordinary pages.
    public var showLinkCards: Bool = true
    public var siteRules = SiteRules()
    /// Block sites on the bundled adult list and pages that label themselves adult.
    public var filterAdultSites: Bool = true
    /// Extra adult-list domains (tests and demo mode), matched like the bundled list.
    public var extraAdultDomains: Set<String> = []
    /// False makes every site text-only (e.g. a per-link decision that images are off).
    public var imagesAllowed: Bool = true
    /// Domains the user chose "Show once" for; they get everything,
    /// bypassing rules, the adult list and the allowed-sites restriction.
    public var allowedOnce: Set<String> = []
    /// Only sites with an allow or textOnly rule get previews.
    public var restrictToAllowedDomains: Bool = false
    public var maxImageBytes: Int = 10 * 1024 * 1024
    /// Allow fetching from `localhost`, private/link-local IP literals and
    /// single-label or `.local` hosts. Off by default so a link pasted in a
    /// channel cannot make Vela send requests into the user's LAN.
    public var allowPrivateNetworkHosts: Bool = false

    public init(
        autoLoad: Bool = true,
        showLinkCards: Bool = true,
        siteRules: SiteRules = SiteRules(),
        filterAdultSites: Bool = true,
        extraAdultDomains: Set<String> = [],
        imagesAllowed: Bool = true,
        allowedOnce: Set<String> = [],
        restrictToAllowedDomains: Bool = false,
        maxImageBytes: Int = 10 * 1024 * 1024,
        allowPrivateNetworkHosts: Bool = false
    ) {
        self.autoLoad = autoLoad
        self.showLinkCards = showLinkCards
        self.siteRules = siteRules
        self.filterAdultSites = filterAdultSites
        self.extraAdultDomains = extraAdultDomains
        self.imagesAllowed = imagesAllowed
        self.allowedOnce = allowedOnce
        self.restrictToAllowedDomains = restrictToAllowedDomains
        self.maxImageBytes = maxImageBytes
        self.allowPrivateNetworkHosts = allowPrivateNetworkHosts
    }

    // MARK: - Verdicts

    public func verdict(for url: URL) -> SiteVerdict {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = SiteRules.normalizedHost(url)
        else { return .forbidden }
        return verdict(forHost: host)
    }

    /// The verdict for any `http(s)` URL on `host`.
    public func verdict(forHost rawHost: String) -> SiteVerdict {
        guard let host = SiteRules.normalizedDomain(rawHost) else { return .forbidden }
        if !allowPrivateNetworkHosts, Self.isPrivateNetworkHost(host) { return .forbidden }
        let open: SiteVerdict = imagesAllowed ? .everything : .textOnly

        if isAllowedOnce(host: host) { return open }
        if let rule = rule(forHost: host) {
            switch rule.access {
            case .allow: return open
            case .textOnly: return .textOnly
            case .block: return .blocked(SiteBlock(reason: .userBlocked, domain: rule.domain))
            }
        }
        if filterAdultSites, let domain = adultDomain(forHost: host) {
            return .blocked(SiteBlock(reason: .adultSite, domain: domain))
        }
        if restrictToAllowedDomains {
            let domain = SiteRules.suggestedRuleDomain(forHost: host) ?? host
            return .blocked(SiteBlock(reason: .notAllowed, domain: domain))
        }
        return open
    }

    /// Whether Vela may request `url` at all (pages, oEmbed, redirect hops).
    public func allows(_ url: URL) -> Bool {
        switch verdict(for: url) {
        case .everything, .textOnly: true
        case .blocked, .forbidden: false
        }
    }

    /// Whether Vela may load `url` as an image, thumbnail, favicon, poster or
    /// direct video. Only "everything" sites qualify.
    public func allowsImage(_ url: URL) -> Bool {
        verdict(for: url) == .everything
    }

    /// The most specific site rule for `host`. Hosts of a video provider's
    /// asset domains (`youtu.be`, `i.ytimg.com`) without a rule of their own
    /// follow the provider's main-domain rule.
    public func rule(forHost host: String) -> (domain: String, access: SiteAccess)? {
        guard !siteRules.isEmpty else { return nil }
        if let match = siteRules.access(forHost: host) { return match }
        if let provider = EmbedProvider.provider(forHost: host) {
            return siteRules.access(forHost: provider.mainDomain)
        }
        return nil
    }

    /// Whether `host` is covered by an `allowedOnce` domain.
    public func isAllowedOnce(host: String) -> Bool {
        guard !allowedOnce.isEmpty, let host = SiteRules.normalizedDomain(host) else { return false }
        return allowedOnce.contains { entry in
            SiteRules.normalizedDomain(entry).map { SiteRules.host(host, isWithin: $0) } ?? false
        }
    }

    /// The adult-list domain covering `host` (bundled list, then `extraAdultDomains`),
    /// regardless of `filterAdultSites`.
    public func adultDomain(forHost host: String) -> String? {
        if let match = AdultSiteList.bundled.matchingDomain(forHost: host) { return match }
        guard !extraAdultDomains.isEmpty, let host = SiteRules.normalizedDomain(host) else { return nil }
        for suffix in SiteRules.domainSuffixes(of: host) {
            if extraAdultDomains.contains(where: { SiteRules.normalizedDomain($0) == suffix }) { return suffix }
        }
        return nil
    }

    // MARK: - Errors

    /// Nil when `url` may be requested; otherwise the error to fail with.
    func requestError(for url: URL) -> MediaError? {
        switch verdict(for: url) {
        case .everything, .textOnly: nil
        case .blocked(let block): .siteBlocked(block)
        case .forbidden: .blockedByPolicy
        }
    }

    /// Nil when `url` may be loaded as an image or video; otherwise the error to fail with.
    func imageError(for url: URL) -> MediaError? {
        switch verdict(for: url) {
        case .everything: nil
        case .blocked(let block): .siteBlocked(block)
        case .textOnly, .forbidden: .blockedByPolicy
        }
    }

    /// The policy with the switches that don't change what a fetch returns
    /// reset, so previews and remembered failures are shared across them.
    var fetchKey: MediaPolicy {
        var key = self
        key.autoLoad = true
        key.showLinkCards = true
        key.imagesAllowed = true
        return key
    }

    // MARK: - Private networks

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
