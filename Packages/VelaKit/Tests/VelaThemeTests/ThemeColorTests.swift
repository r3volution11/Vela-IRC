// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaTheme

@Suite("ThemeColor")
struct ThemeColorTests {
    @Test("Parses every hex form", arguments: [
        ("#FFF", "#FFFFFF"),
        ("#f80", "#FF8800"),
        ("#F808", "#FF880088"),
        ("#1B2430", "#1B2430"),
        ("#1b243080", "#1B243080"),
        ("1B2430", "#1B2430"),
        ("  #abcdef  ", "#ABCDEF"),
        ("#000000FF", "#000000"),
    ])
    func parses(input: String, expected: String) throws {
        let color = try #require(ThemeColor(hex: input))
        #expect(color.hex == expected)
    }

    @Test("Rejects malformed hex", arguments: ["", "#", "#12", "#12345", "#1234567", "#GGGGGG", "red", "#123456789"])
    func rejects(input: String) {
        #expect(ThemeColor(hex: input) == nil)
    }

    @Test func components() throws {
        let color = try #require(ThemeColor(hex: "#FF000080"))
        #expect(color.red == 1)
        #expect(color.green == 0)
        #expect(abs(color.alpha - 128.0 / 255) < 0.0001)
    }

    @Test func luminanceAndContrast() {
        #expect(ThemeColor.black.luminance == 0)
        #expect(abs(ThemeColor.white.luminance - 1) < 0.0001)
        #expect(abs(ThemeColor.white.contrastRatio(against: .black) - 21) < 0.01)
        #expect(abs(hex("#777777").contrastRatio(against: .white) - 4.48) < 0.01)
        #expect(ThemeColor.black.isDark)
        #expect(!ThemeColor.white.isDark)
    }

    @Test func mixingAndAlpha() {
        let grey = ThemeColor.black.mixed(with: .white, amount: 0.5)
        #expect(grey.hex == "#808080")
        #expect(ThemeColor.black.mixed(with: .white, amount: 0) == .black)
        #expect(ThemeColor.black.mixed(with: .white, amount: 2) == .white)
        #expect(ThemeColor.white.withAlpha(0.5).hex == "#FFFFFF80")
        #expect(ThemeColor.white.withAlpha(0.5).composited(over: .black).hex == "#808080")
    }

    @Test func translucentContrastIsComposited() {
        // Fully transparent text has no contrast at all.
        #expect(abs(ThemeColor.white.withAlpha(0).contrastRatio(against: .black) - 1) < 0.0001)
    }

    @Test func codableAsHexString() throws {
        let data = try JSONEncoder().encode(["accent": hex("#C792EA")])
        #expect(String(decoding: data, as: UTF8.self) == ##"{"accent":"#C792EA"}"##)
        let decoded = try JSONDecoder().decode([String: ThemeColor].self, from: Data(##"{"a":"#0f08"}"##.utf8))
        #expect(decoded["a"]?.hex == "#00FF0088")
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([String: ThemeColor].self, from: Data(##"{"a":"blue"}"##.utf8))
        }
    }

    @Test func ensuringContrast() {
        let background = hex("#1A1B26")
        let dim = hex("#3D59A1")
        #expect(dim.contrastRatio(against: background) < 4.5)
        #expect(dim.ensuringContrast(4.5, against: background).contrastRatio(against: background) >= 4.5)
        let bright = hex("#7AA2F7")
        #expect(bright.ensuringContrast(4.5, against: background) == bright)
    }
}

@Suite("ThemeDefinition")
struct ThemeDefinitionTests {
    @Test func decodesJSONCWithSchema() throws {
        let text = """
            {
              // comment
              "$schema": "https://example.com/schema.json",
              "name": "Sample", "type": "dark",
              "colors": { "accent": "#FF0000", },
              "ircColors": { "4": "#FF5555" },
            }
            """
        let definition = try ThemeLoader.decode(Data(text.utf8))
        #expect(definition.schema == "https://example.com/schema.json")
        #expect(definition.name == "Sample")
        #expect(definition.type == .dark)
        #expect(definition.colors == ["accent": "#FF0000"])
        #expect(definition.ircColors == ["4": "#FF5555"])
        #expect(definition.nickColors == nil)
    }

    @Test func acceptsVSCodeKinds() throws {
        let light = try ThemeLoader.decode(Data(##"{"name": "A", "type": "vs"}"##.utf8))
        #expect(light.type == .light)
        let dark = try ThemeLoader.decode(Data(##"{"name": "A", "type": "hc-black"}"##.utf8))
        #expect(dark.type == .dark)
    }

    @Test func readableErrors() {
        #expect(throws: ThemeError.missingField("type")) {
            try ThemeLoader.decode(Data(##"{"name": "A"}"##.utf8))
        }
        #expect(throws: ThemeError.invalidColor(key: "colors.accent", value: "orange")) {
            try ThemeLoader.decode(Data(##"{"name": "A", "type": "dark", "colors": {"accent": "orange"}}"##.utf8))
        }
        #expect(throws: ThemeError.invalidValue(path: "ircColors.99", message: "IRC color indexes run from 0 to 98.")) {
            try ThemeLoader.decode(Data(##"{"name": "A", "type": "dark", "ircColors": {"99": "#FFF"}}"##.utf8))
        }
        do {
            _ = try ThemeLoader.decode(Data(##"{"name": "A" "type": "dark"}"##.utf8))
            Issue.record("Expected a JSON error")
        } catch let error as ThemeError {
            guard case .invalidJSON = error else {
                Issue.record("Expected invalidJSON, got \(error)")
                return
            }
            #expect(error.localizedDescription.hasPrefix("The file isn't valid JSON"))
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    @Test func writesStableHandEditableJSON() throws {
        let definition = ThemeDefinition(
            name: "Round \"Trip\"",
            type: .light,
            include: "Lighter",
            author: "Tester",
            colors: ["zzz.custom": "#010203", "chat.background": "#FFFFFF", "window.background": "#FAFAFA"],
            nickColors: ["#112233"],
            ircColors: ["10": "#00AAAA", "2": "#0000AA"],
            vibrancy: .sidebar
        )
        let text = String(decoding: definition.jsonData(), as: UTF8.self)
        let decoded = try ThemeLoader.decode(Data(text.utf8))
        #expect(decoded == definition)

        // Metadata first, colors in registry order, unknown keys last, IRC indexes numeric.
        func position(_ needle: String) -> Int {
            text.range(of: needle).map { text.distance(from: text.startIndex, to: $0.lowerBound) } ?? -1
        }
        #expect(position("\"$schema\"") < position("\"name\""))
        #expect(position("\"name\"") < position("\"colors\""))
        #expect(position("\"window.background\"") < position("\"chat.background\""))
        #expect(position("\"chat.background\"") < position("\"zzz.custom\""))
        #expect(position("\"2\":") < position("\"10\":"))
        #expect(text.hasSuffix("}\n"))
    }
}
