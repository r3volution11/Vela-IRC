// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaFoundation
@testable import VelaStore

/// settings.json keeps comments and formatting through app-side changes,
/// and the JSON view's text API.
@MainActor
@Suite struct SettingsFileEditingTests {
    static let commentRich = """
        // Vela settings — edited by hand and in the app.
        {
            // Look
            "appearance.theme": "Palenight", // my favorite
            "appearance.colorCustomizations": {
                "chat.background": "#1e1e2e", // a bit darker
                "[Lighter]": {
                    "accent": "#ff8800" // orange
                }
            },

            /* Chat */
            "chat.fontSize": 14,
            "chat.layout": "classic", // like irssi
            "highlight.words": ["vela"],
            "media.siteRules": {
                // never
                "tracker.example": "block",
                "imgur.com": "allow" // images ok
            },
            "future.setting": {"keep": true} // unknown, kept
        }

        """

    @Test func commentsSurviveChangesMadeInTheApp() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let url = directory.file("settings.json")
        try writeString(Self.commentRich, to: url)

        let store = SettingsStore(fileURL: url, watchForChanges: false)
        #expect(store.lastError == nil)
        store[.appearanceTheme] = "Tokyo Night"
        store[.chatFontSize] = 15
        store.reset(.chatLayout)
        store[.highlightWords] = ["vela", "release"]
        var colors = store[.appearanceColorCustomizations]
        colors["chat.background"] = "#000000"
        colors["[Lighter]"] = .object(["accent": "#ff8800", "chat.foreground": "#222222"])
        store[.appearanceColorCustomizations] = colors
        var rules = store[.mediaSiteRules]
        rules["imgur.com"] = nil
        rules["example.com"] = "textOnly"
        store[.mediaSiteRules] = rules
        store[.sidebarWidth] = 240
        store.flush()

        #expect(store.lastError == nil)
        #expect(!store.lastWriteRewroteFile)
        #expect(try readString(url) == """
            // Vela settings — edited by hand and in the app.
            {
                // Look
                "appearance.theme": "Tokyo Night", // my favorite
                "appearance.colorCustomizations": {
                    "chat.background": "#000000", // a bit darker
                    "[Lighter]": {
                        "accent": "#ff8800", // orange
                        "chat.foreground": "#222222"
                    }
                },

                /* Chat */
                "chat.fontSize": 15,
                "highlight.words": [
                    "vela",
                    "release"
                ],
                "media.siteRules": {
                    // never
                    "tracker.example": "block",
                    "example.com": "textOnly"
                },
                "future.setting": {"keep": true}, // unknown, kept
                "sidebar.width": 240
            }

            """)

        let reopened = SettingsStore(fileURL: url, watchForChanges: false)
        #expect(reopened.values == store.values)
        #expect(reopened[.mediaSiteRules] == ["tracker.example": "block", "example.com": "textOnly"])
    }

    @Test func missingFileGetsAFreshPrettyPrintedFile() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let url = directory.file("settings.json")
        let store = SettingsStore(fileURL: url, watchForChanges: false)
        store[.chatLayout] = .classic
        store[.chatFontSize] = 15
        store[.appearanceColorCustomizations] = ["chat.background": "#000000"]
        store.flush()
        #expect(try readString(url) == """
            {
                "appearance.colorCustomizations": {
                    "chat.background": "#000000"
                },
                "chat.fontSize": 15,
                "chat.layout": "classic"
            }

            """)
    }

    @Test func blankAndCommentOnlyFiles() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let url = directory.file("settings.json")

        try writeString("\n\n", to: url)
        let blank = SettingsStore(fileURL: url, watchForChanges: false)
        blank[.chatFontSize] = 15
        blank.flush()
        #expect(try readString(url) == "{\n    \"chat.fontSize\": 15\n}\n")

        try writeString("// My settings\n", to: url)
        let commented = SettingsStore(fileURL: url, watchForChanges: false)
        commented[.chatFontSize] = 15
        commented[.chatLayout] = .columns
        commented.flush()
        #expect(try readString(url) == "// My settings\n{\n    \"chat.fontSize\": 15,\n    \"chat.layout\": \"columns\"\n}\n")
        #expect(!commented.lastWriteRewroteFile)
    }

    @Test func filesWrittenByOlderVersionsKeepTheirStyle() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let url = directory.file("settings.json")
        try writeString("{\n  \"chat.fontSize\" : 14,\n  \"chat.layout\" : \"classic\"\n}\n", to: url)
        let store = SettingsStore(fileURL: url, watchForChanges: false)
        store[.sidebarWidth] = 240
        store[.chatFontSize] = 12
        store.flush()
        #expect(try readString(url) == "{\n  \"chat.fontSize\" : 12,\n  \"chat.layout\" : \"classic\",\n  \"sidebar.width\" : 240\n}\n")
    }

    @Test func tabsCRLFAndTrailingCommas() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let url = directory.file("settings.json")
        try writeString("{\r\n\t\"chat.fontSize\": 14, // size\r\n\t\"chat.layout\": \"classic\",\r\n}\r\n", to: url)
        let store = SettingsStore(fileURL: url, watchForChanges: false)
        store[.mediaSiteRules] = ["example.com": "block"]
        store.reset(.chatFontSize)
        store.flush()
        #expect(try readString(url) == "{\r\n\t\"chat.layout\": \"classic\",\r\n\t\"media.siteRules\": {\r\n\t\t\"example.com\": \"block\",\r\n\t},\r\n}\r\n")
    }

    @Test func duplicateKeysTheLastOneWinsAndIsEdited() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let url = directory.file("settings.json")
        try writeString("{\n  \"chat.fontSize\": 12,\n  \"chat.fontSize\": 16\n}\n", to: url)
        let store = SettingsStore(fileURL: url, watchForChanges: false)
        #expect(store[.chatFontSize] == 16)
        store[.chatFontSize] = 18
        store.flush()
        #expect(try readString(url) == "{\n  \"chat.fontSize\": 12,\n  \"chat.fontSize\": 18\n}\n")
        store.reset(.chatFontSize)
        store.flush()
        #expect(try readString(url) == "{\n}\n")
        #expect(!store.lastWriteRewroteFile)
    }

    @Test func migrationsKeepComments() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let url = directory.file("settings.json")
        try writeString("""
            // My settings
            {
              "chat.fontSize": 15, // big
              "media.blockedDomains": ["tracker.io"],
            }

            """, to: url)
        let store = SettingsStore(fileURL: url, watchForChanges: false)
        #expect(!store.applyMigrations().isEmpty)
        #expect(try readString(url) == """
            // My settings
            {
              "chat.fontSize": 15, // big
              "media.siteRules": {
                "tracker.io": "block",
              },
            }

            """)
    }

    @Test func externalEditsAreMergedWithoutLosingTheirComments() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let url = directory.file("settings.json")
        try writeString("{\n  \"chat.fontSize\": 14\n}\n", to: url)
        let store = SettingsStore(fileURL: url, watchForChanges: false)
        store[.sidebarWidth] = 240  // pending
        try writeString("{\n  // added in VS Code\n  \"chat.fontSize\": 16 // bigger\n}\n", to: url)
        store.flush()  // folds in the external edit first
        #expect(store[.chatFontSize] == 16)
        #expect(try readString(url) == "{\n  // added in VS Code\n  \"chat.fontSize\": 16, // bigger\n  \"sidebar.width\": 240\n}\n")
    }

    @Test func invalidFilesExplainWhere() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let url = directory.file("settings.json")
        try writeString("{\n  \"chat.fontSize\": 14\n  \"chat.layout\": \"classic\"\n}", to: url)
        let store = SettingsStore(fileURL: url, watchForChanges: false)
        #expect(store.lastError == "settings.json is invalid; keeping previous values. Line 3, column 3: Expected a comma.")
        #expect(store.values.isEmpty)
    }

    // MARK: The JSON view's API

    @Test func fileText() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let url = directory.file("settings.json")
        let store = SettingsStore(fileURL: url, watchForChanges: false)
        #expect(store.fileText() == "{\n}\n")

        try writeString("  \n", to: url)
        #expect(store.fileText() == "{\n}\n")

        try writeString("// hi\n{ \"chat.fontSize\": 14 }\n", to: url)
        #expect(store.fileText() == "// hi\n{ \"chat.fontSize\": 14 }\n")
        #expect(store[.chatFontSize] == 14)  // read from disk on the way

        // Pending app-side changes are written first.
        store[.chatLayout] = .columns
        #expect(store.fileText() == "// hi\n{ \"chat.fontSize\": 14, \"chat.layout\": \"columns\" }\n")
    }

    @Test func saveFileTextWritesExactlyAndReloads() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let url = directory.file("settings.json")
        let store = SettingsStore(fileURL: url, watchForChanges: false)
        let revision = store.fileRevision

        let text = "// typed in the JSON view\n{\n\t\"chat.fontSize\": 17, /* big */\n}"
        try store.saveFileText(text)
        #expect(try readString(url) == text)
        #expect(store[.chatFontSize] == 17)
        #expect(store.lastError == nil)
        #expect(store.fileRevision == revision + 1)
        #expect(store.fileText() == text)

        // Saving the same text again changes nothing.
        try store.saveFileText(text)
        #expect(store.fileRevision == revision + 1)
    }

    @Test func savingInvalidTextKeepsValuesAndHoldsAppWrites() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let url = directory.file("settings.json")
        try writeString("{\n  \"chat.fontSize\": 14\n}\n", to: url)
        let store = SettingsStore(fileURL: url, watchForChanges: false)

        let broken = "{\n  \"chat.fontSize\": 20,\n  \"chat.layout\": \n"
        try store.saveFileText(broken)
        #expect(try readString(url) == broken)
        #expect(store.lastError != nil)
        #expect(store[.chatFontSize] == 14)

        // App-side changes wait for the file to be fixed.
        store[.sidebarWidth] = 240
        store.flush()
        #expect(try readString(url) == broken)

        try store.saveFileText("{\n  \"chat.fontSize\": 20\n}\n")
        #expect(store.lastError == nil)
        #expect(store[.chatFontSize] == 20)
        #expect(store[.sidebarWidth] == 240)
        store.flush()
        #expect(try readString(url) == "{\n  \"chat.fontSize\": 20,\n  \"sidebar.width\": 240\n}\n")
    }

    @Test func fileRevisionCountsContentChanges() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let url = directory.file("settings.json")
        try writeString("{}\n", to: url)
        let store = SettingsStore(fileURL: url, watchForChanges: false)
        #expect(store.fileRevision == 0)

        store.flush()  // nothing pending
        store.reload()  // nothing changed
        #expect(store.fileRevision == 0)

        store[.chatFontSize] = 15
        #expect(store.fileRevision == 0)  // not written yet
        store.flush()
        #expect(store.fileRevision == 1)

        try writeString("{\"chat.fontSize\": 16}\n", to: url)
        store.reload()
        #expect(store.fileRevision == 2)
        #expect(store[.chatFontSize] == 16)

        try FileManager.default.removeItem(at: url)
        store.reload()
        #expect(store.fileRevision == 3)
        #expect(store.fileText() == "{\n}\n")
    }

    /// Random batches of changes, like the settings editor makes them:
    /// minimal edits must always produce exactly the store's values.
    @Test func randomChangesNeverNeedARewrite() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let url = directory.file("settings.json")
        try writeString(Self.commentRich, to: url)
        let store = SettingsStore(fileURL: url, watchForChanges: false)

        var seed: UInt64 = 2026
        func next(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(bound))
        }
        let keys = ["appearance.theme", "chat.fontSize", "chat.layout", "highlight.words", "sidebar.width", "future.setting", "new.thing"]
        let tokens = ["chat.background", "accent", "[Lighter]", "[Palenight]", "nickColors"]
        let colors: [JSONValue] = ["#000000", "#ffffff", .array(["#111111", "#222222"]), .object(["accent": "#ff8800"])]
        for _ in 0..<60 {
            for _ in 0..<(1 + next(4)) {
                switch next(4) {
                case 0:
                    var object = store[.appearanceColorCustomizations]
                    let token = tokens[next(tokens.count)]
                    object[token] = next(3) == 0 ? nil : colors[next(colors.count)]
                    store[.appearanceColorCustomizations] = object
                case 1:
                    var rules = store[.mediaSiteRules]
                    let domain = ["a.com", "imgur.com", "tracker.example", "b.org"][next(4)]
                    rules[domain] = next(3) == 0 ? nil : .string(["allow", "textOnly", "block"][next(3)])
                    store[.mediaSiteRules] = rules
                default:
                    let key = keys[next(keys.count)]
                    let values: [JSONValue?] = [nil, 12, "x", true, .array(["a"]), .object(["k": .object([:])])]
                    store.setValue(values[next(values.count)], forKey: key)
                }
            }
            store.flush()
            #expect(store.lastError == nil)
            let written = try readString(url)
            #expect(!store.lastWriteRewroteFile, "\(written)")
            #expect(written.hasPrefix("// Vela settings — edited by hand and in the app.\n{\n    // Look\n"))
            #expect(SettingsStore(fileURL: url, watchForChanges: false).values == store.values)
        }
    }

    @Test func fileRevisionFollowsTheWatcher() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let url = directory.file("settings.json")
        try writeString("{}\n", to: url)
        let store = SettingsStore(fileURL: url)
        try await Task.sleep(for: .milliseconds(300))
        try writeString("{\"chat.fontSize\": 19}\n", to: url)
        let changed = await waitUntil(timeout: .seconds(15)) { store.fileRevision > 0 }
        #expect(changed)
        #expect(store[.chatFontSize] == 19)
    }
}
