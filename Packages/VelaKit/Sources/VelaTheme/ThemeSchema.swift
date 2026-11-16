// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaFoundation

/// Generates the JSON Schema for theme files and the token reference table,
/// both straight from `ThemeRegistry` so they can't drift.
public enum ThemeSchema {
    public static let hexPattern = "^#([0-9A-Fa-f]{3}|[0-9A-Fa-f]{4}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$"
    public static let ircIndexPattern = "^([0-9]|[1-8][0-9]|9[0-8])$"

    /// JSON Schema (draft-07) for Vela theme files.
    public static func themeFileSchema() -> JSONValue {
        .object([
            "$schema": "http://json-schema.org/draft-07/schema#",
            "$id": .string(ThemeDefinition.schemaURL),
            "title": "Vela theme",
            "description": "A color theme for the Vela IRC client. See docs/THEMES.md.",
            "type": "object",
            "required": .array(["name", "type"]),
            "additionalProperties": false,
            "properties": .object([
                "$schema": .object(["type": "string", "description": "Schema URL, for editor autocompletion."]),
                "name": .object([
                    "type": "string",
                    "minLength": 1,
                    "description": "Display name. Settings refer to themes by this name (case-insensitive) or by file name.",
                ]),
                "type": .object([
                    "enum": .array(["dark", "light"]),
                    "description": "Whether the theme is dark or light. Picks token defaults and the appearance of system menus and alerts.",
                ]),
                "include": .object([
                    "type": "string",
                    "description": "Name or id of a theme to start from. This theme's values are layered on top of it.",
                ]),
                "author": .object(["type": "string", "description": "Who made the theme."]),
                "description": .object(["type": "string", "description": "A short description shown in the theme picker."]),
                "vibrancy": vibrancySchema(),
                "colors": colorsSchema(),
                "nickColors": nickColorsSchema(),
                "ircColors": ircColorsSchema(),
            ]),
        ])
    }

    /// Schema for a settings `colorCustomizations` object: token overrides
    /// at the top level and `"[Theme Name]"` scoped objects.
    public static func colorCustomizationsSchema() -> JSONValue {
        let overrides = customizationEntries()
        var scoped = overrides
        scoped["additionalProperties"] = false
        var schema = overrides
        schema["description"] = .string(
            "Color overrides applied on top of the active theme, like VS Code's workbench.colorCustomizations. "
                + "Wrap overrides in \"[Theme Name]\" to apply them to one theme only (several: \"[A][B]\", wildcards: \"[Catppuccin *]\")."
        )
        schema["patternProperties"] = .object(["^\\[.+\\]$": .object(scoped)])
        schema["additionalProperties"] = false
        return .object(schema)
    }

    private static func customizationEntries() -> [String: JSONValue] {
        var properties = tokenProperties()
        properties["nickColors"] = nickColorsSchema()
        properties["ircColors"] = ircColorsSchema()
        properties["vibrancy"] = vibrancySchema()
        return ["type": "object", "properties": .object(properties)]
    }

    private static func colorSchema(description: String? = nil) -> JSONValue {
        var schema: [String: JSONValue] = [
            "type": "string",
            "pattern": .string(hexPattern),
            "format": "color-hex",
            "patternErrorMessage": "Use a hex color: #RGB, #RGBA, #RRGGBB or #RRGGBBAA.",
        ]
        if let description { schema["description"] = .string(description) }
        return .object(schema)
    }

    private static func tokenProperties() -> [String: JSONValue] {
        var properties: [String: JSONValue] = [:]
        for token in ThemeRegistry.tokens {
            let defaults = token.dark == token.light
                ? "Default: \(token.dark.expression)"
                : "Default: \(token.dark.expression) (dark), \(token.light.expression) (light)"
            properties[token.key] = colorSchema(description: "\(token.description)\n\n\(defaults)")
        }
        return properties
    }

    private static func colorsSchema() -> JSONValue {
        .object([
            "type": "object",
            "description": "Token colors. Anything left out is derived from the other tokens.",
            "properties": .object(tokenProperties()),
            "additionalProperties": false,
        ])
    }

    private static func nickColorsSchema() -> JSONValue {
        .object([
            "type": "array",
            "description": "Palette for nickname colors. Each nick starts from a stable entry; people talking in the same conversation get different entries while the palette has room. Entries too close to chat.foreground, or under 3:1 against chat.background, aren't used. Replaces the default palette.",
            "items": colorSchema(),
            "minItems": 1,
        ])
    }

    private static func ircColorsSchema() -> JSONValue {
        var named: [String: JSONValue] = [:]
        for index in 0..<IRCPalette.names.count {
            named[String(index)] = colorSchema(
                description: "mIRC color \(index): \(IRCPalette.names[index]). Default \(IRCPalette.standardHex[index])."
            )
        }
        return .object([
            "type": "object",
            "description": "mIRC formatting colors by index (0–98). Only listed indexes change; 16–98 rarely need it.",
            "properties": .object(named),
            "patternProperties": .object([ircIndexPattern: colorSchema()]),
            "additionalProperties": false,
        ])
    }

    private static func vibrancySchema() -> JSONValue {
        .object([
            "enum": .array(["none", "sidebar", "window"]),
            "description": "Use the system's translucent materials: none (opaque colors), sidebar (sidebar and rail) or window.",
        ])
    }

    /// Pretty-printed JSON text of `themeFileSchema()`.
    public static func themeFileSchemaJSON() -> String {
        let data = (try? themeFileSchema().prettyPrinted()) ?? Data()
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    // MARK: - Markdown

    /// A Markdown reference of every token, grouped by section.
    public static func markdownTokenTable() -> String {
        func cell(_ text: String) -> String {
            text.replacingOccurrences(of: "|", with: "\\|")
        }
        var output: [String] = []
        for group in ThemeRegistry.groups {
            let tokens = ThemeRegistry.tokens(in: group.id)
            guard !tokens.isEmpty else { continue }
            output.append("### \(group.title)")
            output.append("")
            output.append(group.description)
            output.append("")
            output.append("| Token | Description | Dark default | Light default |")
            output.append("| --- | --- | --- | --- |")
            for token in tokens {
                output.append(
                    "| `\(token.key)` | \(cell(token.description)) | `\(cell(token.dark.expression))` | `\(cell(token.light.expression))` |"
                )
            }
            output.append("")
        }
        output.append("### Nick colors")
        output.append("")
        output.append("`nickColors` is an array of colors. Each nickname starts from the entry its name hashes to (case-insensitively, RFC 1459 case mapping), so a nick usually keeps its color across channels and launches. In a conversation, people who talk get different entries while the palette has room. Someone whose usual entry is taken by, or looks like the color of, a person in the current exchange gets the entry closest to their usual one that is clearly different; when none is, a look-alike keeps its usual color. Entries that would read as plain text (close to `chat.foreground`) or fall under 3:1 against `chat.background` aren't used.")
        output.append("")
        output.append("- Dark default: " + NickPalette.darkHex.map { "`\($0)`" }.joined(separator: " "))
        output.append("- Light default: " + NickPalette.lightHex.map { "`\($0)`" }.joined(separator: " "))
        output.append("")
        output.append("### IRC colors")
        output.append("")
        output.append("`ircColors` maps mIRC color indexes to colors. 0–15 default to mIRC's classic values; 16–98 to the standard extended palette.")
        output.append("")
        output.append("| Index | Name | Default |")
        output.append("| --- | --- | --- |")
        for index in 0..<IRCPalette.names.count {
            output.append("| \(index) | \(IRCPalette.names[index]) | `\(IRCPalette.standardHex[index])` |")
        }
        output.append("| 16–98 | Extended palette | see [modern.ircdocs.horse](https://modern.ircdocs.horse/formatting.html#colors-16-98) |")
        output.append("")
        return output.joined(separator: "\n")
    }
}
