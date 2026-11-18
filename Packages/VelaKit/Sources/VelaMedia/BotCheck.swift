// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Why a page fetched without a browser has nothing to preview, and only a
/// browser would see the real page.
enum BotCheck: Sendable, Hashable {
    /// A bot check: a challenge or interstitial that a browser passes by
    /// running the site's own script.
    case challenge(BotCheckService)
    /// A page that is only scripts: no title, no metadata and almost no
    /// text, so its content comes from JavaScript.
    case scriptShell
}

/// Who served a bot check, as far as the response says.
enum BotCheckService: String, Sendable, Hashable, CaseIterable {
    case awsWAF
    case cloudflare
    case akamai
    case dataDome
    case perimeterX
    case imperva
    /// A "Just a moment…" or "Please enable JavaScript" page from anyone else.
    case other
}

/// Decides, from the quick fetch's status, headers and HTML, whether a page
/// is a bot check or a script-only shell (`BotCheck`).
///
/// A page whose metadata already says what it is (a description, an image,
/// a site name or an `og:type`) never is, whatever scripts it carries:
/// many ordinary pages load a bot manager's script too. Otherwise:
/// 1. a header that only bot checks send (`cf-mitigated: challenge`,
///    `x-amzn-waf-action`), or markup that only their pages carry
///    (`awsWafCookieDomainList`, `_cf_chl_opt`, `captcha-delivery.com`, …);
/// 2. a title that only bot checks use ("Just a moment…");
/// 3. a page with no title asking for JavaScript, or made only of scripts.
///
/// An error status (403, 429, 503) counts only with 1 or 2: an ordinary
/// error page stays an error.
enum BotCheckDetector {
    static func assess(
        status: Int,
        headers: [String: String],
        html: String,
        metadata: HTMLMetadata
    ) -> BotCheck? {
        if hasPageMetadata(metadata) { return nil }
        let lowerHeaders = Dictionary(
            headers.map { ($0.key.lowercased(), $0.value.lowercased()) },
            uniquingKeysWith: { first, _ in first }
        )
        let lowerHTML = html.lowercased()
        if let service = service(headers: lowerHeaders) ?? service(markup: lowerHTML) {
            return .challenge(service)
        }
        if let title = metadata.title {
            return isChallengeTitle(title) ? .challenge(service(title: title)) : nil
        }
        guard (200..<300).contains(status) else { return nil }
        if asksForJavaScript(lowerHTML) || isScriptShell(lowerHTML) { return .scriptShell }
        return nil
    }

    static func assess(_ response: HTTPURLResponse, html: String, metadata: HTMLMetadata) -> BotCheck? {
        var headers: [String: String] = [:]
        for (name, value) in response.allHeaderFields {
            if let name = name as? String, let value = value as? String { headers[name] = value }
        }
        return assess(status: response.statusCode, headers: headers, html: html, metadata: metadata)
    }

    /// Statuses bot checks answer with besides 2xx; the body is read for
    /// them only to tell a check from an ordinary error page.
    static let challengeStatuses: Set<Int> = [403, 405, 429, 503]

    /// Metadata a bot check's page never has.
    static func hasPageMetadata(_ metadata: HTMLMetadata) -> Bool {
        metadata.summary != nil || metadata.imageURL != nil || metadata.siteName != nil || metadata.type != nil
            || metadata.videoURL != nil || metadata.oEmbedURL != nil
    }

    /// Whether `metadata` (from the browser engine) is the real page rather
    /// than a bot check still at work: metadata a check never has, or a
    /// title that isn't a check's.
    static func isRealPage(_ metadata: HTMLMetadata) -> Bool {
        if hasPageMetadata(metadata) { return true }
        guard let title = metadata.title else { return false }
        return !isChallengeTitle(title)
    }

    // MARK: - Signals

    private static func service(headers: [String: String]) -> BotCheckService? {
        if headers["cf-mitigated"] == "challenge" { return .cloudflare }
        if let action = headers["x-amzn-waf-action"], action == "challenge" || action == "captcha" { return .awsWAF }
        return nil
    }

    /// Markup found only on bot checks' pages, lowercased.
    static let markers: [(String, BotCheckService)] = [
        ("awswafcookiedomainlist", .awsWAF),
        ("window.gokuprops", .awsWAF),
        ("awswafintegration.checkforcerefresh", .awsWAF),
        ("_cf_chl_opt", .cloudflare),
        ("__cf_chl_", .cloudflare),
        ("cf-browser-verification", .cloudflare),
        ("cf_chl_prog", .cloudflare),
        ("/_sec/cp_challenge/", .akamai),
        ("bm-verify", .akamai),
        ("captcha-delivery.com", .dataDome),
        ("px-captcha", .perimeterX),
        ("_pxcaptcha", .perimeterX),
        ("/_incapsula_resource", .imperva),
    ]

    private static func service(markup: String) -> BotCheckService? {
        markers.first { markup.contains($0.0) }?.1
    }

    /// Titles only bot checks use, lowercased, without trailing dots or
    /// ellipses.
    static let challengeTitles: [(String, BotCheckService)] = [
        ("just a moment", .cloudflare),
        ("attention required! | cloudflare", .cloudflare),
        ("checking your browser", .other),
        ("please wait while we verify", .other),
        ("verifying you are human", .other),
        ("human verification", .other),
        ("access to this page has been denied", .perimeterX),
        ("pardon our interruption", .imperva),
        ("are you a robot?", .other),
        ("robot or human?", .other),
        ("ddos-guard", .other),
        // Placeholders a script replaces once the real page is ready.
        ("loading", .other),
        ("please wait", .other),
    ]

    static func isChallengeTitle(_ title: String) -> Bool {
        let folded = normalizedTitle(title)
        return challengeTitles.contains { folded == $0.0 }
    }

    private static func service(title: String) -> BotCheckService {
        let folded = normalizedTitle(title)
        return challengeTitles.first { folded == $0.0 }?.1 ?? .other
    }

    private static func normalizedTitle(_ title: String) -> String {
        var folded = title.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        while let last = folded.last, last == "." || last == "…" { folded.removeLast() }
        return folded
    }

    /// Phrases from `<noscript>` notes and interstitials.
    static let javaScriptPhrases = [
        "please enable javascript",
        "enable javascript and cookies to continue",
        "javascript is disabled",
        "javascript is required",
        "requires javascript",
        "you need to enable javascript",
        "please turn javascript on",
    ]

    private static func asksForJavaScript(_ html: String) -> Bool {
        javaScriptPhrases.contains { html.contains($0) }
    }

    /// Scripts, and next to no text outside them.
    static func isScriptShell(_ html: String) -> Bool {
        guard html.contains("<script") else { return false }
        return visibleTextLength(html, limit: 200) < 200
    }

    /// Roughly how much text a reader would see, counting up to `limit`:
    /// what's outside tags, scripts, styles, `<noscript>` and comments.
    static func visibleTextLength(_ html: String, limit: Int) -> Int {
        var count = 0
        var index = html.startIndex
        var lastWasSpace = true
        while index < html.endIndex, count < limit {
            let character = html[index]
            if character == "<" {
                let rest = html[index...]
                if let skipTo = skippedElementEnd(rest) {
                    index = skipTo
                    continue
                }
                guard let close = rest.firstIndex(of: ">") else { break }
                index = html.index(after: close)
                continue
            }
            if character.isWhitespace {
                if !lastWasSpace { count += 1 }
                lastWasSpace = true
            } else {
                count += 1
                lastWasSpace = false
            }
            index = html.index(after: index)
        }
        return count
    }

    /// For `<script…`, `<style…`, `<noscript…`, `<template…` and `<!--`: where
    /// the element (or comment) ends, or the end of the text.
    private static func skippedElementEnd(_ rest: Substring) -> String.Index? {
        if rest.hasPrefix("<!--") {
            return rest.range(of: "-->")?.upperBound ?? rest.endIndex
        }
        for name in ["script", "style", "noscript", "template"] where rest.dropFirst().hasPrefix(name) {
            guard let close = rest.range(of: "</\(name)") else { return rest.endIndex }
            return rest[close.upperBound...].firstIndex(of: ">").map { rest.index(after: $0) } ?? rest.endIndex
        }
        return nil
    }
}
