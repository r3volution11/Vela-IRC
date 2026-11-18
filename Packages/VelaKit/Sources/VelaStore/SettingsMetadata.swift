// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaFoundation

// Presentation metadata for the settings editor (Settings → Advanced) and
// the settings.json validator: titles, categories, which Settings pane a
// setting belongs to, number ranges, and where value suggestions come from.

/// A group of settings, shown as a category chip in the settings editor.
/// Every category belongs to exactly one Settings pane.
public enum SettingsCategory: String, CaseIterable, Sendable, Identifiable {
    case appearance
    case layout
    case chat
    case typing
    case history
    case media
    case notifications
    case connection
    case intelligence

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .appearance: "Appearance"
        case .layout: "Layout"
        case .chat: "Messages"
        case .typing: "Typing"
        case .history: "History"
        case .media: "Media"
        case .notifications: "Notifications"
        case .connection: "Connection"
        case .intelligence: "Apple Intelligence"
        }
    }

    /// The key prefixes (the part before the first dot) in this category.
    public var keyPrefixes: [String] {
        switch self {
        case .appearance: ["appearance"]
        case .layout: ["navigation", "tabs", "sidebar", "memberList"]
        case .chat: ["chat"]
        case .typing: ["input"]
        case .history: ["history", "logging"]
        case .media: ["media"]
        case .notifications: ["notifications", "dock", "highlight"]
        case .connection: ["connection"]
        case .intelligence: ["intelligence", "translation"]
        }
    }

    /// The id of the Settings pane these settings live on
    /// (`SettingsPane.rawValue` in VelaUI).
    public var paneID: String {
        switch self {
        case .appearance: "appearance"
        case .layout: "layout"
        case .chat, .typing, .history: "messages"
        case .media: "media"
        case .notifications: "notifications"
        case .connection: "networks"
        case .intelligence: "intelligence"
        }
    }

    /// The category of a settings.json key, or nil for unknown prefixes.
    public static func category(forKey key: String) -> SettingsCategory? {
        let prefix = String(key.prefix(while: { $0 != "." }))
        return allCases.first { $0.keyPrefixes.contains(prefix) }
    }

    /// The categories shown on a Settings pane.
    public static func categories(forPane paneID: String) -> [SettingsCategory] {
        allCases.filter { $0.paneID == paneID }
    }
}

/// Where the settings editor gets suggestions for a value (or, for
/// objects, for keys). The UI layer supplies the actual lists.
public enum SettingSuggestionSource: String, Sendable {
    /// Installed font families.
    case fontFamilies
    /// Installed fixed-pitch font families.
    case monospacedFontFamilies
    /// Theme names (built-in and user themes).
    case themes
    /// Common Unicode date patterns for timestamps.
    case timestampPatterns
    /// Translation languages (`translation.language`).
    case languages
    /// Channels and conversations, stored as `"<networkUUID>/<foldedName>"`
    /// (or `"<networkUUID>/*"` for a whole network).
    case buffers
    /// Sites from links seen in chat (keys of `media.siteRules`).
    case domains
    /// Theme color tokens and `"[Theme Name]"` scopes (keys of
    /// `appearance.colorCustomizations`).
    case themeTokens
}

extension SettingDescriptor {
    /// VS Code-style title: `"Chat: Font Size"`.
    public var title: String { "\(groupTitle): \(name)" }

    /// The part before the colon in ``title``, from the key's prefix.
    public var groupTitle: String {
        let prefix = String(key.prefix(while: { $0 != "." }))
        return SettingsMetadata.prefixTitles[prefix] ?? SettingsMetadata.humanize(prefix)
    }

    /// The part after the colon in ``title``: `"Font Size"`.
    public var name: String {
        if let name = SettingsMetadata.nameOverrides[key] { return name }
        let rest = key.drop(while: { $0 != "." }).dropFirst()
        return SettingsMetadata.humanize(String(rest))
    }

    /// The editor category (category chip), if the prefix is known.
    public var settingsCategory: SettingsCategory? { SettingsCategory.category(forKey: key) }

    /// Allowed range for numbers, from the schema's `minimum`/`maximum`.
    public var numberRange: ClosedRange<Double>? {
        guard let object = schema.objectValue,
              let minimum = object["minimum"]?.doubleValue,
              let maximum = object["maximum"]?.doubleValue,
              minimum <= maximum
        else { return nil }
        return minimum...maximum
    }

    /// The allowed string values from the schema's `enum`, if any.
    public var enumValues: [String]? {
        schema.objectValue?["enum"]?.arrayValue?.compactMap(\.stringValue)
    }

    /// For lists whose elements are a fixed set of strings
    /// (`dock.badgeCounts`): the strings, from the schema's `items.enum`.
    public var itemEnumValues: [String]? {
        guard schema.objectValue?["type"]?.stringValue == "array" else { return nil }
        return schema.objectValue?["items"]?.objectValue?["enum"]?.arrayValue?.compactMap(\.stringValue)
    }

    /// True for settings that follow a macOS setting until set
    /// (``SystemFollowingBool``): `true`, `false` or `"system"`.
    public var followsSystem: Bool { SettingsMetadata.systemFollowingKeys.contains(key) }

    /// Suggestions for the value (or object keys), if any.
    public var suggestionSource: SettingSuggestionSource? { SettingsMetadata.suggestionSources[key] }

    /// For object settings whose values are a fixed set of strings
    /// (`media.siteRules`): those strings.
    public var objectValueEnum: [String]? { SettingsMetadata.objectValueEnums[key] }
}

/// Tables behind the ``SettingDescriptor`` metadata.
public enum SettingsMetadata {
    /// Titles for key prefixes that don't humanize well.
    static let prefixTitles: [String: String] = [
        "memberList": "Member List",
        "input": "Typing",
        "intelligence": "Apple Intelligence",
        "highlight": "Highlights",
        "logging": "Chat Logs",
    ]

    /// Names for keys that don't humanize well.
    static let nameOverrides: [String: String] = [
        "media.maxImageSizeMB": "Max Image Size (MB)",
        "media.disabledBuffers": "Channels Without Media",
        "media.blurredBuffers": "Blurred Channels",
        "media.restrictToAllowed": "Only Listed Sites",
        "chat.showJoinPart": "Join/Part Messages",
        "chat.openAt": "Open Channels At",
        "chat.showUnreadMarker": "Show New Line",
        "chat.timestampPosition.classic": "Timestamp Position in Classic",
        "chat.timestampPosition.grouped": "Timestamp Position in Modern",
        "chat.timestampPosition.columns": "Timestamp Position in Compact Columns",
        "intelligence.catchUp": "Catch Me Up",
        "intelligence.catchUpThreshold": "Catch Me Up After",
        "intelligence.spotlightChannels": "Channels in Spotlight",
        "translation.autoTranslate": "Auto-Translated Channels",
        "translation.language": "Translate Into",
        "input.spellCheck": "Check Spelling",
        "input.grammarCheck": "Check Grammar",
        "history.retentionDays": "Keep Messages (Days)",
        "dock.showOffline": "Show Offline Mark",
        "logging.enabled": "Save Chat Logs",
        "logging.maxFileSizeMB": "Max File Size (MB)",
        "logging.keepFiles": "Files to Keep",
        "logging.includeEvents": "Include Channel Events",
        "logging.includeServer": "Include Server Messages",
        "logging.excludedBuffers": "Channels Not Logged",
    ]

    /// Number ranges, merged into each descriptor's schema as
    /// `minimum`/`maximum` (see ``SettingsCatalog/all``).
    public static let numberRanges: [String: ClosedRange<Double>] = [
        "chat.fontSize": 9...28,
        "chat.lineSpacing": 0...10,
        "chat.messageSpacing": 0...24,
        "chat.groupingInterval": 0...86_400,
        "chat.columnsNickWidth": 60...240,
        "chat.scrollbackInMemory": 200...100_000,
        "sidebar.width": 110...360,
        "sidebar.rowHeight": 18...34,
        "sidebar.fontSize": 10...17,
        "memberList.width": 120...320,
        "tabs.roundness": 0...1,
        "tabs.height": 22...40,
        "media.maxImageSizeMB": 1...100,
        "media.maxImageHeight": 120...800,
        "history.retentionDays": 0...3650,
        "logging.maxFileSizeMB": 1...1024,
        "logging.keepFiles": 0...1000,
        "intelligence.catchUpThreshold": 1...1000,
    ]

    static let systemFollowingKeys: Set<String> = [
        "input.autocorrect", "input.textReplacements", "input.smartPunctuation",
    ]

    static let suggestionSources: [String: SettingSuggestionSource] = [
        "appearance.theme": .themes,
        "appearance.preferredDarkTheme": .themes,
        "appearance.preferredLightTheme": .themes,
        "appearance.colorCustomizations": .themeTokens,
        "chat.fontFamily": .fontFamilies,
        "chat.monospaceFontFamily": .monospacedFontFamilies,
        "chat.timestampFormat": .timestampPatterns,
        "media.siteRules": .domains,
        "media.disabledBuffers": .buffers,
        "media.blurredBuffers": .buffers,
        "translation.autoTranslate": .buffers,
        "logging.excludedBuffers": .buffers,
        "translation.language": .languages,
    ]

    static let objectValueEnums: [String: [String]] = [
        "media.siteRules": ["allow", "textOnly", "block"],
    ]

    /// Common timestamp patterns offered for `chat.timestampFormat`.
    public static let timestampPatterns = ["HH:mm", "HH:mm:ss", "h:mm a", "h:mm:ss a", "[HH:mm]", "[HH:mm:ss]", "HH.mm"]

    /// Labels for enum values that don't read well humanized.
    static let enumLabels: [String: String] = [
        "12h": "12-hour",
        "24h": "24-hour",
        "textOnly": "Text only",
        "titleBar": "Title bar",
        "allow": "Everything",
        "block": "Nothing",
        // appearance.messageBoxBorder
        "accent": "Accent when typing",
        // dock.badgeCounts and dock.bounceFor
        "mentions": "Mentions and highlight words",
        "channels": "All channel messages",
        // dock.badgeStyle
        "capped": "Up to 99+",
        "exact": "Exact number",
        "dot": "Dot (•)",
        // dock.bounce
        "untilActive": "Until you switch to Vela",
    ]

    /// A readable label for a settings.json enum value, in sentence case:
    /// `"grouped"` → `"Grouped"`, `"textOnly"` → `"Text only"`, `"12h"` → `"12-hour"`.
    public static func enumLabel(_ raw: String) -> String {
        if let label = enumLabels[raw] { return label }
        let words = humanize(raw).split(separator: " ")
        guard let first = words.first else { return raw }
        let rest = words.dropFirst().map { word in
            word.allSatisfy(\.isUppercase) ? String(word) : word.lowercased()
        }
        return ([String(first)] + rest).joined(separator: " ")
    }

    /// `"fontSize"` → `"Font Size"`, `"showJoinPart"` → `"Show Join Part"`,
    /// `"maxImageSizeMB"` → `"Max Image Size MB"`.
    public static func humanize(_ identifier: String) -> String {
        var words: [String] = []
        var current = ""
        let characters = Array(identifier)
        for (index, character) in characters.enumerated() {
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            let startsWord = character.isUppercase && !current.isEmpty
                && (!(current.last?.isUppercase ?? false) || (next?.isLowercase ?? false))
            if startsWord || character == "." || character == "_" {
                if !current.isEmpty { words.append(current) }
                current = character.isLetter || character.isNumber ? String(character) : ""
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { words.append(current) }
        return words.map { word in
            word.allSatisfy(\.isUppercase) ? word : word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }
}
