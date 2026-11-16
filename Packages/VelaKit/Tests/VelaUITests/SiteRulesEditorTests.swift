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

    @Test func sizeCommandsReplaceThePresentationPair() {
        let commands = VelaCommandCatalog.mediaCommands(makeSettings())
        let ids = commands.map(\.id)
        #expect(!ids.contains("media.full"))
        #expect(!ids.contains("media.compact"))
        let titles = Dictionary(uniqueKeysWithValues: commands.map { ($0.id, $0.paletteTitle) })
        #expect(titles["media.links.minimal"] == "Media: Minimal Link Previews")
        #expect(titles["media.links.standard"] == "Media: Standard Link Previews")
        #expect(titles["media.links.large"] == "Media: Large Link Previews")
        #expect(titles["media.videos.player"] == "Media: Play Videos Inline")
        #expect(titles["media.videos.compact"] == "Media: Compact Videos")
        #expect(titles["media.videos.off"] == "Media: Videos as Links")
        #expect(titles["media.images.full"] == "Media: Full-Size Images")
        #expect(titles["media.images.thumbnail"] == "Media: Image Thumbnails")
    }

    /// The ids of the checked commands among those starting with `prefix`.
    private func checked(_ prefix: String, in settings: SettingsStore) -> [String] {
        VelaCommandCatalog.mediaCommands(settings)
            .filter { $0.id.hasPrefix(prefix) && $0.isChecked == true }
            .map(\.id)
    }

    private func perform(_ id: String, in settings: SettingsStore) throws {
        try #require(VelaCommandCatalog.mediaCommands(settings).first { $0.id == id }).perform()
    }

    @Test func sizeCommandsCheckTheDefaults() {
        let settings = makeSettings()
        #expect(checked("media.links.", in: settings) == ["media.links.standard"])
        #expect(checked("media.videos.", in: settings) == ["media.videos.player"])
        #expect(checked("media.images.", in: settings) == ["media.images.full"])
    }

    @Test func sizeCommandsSetTheirSettingAndMoveTheCheckmark() throws {
        let settings = makeSettings()

        try perform("media.links.minimal", in: settings)
        #expect(settings[.mediaLinkPreviewSize] == .minimal)
        #expect(checked("media.links.", in: settings) == ["media.links.minimal"])
        try perform("media.links.large", in: settings)
        #expect(settings[.mediaLinkPreviewSize] == .large)
        #expect(checked("media.links.", in: settings) == ["media.links.large"])

        try perform("media.videos.compact", in: settings)
        #expect(settings[.mediaVideos] == .compact)
        #expect(checked("media.videos.", in: settings) == ["media.videos.compact"])
        try perform("media.videos.off", in: settings)
        #expect(settings[.mediaVideos] == .off)
        #expect(checked("media.videos.", in: settings) == ["media.videos.off"])

        try perform("media.images.thumbnail", in: settings)
        #expect(settings[.mediaImageSize] == .thumbnail)
        #expect(checked("media.images.", in: settings) == ["media.images.thumbnail"])

        // Each group is independent of the others.
        #expect(settings[.mediaLinkPreviewSize] == .large)
        #expect(settings[.mediaVideos] == .off)
    }

    @Test func paletteFindsSizeCommandsByName() throws {
        let items = PaletteSource.commandItems(VelaCommandCatalog.mediaCommands(makeSettings()), history: [])
        func first(_ query: String) throws -> String {
            try #require(PaletteRanker.rows(for: items, query: query, list: .commands).first).id
        }
        #expect(try first("thumbnail") == "media.images.thumbnail")
        #expect(try first("compact videos") == "media.videos.compact")
        #expect(try first("large link") == "media.links.large")
        #expect(try first("minimal") == "media.links.minimal")
        let youtube = PaletteRanker.rows(for: items, query: "youtube", list: .commands).map(\.id)
        #expect(Set(youtube) == ["media.videos.player", "media.videos.compact", "media.videos.off"])
    }
}

@Suite("Layout schematic")
struct LayoutSchematicConfigTests {
    private func makeSettings() -> SettingsStore {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "VelaUITests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "settings.json")
        return SettingsStore(fileURL: url, watchForChanges: false)
    }

    @Test func readsMediaSizesFromSettings() {
        let settings = makeSettings()
        var config = LayoutSchematicConfig(settings: settings)
        #expect(config.linkPreviewSize == .standard)
        #expect(config.videoStyle == .player)
        #expect(config.imageSize == .full)
        #expect(config.showLinkCards)

        settings[.mediaLinkPreviewSize] = .large
        settings[.mediaShowLinkCards] = false
        config = LayoutSchematicConfig(settings: settings)
        #expect(config.linkPreviewSize == .large)
        #expect(!config.showLinkCards)
    }

    @Test func presetValuesOverrideSettings() {
        let settings = makeSettings()
        settings[.mediaLinkPreviewSize] = .large
        let config = LayoutSchematicConfig(settings: settings, overrides: [
            "media.linkPreviewSize": "minimal",
            "media.videos": "compact",
            "media.imageSize": "thumbnail",
        ])
        #expect(config.linkPreviewSize == .minimal)
        #expect(config.videoStyle == .compact)
        #expect(config.imageSize == .thumbnail)
    }
}
