// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaFoundation
@testable import VelaTheme

@Suite("Schema and docs generation")
struct ThemeSchemaTests {
    @Test func schemaCoversEveryToken() throws {
        let schema = ThemeSchema.themeFileSchema()
        #expect(schema["$schema"]?.stringValue == "http://json-schema.org/draft-07/schema#")
        #expect(schema["required"] == .array(["name", "type"]))
        let properties = try #require(schema["properties"])
        for field in ["$schema", "name", "type", "include", "author", "description", "colors", "nickColors", "ircColors", "vibrancy"] {
            #expect(properties[field] != nil, "missing \(field)")
        }
        #expect(properties["type"]?["enum"] == .array(["dark", "light"]))
        #expect(properties["vibrancy"]?["enum"] == .array(["none", "sidebar", "window"]))

        let tokens = try #require(properties["colors"]?["properties"]?.objectValue)
        #expect(Set(tokens.keys) == Set(ThemeRegistry.tokens.map(\.key)))
        for token in ThemeRegistry.tokens {
            let entry = try #require(tokens[token.key])
            #expect(entry["pattern"]?.stringValue == ThemeSchema.hexPattern)
            #expect(entry["description"]?.stringValue?.hasPrefix(token.description) == true)
        }
        #expect(properties["ircColors"]?["patternProperties"]?[ThemeSchema.ircIndexPattern] != nil)
    }

    @Test func hexPatternMatchesTheParser() throws {
        let regex = try Regex(ThemeSchema.hexPattern)
        for sample in ["#FFF", "#FFFA", "#FFFFFF", "#FFFFFFAA", "#abc", "#12", "#12345", "FFFFFF", "#GGG"] {
            let schemaAccepts = sample.wholeMatch(of: regex) != nil
            let parserAccepts = ThemeColor(hex: sample) != nil && sample.hasPrefix("#")
            #expect(schemaAccepts == parserAccepts, "\(sample)")
        }
        let irc = try Regex(ThemeSchema.ircIndexPattern)
        #expect((0...98).allSatisfy { String($0).wholeMatch(of: irc) != nil })
        #expect("99".wholeMatch(of: irc) == nil)
        #expect("007".wholeMatch(of: irc) == nil)
    }

    @Test func customizationsSchemaAllowsScopes() throws {
        let schema = ThemeSchema.colorCustomizationsSchema()
        #expect(schema["properties"]?["chat.background"] != nil)
        #expect(schema["properties"]?["nickColors"] != nil)
        #expect(schema["patternProperties"]?["^\\[.+\\]$"]?["properties"]?["accent"] != nil)
    }

    @Test func markdownTableListsEveryToken() {
        let table = ThemeSchema.markdownTokenTable()
        for token in ThemeRegistry.tokens {
            #expect(table.contains("| `\(token.key)` |"), "\(token.key)")
        }
        for group in ThemeRegistry.groups {
            #expect(table.contains("### \(group.title)"))
        }
    }

    /// The committed schema must match the generator: run
    /// `swift run vela-theme-tool schema > ../../schemas/vela-theme.schema.json`.
    @Test func committedSchemaIsUpToDate() throws {
        let url = Repository.root.appendingPathComponent("schemas/vela-theme.schema.json")
        let committed = try String(contentsOf: url, encoding: .utf8)
        #expect(committed == ThemeSchema.themeFileSchemaJSON())
    }

    /// docs/THEMES.md must embed the current token table between its markers.
    @Test func themesDocEmbedsCurrentTokenTable() throws {
        let url = Repository.root.appendingPathComponent("docs/THEMES.md")
        let doc = try String(contentsOf: url, encoding: .utf8)
        #expect(doc.contains(ThemeSchema.markdownTokenTable()))
    }

    /// Every built-in theme file validates against the generated schema's
    /// structural rules (known top-level fields, known tokens, hex values).
    @Test func builtInsConformToSchema() throws {
        let schema = ThemeSchema.themeFileSchema()
        let topLevel = Set(try #require(schema["properties"]?.objectValue).keys)
        let regex = try Regex(ThemeSchema.hexPattern)
        for url in ThemeLoader.themeFiles(in: ThemeLoader.builtInThemesDirectory) {
            let value = try JSONC.value(from: Data(contentsOf: url))
            let object = try #require(value.objectValue)
            #expect(Set(object.keys).isSubset(of: topLevel), "\(url.lastPathComponent)")
            for (key, color) in object["colors"]?.objectValue ?? [:] {
                #expect(ThemeRegistry.token(key) != nil, "\(url.lastPathComponent): \(key)")
                #expect(color.stringValue?.wholeMatch(of: regex) != nil, "\(url.lastPathComponent): \(key)")
            }
        }
    }
}
