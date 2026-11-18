// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaMedia

@Suite struct PreviewDeciderTests {
    private static func url(_ string: String) -> URL { URL(string: string)! }
    private func url(_ string: String) -> URL { URL(string: string)! }

    private let page = Self.url("https://example.com/article")
    private let imageLink = Self.url("https://example.com/cat.png")
    private let videoLink = Self.url("https://example.com/clip.mp4")
    private let youtube = Self.url("https://youtu.be/dQw4w9WgXcQ")

    private func decide(
        _ link: URL,
        preview: LinkPreview? = nil,
        fetchBlock: SiteBlock? = nil,
        policy: MediaPolicy = MediaPolicy(),
        layout: PreviewLayout = PreviewLayout(),
        blur: Bool = false,
        overrides: PreviewOverrides = PreviewOverrides()
    ) -> PreviewDecision {
        PreviewDecider.decide(
            url: link,
            classification: MediaClassifier.classify(link),
            preview: preview,
            fetchBlock: fetchBlock,
            context: PreviewContext(policy: policy, layout: layout, blurImages: blur),
            overrides: overrides
        )
    }

    private func pagePreview(
        _ link: URL? = nil,
        finalURL: URL? = nil,
        title: String? = "Title",
        imageURL: URL? = URL(string: "https://cdn.example.org/card.jpg"),
        declaresAdult: Bool? = false
    ) -> LinkPreview {
        let link = link ?? page
        return LinkPreview(
            url: link, finalURL: finalURL, kind: .page, title: title, imageURL: imageURL, declaresAdult: declaresAdult
        )
    }

    private func imagePreview(_ link: URL, kind: LinkPreview.Kind = .image) -> LinkPreview {
        LinkPreview(url: link, kind: kind, mediaURL: link)
    }

    private func embedPreview() -> LinkPreview {
        let info = EmbedInfo.youtube(id: "dQw4w9WgXcQ", start: nil, isShort: false)
        return LinkPreview(
            url: youtube, kind: .embed, title: "Never Gonna Give You Up", siteName: "YouTube",
            imageURL: info.thumbnailURL, embed: info
        )
    }

    private func rules(_ raw: [String: String]) -> SiteRules { SiteRules(raw) }

    // MARK: Settings mirrors

    @Test func layoutRawValuesAndDefaults() {
        #expect(PreviewLinkSize.allCases.map(\.rawValue) == ["minimal", "standard", "large"])
        #expect(PreviewVideoStyle.allCases.map(\.rawValue) == ["player", "compact", "off"])
        #expect(PreviewImageSize.allCases.map(\.rawValue) == ["full", "thumbnail"])
        let layout = PreviewLayout()
        #expect(layout.linkSize == .standard)
        #expect(layout.videoStyle == .player)
        #expect(layout.imageSize == .full)
        #expect(PreviewContext().blurImages == false)
        #expect(PreviewOverrides() == PreviewOverrides(loadRequested: false, allowedOnce: [], revealed: false))
    }

    // MARK: Forbidden

    @Test(arguments: ["http://localhost:8080/", "http://192.168.1.1/admin", "ftp://example.com/file.png"])
    func forbiddenLinksShowNothing(_ link: String) {
        let decision = decide(url(link))
        #expect(decision.plan == PreviewPlan.none)
        #expect(!decision.shouldFetch)
    }

    // MARK: Pages

    @Test func pageBeforeAndAfterFetching() {
        let pending = decide(page)
        #expect(pending.plan == .pending)
        #expect(pending.shouldFetch)
        #expect(pending.showsImages)
        #expect(!pending.blurred)
        #expect(pending.policy == MediaPolicy())

        let loaded = decide(page, preview: pagePreview())
        #expect(loaded.plan == .card(.standard))
        #expect(!loaded.shouldFetch)
        #expect(loaded.showsImages)
    }

    @Test(arguments: PreviewLinkSize.allCases)
    func cardSizeFollowsLayout(_ size: PreviewLinkSize) {
        let decision = decide(page, preview: pagePreview(), layout: PreviewLayout(linkSize: size))
        #expect(decision.plan == .card(size))
    }

    @Test func cardsOffShowNothing() {
        let policy = MediaPolicy(showLinkCards: false)
        #expect(decide(page, policy: policy).plan == PreviewPlan.none)
        #expect(!decide(page, policy: policy).shouldFetch)
        #expect(decide(page, preview: pagePreview(), policy: policy).plan == PreviewPlan.none)
    }

    @Test func pageWithoutCardContentShowsNothing() {
        let bare = pagePreview(title: nil, imageURL: nil)
        #expect(decide(page, preview: bare).plan == PreviewPlan.none)
        // An image alone is content, unless images are off for the site.
        let imageOnly = pagePreview(title: nil)
        #expect(decide(page, preview: imageOnly).plan == .card(.standard))
        let textOnly = MediaPolicy(siteRules: rules(["example.com": "textOnly"]))
        #expect(decide(page, preview: imageOnly, policy: textOnly).plan == PreviewPlan.none)
    }

    // MARK: Images

    @Test func imagesLoadWithoutAPreviewFetch() {
        let decision = decide(imageLink)
        #expect(decision.plan == .image(.full))
        #expect(!decision.shouldFetch)
        #expect(decision.showsImages)
        #expect(decide(imageLink, layout: PreviewLayout(imageSize: .thumbnail)).plan == .image(.thumbnail))
        // Image settings don't depend on link cards.
        #expect(decide(imageLink, policy: MediaPolicy(showLinkCards: false)).plan == .image(.full))
    }

    @Test func textOnlyImageBecomesACardWithoutImage() {
        let policy = MediaPolicy(siteRules: rules(["example.com": "textOnly"]))
        let pending = decide(imageLink, policy: policy)
        #expect(pending.plan == .pending)
        #expect(pending.shouldFetch)
        #expect(!pending.showsImages)
        #expect(!pending.policy.imagesAllowed)

        let loaded = decide(imageLink, preview: imagePreview(imageLink), policy: policy)
        #expect(loaded.plan == .card(.standard))
        #expect(!loaded.showsImages)
        #expect(!loaded.policy.allowsImage(imageLink))
        #expect(decide(imageLink, preview: imagePreview(imageLink), policy: MediaPolicy(
            showLinkCards: false, siteRules: rules(["example.com": "textOnly"])
        )).plan == PreviewPlan.none)
    }

    @Test func imageURLThatIsReallyAPage() {
        let viewer = pagePreview(imageLink, title: "Viewer")
        #expect(decide(imageLink, preview: viewer).plan == .card(.standard))

        // The inline image failed to decode: preview the link as a page.
        let failed = decide(imageLink, overrides: PreviewOverrides(treatAsPage: true))
        #expect(failed.plan == .pending)
        #expect(failed.shouldFetch)
        #expect(decide(imageLink, preview: viewer, overrides: PreviewOverrides(treatAsPage: true)).plan == .card(.standard))
    }

    @Test func imagesOffForTheBufferMakesEverythingText() {
        let policy = MediaPolicy(imagesAllowed: false)
        #expect(decide(imageLink, policy: policy).plan == .pending)
        let card = decide(page, preview: pagePreview(), policy: policy)
        #expect(card.plan == .card(.standard))
        #expect(!card.showsImages)
    }

    // MARK: Direct video

    @Test func directVideoFollowsVideoStyle() {
        let pending = decide(videoLink)
        #expect(pending.plan == .pending)
        #expect(pending.shouldFetch)

        let preview = LinkPreview(url: videoLink, kind: .video, mediaURL: videoLink)
        #expect(decide(videoLink, preview: preview).plan == .directVideo(.player))
        #expect(decide(videoLink, preview: preview, layout: PreviewLayout(videoStyle: .compact)).plan == .directVideo(.compact))

        // Videos off: a card titled with the file name.
        let off = PreviewLayout(videoStyle: .off)
        #expect(decide(videoLink, layout: off).plan == .pending)
        #expect(decide(videoLink, preview: preview, layout: off).plan == .card(.standard))
        #expect(decide(videoLink, preview: preview, policy: MediaPolicy(showLinkCards: false), layout: off).plan
            == PreviewPlan.none)
        // Text-only sites never load the video.
        let textOnly = MediaPolicy(siteRules: rules(["example.com": "textOnly"]))
        #expect(decide(videoLink, preview: preview, policy: textOnly).plan == .card(.standard))
    }

    // MARK: Video embeds

    @Test func embedsShowTheFacadeRightAway() {
        let before = decide(youtube)
        #expect(before.plan == .videoEmbed(.player))
        #expect(before.shouldFetch)
        #expect(before.showsImages)

        let after = decide(youtube, preview: embedPreview())
        #expect(after.plan == .videoEmbed(.player))
        #expect(!after.shouldFetch)
        #expect(decide(youtube, preview: embedPreview(), layout: PreviewLayout(videoStyle: .compact)).plan
            == .videoEmbed(.compact))
    }

    @Test func videosOffShowsALinkCard() {
        let off = PreviewLayout(linkSize: .minimal, videoStyle: .off)
        let before = decide(youtube, layout: off)
        #expect(before.plan == .pending)
        #expect(before.shouldFetch)
        #expect(decide(youtube, preview: embedPreview(), layout: off).plan == .card(.minimal))
        #expect(decide(youtube, preview: embedPreview(), policy: MediaPolicy(showLinkCards: false), layout: off).plan
            == PreviewPlan.none)
    }

    @Test func textOnlyVideoSiteShowsACardWithoutThumbnail() {
        let policy = MediaPolicy(siteRules: rules(["youtube.com": "textOnly"]))
        #expect(decide(youtube, policy: policy).plan == .pending)
        let card = decide(youtube, preview: embedPreview(), policy: policy)
        #expect(card.plan == .card(.standard))
        #expect(!card.showsImages)
        #expect(!card.policy.allowsImage(embedPreview().imageURL!))
    }

    @Test func providerRuleCoversShortLinks() {
        let policy = MediaPolicy(siteRules: rules(["youtube.com": "block"]))
        let decision = decide(youtube, policy: policy)
        #expect(decision.plan == .blocked(SiteBlock(reason: .userBlocked, domain: "youtube.com")))
        #expect(!decision.shouldFetch)
    }

    // MARK: Click to load

    @Test func autoLoadOffOffersAChip() {
        let manual = MediaPolicy(autoLoad: false)
        #expect(decide(page, policy: manual).plan == .loadChip(.page))
        #expect(!decide(page, policy: manual).shouldFetch)
        // A cached preview doesn't render until asked for.
        #expect(decide(page, preview: pagePreview(), policy: manual).plan == .loadChip(.page))
        #expect(decide(imageLink, policy: manual).plan == .loadChip(.image))
        #expect(decide(videoLink, policy: manual).plan == .loadChip(.video))
        #expect(decide(youtube, policy: manual).plan == .loadChip(.videoEmbed(.youtube)))
        #expect(decide(youtube, policy: manual, layout: PreviewLayout(videoStyle: .off)).plan == .loadChip(.page))
        let textOnly = MediaPolicy(autoLoad: false, siteRules: rules(["example.com": "textOnly"]))
        #expect(decide(imageLink, policy: textOnly).plan == .loadChip(.page))
        // Nothing to offer when that kind of preview is off.
        #expect(decide(page, policy: MediaPolicy(autoLoad: false, showLinkCards: false)).plan == PreviewPlan.none)
        #expect(decide(page, preview: pagePreview(title: nil, imageURL: nil), policy: manual).plan == PreviewPlan.none)
    }

    @Test func loadRequestedProceeds() {
        let manual = MediaPolicy(autoLoad: false)
        let asked = PreviewOverrides(loadRequested: true)
        let pending = decide(page, policy: manual, overrides: asked)
        #expect(pending.plan == .pending)
        #expect(pending.shouldFetch)
        #expect(decide(page, preview: pagePreview(), policy: manual, overrides: asked).plan == .card(.standard))
        #expect(decide(imageLink, policy: manual, overrides: asked).plan == .image(.full))
    }

    // MARK: Blocked

    @Test func blockedLinksShowWhy() {
        let byRule = decide(page, policy: MediaPolicy(siteRules: rules(["example.com": "block"])))
        #expect(byRule.plan == .blocked(SiteBlock(reason: .userBlocked, domain: "example.com")))
        #expect(!byRule.shouldFetch)
        #expect(!byRule.showsImages)

        let adult = decide(url("https://www.nsfw.example/x"), policy: MediaPolicy(extraAdultDomains: ["nsfw.example"]))
        #expect(adult.plan == .blocked(SiteBlock(reason: .adultSite, domain: "nsfw.example")))

        let notListed = decide(page, policy: MediaPolicy(restrictToAllowedDomains: true))
        #expect(notListed.plan == .blocked(SiteBlock(reason: .notAllowed, domain: "example.com")))

        // Blocked chips win over load chips.
        let manual = MediaPolicy(autoLoad: false, siteRules: rules(["example.com": "block"]))
        #expect(decide(page, policy: manual).plan.isBlocked)
    }

    @Test func blockedChipsOnlyForPreviewsThatWouldShow() {
        let blocked = rules(["example.com": "block", "youtube.com": "block"])
        #expect(decide(page, policy: MediaPolicy(showLinkCards: false, siteRules: blocked)).plan == PreviewPlan.none)
        #expect(decide(imageLink, policy: MediaPolicy(showLinkCards: false, siteRules: blocked)).plan.isBlocked)
        let off = PreviewLayout(videoStyle: .off)
        #expect(decide(youtube, policy: MediaPolicy(siteRules: blocked), layout: off).plan.isBlocked)
        #expect(decide(youtube, policy: MediaPolicy(showLinkCards: false, siteRules: blocked), layout: off).plan
            == PreviewPlan.none)
    }

    @Test func explicitRuleBeatsAdultList() {
        let policy = MediaPolicy(siteRules: rules(["nsfw.example": "allow"]), extraAdultDomains: ["nsfw.example"])
        #expect(decide(url("https://nsfw.example/a"), policy: policy).plan == .pending)
    }

    // MARK: Fetch-time blocks

    @Test func fetchBlockShowsUntilLifted() {
        let adultPolicy = MediaPolicy(extraAdultDomains: ["nsfw.example"])
        let block = SiteBlock(reason: .adultSite, domain: "nsfw.example")
        let short = url("https://short.example/x")

        let blocked = decide(short, fetchBlock: block, policy: adultPolicy)
        #expect(blocked.plan == .blocked(block))
        #expect(!blocked.shouldFetch)

        // Show once: refetch with a policy that lets the hop through.
        let once = decide(short, fetchBlock: block, policy: adultPolicy, overrides: PreviewOverrides(allowedOnce: ["nsfw.example"]))
        #expect(once.plan == .pending)
        #expect(once.shouldFetch)
        #expect(once.policy.allowedOnce == ["nsfw.example"])
        #expect(!once.policy.filterAdultSites)
        #expect(once.policy.allows(url("https://cdn.nsfw.example/v")))

        // The block went away some other way (e.g. the filter was switched off).
        let stale = decide(short, fetchBlock: block, policy: MediaPolicy(filterAdultSites: false))
        #expect(stale.plan == .pending)
        #expect(stale.shouldFetch)
    }

    @Test func fetchBlockReportsTheCurrentReason() {
        let block = SiteBlock(reason: .adultSite, domain: "nsfw.example")
        let policy = MediaPolicy(siteRules: rules(["nsfw.example": "block"]), extraAdultDomains: ["nsfw.example"])
        #expect(decide(page, fetchBlock: block, policy: policy).plan
            == .blocked(SiteBlock(reason: .userBlocked, domain: "nsfw.example")))
    }

    // MARK: After fetching

    @Test func previewThatLedSomewhereBlocked() {
        let policy = MediaPolicy(siteRules: rules(["blocked.example": "block"]))
        let landed = pagePreview(url("https://short.example/a"), finalURL: url("https://www.blocked.example/b"))
        #expect(decide(url("https://short.example/a"), preview: landed, policy: policy).plan
            == .blocked(SiteBlock(reason: .userBlocked, domain: "blocked.example")))

        let media = LinkPreview(url: imageLink, kind: .image, mediaURL: url("https://img.blocked.example/cat.png"))
        #expect(decide(imageLink, preview: media, policy: policy).plan.isBlocked)

        let privateLanding = pagePreview(url("https://short.example/a"), finalURL: url("http://10.0.0.1/"))
        #expect(decide(url("https://short.example/a"), preview: privateLanding).plan == PreviewPlan.none)
    }

    @Test func imagesNeedEverythingForTheLinkAndItsLanding() {
        let policy = MediaPolicy(siteRules: rules(["text.example": "textOnly", "short.example": "textOnly"]))
        let toText = pagePreview(url("https://link.example/a"), finalURL: url("https://text.example/b"))
        let viaText = decide(url("https://link.example/a"), preview: toText, policy: policy)
        #expect(viaText.plan == .card(.standard))
        #expect(!viaText.showsImages)
        #expect(!viaText.policy.imagesAllowed)

        let fromText = pagePreview(url("https://short.example/a"), finalURL: url("https://open.example/b"))
        #expect(!decide(url("https://short.example/a"), preview: fromText, policy: policy).showsImages)

        let open = pagePreview(url("https://link.example/a"), finalURL: url("https://open.example/b"))
        let both = decide(url("https://link.example/a"), preview: open, policy: policy)
        #expect(both.showsImages)
        #expect(both.policy.imagesAllowed)
    }

    @Test func pagesLabelledAdultAreBlocked() {
        let link = url("https://www.example.com/x")
        let labelled = pagePreview(link, declaresAdult: true)
        let decision = decide(link, preview: labelled)
        #expect(decision.plan == .blocked(SiteBlock(reason: .adultPage, domain: "example.com")))
        #expect(!decision.shouldFetch)

        // An explicit rule for the site wins…
        #expect(decide(link, preview: labelled, policy: MediaPolicy(siteRules: rules(["example.com": "allow"]))).plan
            == .card(.standard))
        let textOnly = decide(link, preview: labelled, policy: MediaPolicy(siteRules: rules(["example.com": "textOnly"])))
        #expect(textOnly.plan == .card(.standard))
        #expect(!textOnly.showsImages)
        // …as do switching the filter off and "Show once".
        #expect(decide(link, preview: labelled, policy: MediaPolicy(filterAdultSites: false)).plan == .card(.standard))
        let once = decide(link, preview: labelled, overrides: PreviewOverrides(allowedOnce: ["example.com"]))
        #expect(once.plan == .card(.standard))
        #expect(!once.policy.filterAdultSites)
        // Unlabelled or unknown pages are fine.
        #expect(decide(link, preview: pagePreview(link, declaresAdult: nil)).plan == .card(.standard))
    }

    @Test func adultLabelOnTheLandingPageNamesItsSite() {
        let short = url("https://short.example/a")
        let labelled = pagePreview(short, finalURL: url("https://www.landing.example/b"), declaresAdult: true)
        #expect(decide(short, preview: labelled).plan == .blocked(SiteBlock(reason: .adultPage, domain: "landing.example")))
        #expect(decide(short, preview: labelled, overrides: PreviewOverrides(allowedOnce: ["landing.example"])).plan
            == .card(.standard))
    }

    // MARK: Show once

    @Test func showOnceOnANotListedSiteLiftsTheRestrictionForThatPreview() {
        let policy = MediaPolicy(restrictToAllowedDomains: true)
        let once = decide(page, policy: policy, overrides: PreviewOverrides(allowedOnce: ["example.com"]))
        #expect(once.plan == .pending)
        #expect(once.shouldFetch)
        #expect(!once.policy.restrictToAllowedDomains)
        // So the card's image on another host can load.
        let loaded = decide(page, preview: pagePreview(), policy: policy, overrides: PreviewOverrides(allowedOnce: ["example.com"]))
        #expect(loaded.plan == .card(.standard))
        #expect(loaded.policy.allowsImage(url("https://cdn.example.org/card.jpg")))
    }

    @Test func showOnceOnABlockedSiteKeepsOtherRestrictions() {
        let policy = MediaPolicy(
            siteRules: rules(["example.com": "block", "listed.example": "allow"]),
            extraAdultDomains: ["nsfw.example"],
            restrictToAllowedDomains: true
        )
        let once = decide(page, policy: policy, overrides: PreviewOverrides(allowedOnce: ["example.com"]))
        #expect(once.plan == .pending)
        #expect(once.policy.restrictToAllowedDomains)
        #expect(once.policy.filterAdultSites)
        #expect(!once.policy.allowsImage(url("https://cdn.example.org/card.jpg")))
    }

    @Test func showOnceOnAnAdultSite() {
        let policy = MediaPolicy(extraAdultDomains: ["nsfw.example", "nsfwcdn.example"])
        let link = url("https://nsfw.example/a")
        let once = decide(link, policy: policy, overrides: PreviewOverrides(allowedOnce: ["nsfw.example"]))
        #expect(once.plan == .pending)
        #expect(!once.policy.filterAdultSites)
        #expect(once.policy.allowsImage(url("https://nsfwcdn.example/a.jpg")))
        // Other links in the buffer are unaffected: the context's policy is unchanged.
        #expect(decide(url("https://nsfwcdn.example/b"), policy: policy).plan.isBlocked)
    }

    // MARK: Blur

    @Test func blurCoversDrawnImagesUntilRevealed() {
        #expect(decide(imageLink, blur: true).blurred)
        #expect(!decide(imageLink, blur: true, overrides: PreviewOverrides(revealed: true)).blurred)
        #expect(!decide(imageLink, blur: false).blurred)
        #expect(decide(youtube, blur: true).blurred)
        #expect(decide(page, preview: pagePreview(), blur: true).blurred)
        #expect(!decide(page, preview: pagePreview(imageURL: nil), blur: true).blurred)
        #expect(!decide(page, blur: true).blurred)   // pending
        let preview = LinkPreview(url: videoLink, kind: .video, mediaURL: videoLink)
        #expect(decide(videoLink, preview: preview, blur: true).blurred)
        // Nothing to blur on text-only sites, chips or blocked links.
        let textOnly = MediaPolicy(siteRules: rules(["example.com": "textOnly"]))
        #expect(!decide(page, preview: pagePreview(), policy: textOnly, blur: true).blurred)
        #expect(!decide(imageLink, policy: MediaPolicy(autoLoad: false), blur: true).blurred)
        #expect(!decide(page, policy: MediaPolicy(siteRules: rules(["example.com": "block"])), blur: true).blurred)
    }

    // MARK: GIFs

    private let tenorFile = Self.url("https://media.tenor.com/WAeOn7-AdfgAAAAC/karate-kid-body-bag.gif")
    private let tenorShort = Self.url("https://tenor.com/RaDD.gif")
    private let giphyPage = Self.url("https://giphy.com/gifs/cat-funny-JIX9t2j0ZTN9S")

    private func tenorPreview(declaresAdult: Bool = false) -> LinkPreview {
        let gif = GIFInfo(
            provider: .tenor,
            videoURL: url("https://media.tenor.com/WAeOn7-AdfgAAAPo/karate-kid-body-bag.mp4"),
            imageURL: url("https://media.tenor.com/WAeOn7-AdfgAAAAd/karate-kid-body-bag.gif"),
            width: 490, height: 270, title: "Karate Kid"
        )
        return LinkPreview(
            url: tenorShort, finalURL: url("https://tenor.com/view/karate-kid-gif-10249931"), kind: .gif,
            title: "Karate Kid", siteName: "Tenor", mediaURL: gif.videoURL, gif: gif, declaresAdult: declaresAdult
        )
    }

    @Test func gifLinksThatNameTheirAnimationShowAtOnce() {
        for link in [tenorFile, giphyPage] {
            let decision = decide(link)
            #expect(decision.plan == .gif(.full))
            #expect(!decision.shouldFetch)
            #expect(decision.showsImages)
        }
        #expect(decide(tenorFile, layout: PreviewLayout(imageSize: .thumbnail)).plan == .gif(.thumbnail))
        // GIFs follow the image settings, not the video ones.
        #expect(decide(tenorFile, layout: PreviewLayout(videoStyle: .off)).plan == .gif(.full))
    }

    @Test func gifPagesAreFetchedFirst() {
        let pending = decide(tenorShort)
        #expect(pending.plan == .pending)
        #expect(pending.shouldFetch)
        let loaded = decide(tenorShort, preview: tenorPreview())
        #expect(loaded.plan == .gif(.full))
        #expect(!loaded.shouldFetch)
        // A page that turned out to have no animation is a card.
        let card = LinkPreview(url: tenorShort, kind: .page, title: "Tenor")
        #expect(decide(tenorShort, preview: card).plan == .card(.standard))
    }

    @Test func gifsWaitForAClickWhenAutoLoadIsOff() {
        let manual = MediaPolicy(autoLoad: false)
        for link in [tenorFile, tenorShort] {
            let decision = decide(link, policy: manual)
            #expect(decision.plan == .loadChip(.gif))
            #expect(!decision.shouldFetch)
        }
        let clicked = decide(tenorShort, policy: manual, overrides: PreviewOverrides(loadRequested: true))
        #expect(clicked.plan == .pending)
        #expect(clicked.shouldFetch)
        #expect(decide(tenorFile, policy: manual, overrides: PreviewOverrides(loadRequested: true)).plan == .gif(.full))
    }

    @Test func textOnlyGIFSitesGetATextCardAndNoAnimation() {
        let textOnly = MediaPolicy(siteRules: rules(["tenor.com": "textOnly"]))
        let pending = decide(tenorShort, policy: textOnly)
        #expect(pending.plan == .pending)
        #expect(pending.shouldFetch)
        #expect(!pending.policy.imagesAllowed)
        let card = decide(tenorShort, preview: tenorPreview(), policy: textOnly)
        #expect(card.plan == .card(.standard))
        #expect(!card.showsImages)
        #expect(!card.policy.allowsImage(url("https://media.tenor.com/WAeOn7-AdfgAAAPo/karate-kid-body-bag.mp4")))
        // A file link on a text-only site: a card too, never the animation.
        #expect(decide(tenorFile, policy: textOnly).plan == .pending)
        #expect(decide(tenorFile, preview: tenorPreview(), policy: textOnly).plan == .card(.standard))
        // A text-only rule for the media host alone also keeps the animation out.
        let mediaTextOnly = MediaPolicy(siteRules: rules(["media.tenor.com": "textOnly"]))
        #expect(decide(tenorShort, preview: tenorPreview(), policy: mediaTextOnly).plan == .card(.standard))
    }

    @Test func blockedGIFSitesShowAChip() {
        let blocked = MediaPolicy(siteRules: rules(["giphy.com": "block"]))
        #expect(decide(giphyPage, policy: blocked).plan == .blocked(SiteBlock(reason: .userBlocked, domain: "giphy.com")))
        #expect(decide(Self.url("https://gph.is/g/46vwxjM"), policy: blocked).plan
            == .blocked(SiteBlock(reason: .userBlocked, domain: "giphy.com")))
        // The page's media on a blocked host.
        let mediaBlocked = MediaPolicy(siteRules: rules(["media.tenor.com": "block"]))
        #expect(decide(tenorShort, preview: tenorPreview(), policy: mediaBlocked).plan.isBlocked)
        // "Show once" for the media host lifts it for this link.
        let once = decide(
            tenorShort, preview: tenorPreview(), policy: mediaBlocked,
            overrides: PreviewOverrides(allowedOnce: ["media.tenor.com"])
        )
        #expect(once.plan == .gif(.full))
    }

    @Test func adultGIFPagesAreFiltered() {
        let decision = decide(tenorShort, preview: tenorPreview(declaresAdult: true))
        #expect(decision.plan == .blocked(SiteBlock(reason: .adultPage, domain: "tenor.com")))
        #expect(decide(tenorShort, preview: tenorPreview(declaresAdult: true), policy: MediaPolicy(filterAdultSites: false)).plan
            == .gif(.full))
        let listed = MediaPolicy(extraAdultDomains: ["tenor.com"])
        #expect(decide(tenorFile, policy: listed).plan == .blocked(SiteBlock(reason: .adultSite, domain: "tenor.com")))
    }

    @Test func gifsAreBlurredUntilRevealed() {
        #expect(decide(tenorFile, blur: true).blurred)
        #expect(decide(tenorShort, preview: tenorPreview(), blur: true).blurred)
        #expect(!decide(tenorFile, blur: true, overrides: PreviewOverrides(revealed: true)).blurred)
        // Nothing to blur yet, or on a load chip.
        #expect(!decide(tenorShort, blur: true).blurred)
        #expect(!decide(tenorFile, policy: MediaPolicy(autoLoad: false), blur: true).blurred)
    }

    @Test func gifsAreNotShownWhenLinkCardsAndImagesAreOff() {
        // Link cards off: a GIF still shows (it's an image), but a text-only one has nothing to show.
        #expect(decide(tenorFile, policy: MediaPolicy(showLinkCards: false)).plan == .gif(.full))
        let textOnly = MediaPolicy(showLinkCards: false, siteRules: rules(["tenor.com": "textOnly"]))
        #expect(decide(tenorFile, policy: textOnly).plan == PreviewPlan.none)
    }
}

extension PreviewPlan {
    fileprivate var isBlocked: Bool {
        if case .blocked = self { return true }
        return false
    }
}
