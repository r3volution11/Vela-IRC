// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// What a URL most likely points at, decided without touching the network.
public enum MediaClassification: Sendable, Hashable {
    /// A direct image file. The associated URL may be rewritten
    /// (e.g. a GitHub `blob` page to `raw.githubusercontent.com`).
    case image(URL)
    /// A direct video file (e.g. `.mp4`, or Imgur `.gifv` rewritten to `.mp4`).
    case video(URL)
    /// A video from a site whose player can be embedded.
    case embed(EmbedInfo)
    /// Anything else: an HTML page to summarize as a link card.
    case page(URL)
}

/// Classifies URLs by host, path and extension. Pure and synchronous.
public enum MediaClassifier {
    public static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "avif", "bmp", "tiff", "tif", "apng",
    ]
    public static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]

    public static func classify(_ url: URL) -> MediaClassification {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let rawHost = url.host(percentEncoded: false), !rawHost.isEmpty
        else { return .page(url) }

        let parts = URLParts(url: url, host: rawHost)

        if let embed = youTube(parts) ?? vimeo(parts) ?? twitch(parts) ?? streamable(parts) {
            return .embed(embed)
        }
        if let rewritten = rewrite(parts) {
            return rewritten
        }

        let ext = url.pathExtension.lowercased()
        if imageExtensions.contains(ext) { return .image(url) }
        if videoExtensions.contains(ext) { return .video(url) }
        return .page(url)
    }

    // MARK: - URL pieces

    struct URLParts {
        let url: URL
        /// Lowercased, without a trailing dot.
        let host: String
        /// Non-empty path segments, percent-decoded.
        let segments: [String]
        let query: [String: String]
        let fragment: [String: String]

        init(url: URL, host: String) {
            self.url = url
            var host = host.lowercased()
            if host.hasSuffix(".") { host.removeLast() }
            self.host = host
            self.segments = url.path(percentEncoded: false).split(separator: "/").map(String.init)

            var query: [String: String] = [:]
            for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
                if query[item.name] == nil { query[item.name] = item.value ?? "" }
            }
            self.query = query

            // Fragments like `#t=1m30s` use query syntax.
            var fragment: [String: String] = [:]
            for pair in (url.fragment(percentEncoded: false) ?? "").split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2, fragment[kv[0]] == nil { fragment[kv[0]] = kv[1] }
            }
            self.fragment = fragment
        }

        func hostIs(_ domain: String) -> Bool {
            host == domain || host.hasSuffix("." + domain)
        }
    }

    // MARK: - Providers

    private static func youTube(_ parts: URLParts) -> EmbedInfo? {
        var id: String?
        var isShort = false

        if parts.hostIs("youtu.be") {
            id = parts.segments.first
        } else if parts.hostIs("youtube.com") || parts.hostIs("youtube-nocookie.com") {
            switch parts.segments.first {
            case "watch":
                id = parts.query["v"]
            case "shorts":
                id = parts.segments.dropFirst().first
                isShort = true
            case "embed", "live", "v", "e":
                id = parts.segments.dropFirst().first
            case nil:
                id = parts.query["v"]
            default:
                id = nil
            }
        }
        guard let id, isValidYouTubeID(id) else { return nil }

        let rawStart = parts.query["t"] ?? parts.query["start"] ?? parts.query["time_continue"]
            ?? parts.fragment["t"]
        let start = rawStart.flatMap(TimestampParser.seconds(from:))
        return .youtube(id: id, start: start, isShort: isShort)
    }

    private static func isValidYouTubeID(_ id: String) -> Bool {
        id.utf8.count == 11 && id.unicodeScalars.allSatisfy { isIDScalar($0) }
    }

    private static func vimeo(_ parts: URLParts) -> EmbedInfo? {
        guard parts.hostIs("vimeo.com") else { return nil }
        let segments = parts.segments
        var id: String?
        var hash: String?

        if parts.host == "player.vimeo.com" {
            guard segments.count >= 2, segments[0] == "video", isDigits(segments[1]) else { return nil }
            id = segments[1]
            hash = parts.query["h"]
        } else if let first = segments.first, isDigits(first) {
            // vimeo.com/<id> or vimeo.com/<id>/<unlisted hash>
            id = first
            if segments.count >= 2, isHex(segments[1]) { hash = segments[1] }
        } else if let first = segments.first,
                  ["channels", "groups", "album", "showcase"].contains(first),
                  let last = segments.last, isDigits(last), segments.count >= 3 {
            // vimeo.com/channels/staffpicks/<id>, vimeo.com/groups/<g>/videos/<id>, …
            id = last
        }
        guard let id else { return nil }
        if hash.map({ !isHex($0) }) ?? false { hash = nil }

        let rawStart = parts.fragment["t"] ?? parts.query["t"]
        let start = rawStart.flatMap(TimestampParser.seconds(from:))
        return .vimeo(id: id, hash: hash, start: start)
    }

    private static func twitch(_ parts: URLParts) -> EmbedInfo? {
        let segments = parts.segments
        if parts.host == "clips.twitch.tv" {
            let slug = segments.first == "embed" ? parts.query["clip"] : segments.first
            guard let slug, segments.count <= 1 || segments.first == "embed", isValidSlug(slug),
                  slug != "embed", slug != "create"
            else { return nil }
            return .twitchClip(slug: slug)
        }
        guard parts.host == "twitch.tv" || parts.host == "www.twitch.tv" || parts.host == "m.twitch.tv" else {
            return nil
        }
        if segments.count >= 3, segments[1] == "clip", isValidSlug(segments[2]) {
            return .twitchClip(slug: segments[2])
        }
        if segments.count >= 2, segments[0] == "videos" {
            // VOD IDs are numeric; links sometimes carry a "v" prefix.
            var id = segments[1]
            if id.hasPrefix("v") { id.removeFirst() }
            guard isDigits(id) else { return nil }
            let start = parts.query["t"].flatMap(TimestampParser.seconds(from:))
            return .twitchVideo(id: id, start: start)
        }
        return nil
    }

    /// First path segments on streamable.com that are site pages, not videos.
    private static let streamableReserved: Set<String> = [
        "about", "account", "api", "blog", "careers", "clipper", "community", "contact", "documentation",
        "download", "e", "embed", "faq", "help", "home", "legal", "login", "logout", "o", "pricing",
        "privacy", "s", "settings", "signup", "support", "terms", "upload", "videos",
    ]

    private static func streamable(_ parts: URLParts) -> EmbedInfo? {
        guard parts.host == "streamable.com" || parts.host == "www.streamable.com" else { return nil }
        let segments = parts.segments
        let id: String?
        switch segments.count {
        case 1: id = segments[0]
        case 2 where ["e", "o", "s"].contains(segments[0]): id = segments[1]
        default: id = nil
        }
        guard let id, (3...16).contains(id.count), !streamableReserved.contains(id.lowercased()),
              id.unicodeScalars.allSatisfy({ $0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0)) })
        else { return nil }
        return .streamable(id: id)
    }

    // MARK: - Rewrites

    private static func rewrite(_ parts: URLParts) -> MediaClassification? {
        let url = parts.url

        // i.imgur.com/<id>.gifv is an HTML wrapper around an MP4.
        if parts.host == "i.imgur.com", url.pathExtension.lowercased() == "gifv",
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.path = (components.path as NSString).deletingPathExtension + ".mp4"
            components.query = nil
            components.fragment = nil
            if let mp4 = components.url { return .video(mp4) }
        }

        // github.com/<owner>/<repo>/blob/<ref>/<path> → raw.githubusercontent.com/<owner>/<repo>/<ref>/<path>
        if parts.host == "github.com" || parts.host == "www.github.com" {
            let segments = parts.segments
            let ext = url.pathExtension.lowercased()
            let isImage = imageExtensions.contains(ext)
            let isVideo = videoExtensions.contains(ext)
            if segments.count >= 5, segments[2] == "blob", isImage || isVideo {
                var components = URLComponents()
                components.scheme = "https"
                components.host = "raw.githubusercontent.com"
                let rest = [segments[0], segments[1]] + segments[3...]
                components.path = "/" + rest.joined(separator: "/")
                if let raw = components.url { return isImage ? .image(raw) : .video(raw) }
            }
        }
        return nil
    }

    // MARK: - Character classes

    private static func isIDScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "a"..."z", "A"..."Z", "0"..."9", "-", "_": true
        default: false
        }
    }

    private static func isValidSlug(_ slug: String) -> Bool {
        (1...128).contains(slug.utf8.count) && slug.unicodeScalars.allSatisfy { isIDScalar($0) }
    }

    private static func isDigits(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 20 && value.unicodeScalars.allSatisfy { ("0"..."9").contains($0) }
    }

    private static func isHex(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy {
            ("0"..."9").contains($0) || ("a"..."f").contains($0) || ("A"..."F").contains($0)
        }
    }
}
