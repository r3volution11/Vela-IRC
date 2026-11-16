// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaMedia
import VelaStore
@testable import VelaUI

@Suite("Site rules editor")
struct SiteRulesEditorTests {
    @Test func cleansUpTypedAndPastedSites() {
        #expect(SiteRulesEditor.ruleDomain("example.com") == "example.com")
        #expect(SiteRulesEditor.ruleDomain("  Example.COM  ") == "example.com")
        #expect(SiteRulesEditor.ruleDomain("https://i.imgur.com/abc.png?x=1#y") == "i.imgur.com")
        #expect(SiteRulesEditor.ruleDomain("*.example.com") == "example.com")
        #expect(SiteRulesEditor.ruleDomain(".example.com.") == "example.com")
        #expect(SiteRulesEditor.ruleDomain("user@example.com:8443") == "example.com")
        #expect(SiteRulesEditor.ruleDomain("news.example") == "news.example")
        #expect(SiteRulesEditor.ruleDomain("my-site_1.example.co.uk") == "my-site_1.example.co.uk")
    }

    @Test func dropsLeadingWWW() {
        #expect(SiteRulesEditor.ruleDomain("www.example.com") == "example.com")
        #expect(SiteRulesEditor.ruleDomain("https://www.example.com/page") == "example.com")
        // Nothing left but a TLD: keep it as typed.
        #expect(SiteRulesEditor.ruleDomain("www.com") == "www.com")
        // Only a leading www.
        #expect(SiteRulesEditor.ruleDomain("cdn.www.example.com") == "cdn.www.example.com")
    }

    @Test func keepsIPAddresses() {
        #expect(SiteRulesEditor.ruleDomain("192.168.1.10") == "192.168.1.10")
        #expect(SiteRulesEditor.ruleDomain("http://[::1]:8080/x") == "::1")
        #expect(SiteRulesEditor.ruleDomain("[fe80::1]") == "fe80::1")
    }

    @Test func rejectsWhatIsNotADomain() {
        #expect(SiteRulesEditor.ruleDomain("") == nil)
        #expect(SiteRulesEditor.ruleDomain("   ") == nil)
        #expect(SiteRulesEditor.ruleDomain("localhost") == nil)
        #expect(SiteRulesEditor.ruleDomain("com") == nil)
        #expect(SiteRulesEditor.ruleDomain("*.") == nil)
        #expect(SiteRulesEditor.ruleDomain("exa mple.com") == nil)
        #expect(SiteRulesEditor.ruleDomain("a..com") == nil)
        #expect(SiteRulesEditor.ruleDomain("example.com!") == nil)
        #expect(SiteRulesEditor.ruleDomain("[zz::1]") == nil)
    }

    @Test func sortsBySiteWithParentsFirst() {
        let rules: [String: SiteAccess] = [
            "zzz.com": .allow,
            "news.example": .textOnly,
            "i.example.com": .allow,
            "a.zzz.com": .block,
            "example.com": .block,
            "b.example.com": .block,
            "a.b.example.com": .allow,
            "10.0.0.1": .block,
        ]
        #expect(SiteRulesEditor.sorted(rules).map(\.domain) == [
            "10.0.0.1",
            "example.com", "b.example.com", "a.b.example.com", "i.example.com",
            "news.example",
            "zzz.com", "a.zzz.com",
        ])
        #expect(SiteRulesEditor.sorted(rules).first { $0.domain == "news.example" }?.access == .textOnly)
        #expect(SiteRulesEditor.sorted([:]).isEmpty)
    }

    @Test func menuWording() {
        #expect(SiteAccess.allCases.map(SiteRulesEditor.title(for:)) == ["Everything", "Text only", "Nothing"])
        // The wording parses back, so a pasted settings value can use it too.
        for access in SiteAccess.allCases {
            #expect(SiteAccess(settingsValue: SiteRulesEditor.title(for: access)) == access)
        }
    }
}

@Suite("Media commands")
struct MediaCommandTests {
    private func makeSettings() -> SettingsStore {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "VelaUITests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "settings.json")
        return SettingsStore(fileURL: url, watchForChanges: false)
    }

    @Test func adultFilterCommandTogglesTheSetting() throws {
        let settings = makeSettings()
        let command = try #require(VelaCommandCatalog.mediaCommands(settings).first { $0.id == "media.toggleAdultFilter" })
        #expect(command.category == .media)
        #expect(command.title == "Hide Adult Site Previews")
        #expect(command.isChecked == true)
        command.perform()
        #expect(settings[.mediaFilterAdultSites] == false)
        let rebuilt = VelaCommandCatalog.mediaCommands(settings).first { $0.id == "media.toggleAdultFilter" }
        #expect(rebuilt?.isChecked == false)
    }

    @Test func autoLoadCommandKeepsItsIdUnderTheNewTitle() throws {
        let settings = makeSettings()
        let command = try #require(VelaCommandCatalog.mediaCommands(settings).first { $0.id == "media.toggleAutoLoad" })
        #expect(command.title == "Load Previews Automatically")
        command.perform()
        #expect(settings[.mediaAutoLoad] == false)
    }

    @Test func paletteFindsTheAdultFilterByKeyword() throws {
        let items = PaletteSource.commandItems(VelaCommandCatalog.mediaCommands(makeSettings()), history: [])
        for query in ["nsfw", "porn", "safe"] {
            let first = try #require(PaletteRanker.rows(for: items, query: query, list: .commands).first)
            #expect(first.id == "media.toggleAdultFilter", "query \(query)")
        }
        let images = try #require(PaletteRanker.rows(for: items, query: "inline images", list: .commands).first)
        #expect(images.id == "media.toggleAutoLoad")
    }
}
