// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import Foundation

/// Reddit links: `v.redd.it` videos play inline; links to posts get a card
/// with the post's title, subreddit and author.
///
/// Reddit answers clients that don't run JavaScript with a challenge page
/// instead of the post, and its JSON API needs an account, so Vela reads:
/// - Reddit's public oEmbed endpoint, for a post's title and author;
/// - the post's address (where `v.redd.it/<id>` redirects), for the subreddit;
/// - a video's HLS playlist, for its shape and whether it has sound (a
///   Reddit "GIF" is a video without sound).
///
/// None of these say whether a post is NSFW, so a Reddit video shows a plain
/// facade (no thumbnail or frame) until it's clicked, and never autoplays.
enum RedditLinks {
    /// Reddit's own icon, for link cards.
    static let faviconURL = URL(string: "https://www.redditstatic.com/shreddit/assets/favicon/64x64.png")!

    static func playlistURL(videoID: String) -> URL {
        URL(string: "https://v.redd.it/\(videoID)/HLSPlaylist.m3u8")!
    }

    // MARK: Videos

    /// `v.redd.it/<id>`, a file of it (`v.redd.it/<id>/HLSPlaylist.m3u8`),
    /// or `reddit.com/video/<id>`.
    static func videoID(_ parts: MediaClassifier.URLParts) -> String? {
        let segments = parts.segments
        let id: String?
        if parts.host == "v.redd.it" {
            id = segments.first
        } else if parts.hostIs("reddit.com"), segments.count == 2, segments[0] == "video" {
            id = segments[1]
        } else {
            id = nil
        }
        guard let id, isID(id) else { return nil }
        return id
    }

    // MARK: Posts

    /// A link to a post, and what its address says.
    struct Post: Hashable {
        var id: String
        /// "r/aww", or "u/name" for a post on a profile.
        var community: String?
        /// The title as the address spells it ("jet_powered_skateboard").
        var slug: String?
        /// `https://www.reddit.com/…/comments/<id>/<slug>/`.
        var canonicalURL: URL
        /// The address to ask Reddit's oEmbed about: `canonicalURL`, except
        /// for a post without a subreddit or profile in its address
        /// (`reddit.com/comments/<id>`, where `redd.it` short links lead).
        /// Reddit's oEmbed refuses those, but finds a post by its id under
        /// any subreddit, and its markup names the real one; so they're
        /// asked about as `r/all`.
        var oEmbedURL: URL
    }

    /// `reddit.com/r/<sub>/comments/<id>/<slug>`, `reddit.com/comments/<id>`
    /// or `reddit.com/user/<name>/comments/<id>`, on www, old, new, np or m.
    /// Short links (`redd.it/<id>`, `reddit.com/r/<sub>/s/<code>`) aren't
    /// posts until their redirect says which.
    static func post(_ url: URL) -> Post? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = SiteRules.normalizedHost(url), SiteRules.host(host, isWithin: "reddit.com")
        else { return nil }
        let segments = url.path(percentEncoded: false).split(separator: "/").map(String.init)
        guard let comments = segments.firstIndex(of: "comments"), comments + 1 < segments.count else { return nil }
        let prefix = Array(segments[..<comments])
        let community: String?
        switch prefix.count {
        case 0:
            community = nil
        case 2 where prefix[0] == "r" && isName(prefix[1]):
            community = "r/" + prefix[1]
        case 2 where (prefix[0] == "user" || prefix[0] == "u") && isName(prefix[1]):
            community = "u/" + prefix[1]
        default:
            return nil
        }
        let id = segments[comments + 1]
        guard isID(id) else { return nil }
        let slug = comments + 2 < segments.count ? segments[comments + 2] : nil

        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.reddit.com"
        components.path = "/" + (prefix + ["comments", id] + (slug.map { [$0] } ?? [])).joined(separator: "/") + "/"
        guard let canonical = components.url else { return nil }
        var oEmbed = canonical
        if prefix.isEmpty {
            components.path = "/r/all/comments/\(id)/"
            guard let any = components.url else { return nil }
            oEmbed = any
        }
        return Post(id: id, community: community, slug: slug, canonicalURL: canonical, oEmbedURL: oEmbed)
    }

    /// "jet_powered_skateboard" → "Jet powered skateboard": a title for when
    /// Reddit doesn't give one.
    static func title(fromSlug slug: String?) -> String? {
        guard let slug else { return nil }
        let words = slug.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
        guard !words.isEmpty, words.contains(where: \.isLetter) else { return nil }
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    /// The subreddit Reddit's oEmbed markup links to: "r/LoveTrash".
    static func community(inEmbedHTML html: String?) -> String? {
        guard let html, let range = html.range(of: #"reddit\.com/r/[A-Za-z0-9_]{2,32}/"#, options: .regularExpression)
        else { return nil }
        let name = html[range].dropFirst("reddit.com/r/".count).dropLast()
        return "r/" + name
    }

    /// Reddit's age check (`/over18`), which it sends NSFW posts to.
    static func isAgeGate(_ url: URL) -> Bool {
        guard let host = SiteRules.normalizedHost(url), SiteRules.host(host, isWithin: "reddit.com") else { return false }
        return url.path(percentEncoded: false).split(separator: "/").first == "over18"
    }

    // MARK: Character classes

    /// Reddit IDs are lowercase base 36.
    static func isID(_ id: String) -> Bool {
        (3...20).contains(id.utf8.count)
            && id.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) }
    }

    private static func isName(_ name: String) -> Bool {
        (2...32).contains(name.utf8.count) && name.unicodeScalars.allSatisfy {
            ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0) || $0 == "_" || $0 == "-"
        }
    }
}

// MARK: - HLS

/// What a video's HLS master playlist says about it.
struct HLSPlaylistSummary: Sendable, Hashable {
    /// It has a sound track: an audio rendition group, or audio codecs in a variant.
    var hasAudio: Bool
    /// The largest variant's `RESOLUTION`, when given.
    var largestResolution: CGSize?

    /// Width / height of the largest variant.
    var aspectRatio: Double? {
        guard let size = largestResolution, size.width > 0, size.height > 0 else { return nil }
        return size.width / size.height
    }
}

enum HLSPlaylist {
    static let maxBytes = 64 * 1024
    static let accept = "application/vnd.apple.mpegurl,application/x-mpegurl;q=0.9,*/*;q=0.5"

    /// Codec prefixes of audio formats (`mp4a.40.2`, `ac-3`, …).
    private static let audioCodecs = ["mp4a", "ac-3", "ec-3", "opus", "flac", "alac"]

    /// Nil when `text` isn't a master playlist.
    static func summary(_ text: String) -> HLSPlaylistSummary? {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        guard lines.first?.hasPrefix("#EXTM3U") == true else { return nil }
        var hasAudio = false
        var largest: CGSize?
        var sawVariant = false
        for line in lines {
            if line.hasPrefix("#EXT-X-MEDIA:") {
                if attribute("TYPE", in: line)?.uppercased() == "AUDIO" { hasAudio = true }
            } else if line.hasPrefix("#EXT-X-STREAM-INF:") {
                sawVariant = true
                if attribute("AUDIO", in: line) != nil { hasAudio = true }
                if let codecs = attribute("CODECS", in: line)?.lowercased(),
                   codecs.split(separator: ",").contains(where: { codec in
                       audioCodecs.contains { codec.trimmingCharacters(in: .whitespaces).hasPrefix($0) }
                   }) {
                    hasAudio = true
                }
                if let resolution = attribute("RESOLUTION", in: line) {
                    let parts = resolution.lowercased().split(separator: "x").compactMap { Double($0) }
                    if parts.count == 2, parts[0] > 0, parts[1] > 0,
                       parts[0] * parts[1] > (largest.map { $0.width * $0.height } ?? 0) {
                        largest = CGSize(width: parts[0], height: parts[1])
                    }
                }
            }
        }
        guard sawVariant else { return nil }
        return HLSPlaylistSummary(hasAudio: hasAudio, largestResolution: largest)
    }

    /// An attribute's value in a tag line: `CODECS="avc1.64001f,mp4a.40.2"` → `avc1.64001f,mp4a.40.2`.
    static func attribute(_ name: String, in line: String) -> String? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        var rest = line[line.index(after: colon)...]
        while !rest.isEmpty {
            guard let equals = rest.firstIndex(of: "=") else { return nil }
            let key = rest[..<equals].trimmingCharacters(in: .whitespaces)
            rest = rest[rest.index(after: equals)...]
            let value: Substring
            if rest.first == "\"" {
                rest = rest.dropFirst()
                let end = rest.firstIndex(of: "\"") ?? rest.endIndex
                value = rest[..<end]
                rest = end < rest.endIndex ? rest[rest.index(after: end)...] : rest[rest.endIndex...]
            } else {
                let end = rest.firstIndex(of: ",") ?? rest.endIndex
                value = rest[..<end]
                rest = rest[end...]
            }
            if rest.first == "," { rest = rest.dropFirst() }
            if key == name { return String(value) }
        }
        return nil
    }
}
