// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaFoundation
@testable import VelaStore

@Suite struct SettingsMigrationTests {
    private func strings(_ values: String...) -> JSONValue {
        .array(values.map(JSONValue.string))
    }

    @Test func domainListsMergeIntoSiteRules() {
        let values: [String: JSONValue] = [
            "chat.fontSize": 14,
            "media.blockedDomains": strings("tracker.io", "*.Ads.example"),
            "media.allowedDomains": strings("imgur.com", " https://I.Redd.it/path "),
        ]
        let migrated = SettingsMigration.migrated(values)
        #expect(migrated == [
            "chat.fontSize": 14,
            "media.siteRules": .object([
                "tracker.io": "block",
                "ads.example": "block",
                "imgur.com": "allow",
                "i.redd.it": "allow",
            ]),
        ])
    }

    @Test func blockWinsWhenADomainIsInBothLists() {
        let values: [String: JSONValue] = [
            "media.blockedDomains": strings("example.com"),
            "media.allowedDomains": strings("Example.com", "other.example"),
        ]
        let rules = SettingsMigration.migrated(values)["media.siteRules"]
        #expect(rules == .object(["example.com": "block", "other.example": "allow"]))
    }

    @Test func existingSiteRulesAreNotOverwritten() {
        let values: [String: JSONValue] = [
            "media.siteRules": .object(["Example.com": "textOnly", "keep.example": "allow"]),
            "media.blockedDomains": strings("example.com", "new.example"),
            "media.allowedDomains": strings("keep.example"),
        ]
        let rules = SettingsMigration.migrated(values)["media.siteRules"]
        #expect(rules == .object([
            "Example.com": "textOnly",
            "keep.example": "allow",
            "new.example": "block",
        ]))
    }

    @Test func legacyKeysAreRemovedEvenWhenEmptyOrMalformed() {
        let empty = SettingsMigration.changes(for: [
            "media.blockedDomains": .array([]),
            "media.allowedDomains": "not a list",
        ])
        #expect(empty == [.remove(key: "media.allowedDomains"), .remove(key: "media.blockedDomains")])

        // Non-string and empty entries are skipped.
        let mixed = SettingsMigration.migrated(["media.blockedDomains": .array([42, "", "  ", "ok.example"])])
        #expect(mixed == ["media.siteRules": .object(["ok.example": "block"])])
    }

    @Test func malformedSiteRulesIsReplacedOnlyWhenListsAddRules() {
        let nothingToAdd: [String: JSONValue] = ["media.siteRules": "oops", "media.blockedDomains": .array([])]
        #expect(SettingsMigration.migrated(nothingToAdd) == ["media.siteRules": "oops"])

        let somethingToAdd: [String: JSONValue] = ["media.siteRules": "oops", "media.blockedDomains": strings("a.example")]
        #expect(SettingsMigration.migrated(somethingToAdd) == ["media.siteRules": .object(["a.example": "block"])])
    }

    @Test func changesAreSortedByKey() {
        let changes = SettingsMigration.changes(for: [
            "media.allowedDomains": strings("imgur.com"),
            "media.blockedDomains": strings("tracker.io"),
        ])
        #expect(changes == [
            .remove(key: "media.allowedDomains"),
            .remove(key: "media.blockedDomains"),
            .set(key: "media.siteRules", value: .object(["imgur.com": "allow", "tracker.io": "block"])),
        ])
        #expect(changes.map(\.key) == ["media.allowedDomains", "media.blockedDomains", "media.siteRules"])
        #expect(changes[0].value == nil)
    }

    @Test func runningTwiceChangesNothing() {
        let values: [String: JSONValue] = [
            "media.siteRules": .object(["a.example": "allow"]),
            "media.blockedDomains": strings("b.example"),
            "media.allowedDomains": strings("c.example"),
        ]
        let once = SettingsMigration.migrated(values)
        #expect(once != values)
        #expect(SettingsMigration.migrated(once) == once)
        #expect(SettingsMigration.changes(for: once).isEmpty)
    }

    @Test func cleanSettingsNeedNoChanges() {
        #expect(SettingsMigration.changes(for: [:]).isEmpty)
        let current: [String: JSONValue] = [
            "chat.layout": "columns",
            "media.siteRules": .object(["example.com": "block"]),
            "future.setting": .object(["nested": .array([1, 2])]),
        ]
        #expect(SettingsMigration.changes(for: current).isEmpty)
        #expect(SettingsMigration.migrated(current) == current)
    }

    @Test func everyRuleIsIdempotent() {
        let samples: [[String: JSONValue]] = [
            [:],
            ["media.blockedDomains": strings("x.example"), "media.allowedDomains": strings("x.example", "y.example")],
            ["media.siteRules": .object(["x.example": "allow"]), "media.blockedDomains": strings("x.example")],
            ["media.presentation": "compact"],
            ["media.presentation": "full", "media.loadVideoEmbeds": false],
            ["media.presentation": "compact", "media.loadVideoEmbeds": false, "media.videos": "player"],
            ["media.loadVideoEmbeds": "junk", "media.imageSize": 3],
            Self.oldClassic,
            Self.oldFocus,
        ]
        for rule in SettingsMigration.rules {
            for sample in samples {
                var once = sample
                rule.apply(to: &once)
                var twice = once
                rule.apply(to: &twice)
                #expect(twice == once, "\(rule.id) isn't idempotent for \(sample)")
            }
        }
        #expect(Set(SettingsMigration.rules.map(\.id)).count == SettingsMigration.rules.count)
    }

    // MARK: Preview sizes

    /// The Classic preset before `media.presentation` was split, as
    /// `SettingsStore.apply` wrote it.
    static let oldClassic: [String: JSONValue] = [
        "navigation.style": "sidebar",
        "chat.layout": "classic",
        "chat.monospace": true,
        "chat.fontSize": 12,
        "chat.lineSpacing": 1,
        "chat.messageSpacing": 2,
        "chat.showAvatars": false,
        "chat.showJoinPart": "show",
        "chat.showTimestamps": true,
        "sidebar.rowHeight": 20,
        "sidebar.fontSize": 12,
        "memberList.visible": true,
        "media.presentation": "compact",
        "media.loadVideoEmbeds": false,
    ]

    /// The Focus preset before `media.presentation` was split.
    static let oldFocus: [String: JSONValue] = [
        "navigation.style": "tabs",
        "tabs.placement": "titleBar",
        "tabs.roundness": 1,
        "tabs.serverRow": "auto",
        "chat.layout": "columns",
        "chat.monospace": false,
        "chat.fontSize": 13,
        "chat.lineSpacing": 2,
        "chat.messageSpacing": 3,
        "chat.showAvatars": false,
        "chat.showJoinPart": "hide",
        "memberList.visible": false,
        "media.presentation": "compact",
        "media.loadVideoEmbeds": true,
    ]

    private func previewSizes(_ values: [String: JSONValue]) -> [String: JSONValue] {
        values.filter { ["media.linkPreviewSize", "media.videos", "media.imageSize"].contains($0.key) }
    }

    @Test func compactBecomesMinimalCompactAndThumbnail() {
        let migrated = SettingsMigration.migrated(["chat.fontSize": 14, "media.presentation": "compact"])
        #expect(migrated == [
            "chat.fontSize": 14,
            "media.linkPreviewSize": "minimal",
            "media.videos": "compact",
            "media.imageSize": "thumbnail",
        ])
    }

    @Test func fullLeavesTheNewDefaults() {
        #expect(SettingsMigration.migrated(["chat.fontSize": 14, "media.presentation": "full"]) == ["chat.fontSize": 14])
        #expect(SettingsMigration.migrated(["media.presentation": "full", "media.loadVideoEmbeds": true]) == [:])
    }

    @Test func videoEmbedsOffWinsOverCompact() {
        #expect(SettingsMigration.migrated(["media.loadVideoEmbeds": false]) == ["media.videos": "off"])
        #expect(SettingsMigration.migrated(["media.presentation": "full", "media.loadVideoEmbeds": false]) == ["media.videos": "off"])
        #expect(SettingsMigration.migrated(["media.presentation": "compact", "media.loadVideoEmbeds": false]) == [
            "media.linkPreviewSize": "minimal",
            "media.videos": "off",
            "media.imageSize": "thumbnail",
        ])
    }

    @Test func explicitPreviewSizesAreKept() {
        let migrated = SettingsMigration.migrated([
            "media.presentation": "compact",
            "media.loadVideoEmbeds": false,
            "media.linkPreviewSize": "large",
            "media.videos": "player",
        ])
        #expect(migrated == [
            "media.linkPreviewSize": "large",
            "media.videos": "player",
            "media.imageSize": "thumbnail",
        ])
        // Explicit values that equal the default are kept too.
        #expect(SettingsMigration.migrated(["media.presentation": "compact", "media.imageSize": "full"])["media.imageSize"] == "full")
        // An invalid value reads as the default, so the mapping replaces it.
        #expect(SettingsMigration.migrated(["media.loadVideoEmbeds": false, "media.videos": "bogus"]) == ["media.videos": "off"])
    }

    @Test func legacyMediaKeysAreRemovedEvenWhenMalformed() {
        #expect(SettingsMigration.changes(for: ["media.presentation": "full", "media.loadVideoEmbeds": true]) == [
            .remove(key: "media.loadVideoEmbeds"),
            .remove(key: "media.presentation"),
        ])
        #expect(SettingsMigration.migrated(["media.presentation": "huge", "media.loadVideoEmbeds": "no"]) == [:])
        #expect(SettingsMigration.migrated(["media.presentation": 1]) == [:])
    }

    @Test func oldClassicBecomesNewClassic() {
        let migrated = SettingsMigration.migrated(Self.oldClassic)
        // Compact videos, as the new Classic has, rather than the off that
        // media.loadVideoEmbeds: false would give.
        #expect(previewSizes(migrated) == ["media.linkPreviewSize": "minimal", "media.videos": "compact", "media.imageSize": "thumbnail"])
        #expect(migrated["media.presentation"] == nil)
        #expect(migrated["media.loadVideoEmbeds"] == nil)
        var expected = Self.oldClassic.filter { !$0.key.hasPrefix("media.") }
        expected.merge(previewSizes(SettingsPreset.classic.values)) { $1 }
        #expect(migrated == expected)

        // Keys left at their defaults still count as matching.
        var sparse = Self.oldClassic
        for key in ["navigation.style", "chat.showAvatars", "chat.showTimestamps", "sidebar.fontSize", "memberList.visible"] {
            sparse.removeValue(forKey: key)
        }
        sparse["chat.fontSize"] = 12.0
        #expect(SettingsMigration.migrated(sparse)["media.videos"] == "compact")

        // Explicit new keys still win.
        var explicit = Self.oldClassic
        explicit["media.videos"] = "player"
        #expect(SettingsMigration.migrated(explicit)["media.videos"] == "player")
    }

    @Test func customizedClassicGetsThePlainMapping() {
        var custom = Self.oldClassic
        custom["chat.fontSize"] = 14
        #expect(previewSizes(SettingsMigration.migrated(custom)) == [
            "media.linkPreviewSize": "minimal",
            "media.videos": "off",
            "media.imageSize": "thumbnail",
        ])
    }

    @Test func oldFocusBecomesNewFocus() {
        let migrated = SettingsMigration.migrated(Self.oldFocus)
        // Focus now has players, which is the default, so media.videos isn't written.
        #expect(previewSizes(migrated) == ["media.linkPreviewSize": "minimal", "media.imageSize": "thumbnail"])

        // media.loadVideoEmbeds: true is the old default and may be missing.
        var sparse = Self.oldFocus
        sparse.removeValue(forKey: "media.loadVideoEmbeds")
        #expect(SettingsMigration.migrated(sparse) == migrated)

        var custom = Self.oldFocus
        custom["memberList.visible"] = true
        #expect(SettingsMigration.migrated(custom)["media.videos"] == "compact")
    }

    @Test func domainNormalization() {
        #expect(SettingsMigration.normalizedDomain(" HTTPS://*.Example.COM:8443/a?b#c ") == "example.com")
        #expect(SettingsMigration.normalizedDomain(".example.com.") == "example.com")
        #expect(SettingsMigration.normalizedDomain("user@host.example") == "host.example")
        #expect(SettingsMigration.normalizedDomain("[::1]:80") == "::1")
        #expect(SettingsMigration.normalizedDomain("*.") == nil)
        #expect(SettingsMigration.normalizedDomain("") == nil)
    }
}

@MainActor
@Suite struct SettingsStoreMigrationTests {
    @Test func applyMigrationsRewritesTheFileOnce() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let url = directory.file("settings.json")
        try writeString("""
            // My settings
            {
              "chat.fontSize": 15,
              "media.blockedDomains": ["tracker.io", "both.example"],
              "media.allowedDomains": ["imgur.com", "both.example"],
            }
            """, to: url)

        let store = SettingsStore(fileURL: url, watchForChanges: false)
        let changes = store.applyMigrations()
        #expect(changes.map(\.key) == ["media.allowedDomains", "media.blockedDomains", "media.siteRules"])
        let expectedRules: JSONValue = .object(["tracker.io": "block", "both.example": "block", "imgur.com": "allow"])
        #expect(store.value(forKey: "media.siteRules") == expectedRules)
        #expect(store.value(forKey: "media.blockedDomains") == nil)
        #expect(store.value(forKey: "media.allowedDomains") == nil)

        // Saved right away, without waiting for the debounce.
        let saved = try JSONC.value(from: Data(contentsOf: url))
        #expect(saved == .object(["chat.fontSize": 15, "media.siteRules": expectedRules]))

        // A second launch finds nothing to do and leaves the file alone.
        let written = try readString(url)
        let reopened = SettingsStore(fileURL: url, watchForChanges: false)
        #expect(reopened.applyMigrations().isEmpty)
        reopened.flush()
        #expect(try readString(url) == written)
        #expect(reopened.value(forKey: "media.siteRules") == expectedRules)
    }

    @Test func cleanFileIsNotRewritten() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let url = directory.file("settings.json")
        let original = """
            // Comments survive because nothing is written.
            { "chat.fontSize": 15, "media.siteRules": { "example.com": "block" } }
            """
        try writeString(original, to: url)

        let store = SettingsStore(fileURL: url, watchForChanges: false)
        #expect(store.applyMigrations().isEmpty)
        store.flush()
        #expect(try readString(url) == original)
    }

    @Test func missingFileStaysMissing() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let url = directory.file("settings.json")
        let store = SettingsStore(fileURL: url, watchForChanges: false)
        #expect(store.applyMigrations().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test(arguments: ["classic", "modern", "tabbed", "focus"])
    func oldPresetsStillMatchAfterMigrating(_ id: String) throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let url = directory.file("settings.json")
        let preset = try #require(SettingsPreset.all.first { $0.id == id })
        // What applying the preset wrote before media.presentation was split.
        var old = preset.values.filter { !$0.key.hasPrefix("media.") }
        switch id {
        case "classic": old.merge(["media.presentation": "compact", "media.loadVideoEmbeds": false]) { $1 }
        case "focus": old.merge(["media.presentation": "compact", "media.loadVideoEmbeds": true]) { $1 }
        default: old.merge(["media.presentation": "full", "media.loadVideoEmbeds": true]) { $1 }
        }
        try JSONValue.object(old).prettyPrinted().write(to: url)

        let store = SettingsStore(fileURL: url, watchForChanges: false)
        // Old Modern and Tabbed used the defaults, so they match already.
        #expect((store.matchingPreset()?.id == id) == ["modern", "tabbed"].contains(id))
        let changes = store.applyMigrations()
        #expect(changes.contains(.remove(key: "media.presentation")))
        #expect(changes.contains(.remove(key: "media.loadVideoEmbeds")))
        #expect(store.matchingPreset()?.id == id)
        #expect(SettingsStore(fileURL: url, watchForChanges: false).matchingPreset()?.id == id)
    }

    @Test func pendingAppChangesAreSavedWithTheMigration() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let url = directory.file("settings.json")
        try writeString(#"{"media.blockedDomains": ["tracker.io"]}"#, to: url)

        let store = SettingsStore(fileURL: url, watchForChanges: false)
        store.saveDelay = .seconds(60)
        store[.chatFontSize] = 16
        store.applyMigrations()
        let saved = try JSONC.value(from: Data(contentsOf: url))
        #expect(saved == .object(["chat.fontSize": 16, "media.siteRules": .object(["tracker.io": "block"])]))
    }
}
