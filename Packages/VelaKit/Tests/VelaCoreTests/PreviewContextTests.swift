// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaCore
import VelaFoundation
import VelaMedia
import VelaStore

/// `AppModel`'s media settings: the preview context it hands the embed
/// views, site rules and per-buffer media switches.
@MainActor
@Suite("Preview context")
struct PreviewContextTests {
    /// A non-demo model on a scratch settings file.
    private func makeApp(isDemo: Bool = false, settings: [String: JSONValue] = [:]) throws -> AppModel {
        let root = FileManager.default.temporaryDirectory.appending(path: "VelaCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = SettingsStore(fileURL: root.appending(path: "settings.json"), watchForChanges: false)
        store.saveDelay = .seconds(60)
        for (key, value) in settings { store.setValue(value, forKey: key) }
        return AppModel(
            settings: store,
            networkStore: NetworkConfigStore(fileURL: root.appending(path: "networks.json")),
            database: nil,
            notifier: SilentNotifier(),
            isDemo: isDemo
        )
    }

    private func url(_ string: String) -> URL {
        URL(string: string)!
    }

    private let network = UUID()
    private var channel: BufferID { BufferID(networkID: network, foldedName: "#vela") }

    // MARK: Policy

    @Test func policyFollowsSettings() throws {
        let app = try makeApp(settings: [
            "media.autoLoad": false,
            "media.showLinkCards": false,
            "media.restrictToAllowed": true,
            "media.maxImageSizeMB": 2,
        ])
        let policy = app.previewContext(for: nil).policy
        #expect(!policy.autoLoad)
        #expect(!policy.showLinkCards)
        #expect(policy.restrictToAllowedDomains)
        #expect(policy.maxImageBytes == 2 * 1024 * 1024)
        #expect(policy.filterAdultSites)
        #expect(policy.extraAdultDomains.isEmpty)
        #expect(!app.previewContext(for: nil).blurImages)
    }

    @Test func adultFilterFollowsItsSetting() throws {
        let app = try makeApp(isDemo: true)
        let nsfw = url("https://cdn.nsfw.example/a.jpg")
        #expect(app.previewContext(for: nil).policy.filterAdultSites)
        #expect(app.previewContext(for: nil).policy.verdict(for: nsfw) == .blocked(SiteBlock(reason: .adultSite, domain: "nsfw.example")))

        app.settings[.mediaFilterAdultSites] = false
        #expect(!app.previewContext(for: nil).policy.filterAdultSites)
        #expect(app.previewContext(for: nil).policy.verdict(for: nsfw) == .everything)
    }

    @Test func demoAddsAPlaceholderAdultDomain() throws {
        #expect(AppModel.demo().previewContext(for: nil).policy.extraAdultDomains == ["nsfw.example"])
        #expect(try makeApp().previewContext(for: nil).policy.extraAdultDomains.isEmpty)
    }

    @Test func disabledBufferTurnsAutoLoadOff() throws {
        let app = try makeApp()
        let other = BufferID(networkID: UUID(), foldedName: "#vela")
        app.setMediaEnabled(false, for: channel)
        #expect(!app.previewContext(for: channel).policy.autoLoad)
        #expect(app.previewContext(for: other).policy.autoLoad)
        #expect(app.previewContext(for: nil).policy.autoLoad)

        app.setMediaEnabled(true, for: channel)
        app.setMediaEnabled(false, forNetwork: network)
        #expect(!app.previewContext(for: BufferID(networkID: network, foldedName: "#other")).policy.autoLoad)
        #expect(app.previewContext(for: other).policy.autoLoad)
    }

    // MARK: Per-buffer media

    @Test func mediaSwitchesPerBufferAndNetwork() throws {
        let app = try makeApp()
        #expect(app.isMediaEnabled(for: channel))
        #expect(app.isMediaEnabled(forNetwork: network))

        app.setMediaEnabled(false, for: channel)
        #expect(!app.isMediaEnabled(for: channel))
        #expect(app.isMediaEnabled(forNetwork: network))
        #expect(app.settings[.mediaDisabledBuffers] == [channel.description])

        app.setMediaEnabled(false, forNetwork: network)
        #expect(!app.isMediaEnabled(forNetwork: network))
        #expect(!app.isMediaEnabled(for: BufferID(networkID: network, foldedName: "#swift")))
        #expect(app.settings[.mediaDisabledBuffers] == [channel.description, "\(network.uuidString)/*"])

        app.setMediaEnabled(true, forNetwork: network)
        app.setMediaEnabled(true, for: channel)
        #expect(app.settings[.mediaDisabledBuffers].isEmpty)
        #expect(app.isMediaEnabled(for: channel))
    }

    // MARK: Site rules

    @Test func siteRulesComeFromSettings() throws {
        let app = try makeApp(settings: [
            "media.siteRules": .object(["Blocked.example": "block", "text.example": "textOnly", "bad.example": "maybe"]),
        ])
        let policy = app.previewContext(for: nil).policy
        #expect(policy.verdict(for: url("https://www.blocked.example/")) == .blocked(SiteBlock(reason: .userBlocked, domain: "blocked.example")))
        #expect(policy.verdict(for: url("https://text.example/")) == .textOnly)
        #expect(policy.verdict(for: url("https://bad.example/")) == .everything)
        #expect(app.siteRules.count == 2)
        #expect(app.siteRule(for: url("https://a.text.example/x"))?.access == .textOnly)
        #expect(app.siteRule(for: url("https://elsewhere.example/")) == nil)
    }

    @Test func legacyDomainListsStillApply() throws {
        let app = try makeApp(settings: [
            "media.siteRules": .object(["kept.example": "textOnly"]),
            "media.blockedDomains": .array(["tracker.io", "kept.example"]),
            "media.allowedDomains": .array(["imgur.com", "tracker.io"]),
        ])
        let rules = app.siteRules
        #expect(rules.entries == ["kept.example": .textOnly, "tracker.io": .block, "imgur.com": .allow])
        #expect(app.previewContext(for: nil).policy.siteRules == rules)
    }

    @Test func siteRulesFollowSettingsChanges() throws {
        let app = try makeApp()
        #expect(app.siteRules.isEmpty)
        app.settings[.mediaSiteRules] = ["a.example": "block"]
        #expect(app.siteRules.entries == ["a.example": .block])
        app.settings.setValue(.array(["b.example"]), forKey: "media.allowedDomains")
        #expect(app.siteRules.entries == ["a.example": .block, "b.example": .allow])
        app.settings.setValue(nil, forKey: "media.allowedDomains")
        app.settings.reset(.mediaSiteRules)
        #expect(app.siteRules.isEmpty)
    }

    @Test func setSiteRuleSetsReplacesAndRemoves() throws {
        let app = try makeApp(settings: ["media.siteRules": .object(["Example.com": "allow", "other.example": "block"])])

        app.setSiteRule(.textOnly, forDomain: "https://example.com/page")
        #expect(app.settings[.mediaSiteRules] == ["example.com": "textOnly", "other.example": "block"])
        #expect(app.siteRule(for: url("https://img.example.com/"))?.access == .textOnly)

        app.setSiteRule(.block, forDomain: "*.new.example")
        #expect(app.settings[.mediaSiteRules]["new.example"] == "block")

        app.setSiteRule(nil, forDomain: "EXAMPLE.com")
        #expect(app.settings[.mediaSiteRules] == ["other.example": "block", "new.example": "block"])
        #expect(app.siteRule(for: url("https://example.com/")) == nil)

        // Nothing to normalize: ignored.
        app.setSiteRule(.block, forDomain: "  ")
        #expect(app.settings[.mediaSiteRules].count == 2)
    }

    @Test func setSiteRuleRemovesMatchingLegacyEntries() throws {
        let app = try makeApp(settings: [
            "media.blockedDomains": .array(["*.example.com", "tracker.io"]),
            "media.allowedDomains": .array(["Example.com", "imgur.com"]),
        ])
        #expect(app.siteRule(for: url("https://example.com/"))?.access == .block)

        app.setSiteRule(nil, forDomain: "example.com")
        #expect(app.siteRule(for: url("https://example.com/")) == nil)
        // The other legacy entries live on as rules; the lists are gone.
        #expect(app.settings.value(forKey: "media.blockedDomains") == nil)
        #expect(app.settings.value(forKey: "media.allowedDomains") == nil)
        #expect(app.settings[.mediaSiteRules] == ["tracker.io": "block", "imgur.com": "allow"])
    }

    @Test func alwaysAllowAndUnblock() throws {
        let app = try makeApp(isDemo: true, settings: ["media.siteRules": .object(["blocked.example": "block"])])
        let nsfw = url("https://nsfw.example/")
        let adult = try #require(app.previewContext(for: nil).policy.verdict(for: nsfw).block)

        app.alwaysAllow(adult)
        #expect(app.previewContext(for: nil).policy.verdict(for: nsfw) == .everything)
        #expect(app.settings[.mediaSiteRules]["nsfw.example"] == "allow")

        let blocked = try #require(app.previewContext(for: nil).policy.verdict(for: url("https://blocked.example/")).block)
        #expect(blocked.reason == .userBlocked)
        app.unblock(blocked)
        #expect(app.previewContext(for: nil).policy.verdict(for: url("https://blocked.example/")) == .everything)
        #expect(app.settings[.mediaSiteRules] == ["nsfw.example": "allow"])
    }
}
