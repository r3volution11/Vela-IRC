// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Metadata extracted from a page's `<head>`. Strings are entity-decoded with
/// whitespace collapsed; URLs are absolute `http(s)` URLs.
public struct HTMLMetadata: Sendable, Hashable {
    public var title: String?
    public var summary: String?
    public var siteName: String?
    /// `#RRGGBB` from `<meta name="theme-color">`.
    public var themeColor: String?
    /// `og:type`, e.g. `website`, `article`, `video.other`.
    public var type: String?
    public var imageURL: URL?
    public var faviconURL: URL?
    /// From `<link rel="alternate" type="application/json+oembed">`.
    public var oEmbedURL: URL?
    public var videoURL: URL?
    public var imageWidth: Int?
    public var imageHeight: Int?

    public init(
        title: String? = nil,
        summary: String? = nil,
        siteName: String? = nil,
        themeColor: String? = nil,
        type: String? = nil,
        imageURL: URL? = nil,
        faviconURL: URL? = nil,
        oEmbedURL: URL? = nil,
        videoURL: URL? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil
    ) {
        self.title = title
        self.summary = summary
        self.siteName = siteName
        self.themeColor = themeColor
        self.type = type
        self.imageURL = imageURL
        self.faviconURL = faviconURL
        self.oEmbedURL = oEmbedURL
        self.videoURL = videoURL
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
    }
}

/// Extracts OpenGraph, Twitter card and plain HTML metadata from a page.
///
/// Sources, in priority order:
/// - title: `og:title`, `twitter:title`, `<title>`, `itemprop=name`
/// - summary: `og:description`, `twitter:description`, `<meta name=description>`
/// - site name: `og:site_name`, `application-name`
/// - image: `og:image:secure_url`/`og:image`/`og:image:url`, `twitter:image(:src)`,
///   `<link rel=image_src>`, `itemprop=image`
/// - favicon: `<link rel=icon|shortcut icon|apple-touch-icon>`, preferring
///   raster icons of at least 32 px
///
/// Scanning stops at `</head>` when present; `<base href>` is honored.
public enum HTMLMetadataParser {
    public static func parse(html: String, baseURL: URL) -> HTMLMetadata {
        parse(bytes: Array(html.utf8), baseURL: baseURL)
    }

    static func parse(bytes: [UInt8], baseURL: URL) -> HTMLMetadata {
        var scanner = HTMLTagScanner(bytes: bytes)
        var collector = Collector()

        scanning: while let token = scanner.next() {
            switch token {
            case .endTag(let name):
                if name == "head" { break scanning }
            case .startTag(let name, let attributes, let rawText):
                switch name {
                case "title":
                    if collector.htmlTitle == nil { collector.htmlTitle = rawText.map(HTMLEntities.decode) }
                case "meta":
                    collector.addMeta(attributes)
                case "link":
                    collector.addLink(attributes)
                case "base":
                    if collector.baseHref == nil { collector.baseHref = attributes["href"] }
                default:
                    // Without </head> the whole document is scanned:
                    // some pages emit OpenGraph tags inside <body>.
                    break
                }
            }
        }
        return collector.metadata(documentURL: baseURL)
    }

    // MARK: - Collection

    private struct IconCandidate {
        var href: String
        var score: Int
        var order: Int
    }

    private struct ThemeColorCandidate {
        var value: String
        var hasMedia: Bool
    }

    private struct Collector {
        var htmlTitle: String?
        var baseHref: String?
        var values: [String: String] = [:]
        var ogImageCount = 0
        var ogImageSecure: String?
        var ogImageWidth: String?
        var ogImageHeight: String?
        var themeColors: [ThemeColorCandidate] = []
        var icons: [IconCandidate] = []
        var imageSrc: String?
        var oEmbed: String?

        mutating func addMeta(_ attributes: [String: String]) {
            guard let content = attributes["content"] else { return }
            var keys: [String] = []
            for attribute in ["property", "name", "itemprop"] {
                if let key = attributes[attribute]?.trimmingCharacters(in: .whitespaces).lowercased(),
                   !key.isEmpty, !keys.contains(key) {
                    keys.append(attribute == "itemprop" ? "itemprop:" + key : key)
                }
            }
            for key in keys { add(key: key, content: content, attributes: attributes) }
        }

        private mutating func add(key: String, content: String, attributes: [String: String]) {
            switch key {
            case "og:image", "og:image:url":
                // Width/height/secure_url describe the most recent og:image;
                // only the first image is used.
                if key == "og:image" || values["og:image"] == nil { ogImageCount += 1 }
                setFirst("og:image", content)
            case "og:image:secure_url":
                if ogImageCount <= 1, ogImageSecure == nil { ogImageSecure = content }
            case "og:image:width":
                if ogImageCount <= 1, ogImageWidth == nil { ogImageWidth = content }
            case "og:image:height":
                if ogImageCount <= 1, ogImageHeight == nil { ogImageHeight = content }
            case "theme-color":
                themeColors.append(ThemeColorCandidate(value: content, hasMedia: attributes["media"] != nil))
            case "twitter:image:src":
                setFirst("twitter:image", content)
            default:
                setFirst(key, content)
            }
        }

        private mutating func setFirst(_ key: String, _ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, values[key] == nil else { return }
            values[key] = trimmed
        }

        mutating func addLink(_ attributes: [String: String]) {
            guard let href = attributes["href"]?.trimmingCharacters(in: .whitespacesAndNewlines), !href.isEmpty,
                  let rel = attributes["rel"]?.lowercased()
            else { return }
            let tokens = Set(rel.split(whereSeparator: \.isWhitespace).map(String.init))
            let type = attributes["type"]?.lowercased() ?? ""

            if tokens.contains("alternate"), type == "application/json+oembed" || type == "text/json+oembed" {
                if oEmbed == nil { oEmbed = href }
            }
            if tokens.contains("image_src"), imageSrc == nil {
                imageSrc = href
            }
            if tokens.contains("icon") || tokens.contains("apple-touch-icon")
                || tokens.contains("apple-touch-icon-precomposed") {
                let score = Self.iconScore(tokens: tokens, href: href, type: type, sizes: attributes["sizes"])
                icons.append(IconCandidate(href: href, score: score, order: icons.count))
            }
        }

        /// Higher is better. A link card shows the favicon at roughly 16 pt
        /// (32 px on Retina) and ImageIO cannot draw SVG, so raster icons of
        /// at least 32 px win, then Apple touch icons, then small rasters, then SVG.
        private static func iconScore(tokens: Set<String>, href: String, type: String, sizes: String?) -> Int {
            let lowerHref = href.lowercased()
            let isSVG = type.contains("svg") || lowerHref.hasSuffix(".svg") || lowerHref.contains(".svg?")
            if isSVG { return 1 }
            if !tokens.contains("icon") { return 3 }   // apple-touch-icon
            let largest = (sizes ?? "")
                .lowercased()
                .split(whereSeparator: \.isWhitespace)
                .compactMap { $0.split(separator: "x").first.flatMap { Int($0) } }
                .max()
            switch largest {
            case nil: return 4
            case let size? where size >= 32: return 5
            default: return 2
            }
        }

        func metadata(documentURL: URL) -> HTMLMetadata {
            let base = baseHref.flatMap { Self.resolve($0, against: documentURL) } ?? documentURL
            func url(_ raw: String?) -> URL? { raw.flatMap { Self.resolve($0, against: base) } }
            func text(_ key: String) -> String? { values[key].flatMap(Self.cleanText) }

            var meta = HTMLMetadata()
            meta.title = text("og:title") ?? text("twitter:title") ?? htmlTitle.flatMap(Self.cleanText)
                ?? text("itemprop:name")
            meta.summary = text("og:description") ?? text("twitter:description") ?? text("description")
                ?? text("itemprop:description")
            meta.siteName = text("og:site_name") ?? text("application-name")
            meta.type = text("og:type")?.lowercased()

            let ogImage = url(ogImageSecure) ?? url(values["og:image"])
            if let ogImage {
                meta.imageURL = ogImage
                meta.imageWidth = ogImageWidth.flatMap(Self.positiveInt)
                meta.imageHeight = ogImageHeight.flatMap(Self.positiveInt)
            } else {
                meta.imageURL = url(values["twitter:image"]) ?? url(imageSrc) ?? url(values["itemprop:image"])
            }
            meta.videoURL = url(values["og:video:secure_url"]) ?? url(values["og:video:url"])
                ?? url(values["og:video"])
            meta.oEmbedURL = url(oEmbed)

            let preferredColor = themeColors.first { !$0.hasMedia } ?? themeColors.first
            meta.themeColor = preferredColor.flatMap { CSSColor.normalizedHex($0.value) }

            let bestIcon = icons.max { lhs, rhs in
                lhs.score != rhs.score ? lhs.score < rhs.score : lhs.order > rhs.order
            }
            meta.faviconURL = url(bestIcon?.href)
            return meta
        }

        private static func resolve(_ raw: String, against base: URL) -> URL? {
            // The URL spec strips tabs and newlines anywhere in a URL.
            let cleaned = raw.filter { $0 != "\n" && $0 != "\r" && $0 != "\t" }
                .trimmingCharacters(in: .whitespaces)
            guard !cleaned.isEmpty, let url = URL(string: cleaned, relativeTo: base)?.absoluteURL,
                  let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  url.host() != nil
            else { return nil }
            return url
        }

        private static func cleanText(_ raw: String) -> String? {
            let collapsed = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return collapsed.isEmpty ? nil : collapsed
        }

        private static func positiveInt(_ raw: String) -> Int? {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            // Tolerate "1200px" and "1200.0".
            let digits = trimmed.prefix { $0.isASCIIDigit }
            guard let value = Int(digits), value > 0 else { return nil }
            return value
        }
    }
}
