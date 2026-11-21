// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaMedia

/// Keeps `MediaSites` (the registry the docs page and the live checks come
/// from) honest against the code that actually recognizes links:
/// `MediaClassifier`, `GIFLinks`, `RedditLinks`, `OEmbedEndpoint` and `SiteRules`.
@Suite struct MediaSitesTests {
    struct SampleCase: Sendable, CustomTestStringConvertible {
        var site: MediaSite
        var sample: MediaSite.Sample
        var testDescription: String { "\(site.name): \(sample.link)" }
    }

    static let samples: [SampleCase] = MediaSites.all.flatMap { site in
        site.samples.map { SampleCase(site: site, sample: $0) }
    }

    // MARK: - The registry itself

    @Test func registryIsWellFormed() {
        let ids = MediaSites.all.map(\.id)
        #expect(Set(ids).count == ids.count, "site ids repeat")
        let links = MediaSites.all.flatMap(\.samples).map(\.link)
        #expect(Set(links).count == links.count, "sample links repeat")

        for site in MediaSites.all {
            #expect(!site.name.isEmpty)
            if let homepage = site.homepage {
                #expect(URL(string: homepage)?.scheme == "https", "\(site.name): homepage \(homepage)")
            }
            #expect(!site.forms.isEmpty, "\(site.name) has no link forms")
            #expect(!site.privacy.isEmpty, "\(site.name) has no privacy note")
            let formIDs = site.forms.map(\.id)
            #expect(Set(formIDs).count == formIDs.count, "\(site.name): form ids repeat")
            for form in site.forms {
                #expect(site.samples.contains { $0.form == form.id }, "\(site.name): no sample of \(form.pattern)")
            }
            for sample in site.samples {
                #expect(site.form(sample.form) != nil, "\(site.name): \(sample.link) names an unknown form \(sample.form)")
                #expect(sample.url?.scheme == "https", "\(site.name): \(sample.link) isn't an https link")
                if !sample.isLive {
                    #expect(sample.note != nil, "\(site.name): say why \(sample.link) is offline only")
                }
            }
            // Every site is checked against the real one, or says why not.
            #expect(site.liveSamples.isEmpty == (site.liveNote != nil), "\(site.name): live samples vs liveNote")
            for domain in site.domains {
                #expect(SiteRules.normalizedDomain(domain.name) == domain.name, "\(site.name): \(domain.name) isn't a bare domain")
            }
        }
    }

    // MARK: - Samples against the recognizers

    @Test(arguments: samples)
    func sampleIsRecognizedAsDeclared(_ testCase: SampleCase) throws {
        let sample = testCase.sample
        let url = try #require(sample.url)
        let form = try #require(testCase.site.form(sample.form))
        let classification = MediaClassifier.classify(url)

        switch sample.recognized {
        case .embed(let provider):
            guard case .embed(let info) = classification else {
                Issue.record("expected a \(provider.displayName) video, got \(classification)")
                return
            }
            #expect(info.provider == provider)
        case .gif(let provider, let resolved):
            guard case .gif(let info) = classification else {
                Issue.record("expected a \(provider.displayName) GIF, got \(classification)")
                return
            }
            #expect(info.provider == provider)
            #expect(info.isResolved == resolved, "resolved offline: \(info.isResolved)")
        case .image:
            guard case .image = classification else {
                Issue.record("expected an image, got \(classification)")
                return
            }
        case .video:
            guard case .video = classification else {
                Issue.record("expected a video file, got \(classification)")
                return
            }
        case .redditPost:
            guard case .page = classification else {
                Issue.record("expected a page, got \(classification)")
                return
            }
            #expect(RedditLinks.post(url) != nil, "not a Reddit post")
        case .page:
            guard case .page = classification else {
                Issue.record("expected a page, got \(classification)")
                return
            }
            #expect(RedditLinks.post(url) == nil, "a Reddit post, not a page to follow")
        }

        if let loadsFrom = sample.loadsFrom {
            let media = classification.mediaURLs.compactMap { SiteRules.normalizedHost($0) }
            #expect(media.contains(loadsFrom), "loads from \(media), not \(loadsFrom)")
        }

        #expect(Self.shows(classification) == form.shows, "\(form.pattern) says it shows \(form.shows)")
        for problem in Self.stepProblems(form.steps, classification: classification, url: url) {
            Issue.record("\(form.pattern): \(problem)")
        }
    }

    /// What the classification makes Vela draw.
    static func shows(_ classification: MediaClassification) -> MediaSite.Presentation {
        switch classification {
        case .embed(let info): info.provider.playsNatively ? .nativePlayer : .videoPlayer
        case .gif(let info):
            if info.isSticker {
                .sticker
            } else if info.isResolved, info.videoURL == nil {
                // No video copy to play: the GIF or WebP as linked.
                .gifFile
            } else {
                .gif
            }
        case .image: .image
        case .video: .videoFile
        case .page: .linkPreview
        }
    }

    /// Where a form's declared steps disagree with what the code does.
    static func stepProblems(_ steps: [MediaSite.Step], classification: MediaClassification, url: URL) -> [String] {
        var problems: [String] = []
        func require(_ condition: Bool, _ message: String) {
            if !condition { problems.append(message) }
        }
        let offline: Bool = switch classification {
        case .image: true
        case .gif(let info): info.isResolved
        default: false
        }
        require(steps.isEmpty == offline, offline ? "the link names the media: no steps" : "Vela fetches something first")
        if case .video = classification {
            require(steps.contains(.headRequest), "video files get a HEAD request")
        } else {
            require(!steps.contains(.headRequest), "only video files get a HEAD request")
        }
        switch classification {
        case .embed(let info):
            require(steps.contains(.hlsPlaylist) == info.provider.playsNatively, "the HLS playlist is read for native players only")
            if info.provider == .reddit || OEmbedEndpoint.url(for: info) != nil {
                require(steps.contains(.oEmbed), "\(info.provider.displayName) titles come from oEmbed")
            } else {
                require(steps.contains(.pageMetadata), "\(info.provider.displayName) titles come from the page")
                require(!steps.contains(.oEmbed), "\(info.provider.displayName) has no oEmbed endpoint")
            }
        case .gif(let info) where !info.isResolved:
            require(steps.contains(.pageMetadata), "an unresolved GIF link is resolved from its page")
        case .page:
            if let post = RedditLinks.post(url) {
                require(OEmbedEndpoint.reddit(post: post.canonicalURL) != nil && steps.contains(.oEmbed), "posts are read through oEmbed")
            } else {
                require(steps.contains(.redirect), "a page that isn't recognized yet is followed")
            }
        default:
            require(!steps.contains(.hlsPlaylist), "only native players read an HLS playlist")
        }
        if steps.contains(.browserEngine) {
            var ordinaryPage = false
            if case .page = classification, RedditLinks.post(url) == nil, let host = SiteRules.normalizedHost(url),
               SiteRules.providerMainDomain(forHost: host) == nil {
                ordinaryPage = true
            }
            require(ordinaryPage, "only ordinary pages are read with the browser engine")
            require(steps.contains(.pageMetadata), "the browser engine reads a page that was fetched first")
        }
        return problems
    }

    // MARK: - Site rules

    @Test(arguments: MediaSites.all.map(\.id))
    func domainsAreCoveredByTheSiteRule(_ id: String) throws {
        let site = try #require(MediaSites.site(id))
        for domain in site.domains {
            for host in [domain.name, "cdn1." + domain.name] {
                let expected = site.ruleDomain ?? host
                #expect(SiteRules.suggestedRuleDomain(forHost: host) == expected, "\(host) → \(expected)")
            }
        }
        for sample in site.samples {
            let url = try #require(sample.url)
            let host = try #require(SiteRules.normalizedHost(url))
            if !site.domains.isEmpty {
                #expect(site.domains.contains { SiteRules.host(host, isWithin: $0.name) }, "\(host) isn't among \(site.name)'s domains")
            }
            let expected = site.ruleDomain ?? SiteRules.suggestedRuleDomain(forHost: host)
            #expect(SiteRules.suggestedRuleDomain(for: url) == expected, "\(sample.link) → \(expected ?? "nil")")
            if let loadsFrom = sample.loadsFrom {
                #expect(SiteRules.suggestedRuleDomain(forHost: loadsFrom) == (site.ruleDomain ?? loadsFrom))
            }
        }
    }

    /// Every provider in the code has an entry, and every domain the code
    /// treats as the provider's is listed under its rule domain.
    @Test func everyProviderAndDomainIsListed() {
        func domains(ruledBy ruleDomain: String) -> Set<String> {
            Set(MediaSites.all.filter { $0.ruleDomain == ruleDomain }.flatMap(\.domains).map(\.name))
        }
        for provider in EmbedProvider.allCases {
            let sites = MediaSites.all.filter { $0.embedProvider == provider }
            #expect(sites.count == 1, "\(provider.displayName) has \(sites.count) entries")
            #expect(sites.first?.ruleDomain == provider.mainDomain)
            let listed = domains(ruledBy: provider.mainDomain)
            for domain in [provider.mainDomain] + provider.assetDomains {
                #expect(listed.contains(domain), "\(domain) (\(provider.displayName)) isn't listed")
            }
        }
        for provider in GIFProvider.allCases {
            let sites = MediaSites.all.filter { $0.gifProvider == provider }
            #expect(sites.count == 1, "\(provider.displayName) has \(sites.count) entries")
            #expect(sites.first?.ruleDomain == provider.mainDomain)
            #expect(sites.first?.homepage == provider.homepage.absoluteString, "\(provider.displayName)'s home page")
            if let main = provider.mainDomain {
                let listed = domains(ruledBy: main)
                for domain in [main] + provider.assetDomains {
                    #expect(listed.contains(domain), "\(domain) (\(provider.displayName)) isn't listed")
                }
            }
        }
        // And the other way: a listed site rule is one the code applies.
        for site in MediaSites.all {
            if let provider = site.embedProvider { #expect(site.category == .videos || site.category == .reddit, "\(provider)") }
            if site.gifProvider != nil { #expect(site.category == .gifs) }
            // A bot-check site's links are read with the browser engine, and checked that they were.
            if site.category == .botChecks {
                #expect(site.forms.allSatisfy { $0.steps.contains(.browserEngine) }, "\(site.name)")
                #expect(site.liveSamples.allSatisfy { $0.live.contains(.browserEngine) }, "\(site.name)")
            }
        }
    }

    // MARK: - Lookalikes and other links

    /// `www.notyoutube.com`, `www.youtube.com.example` and
    /// `www.youtube-com.example` aren't YouTube.
    @Test(arguments: samples)
    func lookalikeHostsAreNotTheSite(_ testCase: SampleCase) throws {
        let site = testCase.site
        let url = try #require(testCase.sample.url)
        let host = try #require(SiteRules.normalizedHost(url))
        // The broadest of the site's domains the host is on: i.imgur.com → imgur.com.
        guard let domain = site.domains.map(\.name).filter({ SiteRules.host(host, isWithin: $0) })
            .min(by: { $0.count < $1.count })
        else { return }
        let prefix = host.dropLast(domain.count)
        let lookalikes = [
            prefix + "not" + domain,
            prefix + domain + ".example",
            prefix + domain.replacingOccurrences(of: ".", with: "-") + ".example",
        ]
        for lookalike in lookalikes {
            var components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
            components.host = lookalike
            let fake = try #require(components.url)
            let classification = MediaClassifier.classify(fake)
            switch classification {
            case .embed(let info):
                #expect(info.provider != site.embedProvider, "\(fake) passes for \(site.name)")
            case .gif(let info):
                #expect(info.provider != site.gifProvider, "\(fake) passes for \(site.name)")
            case .image, .video, .page:
                break
            }
            #expect(RedditLinks.post(fake) == nil, "\(fake) passes for a Reddit post")
            if let loadsFrom = testCase.sample.loadsFrom {
                #expect(!classification.mediaURLs.contains { $0.host() == loadsFrom }, "\(fake) is rewritten to \(loadsFrom)")
            }
            if let ruleDomain = site.ruleDomain {
                #expect(SiteRules.suggestedRuleDomain(for: fake) != ruleDomain, "\(fake) falls under the \(ruleDomain) rule")
            }
        }
    }

    /// Links on these sites that aren't media stay ordinary pages.
    @Test(arguments: [
        "https://www.youtube.com/@NASA",
        "https://www.youtube.com/feed/trending",
        "https://www.youtube.com/watch?v=tooShort",
        "https://vimeo.com/blog",
        "https://vimeo.com/channels/staffpicks",
        "https://www.twitch.tv/stableronaldo",
        "https://www.twitch.tv/directory",
        "https://streamable.com/login",
        "https://tenor.com/search/cat-gifs",
        "https://giphy.com/explore/cats",
        "https://giphy.com/gifs/funny-cats",
        "https://imgur.com/gallery/abc123",
        "https://i.imgur.com/abc123",
        "https://klipy.com/gifs/awesome-ok--ksMzbJP8D",
        "https://klipy.com/search/thumbs-up",
        "https://www.reddit.com/r/LoveTrash/",
        "https://old.reddit.com/user/downtune79",
        "https://github.com/r3volution11/Vela-IRC",
        "https://github.com/r3volution11/Vela-IRC/blob/main/README.md",
        "https://example.com/watch?v=aqz-KE-bpKQ",
        "https://example.com/view/nasa-gif-9368490",
    ])
    func otherLinksStayPages(_ link: String) throws {
        let url = try #require(URL(string: link))
        let classification = MediaClassifier.classify(url)
        guard case .page = classification else {
            Issue.record("\(link) is recognized as \(classification)")
            return
        }
        #expect(RedditLinks.post(url) == nil)
    }

    // MARK: - The docs page

    @Test func websitePageIsCurrent() throws {
        let url = Self.repositoryRoot.appending(path: MediaSitesPage.pagePath)
        let page = try String(contentsOf: url, encoding: .utf8)
        #expect(
            page.contains(MediaSitesPage.markdown()),
            "\(MediaSitesPage.pagePath) is out of date with MediaSites.swift. Run: \(MediaSitesPage.command)"
        )
    }

    @Test func updatingReplacesOnlyTheGeneratedPart() throws {
        let page = "# Title\n\nIntro.\n\n\(MediaSitesPage.beginMarker)\nold\n\(MediaSitesPage.endMarker)\n\nAfter.\n"
        let updated = try MediaSitesPage.updating(page)
        #expect(updated.hasPrefix("# Title\n\nIntro.\n\n" + MediaSitesPage.beginMarker))
        #expect(updated.hasSuffix(MediaSitesPage.endMarker + "\n\nAfter.\n"))
        #expect(!updated.contains("\nold\n"))
        #expect(try MediaSitesPage.updating(updated) == updated)
        #expect(throws: MediaSitesPage.PageError.self) { try MediaSitesPage.updating("# No markers\n") }
    }

    @Test func pageListsEverySiteAndForm() {
        let markdown = MediaSitesPage.markdown()
        for site in MediaSites.all {
            #expect(markdown.contains(site.homepage.map { "[\(site.name)](\($0))" } ?? site.name))
            for form in site.forms {
                #expect(markdown.contains("`\(form.pattern)`"), "\(form.pattern)")
            }
        }
        for ext in MediaClassifier.imageExtensions.union(MediaClassifier.videoExtensions) {
            #expect(markdown.contains(".\(ext)`"), ".\(ext) isn't listed")
        }
    }

    static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // VelaMediaTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // VelaKit
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent() // repository root
}
