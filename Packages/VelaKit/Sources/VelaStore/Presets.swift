// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaFoundation

// Settings → Presets: three choices that combine freely. Each axis owns a
// few settings and writes only those, so picking a window layout never
// touches the message style, the density or anything else you've set. The
// theme is never part of it.
//
// An axis whose settings match none of its choices exactly is "Customized";
// picking a choice again resets just that axis.

/// One of the three things Settings → Presets chooses.
public enum PresetAxis: String, CaseIterable, Identifiable, Sendable {
    /// Where things live: the sidebar, tabs at the top or in the title
    /// bar, or no navigation at all.
    case windowLayout
    /// How a message is laid out: Modern, Classic IRC or Columns.
    case messageStyle
    /// How much room messages get: Compact, Standard or Comfortable.
    case density

    public var id: String { rawValue }

    /// "Window layout".
    public var title: String {
        switch self {
        case .windowLayout: "Window layout"
        case .messageStyle: "Message style"
        case .density: "Density"
        }
    }

    /// The choices, in the order they're shown.
    public var choices: [PresetChoice] {
        switch self {
        case .windowLayout: [.sidebar, .tabsOnTop, .tabsInTitleBar, .focus]
        case .messageStyle: [.modern, .classicIRC, .columns]
        case .density: [.compact, .standard, .comfortable]
        }
    }

    /// Every setting this axis's choices write, in the order they first
    /// appear. Nothing outside these keys is ever written by the axis.
    public var keys: [String] {
        var keys: [String] = []
        for choice in choices {
            for key in choice.values.keys.sorted() where !keys.contains(key) {
                keys.append(key)
            }
        }
        return keys
    }
}

/// A choice on one ``PresetAxis``: the settings it writes, and how it's
/// named and described in Settings → Presets, the View menu and the
/// command palette.
public struct PresetChoice: Identifiable, Hashable, Sendable {
    public let axis: PresetAxis
    /// Unique within its axis: `"tabsOnTop"`.
    public let id: String
    public let name: String
    public let summary: String
    public let systemImage: String
    /// The settings.json values it writes. A value that's the setting's
    /// default is removed from settings.json instead of written, so the
    /// choice follows Vela's defaults if they ever change.
    public let values: [String: JSONValue]

    public init(axis: PresetAxis, id: String, name: String, summary: String, systemImage: String, values: [String: JSONValue]) {
        self.axis = axis
        self.id = id
        self.name = name
        self.summary = summary
        self.systemImage = systemImage
        self.values = values
    }

    /// `"windowLayout.tabsOnTop"`, unique across axes.
    public var qualifiedID: String { "\(axis.rawValue).\(id)" }

    /// The choice with `qualifiedID`, or with `id` on `axis`.
    public static func named(_ id: String, on axis: PresetAxis? = nil) -> PresetChoice? {
        let axes = axis.map { [$0] } ?? PresetAxis.allCases
        for axis in axes {
            if let choice = axis.choices.first(where: { $0.id == id || $0.qualifiedID == id }) { return choice }
        }
        return nil
    }
}

// MARK: - Window layout

extension PresetChoice {
    public static let sidebar = PresetChoice(
        axis: .windowLayout,
        id: "sidebar",
        name: "Sidebar",
        summary: "Networks and channels in a list on the left.",
        systemImage: "sidebar.left",
        values: ["navigation.style": "sidebar"]
    )

    public static let tabsOnTop = PresetChoice(
        axis: .windowLayout,
        id: "tabsOnTop",
        name: "Tabs on Top",
        summary: "Browser-style tabs under the channel title bar.",
        systemImage: "rectangle.topthird.inset.filled",
        values: ["navigation.style": "tabs", "tabs.placement": "top"]
    )

    public static let tabsInTitleBar = PresetChoice(
        axis: .windowLayout,
        id: "tabsInTitleBar",
        name: "Tabs in Title Bar",
        summary: "Compact tabs; the topic behind an info button.",
        systemImage: "menubar.rectangle",
        values: ["navigation.style": "tabs", "tabs.placement": "titleBar"]
    )

    public static let focus = PresetChoice(
        axis: .windowLayout,
        id: "focus",
        name: "Focus",
        summary: "Just the conversation. Switch with ⌘P or ⌘1\u{2060}–\u{2060}⌘9.",
        systemImage: "rectangle.center.inset.filled",
        values: ["navigation.style": "focus"]
    )
}

// MARK: - Message style

extension PresetChoice {
    public static let modern = PresetChoice(
        axis: .messageStyle,
        id: "modern",
        name: "Modern",
        summary: "Name and time on one line, the message below.",
        systemImage: "text.bubble",
        values: ["chat.layout": "grouped", "chat.monospace": false]
    )

    public static let classicIRC = PresetChoice(
        axis: .messageStyle,
        id: "classic",
        name: "Classic IRC",
        summary: "[time] <nick> message on one line, monospaced.",
        systemImage: "terminal",
        values: ["chat.layout": "classic", "chat.monospace": true]
    )

    public static let columns = PresetChoice(
        axis: .messageStyle,
        id: "columns",
        name: "Columns",
        summary: "The time, a right-aligned column of names, then the message.",
        systemImage: "text.alignright",
        values: ["chat.layout": "columns", "chat.monospace": false]
    )
}

// MARK: - Density

extension PresetChoice {
    public static let compact = PresetChoice(
        axis: .density,
        id: "compact",
        name: "Compact",
        summary: "Tight lines, little space between messages.",
        systemImage: "text.justify",
        values: ["chat.lineSpacing": 2, "chat.messageSpacing": 4]
    )

    /// Vela's defaults.
    public static let standard = PresetChoice(
        axis: .density,
        id: "standard",
        name: "Standard",
        summary: "Vela's defaults: room between lines and messages.",
        systemImage: "text.alignleft",
        values: ["chat.lineSpacing": 4, "chat.messageSpacing": 12]
    )

    public static let comfortable = PresetChoice(
        axis: .density,
        id: "comfortable",
        name: "Comfortable",
        summary: "Extra space between lines and messages.",
        systemImage: "line.3.horizontal",
        values: ["chat.lineSpacing": 6, "chat.messageSpacing": 18]
    )
}

// MARK: - Matching

extension PresetAxis {
    /// The choice whose values `resolve` gives back, or nil when the axis
    /// is customized. `resolve` reads a setting the way the app does: the
    /// stored value, or the default when it's missing or invalid.
    public func currentChoice(resolving resolve: (String) -> JSONValue?) -> PresetChoice? {
        choices.first { choice in
            SettingsPreset.valuesMatch(choice.values, resolving: resolve)
        }
    }

    /// The choice that raw settings.json `values` match (missing keys read
    /// as their defaults), or nil: for migrations and tests.
    public func currentChoice(in values: [String: JSONValue]) -> PresetChoice? {
        currentChoice { key in
            Self.resolved(values[key], forKey: key)
        }
    }

    /// `json` as the app reads the setting `key`: decoded and encoded again
    /// through its ``SettingKey``, so an invalid value reads as the default.
    static func resolved(_ json: JSONValue?, forKey key: String) -> JSONValue? {
        if let resolver = resolvers[key] { return resolver(json) }
        return json ?? SettingsCatalog.descriptor(forKey: key)?.defaultValue
    }

    /// The settings the axes write, read through their typed keys.
    private static let resolvers: [String: @Sendable (JSONValue?) -> JSONValue] = [
        SettingKey<NavigationStyle>.navigationStyle.key: { normalize($0, SettingKey<NavigationStyle>.navigationStyle) },
        SettingKey<TabStackPlacement>.tabsPlacement.key: { normalize($0, SettingKey<TabStackPlacement>.tabsPlacement) },
        SettingKey<ChatLayout>.chatLayout.key: { normalize($0, SettingKey<ChatLayout>.chatLayout) },
        SettingKey<Bool>.chatMonospace.key: { normalize($0, SettingKey<Bool>.chatMonospace) },
        SettingKey<Double>.chatLineSpacing.key: { normalize($0, SettingKey<Double>.chatLineSpacing) },
        SettingKey<Double>.chatMessageSpacing.key: { normalize($0, SettingKey<Double>.chatMessageSpacing) },
    ]

    private static func normalize<Value>(_ json: JSONValue?, _ key: SettingKey<Value>) -> JSONValue {
        key.jsonValue(for: key.value(from: json))
    }
}

extension SettingsStore {
    /// The choice on `axis` the current settings match, or nil when that
    /// axis is customized (its settings were changed by hand).
    public func currentChoice(for axis: PresetAxis) -> PresetChoice? {
        axis.currentChoice { key in
            PresetAxis.resolved(self.value(forKey: key), forKey: key)
        }
    }

    /// Writes `choice`'s settings, and nothing else, in one change: one
    /// update for the views watching settings and one save. A value that's
    /// the setting's default is removed rather than written.
    public func choose(_ choice: PresetChoice) {
        var changes: [String: JSONValue?] = [:]
        for (key, value) in choice.values {
            let isDefault = SettingsCatalog.descriptor(forKey: key).map { descriptor in
                SettingsPreset.valuesMatch([key: value]) { _ in descriptor.defaultValue }
            } ?? false
            // (Not `isDefault ? nil : value`: that `nil` would be JSON's null.)
            changes.updateValue(isDefault ? JSONValue?.none : .some(value), forKey: key)
        }
        setValues(changes)
    }
}
