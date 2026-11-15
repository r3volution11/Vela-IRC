// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Whether a theme is dark or light. Picks the token defaults and the system
/// appearance (menus, alerts, context menus) used alongside the theme.
public enum ThemeKind: String, Codable, Sendable, CaseIterable {
    case dark
    case light

    /// Accepts Vela's `dark`/`light` and VS Code's `vs-dark`, `vs`,
    /// `hc-black`, `hc-light`, `hcDark` and `hcLight`.
    public init?(lenient value: String) {
        switch value.lowercased() {
        case "dark", "vs-dark", "hc-black", "hcdark", "hc-dark": self = .dark
        case "light", "vs", "hc-light", "hclight": self = .light
        default: return nil
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let kind = ThemeKind(lenient: value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "“\(value)” is not a theme type; use \"dark\" or \"light\"."
            )
        }
        self = kind
    }

    public var opposite: ThemeKind { self == .dark ? .light : .dark }
}

/// Lets a theme opt into the system's translucent materials (Liquid Glass /
/// vibrancy) instead of painting opaque surfaces.
public enum ThemeVibrancy: String, Codable, Sendable, CaseIterable {
    /// All surfaces are painted with the theme's opaque colors.
    case none
    /// The sidebar (and collapsed rail) use the system sidebar material,
    /// tinted by `sidebar.background` if it is translucent.
    case sidebar
    /// The whole window uses translucent materials where the system allows.
    case window
}

/// A theme file as stored on disk (JSON with comments).
///
/// ```jsonc
/// {
///   "$schema": "https://raw.githubusercontent.com/r3volution11/Vela-IRC/main/schemas/vela-theme.schema.json",
///   "name": "My Theme",
///   "type": "dark",
///   "include": "Palenight",          // optional base theme (name or id)
///   "colors": { "accent": "#FF8800" },
///   "nickColors": ["#F07178", "#C3E88D"],
///   "ircColors": { "4": "#FF5370" }
/// }
/// ```
public struct ThemeDefinition: Codable, Sendable, Hashable {
    /// `$schema`, kept so saved files keep editor autocompletion.
    public var schema: String?
    public var name: String
    public var type: ThemeKind
    /// Name or id of another theme whose values this theme starts from.
    public var include: String?
    public var author: String?
    public var description: String?
    /// Token key → hex color.
    public var colors: [String: String]
    /// Palette used to color nicknames. Replaces the default palette entirely.
    public var nickColors: [String]?
    /// mIRC color index ("0"…"98") → hex color. Only listed indexes change.
    public var ircColors: [String: String]?
    public var vibrancy: ThemeVibrancy?

    public static let schemaURL =
        "https://raw.githubusercontent.com/r3volution11/Vela-IRC/main/schemas/vela-theme.schema.json"

    public init(
        schema: String? = ThemeDefinition.schemaURL,
        name: String,
        type: ThemeKind,
        include: String? = nil,
        author: String? = nil,
        description: String? = nil,
        colors: [String: String] = [:],
        nickColors: [String]? = nil,
        ircColors: [String: String]? = nil,
        vibrancy: ThemeVibrancy? = nil
    ) {
        self.schema = schema
        self.name = name
        self.type = type
        self.include = include
        self.author = author
        self.description = description
        self.colors = colors
        self.nickColors = nickColors
        self.ircColors = ircColors
        self.vibrancy = vibrancy
    }

    enum CodingKeys: String, CodingKey {
        case schema = "$schema"
        case name, type, include, author, description, colors, nickColors, ircColors, vibrancy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try container.decodeIfPresent(String.self, forKey: .schema)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(ThemeKind.self, forKey: .type)
        include = try container.decodeIfPresent(String.self, forKey: .include)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        colors = try container.decodeIfPresent([String: String].self, forKey: .colors) ?? [:]
        nickColors = try container.decodeIfPresent([String].self, forKey: .nickColors)
        ircColors = try container.decodeIfPresent([String: String].self, forKey: .ircColors)
        vibrancy = try container.decodeIfPresent(ThemeVibrancy.self, forKey: .vibrancy)
    }

    /// Checks every color value and IRC index; throws the first problem found.
    public func validate() throws {
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ThemeError.invalidValue(path: "name", message: "The theme name can't be empty.")
        }
        for key in colors.keys.sorted() where ThemeColor(hex: colors[key]!) == nil {
            throw ThemeError.invalidColor(key: "colors.\(key)", value: colors[key]!)
        }
        for (index, value) in (nickColors ?? []).enumerated() where ThemeColor(hex: value) == nil {
            throw ThemeError.invalidColor(key: "nickColors[\(index)]", value: value)
        }
        for key in (ircColors ?? [:]).keys.sorted() {
            guard let index = Int(key), (0..<IRCPalette.count).contains(index) else {
                throw ThemeError.invalidValue(
                    path: "ircColors.\(key)",
                    message: "IRC color indexes run from 0 to 98."
                )
            }
            if ThemeColor(hex: ircColors![key]!) == nil {
                throw ThemeError.invalidColor(key: "ircColors.\(key)", value: ircColors![key]!)
            }
        }
    }

    // MARK: Writing

    /// A hand-editable JSON rendering: metadata first, colors in registry
    /// order (unknown keys after, sorted), IRC colors in numeric order.
    public func jsonData() -> Data {
        func literal(_ string: String) -> String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.withoutEscapingSlashes]
            let data = (try? encoder.encode(string)) ?? Data("\"\"".utf8)
            return String(decoding: data, as: UTF8.self)
        }

        var lines: [String] = []
        var fields: [String] = []
        if let schema { fields.append("  \"$schema\": \(literal(schema))") }
        fields.append("  \"name\": \(literal(name))")
        fields.append("  \"type\": \(literal(type.rawValue))")
        if let author { fields.append("  \"author\": \(literal(author))") }
        if let description { fields.append("  \"description\": \(literal(description))") }
        if let include { fields.append("  \"include\": \(literal(include))") }
        if let vibrancy { fields.append("  \"vibrancy\": \(literal(vibrancy.rawValue))") }

        let registryOrder = ThemeRegistry.tokens.map(\.key)
        let known = registryOrder.filter { colors[$0] != nil }
        let unknown = colors.keys.filter { ThemeRegistry.token($0) == nil }.sorted()
        let colorLines = (known + unknown).map { "    \(literal($0)): \(literal(colors[$0]!))" }
        if colorLines.isEmpty {
            fields.append("  \"colors\": {}")
        } else {
            fields.append("  \"colors\": {\n" + colorLines.joined(separator: ",\n") + "\n  }")
        }

        if let nickColors {
            let items = nickColors.map { "    \(literal($0))" }
            fields.append(
                items.isEmpty ? "  \"nickColors\": []" : "  \"nickColors\": [\n" + items.joined(separator: ",\n") + "\n  ]"
            )
        }
        if let ircColors {
            let keys = ircColors.keys.sorted { (Int($0) ?? .max, $0) < (Int($1) ?? .max, $1) }
            let items = keys.map { "    \(literal($0)): \(literal(ircColors[$0]!))" }
            fields.append(
                items.isEmpty ? "  \"ircColors\": {}" : "  \"ircColors\": {\n" + items.joined(separator: ",\n") + "\n  }"
            )
        }

        lines.append("{")
        lines.append(fields.joined(separator: ",\n"))
        lines.append("}")
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }
}
