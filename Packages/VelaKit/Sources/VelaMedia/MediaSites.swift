// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// A site whose links Vela shows as more than a plain link (a video player,
/// a GIF, an image, or a link preview built from the site's own data), with
/// sample links and what each should turn into.
///
/// `MediaSites.all` is the one list of them. It doesn't recognize anything
/// itself: `MediaClassifier`, `GIFLinks`, `RedditLinks` and `SiteRules` do.
/// Tests keep the two in step:
/// - `MediaSitesTests` (always run) checks that every sample is recognized
///   as declared, that every domain maps to the declared site rule, that every
///   provider and domain those types know has an entry here, and that the
///   website's page is current;
/// - `LiveMediaSiteTests` (`VELA_LIVE_MEDIA_TESTS=1`, `scripts/check-media-sites.sh`)
///   resolves every live sample against the real site.
///
/// The website's "Supported media sites" page is generated from it with
/// `swift run --package-path Packages/VelaKit vela-media-tool docs --write website/reference/media-sites.md`.
public struct MediaSite: Sendable, Hashable, Identifiable {
    public enum Category: String, Sendable, Hashable, CaseIterable {
        case videos, gifs, reddit, files
    }

    /// What Vela draws for a link.
    public enum Presentation: String, Sendable, Hashable, CaseIterable {
        /// The title and thumbnail, with the site's own player loading in place on ▶.
        case videoPlayer
        /// The title, with Vela's own player (AVKit) playing the site's HLS stream on ▶.
        case nativePlayer
        /// The GIF, played from the site's silent, looping video copy (or the GIF itself).
        case gif
        /// A see-through animated sticker, played from its animated image.
        case sticker
        /// The image; GIF, APNG and WebP animate.
        case image
        /// A video file's still frame, playing when clicked.
        case videoFile
        /// A link preview built from what the site says about the link.
        case linkPreview
    }

    /// A request Vela makes to build the preview, beyond loading the media itself.
    public enum Step: String, Sendable, Hashable, CaseIterable {
        /// A HEAD request for the file's type and size.
        case headRequest
        /// Follows the link's redirects to where it leads.
        case redirect
        /// The site's oEmbed endpoint, for the title, author and thumbnail.
        case oEmbed
        /// The page's OpenGraph and Twitter tags.
        case pageMetadata
        /// The video's HLS playlist, for its shape and whether it has sound.
        case hlsPlaylist
    }

    /// A domain the site's links, media, player or metadata come from.
    /// It covers its subdomains.
    public struct Domain: Sendable, Hashable {
        public var name: String
        /// What it serves, for the docs: "short links", "thumbnails".
        public var purpose: String

        public init(_ name: String, _ purpose: String) {
            self.name = name
            self.purpose = purpose
        }
    }

    /// One shape of link Vela recognizes.
    public struct LinkForm: Sendable, Hashable, Identifiable {
        public var id: String
        /// How the link looks, for the docs: `youtube.com/watch?v=<id>`.
        public var pattern: String
        public var shows: Presentation
        /// What Vela fetches for it, in order. Empty when the link says
        /// where the media is and Vela loads only that.
        public var steps: [Step]
        public var note: String?

        public init(_ id: String, _ pattern: String, shows: Presentation, steps: [Step] = [], note: String? = nil) {
            self.id = id
            self.pattern = pattern
            self.shows = shows
            self.steps = steps
            self.note = note
        }
    }

    /// What `MediaClassifier` (and `RedditLinks`) must make of a sample, offline.
    public enum Recognition: Sendable, Hashable {
        /// A video embed from this provider.
        case embed(EmbedProvider)
        /// A GIF site's animation; `resolved` when the link alone says where it is.
        case gif(GIFProvider, resolved: Bool)
        /// A direct image file.
        case image
        /// A direct video file.
        case video
        /// A page that is a Reddit post (`RedditLinks.post`).
        case redditPost
        /// A page whose nature only shows once it's followed (a short link).
        case page
    }

    /// What must hold when a sample is resolved against the real site, through
    /// `LinkPreviewService`, `ImageLoader` and `LoopingVideoLoader` with a
    /// default `MediaPolicy`.
    public enum LiveCheck: Sendable, Hashable {
        /// `LinkPreviewService` returns a preview of this kind.
        case kind(LinkPreview.Kind)
        /// The preview's title contains this text.
        case title(containing: String)
        /// The embed's author (or a post card's summary) contains this text.
        case author(containing: String)
        /// The embed says where it was posted ("r/LoveTrash").
        case community(String)
        /// After redirects, the preview's address (host without `www.`, then
        /// path) starts with this: `tenor.com/view/`.
        case landsOn(String)
        /// The video's thumbnail loads as an image.
        case thumbnail
        /// The player page (`EmbedPlayerHTML.playerURL`) answers with HTML.
        case player
        /// The embed URL is an HLS master playlist.
        case hlsPlaylist
        /// The GIF's MP4 copy downloads within the size cap and is a playable video.
        case loopingVideo
        /// The GIF's GIF or WebP rendition loads within the size cap and is animated.
        case animatedImage
        /// The image loads within the size cap; animated when `animated`.
        case image(animated: Bool)
        /// The server says it's a video, and its first bytes are a movie file.
        case videoFile
    }

    /// A real link and what it must turn into.
    public struct Sample: Sendable, Hashable {
        public var link: String
        /// The `LinkForm.id` it's an example of.
        public var form: String
        public var recognized: Recognition
        /// The host the media loads from when it isn't the link's own
        /// (a GitHub `blob` link loads from `raw.githubusercontent.com`).
        public var loadsFrom: String?
        /// Checked against the real site. Empty: an offline-only sample, with
        /// `note` saying why.
        public var live: [LiveCheck]
        public var note: String?

        public init(
            _ link: String,
            form: String,
            _ recognized: Recognition,
            loadsFrom: String? = nil,
            live: [LiveCheck] = [],
            note: String? = nil
        ) {
            self.link = link
            self.form = form
            self.recognized = recognized
            self.loadsFrom = loadsFrom
            self.live = live
            self.note = note
        }

        public var url: URL? { URL(string: link) }
        public var isLive: Bool { !live.isEmpty }
    }

    /// A stable identifier: `youtube`, `reddit-videos`.
    public var id: String
    public var name: String
    /// The site's home page; nil for an entry that isn't one site.
    public var homepage: String?
    public var category: Category
    /// The provider whose links these are, for video and GIF sites.
    public var embedProvider: EmbedProvider?
    public var gifProvider: GIFProvider?
    /// The domain a site rule for this site is written for, which also covers
    /// `domains`. Nil when each domain keeps rules of its own.
    public var ruleDomain: String?
    public var domains: [Domain]
    public var forms: [LinkForm]
    /// What Vela contacts, and when, in a sentence or two.
    public var privacy: String
    public var samples: [Sample]
    /// Why no sample is checked against the live site, when none is.
    public var liveNote: String?

    public init(
        id: String,
        name: String,
        homepage: String?,
        category: Category,
        embedProvider: EmbedProvider? = nil,
        gifProvider: GIFProvider? = nil,
        ruleDomain: String?,
        domains: [Domain],
        forms: [LinkForm],
        privacy: String,
        samples: [Sample],
        liveNote: String? = nil
    ) {
        self.id = id
        self.name = name
        self.homepage = homepage
        self.category = category
        self.embedProvider = embedProvider
        self.gifProvider = gifProvider
        self.ruleDomain = ruleDomain
        self.domains = domains
        self.forms = forms
        self.privacy = privacy
        self.samples = samples
        self.liveNote = liveNote
    }

    public var liveSamples: [Sample] { samples.filter(\.isLive) }

    public func form(_ id: String) -> LinkForm? {
        forms.first { $0.id == id }
    }
}

/// Every site Vela recognizes media from, in the order the docs list them.
///
/// To add a site: add its recognizer (`MediaClassifier`, `GIFLinks`, …), then
/// an entry here with a sample for each link form, then regenerate the docs
/// page and run `scripts/check-media-sites.sh`. See CONTRIBUTING.md.
public enum MediaSites {
    public static func site(_ id: String) -> MediaSite? {
        all.first { $0.id == id }
    }

    public static func sites(in category: MediaSite.Category) -> [MediaSite] {
        all.filter { $0.category == category }
    }

    public static let all: [MediaSite] = [
        // MARK: - Videos

        MediaSite(
            id: "youtube",
            name: "YouTube",
            homepage: "https://www.youtube.com",
            category: .videos,
            embedProvider: .youtube,
            ruleDomain: "youtube.com",
            domains: [
                .init("youtube.com", "links and oEmbed"),
                .init("youtu.be", "short links"),
                .init("youtube-nocookie.com", "the player"),
                .init("ytimg.com", "thumbnails"),
            ],
            forms: [
                .init("watch", "youtube.com/watch?v=<id>", shows: .videoPlayer, steps: [.oEmbed],
                      note: "also on `m.youtube.com` and `music.youtube.com`; a `t=` or `start=` time is kept"),
                .init("short-link", "youtu.be/<id>", shows: .videoPlayer, steps: [.oEmbed]),
                .init("shorts", "youtube.com/shorts/<id>", shows: .videoPlayer, steps: [.oEmbed],
                      note: "in a portrait player"),
                .init("live", "youtube.com/live/<id>", shows: .videoPlayer, steps: [.oEmbed]),
                .init("embed", "youtube.com/embed/<id>", shows: .videoPlayer, steps: [.oEmbed]),
                .init("nocookie", "youtube-nocookie.com/embed/<id>", shows: .videoPlayer, steps: [.oEmbed]),
            ],
            privacy: "The title and thumbnail come from YouTube's oEmbed service and `ytimg.com`. The player loads from `youtube-nocookie.com`, only when you press ▶.",
            samples: [
                .init("https://www.youtube.com/watch?v=aqz-KE-bpKQ", form: "watch", .embed(.youtube),
                      live: [.kind(.embed), .title(containing: "Big Buck Bunny"), .thumbnail, .player],
                      note: "Big Buck Bunny, from the Blender Foundation's channel."),
                .init("https://youtu.be/aqz-KE-bpKQ?t=30", form: "short-link", .embed(.youtube),
                      note: "Offline only: the same video as the watch link."),
                .init("https://www.youtube.com/shorts/myZ9kn9MIWQ", form: "shorts", .embed(.youtube),
                      live: [.kind(.embed), .title(containing: "Solar Eclipse"), .thumbnail],
                      note: "A NASA Short."),
                .init("https://www.youtube.com/live/aqz-KE-bpKQ", form: "live", .embed(.youtube),
                      note: "Offline only: a past stream resolves like a watch link."),
                .init("https://www.youtube.com/embed/aqz-KE-bpKQ?start=30", form: "embed", .embed(.youtube),
                      note: "Offline only: the same video as the watch link."),
                .init("https://www.youtube-nocookie.com/embed/aqz-KE-bpKQ", form: "nocookie", .embed(.youtube),
                      note: "Offline only: the same video as the watch link."),
            ]
        ),

        MediaSite(
            id: "vimeo",
            name: "Vimeo",
            homepage: "https://vimeo.com",
            category: .videos,
            embedProvider: .vimeo,
            ruleDomain: "vimeo.com",
            domains: [
                .init("vimeo.com", "links, oEmbed and the player"),
                .init("vimeocdn.com", "thumbnails"),
            ],
            forms: [
                .init("video", "vimeo.com/<id>", shows: .videoPlayer, steps: [.oEmbed],
                      note: "a `#t=` time is kept"),
                .init("unlisted", "vimeo.com/<id>/<hash>", shows: .videoPlayer, steps: [.oEmbed],
                      note: "unlisted videos"),
                .init("player", "player.vimeo.com/video/<id>", shows: .videoPlayer, steps: [.oEmbed]),
                .init("collection", "vimeo.com/channels/<name>/<id>", shows: .videoPlayer, steps: [.oEmbed],
                      note: "also groups, albums and showcases"),
            ],
            privacy: "The title and thumbnail come from Vimeo's oEmbed service and `vimeocdn.com`. The player loads only when you press ▶.",
            samples: [
                .init("https://vimeo.com/1084537", form: "video", .embed(.vimeo),
                      live: [.kind(.embed), .title(containing: "Big Buck Bunny"), .thumbnail],
                      note: "Big Buck Bunny. Vimeo's player answers apps with a bot check that only a browser passes, so the player itself isn't checked."),
                .init("https://vimeo.com/1084537/0f1e2d3c4b", form: "unlisted", .embed(.vimeo),
                      note: "Offline only: unlisted videos can't be public samples; the hash is made up."),
                .init("https://player.vimeo.com/video/1084537", form: "player", .embed(.vimeo),
                      note: "Offline only: the same video as the main sample."),
                .init("https://vimeo.com/channels/staffpicks/1084537", form: "collection", .embed(.vimeo),
                      note: "Offline only: the address is illustrative."),
            ]
        ),

        MediaSite(
            id: "twitch",
            name: "Twitch",
            homepage: "https://www.twitch.tv",
            category: .videos,
            embedProvider: .twitch,
            ruleDomain: "twitch.tv",
            domains: [
                .init("twitch.tv", "links, pages and the player"),
                .init("jtvnw.net", "thumbnails"),
            ],
            forms: [
                .init("clip", "clips.twitch.tv/<clip>", shows: .videoPlayer, steps: [.pageMetadata]),
                .init("channel-clip", "twitch.tv/<channel>/clip/<clip>", shows: .videoPlayer, steps: [.pageMetadata]),
                .init("video", "twitch.tv/videos/<id>", shows: .videoPlayer, steps: [.pageMetadata],
                      note: "past broadcasts and highlights; a `t=` time is kept"),
            ],
            privacy: "Twitch has no public oEmbed service, so Vela reads the clip's or video's page for its title and thumbnail (from `jtvnw.net`). The player loads only when you press ▶.",
            samples: [
                .init("https://clips.twitch.tv/ModernEasyLapwingBCWarrior-FZTCQ5rmbrQmpVZC", form: "clip", .embed(.twitch),
                      live: [.kind(.embed), .title(containing: "nahh"), .thumbnail, .player],
                      note: "stableronaldo's \"nahh\", the most-watched Twitch clip."),
                .init("https://www.twitch.tv/stableronaldo/clip/ModernEasyLapwingBCWarrior-FZTCQ5rmbrQmpVZC", form: "channel-clip", .embed(.twitch),
                      live: [.kind(.embed), .title(containing: "nahh")]),
                .init("https://www.twitch.tv/videos/1234567890?t=1h2m3s", form: "video", .embed(.twitch),
                      note: "Offline only: Twitch deletes most past broadcasts within weeks, so no video makes a lasting sample."),
            ]
        ),

        MediaSite(
            id: "streamable",
            name: "Streamable",
            homepage: "https://streamable.com",
            category: .videos,
            embedProvider: .streamable,
            ruleDomain: "streamable.com",
            domains: [
                .init("streamable.com", "links, oEmbed, the player and thumbnails"),
            ],
            forms: [
                .init("video", "streamable.com/<id>", shows: .videoPlayer, steps: [.oEmbed]),
                .init("embed", "streamable.com/e/<id>", shows: .videoPlayer, steps: [.oEmbed],
                      note: "also `/o/` and `/s/`"),
            ],
            privacy: "The title and thumbnail come from Streamable's oEmbed service. The player loads only when you press ▶.",
            samples: [
                .init("https://streamable.com/moo", form: "video", .embed(.streamable),
                      live: [.kind(.embed), .title(containing: "eat me"), .thumbnail, .player],
                      note: "The video Streamable's own API documentation uses."),
                .init("https://streamable.com/e/moo", form: "embed", .embed(.streamable),
                      note: "Offline only: the same video as the main sample."),
            ]
        ),

        // MARK: - GIFs

        MediaSite(
            id: "tenor",
            name: "Tenor",
            homepage: "https://tenor.com",
            category: .gifs,
            gifProvider: .tenor,
            ruleDomain: "tenor.com",
            domains: [
                .init("tenor.com", "links and pages"),
                .init("media.tenor.com", "the GIFs and their video copies"),
            ],
            forms: [
                .init("page", "tenor.com/view/<title>-gif-<id>", shows: .gif, steps: [.pageMetadata],
                      note: "also with a language, as in `tenor.com/de/view/…`"),
                .init("sticker", "tenor.com/view/<title>-sticker-<id>", shows: .sticker, steps: [.pageMetadata]),
                .init("short-link", "tenor.com/<code>.gif", shows: .gif, steps: [.redirect, .pageMetadata]),
                .init("file", "media.tenor.com/<id>/<name>.gif", shows: .gif,
                      note: "also `.mp4` and `.webp`, and on `media1.tenor.com` and `c.tenor.com`"),
            ],
            privacy: "A link to a GIF file needs no page: Vela loads only the GIF's video copy from `media.tenor.com`. Pages and short links are fetched to find the GIF.",
            samples: [
                .init("https://tenor.com/view/nasa-nasa-gifs-earth-space-station-space-gif-9368490", form: "page", .gif(.tenor, resolved: false),
                      live: [.kind(.gif), .title(containing: "Space Station"), .loopingVideo, .animatedImage],
                      note: "Earth and the space station, from NASA."),
                .init("https://tenor.com/view/nasa-logo-space-sticker-17405863", form: "sticker", .gif(.tenor, resolved: false),
                      live: [.kind(.gif), .animatedImage],
                      note: "The NASA logo sticker."),
                .init("https://tenor.com/RaDD.gif", form: "short-link", .gif(.tenor, resolved: false),
                      live: [.kind(.gif), .landsOn("tenor.com/view/"), .loopingVideo]),
                .init("https://media.tenor.com/PCwDzlWKT7kAAAAC/nasa-nasa-gifs.gif", form: "file", .gif(.tenor, resolved: true),
                      live: [.loopingVideo],
                      note: "The file behind the page sample."),
                .init("https://media1.tenor.com/m/PCwDzlWKT7kAAAAC/nasa-nasa-gifs.gif", form: "file", .gif(.tenor, resolved: true),
                      note: "Offline only: the same GIF as the file sample."),
            ]
        ),

        MediaSite(
            id: "giphy",
            name: "GIPHY",
            homepage: "https://giphy.com",
            category: .gifs,
            gifProvider: .giphy,
            ruleDomain: "giphy.com",
            domains: [
                .init("giphy.com", "links, pages and the GIFs' servers"),
                .init("gph.is", "short links"),
            ],
            forms: [
                .init("page", "giphy.com/gifs/<title>-<id>", shows: .gif,
                      note: "the page is read only for a text-only preview"),
                .init("embed", "giphy.com/embed/<id>", shows: .gif),
                .init("sticker", "giphy.com/stickers/<title>-<id>", shows: .sticker),
                .init("short-link", "gph.is/<code>", shows: .gif, steps: [.redirect, .pageMetadata]),
                .init("file", "media.giphy.com/media/<id>/giphy.gif", shows: .gif,
                      note: "also `.mp4` and `.webp`, and on `media0.giphy.com` to `media4.giphy.com`"),
                .init("i-file", "i.giphy.com/<id>.gif", shows: .gif),
            ],
            privacy: "Links that name the GIF (pages, embeds and files) need no page: Vela loads only the GIF's video copy from GIPHY's servers. `gph.is` short links are followed to find the GIF.",
            samples: [
                .init("https://giphy.com/gifs/nasa-space-rocket-launch-x4vlKY5ocArL3SeVVU", form: "page", .gif(.giphy, resolved: true),
                      live: [.kind(.gif), .title(containing: "NASA"), .loopingVideo, .animatedImage],
                      note: "A night rocket launch, from NASA."),
                .init("https://giphy.com/embed/x4vlKY5ocArL3SeVVU", form: "embed", .gif(.giphy, resolved: true),
                      note: "Offline only: the same GIF as the page sample."),
                .init("https://giphy.com/stickers/nasa-nasagif-3ov2eN8C5j9jtRM2jf", form: "sticker", .gif(.giphy, resolved: true),
                      live: [.animatedImage],
                      note: "NASA's waving astronaut sticker."),
                .init("https://gph.is/g/46vwxjM", form: "short-link", .gif(.giphy, resolved: false),
                      live: [.kind(.gif), .landsOn("giphy.com/gifs/"), .loopingVideo]),
                .init("https://media.giphy.com/media/x4vlKY5ocArL3SeVVU/giphy.gif", form: "file", .gif(.giphy, resolved: true),
                      note: "Offline only: the same GIF as the page sample."),
                .init("https://i.giphy.com/x4vlKY5ocArL3SeVVU.webp", form: "i-file", .gif(.giphy, resolved: true),
                      note: "Offline only: the same GIF as the page sample."),
            ]
        ),

        MediaSite(
            id: "imgur",
            name: "Imgur",
            homepage: "https://imgur.com",
            category: .gifs,
            gifProvider: .imgur,
            ruleDomain: nil,
            domains: [
                .init("i.imgur.com", "links and the video copies"),
                .init("imgur.com", "links"),
            ],
            forms: [
                .init("gifv", "i.imgur.com/<id>.gifv", shows: .gif,
                      note: "also on `imgur.com`; other Imgur images, such as `i.imgur.com/<id>.jpg`, show like any image file"),
            ],
            privacy: "Vela loads the GIF's video copy (`i.imgur.com/<id>.mp4`) and never the `.gifv` page.",
            samples: [
                .init("https://i.imgur.com/fv0qgkc.gifv", form: "gifv", .gif(.imgur, resolved: true),
                      live: [.loopingVideo],
                      note: "From Imgur's .gifv launch in 2014."),
            ]
        ),

        // MARK: - Reddit

        MediaSite(
            id: "reddit-videos",
            name: "Reddit videos",
            homepage: "https://www.reddit.com",
            category: .reddit,
            embedProvider: .reddit,
            ruleDomain: "reddit.com",
            domains: [
                .init("redd.it", "videos on `v.redd.it`"),
                .init("reddit.com", "posts and oEmbed"),
                .init("redditstatic.com", "Reddit's icon"),
            ],
            forms: [
                .init("video", "v.redd.it/<id>", shows: .nativePlayer, steps: [.redirect, .oEmbed, .hlsPlaylist],
                      note: "a video without sound loops like a GIF"),
                .init("video-page", "reddit.com/video/<id>", shows: .nativePlayer, steps: [.redirect, .oEmbed, .hlsPlaylist]),
            ],
            privacy: "Vela follows the link to its post, reads the post's oEmbed for the title and author, and the video's playlist for its shape and sound. None of that says whether a post is NSFW, so no picture shows until you press ▶, and Reddit videos never play by themselves.",
            samples: [
                .init("https://v.redd.it/1crlzghxl82i1", form: "video", .embed(.reddit),
                      live: [.kind(.embed), .title(containing: "Jet powered skateboard"), .community("r/LoveTrash"),
                             .author(containing: "u/"), .hlsPlaylist]),
                .init("https://www.reddit.com/video/1crlzghxl82i1", form: "video-page", .embed(.reddit),
                      note: "Offline only: the same video as the v.redd.it sample."),
            ]
        ),

        MediaSite(
            id: "reddit-posts",
            name: "Reddit posts",
            homepage: "https://www.reddit.com",
            category: .reddit,
            ruleDomain: "reddit.com",
            domains: [
                .init("reddit.com", "posts and oEmbed, also on `old`, `new`, `np` and `m`"),
                .init("redd.it", "short links"),
                .init("redditstatic.com", "Reddit's icon"),
            ],
            forms: [
                .init("post", "reddit.com/r/<subreddit>/comments/<id>/<title>", shows: .linkPreview, steps: [.oEmbed]),
                .init("bare-post", "reddit.com/comments/<id>", shows: .linkPreview, steps: [.oEmbed]),
                .init("profile-post", "reddit.com/user/<name>/comments/<id>", shows: .linkPreview, steps: [.oEmbed]),
                .init("short-link", "redd.it/<id>", shows: .linkPreview, steps: [.redirect, .oEmbed]),
                .init("share-link", "reddit.com/r/<subreddit>/s/<code>", shows: .linkPreview, steps: [.redirect, .oEmbed],
                      note: "what Reddit's Share button makes"),
            ],
            privacy: "Reddit answers apps with a challenge page instead of the post, so Vela reads only Reddit's public oEmbed for the title and author. Short and share links are followed to the post first.",
            samples: [
                .init("https://www.reddit.com/r/LoveTrash/comments/1xyw5ml/jet_powered_skateboard/", form: "post", .redditPost,
                      live: [.kind(.page), .title(containing: "Jet powered skateboard"), .author(containing: "u/downtune79")]),
                .init("https://old.reddit.com/comments/1xyw5ml", form: "bare-post", .redditPost,
                      note: "Offline only: the same post as the main sample."),
                .init("https://www.reddit.com/user/downtune79/comments/1xyw5ml/", form: "profile-post", .redditPost,
                      note: "Offline only: the address is illustrative."),
                .init("https://redd.it/1xyw5ml", form: "short-link", .page,
                      live: [.kind(.page), .landsOn("reddit.com/comments/1xyw5ml"), .title(containing: "Jet powered skateboard"),
                             .author(containing: "u/downtune79")],
                      note: "Lands on the post's address without its subreddit."),
                .init("https://www.reddit.com/r/LoveTrash/s/Ab3dE5gH7j", form: "share-link", .page,
                      note: "Offline only: share codes are personal, so this one is made up."),
            ]
        ),

        MediaSite(
            id: "reddit-images",
            name: "Reddit images",
            homepage: "https://www.reddit.com",
            category: .reddit,
            ruleDomain: "reddit.com",
            domains: [
                .init("redd.it", "images on `i.redd.it` and `preview.redd.it`"),
                .init("redditmedia.com", "older image servers"),
            ],
            forms: [
                .init("image", "i.redd.it/<name>.jpg", shows: .image, note: "and other image files"),
                .init("preview", "preview.redd.it/<name>.jpg?…", shows: .image),
            ],
            privacy: "Images load straight from Reddit's image servers, like any other image.",
            samples: [
                .init("https://i.redd.it/2k8fy1s4b5vf1.jpeg", form: "image", .image,
                      note: "Offline only: the address is illustrative."),
                .init("https://preview.redd.it/2k8fy1s4b5vf1.jpeg?width=1080&format=pjpg&auto=webp", form: "preview", .image,
                      note: "Offline only: the address is illustrative."),
            ],
            liveNote: "Reddit images load like any image file, which the direct file samples check; Reddit offers apps no lasting public image to use as a sample."
        ),

        // MARK: - Files

        MediaSite(
            id: "github",
            name: "GitHub",
            homepage: "https://github.com",
            category: .files,
            ruleDomain: nil,
            domains: [
                .init("github.com", "links"),
                .init("raw.githubusercontent.com", "the files"),
            ],
            forms: [
                .init("blob", "github.com/<owner>/<repo>/blob/<branch>/<path>.png", shows: .image,
                      note: "image and video files; Vela loads the raw file"),
            ],
            privacy: "Vela loads the file from `raw.githubusercontent.com`, never the `github.com` page. A rule for either domain applies.",
            samples: [
                .init("https://github.com/r3volution11/Vela-IRC/blob/main/docs/vela-icon.png", form: "blob", .image,
                      loadsFrom: "raw.githubusercontent.com",
                      live: [.image(animated: false)],
                      note: "Vela's own icon."),
            ]
        ),

        MediaSite(
            id: "files",
            name: "Image and video files",
            homepage: nil,
            category: .files,
            ruleDomain: nil,
            domains: [],
            forms: [
                .init("image", "<any site>/<name>.jpg", shows: .image,
                      note: "or " + MediaSites.extensionList(MediaClassifier.imageExtensions.subtracting(["jpg"]))),
                .init("video", "<any site>/<name>.mp4", shows: .videoFile, steps: [.headRequest],
                      note: "or " + MediaSites.extensionList(MediaClassifier.videoExtensions.subtracting(["mp4"]))),
            ],
            privacy: "Images load from the link's own site, up to your size limit. For a video file, Vela checks its type and size first and reads only enough for a still frame; the rest streams when you play it.",
            samples: [
                .init("https://upload.wikimedia.org/wikipedia/commons/thumb/0/00/Crab_Nebula.jpg/1280px-Crab_Nebula.jpg", form: "image", .image,
                      live: [.image(animated: false)],
                      note: "The Crab Nebula (NASA, ESA), on Wikimedia Commons."),
                .init("https://upload.wikimedia.org/wikipedia/commons/thumb/e/e1/Rotating_earth_animated.gif/250px-Rotating_earth_animated.gif", form: "image", .image,
                      live: [.image(animated: true)],
                      note: "NASA's rotating Earth, on Wikimedia Commons."),
                .init("https://images-assets.nasa.gov/video/GSFC_20150729_Yarkovsky_m11964_Effect/GSFC_20150729_Yarkovsky_m11964_Effect~mobile.mp4", form: "video", .video,
                      live: [.kind(.video), .videoFile],
                      note: "\"How Sunlight Pushes Asteroids\", from NASA's image and video library."),
                .init("https://images-assets.nasa.gov/video/GSFC_20150729_Yarkovsky_m11964_Effect/GSFC_20150729_Yarkovsky_m11964_Effect~orig.mov", form: "video", .video,
                      live: [.kind(.video), .videoFile],
                      note: "The same video as a QuickTime movie."),
            ]
        ),
    ]

    /// `["mp4", "mov", "m4v"]` → "`.m4v`, `.mov` or `.mp4`" (in backticks), sorted, for the docs.
    static func extensionList(_ extensions: Set<String>) -> String {
        let items = extensions.sorted().map { "`.\($0)`" }
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " or " + items[items.count - 1]
    }
}
