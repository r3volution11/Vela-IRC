// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaMedia

@Suite struct MediaPolicyTests {
    private func url(_ string: String) -> URL { URL(string: string)! }

    private func rules(_ raw: [String: String]) -> SiteRules { SiteRules(raw) }

    @Test func defaults() {
        let policy = MediaPolicy()
        #expect(policy.autoLoad)
        #expect(policy.showLinkCards)
        #expect(policy.filterAdultSites)
        #expect(policy.imagesAllowed)
        #expect(policy.siteRules.isEmpty)
        #expect(policy.allowedOnce.isEmpty)
        #expect(policy.extraAdultDomains.isEmpty)
        #expect(policy.maxImageBytes == 10 * 1024 * 1024)
        #expect(!policy.restrictToAllowedDomains)
        #expect(!policy.allowPrivateNetworkHosts)
        #expect(policy.verdict(for: url("https://example.com/a.png")) == .everything)
        #expect(policy.allows(url("https://example.com/a.png")))
        #expect(policy.allowsImage(url("http://example.com/")))
    }

    @Test func onlyHTTPSchemes() {
        let policy = MediaPolicy()
        for string in ["ftp://example.com/a.png", "file:///etc/passwd", "data:text/plain,hi", "javascript:alert(1)"] {
            #expect(policy.verdict(for: url(string)) == .forbidden, "\(string)")
            #expect(!policy.allows(url(string)))
            #expect(!policy.allowsImage(url(string)))
        }
    }

    @Test(arguments: [
        "http://localhost/", "http://localhost:8080/admin", "http://app.localhost/", "http://127.0.0.1/",
        "http://10.0.0.1/", "http://172.16.5.4/", "http://172.31.255.255/", "http://192.168.1.1/reboot",
        "http://169.254.169.254/latest/meta-data/", "http://100.64.0.1/", "http://0.0.0.0/",
        "http://[::1]/", "http://[fe80::1]/", "http://[fd12:3456::1]/", "http://[::ffff:192.168.0.1]/",
        "http://router/", "http://nas.local/", "http://printer.lan/", "http://box.home.arpa/",
    ])
    func privateNetworkHostsAreForbiddenByDefault(_ string: String) {
        #expect(MediaPolicy().verdict(for: url(string)) == .forbidden)
        #expect(!MediaPolicy().allows(url(string)))
        #expect(MediaPolicy(allowPrivateNetworkHosts: true).allows(url(string)))
    }

    @Test(arguments: ["http://172.32.0.1/", "http://8.8.8.8/", "http://[2606:4700::1111]/", "http://192.169.0.1/"])
    func publicIPLiteralsAreAllowed(_ string: String) {
        #expect(MediaPolicy().verdict(for: url(string)) == .everything)
    }

    @Test func forbiddenBeatsEverything() {
        // Neither a rule nor "Show once" opens a private host.
        let policy = MediaPolicy(siteRules: rules(["localhost": "allow"]), allowedOnce: ["localhost"])
        #expect(policy.verdict(for: url("http://localhost/")) == .forbidden)
    }

    // MARK: Rules

    @Test func blockRuleMatchesOnLabelBoundaries() {
        let policy = MediaPolicy(siteRules: rules(["example.com": "block"]))
        let blocked = SiteVerdict.blocked(SiteBlock(reason: .userBlocked, domain: "example.com"))
        #expect(policy.verdict(for: url("https://example.com/")) == blocked)
        #expect(policy.verdict(for: url("https://img.example.com/x.png")) == blocked)
        #expect(policy.verdict(for: url("https://a.b.EXAMPLE.com/")) == blocked)
        #expect(policy.verdict(for: url("https://example.com./")) == blocked)
        #expect(policy.allows(url("https://badexample.com/")))
        #expect(policy.allows(url("https://example.com.evil.net/")))
        #expect(policy.allows(url("https://example.org/")))
    }

    @Test func textOnlyRefusesImagesButAllowsRequests() {
        let policy = MediaPolicy(siteRules: rules(["news.example": "textOnly"]))
        let article = url("https://www.news.example/story")
        #expect(policy.verdict(for: article) == .textOnly)
        #expect(policy.allows(article))
        #expect(!policy.allowsImage(article))
        #expect(!policy.allowsImage(url("https://cdn.news.example/photo.jpg")))
        #expect(policy.allowsImage(url("https://other.example/photo.jpg")))
    }

    @Test func mostSpecificRuleWins() {
        let policy = MediaPolicy(siteRules: rules([
            "example.com": "block", "img.example.com": "allow", "text.img.example.com": "textOnly",
        ]))
        #expect(policy.verdict(for: url("https://www.example.com/")).block?.domain == "example.com")
        #expect(policy.verdict(for: url("https://img.example.com/a.png")) == .everything)
        #expect(policy.verdict(for: url("https://cdn.img.example.com/a.png")) == .everything)
        #expect(policy.verdict(for: url("https://text.img.example.com/a")) == .textOnly)
    }

    @Test func imagesOffMakesEverythingTextOnly() {
        let policy = MediaPolicy(siteRules: rules(["blocked.example": "block"]), imagesAllowed: false)
        #expect(policy.verdict(for: url("https://example.com/")) == .textOnly)
        #expect(policy.allows(url("https://example.com/")))
        #expect(!policy.allowsImage(url("https://example.com/a.png")))
        #expect(policy.verdict(for: url("https://blocked.example/")).block?.reason == .userBlocked)
    }

    @Test func providerRulesCoverTheirAssetDomains() {
        let policy = MediaPolicy(siteRules: rules(["youtube.com": "block", "vimeo.com": "textOnly"]))
        let youtube = SiteVerdict.blocked(SiteBlock(reason: .userBlocked, domain: "youtube.com"))
        #expect(policy.verdict(for: url("https://youtu.be/dQw4w9WgXcQ")) == youtube)
        #expect(policy.verdict(for: url("https://www.youtube-nocookie.com/embed/x")) == youtube)
        #expect(policy.verdict(for: url("https://i.ytimg.com/vi/x/hqdefault.jpg")) == youtube)
        #expect(policy.verdict(for: url("https://i.vimeocdn.com/video/1.jpg")) == .textOnly)
        #expect(policy.verdict(for: url("https://player.vimeo.com/video/1")) == .textOnly)

        // A rule of the asset domain's own wins.
        let own = MediaPolicy(siteRules: rules(["youtube.com": "block", "ytimg.com": "allow"]))
        #expect(own.verdict(for: url("https://i.ytimg.com/vi/x/hqdefault.jpg")) == .everything)
    }

    // MARK: Adult sites

    @Test func adultListBlocksUnlessFilterIsOff() {
        let policy = MediaPolicy(extraAdultDomains: ["nsfw.example"])
        let blocked = SiteVerdict.blocked(SiteBlock(reason: .adultSite, domain: "nsfw.example"))
        #expect(policy.verdict(for: url("https://nsfw.example/")) == blocked)
        #expect(policy.verdict(for: url("https://cdn.nsfw.example/a.jpg")) == blocked)
        #expect(policy.allows(url("https://notnsfw.example/")))
        #expect(policy.allows(url("https://nsfw.example.com/")))

        var off = policy
        off.filterAdultSites = false
        #expect(off.verdict(for: url("https://nsfw.example/")) == .everything)
    }

    @Test(arguments: ["https://site.xxx/", "https://videos.site.porn/", "https://a.adult/", "https://SITE.SEX/x"])
    func adultTopLevelDomainsAreBuiltIn(_ string: String) {
        #expect(MediaPolicy().verdict(for: url(string)).block?.reason == .adultSite)
        #expect(MediaPolicy(filterAdultSites: false).verdict(for: url(string)) == .everything)
    }

    @Test func adultTopLevelDomainReportsTheSite() {
        #expect(MediaPolicy().verdict(for: url("https://videos.site.xxx/")).block?.domain == "site.xxx")
    }

    @Test func explicitRuleBeatsTheAdultList() {
        let base = MediaPolicy(extraAdultDomains: ["nsfw.example"])
        var allowed = base
        allowed.siteRules = rules(["nsfw.example": "allow"])
        #expect(allowed.verdict(for: url("https://nsfw.example/")) == .everything)

        var textOnly = base
        textOnly.siteRules = rules(["cdn.nsfw.example": "textOnly"])
        #expect(textOnly.verdict(for: url("https://cdn.nsfw.example/")) == .textOnly)
        #expect(textOnly.verdict(for: url("https://nsfw.example/")).block?.reason == .adultSite)

        var blocked = base
        blocked.siteRules = rules(["nsfw.example": "block"])
        #expect(blocked.verdict(for: url("https://nsfw.example/")).block?.reason == .userBlocked)
    }

    // MARK: Show once

    @Test func allowedOnceBeatsRulesAdultListAndRestriction() {
        var policy = MediaPolicy(
            siteRules: rules(["blocked.example": "block", "text.example": "textOnly"]),
            extraAdultDomains: ["nsfw.example"],
            restrictToAllowedDomains: true
        )
        #expect(!policy.allows(url("https://blocked.example/")))
        #expect(!policy.allows(url("https://nsfw.example/")))
        #expect(!policy.allows(url("https://elsewhere.example/")))

        policy.allowedOnce = ["blocked.example", "nsfw.example", "elsewhere.example", "text.example"]
        #expect(policy.verdict(for: url("https://www.blocked.example/")) == .everything)
        #expect(policy.verdict(for: url("https://nsfw.example/")) == .everything)
        #expect(policy.verdict(for: url("https://elsewhere.example/")) == .everything)
        #expect(policy.verdict(for: url("https://text.example/")) == .everything)
        #expect(policy.verdict(for: url("https://other.example/")).block?.reason == .notAllowed)
        #expect(policy.isAllowedOnce(host: "a.nsfw.example"))
        #expect(!policy.isAllowedOnce(host: "nsfw.example.evil.net"))
    }

    // MARK: Restrict to listed sites

    @Test func restrictionAllowsOnlyListedSites() {
        let policy = MediaPolicy(
            siteRules: rules(["imgur.com": "allow", "news.example": "textOnly", "i.imgur.com": "block"]),
            restrictToAllowedDomains: true
        )
        #expect(policy.verdict(for: url("https://imgur.com/gallery/x")) == .everything)
        #expect(policy.verdict(for: url("https://news.example/a")) == .textOnly)
        #expect(policy.verdict(for: url("https://i.imgur.com/a.png")).block?.reason == .userBlocked)
        #expect(policy.verdict(for: url("https://www.example.com/")) == .blocked(SiteBlock(
            reason: .notAllowed, domain: "example.com"
        )))
        #expect(policy.verdict(for: url("https://notimgur.com/")).block?.reason == .notAllowed)
        // Video links name the provider's domain, which is what "Always allow" should add.
        #expect(policy.verdict(for: url("https://youtu.be/dQw4w9WgXcQ")).block?.domain == "youtube.com")

        var open = policy
        open.restrictToAllowedDomains = false
        #expect(open.verdict(for: url("https://www.example.com/")) == .everything)
    }

    // MARK: Errors

    @Test func requestAndImageErrors() {
        let policy = MediaPolicy(siteRules: rules(["blocked.example": "block", "text.example": "textOnly"]))
        let block = SiteBlock(reason: .userBlocked, domain: "blocked.example")
        #expect(policy.requestError(for: url("https://blocked.example/")) == .siteBlocked(block))
        #expect(policy.requestError(for: url("http://localhost/")) == .blockedByPolicy)
        #expect(policy.requestError(for: url("https://text.example/")) == nil)
        #expect(policy.imageError(for: url("https://text.example/a.png")) == .blockedByPolicy)
        #expect(policy.imageError(for: url("https://blocked.example/a.png")) == .siteBlocked(block))
        #expect(policy.imageError(for: url("https://example.com/a.png")) == nil)
        #expect(MediaError.siteBlocked(block).siteBlock == block)
        #expect(MediaError.siteBlocked(block).isPolicyRefusal)
        #expect(!MediaError.tooLarge.isPolicyRefusal)
    }

    @Test func fetchKeyIgnoresDisplaySwitches() {
        let a = MediaPolicy(autoLoad: false, showLinkCards: false, imagesAllowed: false)
        #expect(a.fetchKey == MediaPolicy().fetchKey)
        #expect(MediaPolicy(allowedOnce: ["x.example"]).fetchKey != MediaPolicy().fetchKey)
    }
}
