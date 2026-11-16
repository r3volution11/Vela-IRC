// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import Foundation
import Testing
import VelaMedia
@testable import VelaUI

private func link(_ string: String) -> EmbedLink {
    EmbedLink(url: URL(string: string)!)
}

private func context(
    _ policy: MediaPolicy = MediaPolicy(),
    links: PreviewLinkSize = .large,
    videos: PreviewVideoStyle = .player,
    images: PreviewImageSize = .full
) -> VelaMedia.PreviewContext {
    VelaMedia.PreviewContext(policy: policy, layout: PreviewLayout(linkSize: links, videoStyle: videos, imageSize: images))
}

private func rules(_ raw: [String: String]) -> SiteRules {
    SiteRules(raw)
}

@MainActor
@Suite("Embed line store")
struct EmbedLineStoreTests {
    let lineA = UUID()
    let lineB = UUID()

    @Test func collapsesPerLine() {
        let store = EmbedLineStore()
        store.setCollapsed(true, for: lineA)
        #expect(store.isCollapsed(lineA))
        #expect(!store.isCollapsed(lineB))
        store.setCollapsed(false, for: lineA)
        #expect(!store.isCollapsed(lineA))
    }

    @Test func loadRequestsArePerLink() {
        let store = EmbedLineStore()
        store.requestLoad(lineID: lineA, linkID: "one")
        #expect(store.overrides(lineID: lineA, linkID: "one").loadRequested)
        #expect(!store.overrides(lineID: lineA, linkID: "two").loadRequested)
        #expect(!store.overrides(lineID: lineB, linkID: "one").loadRequested)
    }

    @Test func showOnceCoversEveryLinkInTheLine() {
        let store = EmbedLineStore()
        store.allowOnce("nsfw.example", in: lineA)
        #expect(store.overrides(lineID: lineA, linkID: "one").allowedOnce == ["nsfw.example"])
        #expect(store.overrides(lineID: lineA, linkID: "two").allowedOnce == ["nsfw.example"])
        #expect(store.overrides(lineID: lineB, linkID: "one").allowedOnce.isEmpty)
    }

    @Test func remembersRevealAndPageFallbackPerLink() {
        let store = EmbedLineStore()
        store.setRevealed(true, lineID: lineA, linkID: "one")
        store.treatAsPage(lineID: lineA, linkID: "one")
        #expect(store.overrides(lineID: lineA, linkID: "one").revealed)
        #expect(store.overrides(lineID: lineA, linkID: "one").treatAsPage)
        #expect(store.overrides(lineID: lineA, linkID: "two") == PreviewOverrides())
        store.setRevealed(false, lineID: lineA, linkID: "one")
        #expect(!store.overrides(lineID: lineA, linkID: "one").revealed)
    }
}

@MainActor
@Suite("Embed decisions")
struct EmbedDecisionTests {
    let line = UUID()

    @Test func rememberedPreviewWaitsForLoadClickWhenAutoLoadIsOff() {
        let memory = EmbedMemory()
        let store = EmbedLineStore()
        let page = link("https://example.com/post")
        memory.remember(LinkPreview(url: page.url, kind: .page, title: "Post"), for: page.url)
        let manual = context(MediaPolicy(autoLoad: false))

        #expect(store.rememberedDecision(for: page, in: line, context: manual, memory: memory).plan == .loadChip(.page))
        store.requestLoad(lineID: line, linkID: page.id)
        #expect(store.rememberedDecision(for: page, in: line, context: manual, memory: memory).plan == .card(.large))
    }

    @Test func blockedLinksGetAChipAndNoRememberedPreview() {
        let memory = EmbedMemory()
        let store = EmbedLineStore()
        let page = link("https://news.example.com/post")
        memory.remember(LinkPreview(url: page.url, kind: .page, title: "Post"), for: page.url)
        let blocking = context(MediaPolicy(siteRules: rules(["example.com": "block"])))

        #expect(store.rememberedPreview(for: page, in: line, context: blocking, memory: memory) == nil)
        let decision = store.rememberedDecision(for: page, in: line, context: blocking, memory: memory)
        #expect(decision.plan == .blocked(SiteBlock(reason: .userBlocked, domain: "example.com")))
        #expect(!decision.shouldFetch)
    }

    @Test func showOnceOpensABlockedSiteForThatLineOnly() {
        let store = EmbedLineStore()
        let page = link("https://nsfw.example/gallery")
        let adult = context(MediaPolicy(extraAdultDomains: ["nsfw.example"]))
        let blocked = store.decision(for: page, in: line, preview: nil, fetchBlock: nil, context: adult)
        #expect(blocked.plan == .blocked(SiteBlock(reason: .adultSite, domain: "nsfw.example")))

        store.allowOnce("nsfw.example", in: line)
        let opened = store.decision(for: page, in: line, preview: nil, fetchBlock: nil, context: adult)
        #expect(opened.plan == .pending)
        #expect(opened.shouldFetch)
        // The fetch runs under a different policy, so the view's fetch task restarts.
        #expect(opened.policy != blocked.policy)
        #expect(opened.policy.allows(page.url))

        let otherLine = store.decision(for: page, in: UUID(), preview: nil, fetchBlock: nil, context: adult)
        #expect(otherLine.plan == blocked.plan)
    }

    @Test func aRedirectIntoABlockedSiteShowsItsChipUntilLifted() {
        let store = EmbedLineStore()
        let page = link("https://short.example/abc")
        let block = SiteBlock(reason: .userBlocked, domain: "tracker.example")
        let blocking = context(MediaPolicy(siteRules: rules(["tracker.example": "block"])))
        #expect(store.decision(for: page, in: line, preview: nil, fetchBlock: block, context: blocking).plan == .blocked(block))

        let unblocked = context(MediaPolicy())
        #expect(store.decision(for: page, in: line, preview: nil, fetchBlock: block, context: unblocked).plan == .pending)
    }

    @Test func textOnlySitesGetCardsWithoutImages() throws {
        let page = link("https://www.swift.org/blog/")
        let image = URL(string: "https://www.swift.org/assets/og.png")!
        let preview = LinkPreview(
            url: page.url, kind: .page, title: "Swift Blog", imageURL: image,
            faviconURL: URL(string: "https://www.swift.org/favicon.ico")
        )
        let textOnly = context(MediaPolicy(siteRules: rules(["swift.org": "textOnly"])))
        let decision = EmbedLineStore().decision(for: page, in: line, preview: preview, fetchBlock: nil, context: textOnly)

        #expect(decision.plan == .card(.large))
        #expect(!decision.showsImages)
        #expect(!decision.policy.allowsImage(image))
        #expect(LinkCardView.imageURL(of: preview, policy: decision.policy, showsImages: decision.showsImages) == nil)

        let open = EmbedLineStore().decision(for: page, in: line, preview: preview, fetchBlock: nil, context: context())
        #expect(LinkCardView.imageURL(of: preview, policy: open.policy, showsImages: open.showsImages) == image)
    }

    @Test func cardImagesOnARestrictedHostAreLeftOut() {
        let page = link("https://example.com/post")
        let image = URL(string: "https://cdn.tracker.example/og.png")!
        let preview = LinkPreview(url: page.url, kind: .page, title: "Post", imageURL: image)
        let policy = MediaPolicy(siteRules: rules(["tracker.example": "textOnly"]))
        #expect(LinkCardView.imageURL(of: preview, policy: policy, showsImages: true) == nil)
    }

    @Test func rememberedImagesFollowThePolicy() throws {
        let memory = EmbedMemory()
        let url = URL(string: "https://www.swift.org/assets/og.png")!
        let key = StillImageKey(url: url, maxPixelSize: 80)
        let image = try #require(Self.pixel())
        memory.remember(still: image, for: key)
        memory.remember(pixelSize: CGSize(width: 1200, height: 630), for: url)

        let textOnly = MediaPolicy(siteRules: rules(["swift.org": "textOnly"]))
        #expect(memory.still(key, policy: textOnly) == nil)
        #expect(memory.pixelSize(for: url, policy: textOnly) == nil)
        #expect(memory.still(key, policy: MediaPolicy()) != nil)
        #expect(memory.pixelSize(for: url, policy: MediaPolicy()) == CGSize(width: 1200, height: 630))
    }

    private static func pixel() -> CGImage? {
        let context = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        return context?.makeImage()
    }
}

@MainActor
@Suite("Embed presentation")
struct EmbedPresentationTests {
    @Test func imagesUseTheClassifiedURLOrTheFetchedImage() {
        let image = link("https://upload.wikimedia.org/wikipedia/commons/a/a1/Nebula.jpg")
        guard case .image(let imageURL) = image.classification else {
            Issue.record("not classified as an image")
            return
        }
        #expect(EmbedPresentation(plan: .image(.thumbnail), link: image, preview: nil) == .image(imageURL, .thumbnail))

        let page = link("https://example.com/picture")
        let media = URL(string: "https://cdn.example.com/picture.png")!
        let preview = LinkPreview(url: page.url, kind: .image, mediaURL: media)
        #expect(EmbedPresentation(plan: .image(.full), link: page, preview: preview) == .image(media, .full))
        #expect(EmbedPresentation(plan: .image(.full), link: page, preview: nil) == .nothing)
    }

    @Test func videosPreferTheFetchedEmbed() {
        let video = link("https://www.youtube.com/watch?v=aqz-KE-bpKQ")
        guard case .embed(let classified) = video.classification else {
            Issue.record("not classified as an embed")
            return
        }
        #expect(EmbedPresentation(plan: .videoEmbed(.compact), link: video, preview: nil) == .videoEmbed(classified, .compact))

        var fetched = classified
        fetched.title = "Big Buck Bunny"
        let preview = LinkPreview(url: video.url, kind: .embed, embed: fetched)
        #expect(EmbedPresentation(plan: .videoEmbed(.player), link: video, preview: preview) == .videoEmbed(fetched, .player))
    }

    @Test func directVideosAndCardsNeedTheFetchedPreview() {
        let clip = link("https://example.com/clip.mp4")
        let final = URL(string: "https://media.example.com/clip.mp4")!
        let preview = LinkPreview(url: clip.url, finalURL: final, kind: .video)
        #expect(EmbedPresentation(plan: .directVideo(.player), link: clip, preview: nil) == .nothing)
        #expect(EmbedPresentation(plan: .directVideo(.player), link: clip, preview: preview) == .directVideo(final, .player))
        #expect(EmbedPresentation(plan: .card(.minimal), link: clip, preview: nil) == .nothing)
        #expect(EmbedPresentation(plan: .card(.minimal), link: clip, preview: preview) == .card(preview, .minimal))
    }

    @Test func videosOffBecomeCards() {
        let video = link("https://youtu.be/aqz-KE-bpKQ")
        let preview = LinkPreview(url: video.url, kind: .embed, title: "Big Buck Bunny")
        let decision = EmbedLineStore().decision(
            for: video, in: UUID(), preview: preview, fetchBlock: nil, context: context(videos: .off)
        )
        #expect(EmbedPresentation(plan: decision.plan, link: video, preview: preview) == .card(preview, .large))
    }

    @Test func passesThroughChips() {
        let page = link("https://example.com/")
        let block = SiteBlock(reason: .notAllowed, domain: "example.com")
        #expect(EmbedPresentation(plan: .blocked(block), link: page, preview: nil) == .blocked(block))
        #expect(EmbedPresentation(plan: .loadChip(.page), link: page, preview: nil) == .loadChip(.page))
        #expect(EmbedPresentation(plan: .pending, link: page, preview: nil) == .nothing)
        #expect(EmbedPresentation(plan: .none, link: page, preview: nil) == .nothing)
    }

    @Test func loadChipLabels() {
        #expect(EmbedPresentation.loadChipLabel(.image).title == "Load image")
        #expect(EmbedPresentation.loadChipLabel(.video).title == "Load video")
        #expect(EmbedPresentation.loadChipLabel(.videoEmbed(.youtube)).title == "Load YouTube video")
        #expect(EmbedPresentation.loadChipLabel(.page).title == "Load preview")
    }
}

@MainActor
@Suite("Embed site menu")
struct EmbedSiteTargetTests {
    private func resolve(_ url: String, _ raw: [String: String] = [:]) -> EmbedSiteTarget? {
        let siteRules = rules(raw)
        return EmbedSiteTarget.resolve(for: URL(string: url)!) { siteRules.access(for: $0) }
    }

    @Test func suggestsTheSiteWithoutWWW() {
        #expect(resolve("https://www.swift.org/blog/") == EmbedSiteTarget(domain: "swift.org", access: nil))
        #expect(resolve("https://news.example.com/a") == EmbedSiteTarget(domain: "news.example.com", access: nil))
    }

    @Test func editsTheMatchingRule() {
        #expect(resolve("https://news.example.com/a", ["example.com": "textOnly"])
            == EmbedSiteTarget(domain: "example.com", access: .textOnly))
        #expect(resolve("https://ircv3.net/irc/", ["ircv3.net": "block"]) == EmbedSiteTarget(domain: "ircv3.net", access: .block))
    }

    @Test func videoShortLinksFollowTheProvider() {
        #expect(resolve("https://youtu.be/aqz-KE-bpKQ") == EmbedSiteTarget(domain: "youtube.com", access: nil))
        #expect(resolve("https://youtu.be/aqz-KE-bpKQ", ["youtube.com": "block"])
            == EmbedSiteTarget(domain: "youtube.com", access: .block))
    }

    @Test func nonWebLinksHaveNoSite() {
        #expect(resolve("ftp://example.com/file") == nil)
    }

    @Test func choicesAreInMenuOrder() {
        #expect(EmbedSiteTarget.choices.map(\.title) == ["Default", "Everything", "Text Only", "Nothing"])
        #expect(EmbedSiteTarget.choices.map(\.access) == [nil, .allow, .textOnly, .block])
    }
}

@MainActor
@Suite("Blocked preview chip")
struct BlockedPreviewChipTests {
    @Test func saysWhy() {
        #expect(BlockedPreviewChip.title(for: .adultSite) == "Adult site · preview blocked")
        #expect(BlockedPreviewChip.title(for: .adultPage) == "Page marked adult · preview blocked")
        #expect(BlockedPreviewChip.title(for: .userBlocked) == "Blocked site")
        #expect(BlockedPreviewChip.title(for: .notAllowed) == "Not on your allowed sites")
    }

    @Test func offersShowOnceAndALastingFix() {
        #expect(BlockedPreviewChip.actions(for: .adultSite) == [.showOnce, .alwaysAllow])
        #expect(BlockedPreviewChip.actions(for: .adultPage) == [.showOnce, .alwaysAllow])
        #expect(BlockedPreviewChip.actions(for: .notAllowed) == [.showOnce, .alwaysAllow])
        #expect(BlockedPreviewChip.actions(for: .userBlocked) == [.showOnce, .unblock])
    }

    @Test func readsNaturallyToVoiceOver() {
        let block = SiteBlock(reason: .adultSite, domain: "nsfw.example")
        #expect(BlockedPreviewChip.accessibilityLabel(for: block) == "Adult site, preview blocked, nsfw.example")
    }
}
