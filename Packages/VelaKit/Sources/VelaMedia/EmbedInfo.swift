// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Video sites whose players Vela can embed.
public enum EmbedProvider: String, Sendable, Codable, Hashable, CaseIterable {
    case youtube, vimeo, twitch, streamable

    /// Human-readable name, e.g. for a card's site label.
    public var displayName: String {
        switch self {
        case .youtube: "YouTube"
        case .vimeo: "Vimeo"
        case .twitch: "Twitch"
        case .streamable: "Streamable"
        }
    }

    /// The provider's brand color as `#RRGGBB`, used as a card accent.
    public var brandColor: String {
        switch self {
        case .youtube: "#FF0000"
        case .vimeo: "#1AB7EA"
        case .twitch: "#9146FF"
        case .streamable: "#0F90FA"
        }
    }

    /// The domain a site rule for this provider is written for. Rules for it
    /// also cover `assetDomains` (short links, players, thumbnails) unless
    /// those have rules of their own.
    public var mainDomain: String {
        switch self {
        case .youtube: "youtube.com"
        case .vimeo: "vimeo.com"
        case .twitch: "twitch.tv"
        case .streamable: "streamable.com"
        }
    }

    /// Other domains the provider serves its links, players and thumbnails from.
    public var assetDomains: [String] {
        switch self {
        case .youtube: ["youtu.be", "youtube-nocookie.com", "ytimg.com"]
        case .vimeo: ["vimeocdn.com"]
        case .twitch: ["jtvnw.net"]
        case .streamable: []
        }
    }

    /// The provider whose main or asset domains cover `host`, if any.
    public static func provider(forHost host: String) -> EmbedProvider? {
        guard let host = SiteRules.normalizedDomain(host) else { return nil }
        return allCases.first { provider in
            SiteRules.host(host, isWithin: provider.mainDomain)
                || provider.assetDomains.contains { SiteRules.host(host, isWithin: $0) }
        }
    }
}

/// Everything needed to show a video facade and, on click, its player.
public struct EmbedInfo: Sendable, Codable, Hashable {
    public var provider: EmbedProvider
    /// Provider-specific ID: YouTube video ID, Vimeo numeric ID,
    /// Twitch clip slug or numeric VOD ID, Streamable short code.
    public var videoID: String
    /// Where playback should start, when the link carried a timestamp.
    public var startSeconds: Int?
    /// The player URL to load inside `EmbedPlayerHTML`'s iframe.
    public var embedURL: URL
    public var thumbnailURL: URL?
    public var title: String?
    public var authorName: String?
    /// Width / height of the player. 16:9 unless known otherwise
    /// (YouTube Shorts are 9:16).
    public var aspectRatio: Double

    public init(
        provider: EmbedProvider,
        videoID: String,
        startSeconds: Int? = nil,
        embedURL: URL,
        thumbnailURL: URL? = nil,
        title: String? = nil,
        authorName: String? = nil,
        aspectRatio: Double = 16.0 / 9.0
    ) {
        self.provider = provider
        self.videoID = videoID
        self.startSeconds = startSeconds
        self.embedURL = embedURL
        self.thumbnailURL = thumbnailURL
        self.title = title
        self.authorName = authorName
        self.aspectRatio = aspectRatio
    }
}

extension EmbedInfo {
    /// Host that Twitch embeds must name in their `parent` parameter.
    /// It has to match the page the iframe lives in, i.e. `EmbedPlayerHTML.baseURL`.
    static var twitchParent: String {
        EmbedPlayerHTML.baseURL.host() ?? "r3volution11.github.io"
    }

    static func youtube(id: String, start: Int?, isShort: Bool) -> EmbedInfo {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube-nocookie.com"
        components.path = "/embed/\(id)"
        var items: [URLQueryItem] = []
        if let start { items.append(URLQueryItem(name: "start", value: String(start))) }
        items += [
            URLQueryItem(name: "autoplay", value: "1"),
            URLQueryItem(name: "playsinline", value: "1"),
            URLQueryItem(name: "rel", value: "0"),
        ]
        components.queryItems = items
        return EmbedInfo(
            provider: .youtube,
            videoID: id,
            startSeconds: start,
            embedURL: components.url!,
            thumbnailURL: URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg"),
            aspectRatio: isShort ? 9.0 / 16.0 : 16.0 / 9.0
        )
    }

    static func vimeo(id: String, hash: String?, start: Int?) -> EmbedInfo {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "player.vimeo.com"
        components.path = "/video/\(id)"
        if let hash { components.queryItems = [URLQueryItem(name: "h", value: hash)] }
        // Vimeo's player reads the start time from the fragment.
        if let start { components.fragment = "t=\(start)s" }
        return EmbedInfo(provider: .vimeo, videoID: id, startSeconds: start, embedURL: components.url!)
    }

    static func twitchClip(slug: String) -> EmbedInfo {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "clips.twitch.tv"
        components.path = "/embed"
        components.queryItems = [
            URLQueryItem(name: "clip", value: slug),
            URLQueryItem(name: "parent", value: twitchParent),
        ]
        return EmbedInfo(provider: .twitch, videoID: slug, embedURL: components.url!)
    }

    static func twitchVideo(id: String, start: Int?) -> EmbedInfo {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "player.twitch.tv"
        components.path = "/"
        var items = [
            URLQueryItem(name: "video", value: id),
            URLQueryItem(name: "parent", value: twitchParent),
        ]
        if let start { items.append(URLQueryItem(name: "time", value: TimestampParser.twitchFormat(start))) }
        components.queryItems = items
        return EmbedInfo(provider: .twitch, videoID: id, startSeconds: start, embedURL: components.url!)
    }

    static func streamable(id: String) -> EmbedInfo {
        EmbedInfo(provider: .streamable, videoID: id, embedURL: URL(string: "https://streamable.com/e/\(id)")!)
    }

    /// The public page for this video, used as the `url` parameter of oEmbed lookups.
    var canonicalPageURL: URL? {
        switch provider {
        case .youtube:
            if aspectRatio < 1 { return URL(string: "https://www.youtube.com/shorts/\(videoID)") }
            return URL(string: "https://www.youtube.com/watch?v=\(videoID)")
        case .vimeo:
            let hash = URLComponents(url: embedURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "h" }?.value
            if let hash { return URL(string: "https://vimeo.com/\(videoID)/\(hash)") }
            return URL(string: "https://vimeo.com/\(videoID)")
        case .twitch:
            if embedURL.host() == "clips.twitch.tv" { return URL(string: "https://clips.twitch.tv/\(videoID)") }
            return URL(string: "https://www.twitch.tv/videos/\(videoID)")
        case .streamable:
            return URL(string: "https://streamable.com/\(videoID)")
        }
    }
}

/// Parses timestamps as written in video links: `90`, `90s`, `1m30s`,
/// `1h2m3s`, `1:30`, `01:02:03`.
enum TimestampParser {
    static func seconds(from raw: String) -> Int? {
        let value = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !value.isEmpty else { return nil }

        let total: Int?
        if value.allSatisfy(\.isASCIIDigit) {
            total = Int(value)
        } else if value.contains(":") {
            let parts = value.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count <= 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCIIDigit) }) else {
                return nil
            }
            total = parts.reduce(0) { $0 * 60 + (Int($1) ?? 0) }
        } else {
            var sum = 0
            var number = ""
            var sawUnit = false
            for character in value {
                if character.isASCIIDigit {
                    number.append(character)
                    continue
                }
                guard let amount = Int(number) else { return nil }
                switch character {
                case "h": sum += amount * 3600
                case "m": sum += amount * 60
                case "s": sum += amount
                default: return nil
                }
                sawUnit = true
                number = ""
            }
            if !number.isEmpty {
                // A trailing bare number counts as seconds ("1m30").
                guard let amount = Int(number) else { return nil }
                sum += amount
            }
            total = sawUnit ? sum : nil
        }
        guard let total, total > 0, total < 7 * 24 * 3600 else { return nil }
        return total
    }

    /// Twitch's `time` parameter format: `1h2m3s`.
    static func twitchFormat(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        return "\(hours)h\(minutes)m\(secs)s"
    }
}

extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
