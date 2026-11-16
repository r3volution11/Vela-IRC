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
