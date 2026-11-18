// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaMedia

@Suite struct SiteRulesTests {
    private func url(_ string: String) -> URL { URL(string: string)! }

    @Test func parsesSettingsShape() {
        let rules = SiteRules([
            "example.com": "block", "news.example": "textOnly", "i.imgur.com": "allow",
            "bad.example": "sometimes", "": "block",
        ])
        #expect(rules.entries == ["example.com": .block, "news.example": .textOnly, "i.imgur.com": .allow])
        #expect(rules.count == 3)
        #expect(rules.settingsValue == ["example.com": "block", "news.example": "textOnly", "i.imgur.com": "allow"])
    }

    @Test func toleratesValueSpellings() {
        #expect(SiteAccess(settingsValue: "TextOnly") == .textOnly)
        #expect(SiteAccess(settingsValue: "text-only") == .textOnly)
        #expect(SiteAccess(settingsValue: "text_only") == .textOnly)
        #expect(SiteAccess(settingsValue: "Everything") == .allow)
        #expect(SiteAccess(settingsValue: "nothing") == .block)
        #expect(SiteAccess(settingsValue: "maybe") == nil)
        #expect(SiteAccess.allCases.map(\.rawValue) == ["allow", "textOnly", "block"])
    }

    @Test func domainsAreNormalized() {
        for entry in ["*.example.com", ".example.com", "EXAMPLE.COM", "https://example.com/path", " example.com ",
                      "example.com:8443", "example.com.", "user@example.com"] {
            let rules = SiteRules([entry: "block"])
            #expect(rules.entries == ["example.com": .block], "\(entry)")
            #expect(rules.access(forHost: "cdn.example.com")?.access == .block, "\(entry)")
            #expect(rules.access(forHost: "notexample.com") == nil, "\(entry)")
        }
        #expect(SiteRules(["": "block", "   ": "block", "*.": "block"]).isEmpty)
        #expect(SiteRules.normalizedDomain("[::1]:8080") == "::1")
    }

    @Test func collidingEntriesKeepTheStricterRule() {
        let rules = SiteRules(["Example.com": "allow", "example.com": "block", "*.example.com": "textOnly"])
        #expect(rules.entries == ["example.com": .block])
        let mixed = SiteRules(["a.example": "allow", "A.example": "textOnly"])
        #expect(mixed.entries == ["a.example": .textOnly])
    }

    @Test func mostSpecificRuleWins() {
        let rules = SiteRules(["example.com": "block", "img.example.com": "allow", "com": "textOnly"])
        #expect(rules.access(forHost: "img.example.com")?.domain == "img.example.com")
        #expect(rules.access(forHost: "a.img.example.com")?.access == .allow)
        #expect(rules.access(forHost: "www.example.com")?.domain == "example.com")
        #expect(rules.access(forHost: "example.com")?.access == .block)
        #expect(rules.access(forHost: "other.com")?.domain == "com")
        #expect(rules.access(forHost: "example.org") == nil)
        #expect(rules.access(forHost: "WWW.EXAMPLE.COM.")?.domain == "example.com")
        #expect(rules.access(for: url("https://img.example.com/a.png"))?.access == .allow)
    }

    @Test func matchingRespectsLabelBoundaries() {
        let rules = SiteRules(["example.com": "block"])
        #expect(rules.access(forHost: "badexample.com") == nil)
        #expect(rules.access(forHost: "example.com.evil.net") == nil)
        #expect(rules.access(forHost: "example.co") == nil)
    }

    @Test func ipLiteralsMatchExactly() {
        let rules = SiteRules(["1.2.3.4": "block", "3.4": "block"])
        #expect(rules.access(forHost: "1.2.3.4")?.access == .block)
        #expect(rules.access(forHost: "9.9.3.4") == nil)
    }

    @Test func subscriptEditsNormalizedEntries() {
        var rules = SiteRules()
        rules["https://WWW.Example.com/x"] = .textOnly
        #expect(rules.entries == ["www.example.com": .textOnly])
        #expect(rules["www.example.com"] == .textOnly)
        rules["www.example.com"] = nil
        #expect(rules.isEmpty)
        #expect(SiteRules(entries: ["A.com": .allow]).domains(with: .allow) == ["a.com"])
    }

    @Test func suggestedRuleDomain() {
        #expect(SiteRules.suggestedRuleDomain(for: url("https://www.example.com/a")) == "example.com")
        #expect(SiteRules.suggestedRuleDomain(for: url("https://cdn.example.com/a")) == "cdn.example.com")
        #expect(SiteRules.suggestedRuleDomain(for: url("https://EXAMPLE.com./")) == "example.com")
        #expect(SiteRules.suggestedRuleDomain(for: url("https://youtu.be/dQw4w9WgXcQ")) == "youtube.com")
        #expect(SiteRules.suggestedRuleDomain(for: url("https://m.youtube.com/watch?v=dQw4w9WgXcQ")) == "youtube.com")
        #expect(SiteRules.suggestedRuleDomain(for: url("https://player.vimeo.com/video/76979871")) == "vimeo.com")
        #expect(SiteRules.suggestedRuleDomain(for: url("https://clips.twitch.tv/SomeSlug")) == "twitch.tv")
        #expect(SiteRules.suggestedRuleDomain(for: url("https://streamable.com/abc123")) == "streamable.com")
        #expect(SiteRules.suggestedRuleDomain(for: url("https://i.ytimg.com/vi/x/hq.jpg")) == "youtube.com")
        #expect(SiteRules.suggestedRuleDomain(for: url("ftp://example.com/")) == nil)
        #expect(SiteRules.suggestedRuleDomain(forHost: "www.com") == "www.com")
    }

    @Test func providerDomains() {
        #expect(EmbedProvider.allCases.map(\.mainDomain) == ["youtube.com", "vimeo.com", "twitch.tv", "streamable.com", "reddit.com"])
        #expect(EmbedProvider.provider(forHost: "youtu.be") == .youtube)
        #expect(EmbedProvider.provider(forHost: "www.youtube-nocookie.com") == .youtube)
        #expect(EmbedProvider.provider(forHost: "i.ytimg.com") == .youtube)
        #expect(EmbedProvider.provider(forHost: "static-cdn.jtvnw.net") == .twitch)
        #expect(EmbedProvider.provider(forHost: "notyoutube.com") == nil)
        #expect(EmbedProvider.provider(forHost: "example.com") == nil)
    }
}
