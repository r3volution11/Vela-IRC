// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import Foundation

/// Sites whose GIF links Vela shows as looping animations.
public enum GIFProvider: String, Sendable, Codable, Hashable, CaseIterable {
    case tenor, giphy, imgur

    /// The name shown in the "via …" caption.
    public var displayName: String {
        switch self {
        case .tenor: "Tenor"
        case .giphy: "GIPHY"
        case .imgur: "Imgur"
        }
    }

    /// The domain a site rule for this provider is written for. Rules for it
    /// also cover `assetDomains` (short links) unless those have rules of
    /// their own. Nil for Imgur, whose image host keeps rules of its own.
    public var mainDomain: String? {
        switch self {
        case .tenor: "tenor.com"
        case .giphy: "giphy.com"
        case .imgur: nil
        }
    }

    /// Other domains the provider serves its links from.
    public var assetDomains: [String] {
        switch self {
        case .giphy: ["gph.is"]
        case .tenor, .imgur: []
        }
    }

    /// The provider with a main domain whose domains cover `host`, if any.
    public static func ruleProvider(forHost host: String) -> GIFProvider? {
        guard let host = SiteRules.normalizedDomain(host) else { return nil }
        return allCases.first { provider in
            guard let main = provider.mainDomain else { return false }
            return SiteRules.host(host, isWithin: main)
                || provider.assetDomains.contains { SiteRules.host(host, isWithin: $0) }
        }
    }
}

/// An animation from a GIF site and where its renditions are.
///
/// A link that names the animation (a Tenor or GIPHY file, a GIPHY page,
/// an Imgur `.gifv`) is resolved offline by `MediaClassifier`; a page link
/// that doesn't (`tenor.com/view/…`, `tenor.com/<code>.gif`, `gph.is/…`) is
/// resolved by `LinkPreviewService` from the page's metadata.
public struct GIFInfo: Sendable, Codable, Hashable {
    public var provider: GIFProvider
    /// An MP4 rendition, shown muted and looping like a GIF: usually a
    /// tenth of the GIF's size or less, and decoded by the GPU.
    public var videoURL: URL?
    /// An animated GIF or WebP rendition: shown when there's no video (or
    /// it fails to load), and for stickers, whose transparency an MP4 loses.
    public var imageURL: URL?
    /// The animation's size in pixels, when the page said.
    public var width: Int?
    public var height: Int?
    public var title: String?
    /// A sticker (transparent): its page is resolved to the image rendition.
    /// Only matters before resolving, so it isn't stored.
    public var isSticker = false

    private enum CodingKeys: String, CodingKey {
        case provider, videoURL, imageURL, width, height, title
    }

    public init(
        provider: GIFProvider,
        videoURL: URL? = nil,
        imageURL: URL? = nil,
        width: Int? = nil,
        height: Int? = nil,
        title: String? = nil,
        isSticker: Bool = false
    ) {
        self.provider = provider
        self.videoURL = videoURL
        self.imageURL = imageURL
        self.width = width
        self.height = height
        self.title = title
        self.isSticker = isSticker
    }

    /// Whether the animation's address is known. A page link isn't until its page is fetched.
    public var isResolved: Bool { videoURL != nil || imageURL != nil }

    /// What is loaded first: the video, else the image.
    public var primaryURL: URL? { videoURL ?? imageURL }

    /// Every rendition, for policy checks.
    public var mediaURLs: [URL] { [videoURL, imageURL].compactMap { $0 } }

    /// `width` × `height`, when both are known.
    public var pixelSize: CGSize? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }
}

// MARK: - Recognizing links

/// URL patterns of the GIF sites. Pure and synchronous, like `MediaClassifier`.
enum GIFLinks {
    static func classify(_ parts: MediaClassifier.URLParts) -> GIFInfo? {
        tenor(parts) ?? giphy(parts) ?? imgur(parts)
    }

    // MARK: Tenor

    /// The last five characters of a Tenor media ID name the rendition.
    /// These are renditions of an ordinary GIF, each of which has an MP4.
    static let tenorAnimatedFormats: Set<String> = [
        "AAAAC",   // gif
        "AAAAd",   // mediumgif
        "AAAAM",   // tinygif
        "AAAAe",   // nanogif
        "AAAA1",   // webp
        "AAAPo",   // mp4
        "AAAP1",   // tinymp4
        "AAAP3",   // nanowebm
        "AAAPs",   // webm
    ]
    /// A sticker's transparent WebP.
    static let tenorStickerFormat = "AAAAm"
    static let tenorMP4Format = "AAAPo"
    /// The fallback image: Tenor's medium GIF, a fraction of the full one.
    static let tenorMediumGIFFormat = "AAAAd"

    private static func tenor(_ parts: MediaClassifier.URLParts) -> GIFInfo? {
        guard parts.hostIs("tenor.com") else { return nil }
        let segments = parts.segments

        if parts.host == "tenor.com" || parts.host == "www.tenor.com" {
            // tenor.com/RaDD.gif: a short link to a GIF page.
            if segments.count == 1, segments[0].lowercased().hasSuffix(".gif"), segments[0].count > 4 {
                return GIFInfo(provider: .tenor)
            }
            // tenor.com/view/<slug>-gif-<id>, or with a locale: tenor.com/de/view/…
            let viewIndex = segments.firstIndex(of: "view")
            guard let viewIndex, viewIndex <= 1, segments.count == viewIndex + 2 else { return nil }
            let slug = segments[viewIndex + 1]
            guard let dash = slug.lastIndex(of: "-"), isDigits(String(slug[slug.index(after: dash)...])) else {
                return nil
            }
            return GIFInfo(provider: .tenor, isSticker: slug.contains("-sticker-"))
        }

        // media.tenor.com/<id>/<name>, media1.tenor.com/m/<id>/<name>, c.tenor.com/<id>/<name>
        var rest = segments[...]
        if rest.first == "m" { rest = rest.dropFirst() }
        guard rest.count == 2, let mediaID = rest.first, let name = rest.last,
              mediaID.utf8.count == 16, mediaID.unicodeScalars.allSatisfy(isIDScalar)
        else { return nil }
        let base = String(mediaID.prefix(11))
        let format = String(mediaID.suffix(5))
        let ext = (name as NSString).pathExtension.lowercased()
        let stem = (name as NSString).deletingPathExtension

        if format == tenorStickerFormat {
            return GIFInfo(provider: .tenor, imageURL: parts.url, isSticker: true)
        }
        guard tenorAnimatedFormats.contains(format),
              let video = tenorMediaURL(base: base, format: tenorMP4Format, stem: stem, ext: "mp4")
        else { return nil }
        // The GIF as posted, unless the link is to a video.
        let image = ["gif", "webp"].contains(ext)
            ? parts.url
            : tenorMediaURL(base: base, format: tenorMediumGIFFormat, stem: stem, ext: "gif")
        return GIFInfo(provider: .tenor, videoURL: video, imageURL: image)
    }

    private static func tenorMediaURL(base: String, format: String, stem: String, ext: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "media.tenor.com"
        components.path = "/\(base)\(format)/\(stem.isEmpty ? "tenor" : stem).\(ext)"
        return components.url
    }

    // MARK: GIPHY

    private static func giphy(_ parts: MediaClassifier.URLParts) -> GIFInfo? {
        let segments = parts.segments
        if parts.host == "gph.is" || parts.host == "www.gph.is" {
            // A short link to a GIF page.
            return segments.isEmpty ? nil : GIFInfo(provider: .giphy)
        }
        guard parts.hostIs("giphy.com") else { return nil }

        if parts.host == "giphy.com" || parts.host == "www.giphy.com" {
            // giphy.com/gifs/<slug>-<id>, giphy.com/gifs/<id>/fullscreen,
            // giphy.com/embed/<id>, giphy.com/stickers/<slug>-<id>
            guard segments.count >= 2 else { return nil }
            switch segments[0] {
            case "gifs", "embed":
                return giphyID(fromSlug: segments[1]).map { giphyInfo(id: $0, sticker: false) }
            case "stickers":
                return giphyID(fromSlug: segments[1]).map { giphyInfo(id: $0, sticker: true) }
            default:
                return nil
            }
        }

        // media.giphy.com/media/<id>/giphy.gif, media2.giphy.com/media/v1.<token>/<id>/giphy.webp,
        // i.giphy.com/<id>.gif, i.giphy.com/media/<id>/giphy.mp4
        var rest = segments[...]
        let id: String?
        if rest.first == "media" {
            rest = rest.dropFirst()
            if rest.first?.hasPrefix("v1.") == true { rest = rest.dropFirst() }
            id = rest.count == 2 ? rest.first : nil
        } else if parts.host == "i.giphy.com", rest.count == 1, let file = rest.first {
            id = (file as NSString).deletingPathExtension
        } else {
            id = nil
        }
        guard let id, isGiphyID(id) else { return nil }
        return giphyInfo(id: id, sticker: false)
    }

    /// `cat-funny-JIX9t2j0ZTN9S` → `JIX9t2j0ZTN9S`; a bare ID stays as it is.
    static func giphyID(fromSlug slug: String) -> String? {
        let candidate = slug.split(separator: "-").last.map(String.init) ?? slug
        return isGiphyID(candidate) ? candidate : nil
    }

    /// GIPHY IDs are letters and digits, with a capital or a digit somewhere,
    /// which keeps slug words ("funny-cats") from passing for one.
    static func isGiphyID(_ id: String) -> Bool {
        (8...40).contains(id.utf8.count)
            && id.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0) }
            && id.unicodeScalars.contains { ("A"..."Z").contains($0) || ("0"..."9").contains($0) }
    }

    /// GIPHY serves every GIF as `giphy.mp4` (the video) and `giphy.webp`
    /// (an animated WebP, far smaller than `giphy.gif`).
    static func giphyInfo(id: String, sticker: Bool) -> GIFInfo {
        let base = "https://media.giphy.com/media/\(id)/"
        return GIFInfo(
            provider: .giphy,
            videoURL: sticker ? nil : URL(string: base + "giphy.mp4"),
            imageURL: URL(string: base + "giphy.webp"),
            isSticker: sticker
        )
    }

    // MARK: Imgur

    /// `i.imgur.com/<id>.gifv` is an HTML page around `i.imgur.com/<id>.mp4`.
    private static func imgur(_ parts: MediaClassifier.URLParts) -> GIFInfo? {
        guard parts.hostIs("imgur.com"), parts.segments.count == 1, let file = parts.segments.first,
              (file as NSString).pathExtension.lowercased() == "gifv"
        else { return nil }
        let id = (file as NSString).deletingPathExtension
        guard (3...32).contains(id.utf8.count), id.unicodeScalars.allSatisfy(isIDScalar),
              let video = URL(string: "https://i.imgur.com/\(id).mp4")
        else { return nil }
        return GIFInfo(provider: .imgur, videoURL: video)
    }

    // MARK: Character classes

    private static func isIDScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "a"..."z", "A"..."Z", "0"..."9", "-", "_": true
        default: false
        }
    }

    private static func isDigits(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 20 && value.unicodeScalars.allSatisfy { ("0"..."9").contains($0) }
    }
}

// MARK: - Resolving pages

/// Finds the animation on a GIF site's page from its OpenGraph tags.
///
/// Tenor and GIPHY pages list an MP4 as `og:video` and the GIF or WebP as
/// `og:image`. The video is preferred, except for stickers.
enum GIFResolver {
    static func resolve(_ metadata: HTMLMetadata, provider: GIFProvider, isSticker: Bool) -> GIFInfo? {
        var video: URL?
        if let candidate = metadata.videoURL,
           metadata.videoType == "video/mp4" || candidate.pathExtension.lowercased() == "mp4" {
            video = candidate
        }
        var image: URL?
        if let candidate = metadata.imageURL, ["gif", "webp"].contains(candidate.pathExtension.lowercased()) {
            image = candidate
        }
        if isSticker, image != nil { video = nil }

        var info = GIFInfo(provider: provider, videoURL: video, imageURL: image, title: metadata.title, isSticker: isSticker)
        guard info.isResolved else { return nil }

        // A rendition on the provider's own media host names the others the
        // way a link to it would: Tenor's MP4 names its smaller fallback GIF,
        // GIPHY's renditions lose their tracking tokens.
        if let primary = info.primaryURL, case .gif(let known) = MediaClassifier.classify(primary),
           known.provider == provider, known.isResolved {
            info.videoURL = isSticker && image != nil ? nil : (known.videoURL ?? info.videoURL)
            info.imageURL = known.imageURL ?? info.imageURL
        }

        if info.videoURL != nil, let width = metadata.videoWidth, let height = metadata.videoHeight {
            (info.width, info.height) = (width, height)
        } else if let width = metadata.imageWidth, let height = metadata.imageHeight {
            (info.width, info.height) = (width, height)
        }
        return info
    }
}
