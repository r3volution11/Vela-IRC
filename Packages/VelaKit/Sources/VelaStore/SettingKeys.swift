// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaFoundation

/// How chat lines are laid out.
public enum ChatLayout: String, Codable, Sendable, CaseIterable, SettingValueConvertible {
    /// One line per message: `[time] <nick> text`.
    case classic
    /// Consecutive messages from one sender grouped under a header.
    case grouped
    /// Fixed-width time / nick columns, text aligned in a third column.
    case columns
}

/// What to do with join/part/quit/nick noise.
public enum JoinPartDisplay: String, Codable, Sendable, CaseIterable, SettingValueConvertible {
    case show
    /// Consecutive events folded into one summary line.
    case collapse
    case hide
}

// MARK: Appearance

extension SettingKey where Value == String {
    public static var appearanceTheme: SettingKey<String> {
        .init("appearance.theme", default: "Palenight",
              summary: "Theme used when appearance.followSystem is off.")
    }
    public static var appearancePreferredDarkTheme: SettingKey<String> {
        .init("appearance.preferredDarkTheme", default: "Palenight",
              summary: "Theme used in Dark Mode when appearance.followSystem is on.")
    }
    public static var appearancePreferredLightTheme: SettingKey<String> {
        .init("appearance.preferredLightTheme", default: "Lighter",
              summary: "Theme used in Light Mode when appearance.followSystem is on.")
    }
}

extension SettingKey where Value == Bool {
    public static var appearanceFollowSystem: SettingKey<Bool> {
        .init("appearance.followSystem", default: true,
              summary: "Switch between the preferred dark and light themes with the system appearance.")
    }
}

extension SettingKey where Value == [String: JSONValue] {
    public static var appearanceColorCustomizations: SettingKey<[String: JSONValue]> {
        .init("appearance.colorCustomizations", default: [:],
              summary: "Overrides for theme color tokens, e.g. {\"chat.background\": \"#1e1e2e\"}.")
    }
}

// MARK: Chat

extension SettingKey where Value == ChatLayout {
    public static var chatLayout: SettingKey<ChatLayout> {
        .init("chat.layout", default: .grouped,
              summary: "Message layout: classic, grouped or columns.")
    }
}

extension SettingKey where Value == JoinPartDisplay {
    public static var chatShowJoinPart: SettingKey<JoinPartDisplay> {
        .init("chat.showJoinPart", default: .collapse,
              summary: "How join, part, quit and nick changes are shown: show, collapse or hide.")
    }
}

extension SettingKey where Value == String {
    public static var chatFontFamily: SettingKey<String> {
        .init("chat.fontFamily", default: "",
              summary: "Chat font family. Empty uses the system font.")
    }
    public static var chatMonospaceFontFamily: SettingKey<String> {
        .init("chat.monospaceFontFamily", default: "SF Mono",
              summary: "Font for code spans and the columns layout's fixed-width parts.")
    }
    public static var chatTimestampFormat: SettingKey<String> {
        .init("chat.timestampFormat", default: "HH:mm",
              summary: "Timestamp format (Unicode date pattern, e.g. \"HH:mm:ss\").")
    }
}

extension SettingKey where Value == Double {
    public static var chatFontSize: SettingKey<Double> {
        .init("chat.fontSize", default: 13, summary: "Chat font size in points.")
    }
    public static var chatLineSpacing: SettingKey<Double> {
        .init("chat.lineSpacing", default: 2, summary: "Extra spacing between lines of a message, in points.")
    }
    public static var chatMessageSpacing: SettingKey<Double> {
        .init("chat.messageSpacing", default: 6, summary: "Spacing between message groups, in points.")
    }
    public static var chatGroupingInterval: SettingKey<Double> {
        .init("chat.groupingInterval", default: 300,
              summary: "Messages from the same sender within this many seconds are grouped.")
    }
    public static var chatColumnsNickWidth: SettingKey<Double> {
        .init("chat.columnsNickWidth", default: 120, summary: "Nick column width in the columns layout, in points.")
    }
}

extension SettingKey where Value == Bool {
    public static var chatShowTimestamps: SettingKey<Bool> {
        .init("chat.showTimestamps", default: true, summary: "Show message timestamps.")
    }
    public static var chatColorNicks: SettingKey<Bool> {
        .init("chat.colorNicks", default: true, summary: "Give each nick a stable color.")
    }
    public static var chatShowAvatars: SettingKey<Bool> {
        .init("chat.showAvatars", default: true, summary: "Show avatars next to message groups.")
    }
    public static var chatRenderFormatting: SettingKey<Bool> {
        .init("chat.renderFormatting", default: true,
              summary: "Render mIRC formatting (colors, bold, italics). Off strips it.")
    }
    public static var chatLargeEmoji: SettingKey<Bool> {
        .init("chat.largeEmoji", default: true, summary: "Show emoji-only messages larger.")
    }
}

extension SettingKey where Value == Int {
    public static var chatScrollbackInMemory: SettingKey<Int> {
        .init("chat.scrollbackInMemory", default: 1000,
              summary: "Messages kept in memory per buffer; older ones are paged from disk.")
    }
}

// MARK: Sidebar & panes

extension SettingKey where Value == Bool {
    public static var sidebarCollapsed: SettingKey<Bool> {
        .init("sidebar.collapsed", default: false, summary: "Hide the buffer sidebar.")
    }
    public static var sidebarShowUnreadCounts: SettingKey<Bool> {
        .init("sidebar.showUnreadCounts", default: true, summary: "Show unread message counts in the sidebar.")
    }
    public static var memberListVisible: SettingKey<Bool> {
        .init("memberList.visible", default: true, summary: "Show the channel member list.")
    }
}

extension SettingKey where Value == Double {
    public static var sidebarWidth: SettingKey<Double> {
        .init("sidebar.width", default: 200, summary: "Sidebar width in points.")
    }
    public static var sidebarRowHeight: SettingKey<Double> {
        .init("sidebar.rowHeight", default: 22, summary: "Sidebar row height in points.")
    }
    public static var sidebarFontSize: SettingKey<Double> {
        .init("sidebar.fontSize", default: 12, summary: "Sidebar font size in points.")
    }
    public static var memberListWidth: SettingKey<Double> {
        .init("memberList.width", default: 170, summary: "Member list width in points.")
    }
}

// MARK: Media

extension SettingKey where Value == Bool {
    public static var mediaAutoLoad: SettingKey<Bool> {
        .init("media.autoLoad", default: true, summary: "Load inline images automatically.")
    }
    public static var mediaShowLinkCards: SettingKey<Bool> {
        .init("media.showLinkCards", default: true, summary: "Show preview cards for links.")
    }
    public static var mediaLoadVideoEmbeds: SettingKey<Bool> {
        .init("media.loadVideoEmbeds", default: true, summary: "Show embedded players for video links.")
    }
    public static var mediaRestrictToAllowed: SettingKey<Bool> {
        .init("media.restrictToAllowed", default: false,
              summary: "Only load media from domains listed in media.allowedDomains.")
    }
}

extension SettingKey where Value == [String] {
    public static var mediaBlockedDomains: SettingKey<[String]> {
        .init("media.blockedDomains", default: [], summary: "Never load media from these domains (and subdomains).")
    }
    public static var mediaAllowedDomains: SettingKey<[String]> {
        .init("media.allowedDomains", default: [],
              summary: "Domains media may load from when media.restrictToAllowed is on.")
    }
    public static var mediaDisabledBuffers: SettingKey<[String]> {
        .init("media.disabledBuffers", default: [],
              summary: "Buffers without inline media: \"<networkUUID>/<foldedName>\" or \"<networkUUID>/*\".")
    }
}

extension SettingKey where Value == Double {
    public static var mediaMaxImageSizeMB: SettingKey<Double> {
        .init("media.maxImageSizeMB", default: 10, summary: "Skip auto-loading images larger than this many megabytes.")
    }
    public static var mediaMaxImageHeight: SettingKey<Double> {
        .init("media.maxImageHeight", default: 320, summary: "Maximum height of inline images, in points.")
    }
}

// MARK: Notifications & behavior

extension SettingKey where Value == Bool {
    public static var notifyHighlights: SettingKey<Bool> {
        .init("notifications.highlights", default: true, summary: "Notify when you are mentioned or a highlight word matches.")
    }
    public static var notifyPrivateMessages: SettingKey<Bool> {
        .init("notifications.privateMessages", default: true, summary: "Notify on private messages.")
    }
    public static var notifySound: SettingKey<Bool> {
        .init("notifications.sound", default: true, summary: "Play a sound with notifications.")
    }
    public static var inputSendTypingIndicators: SettingKey<Bool> {
        .init("input.sendTypingIndicators", default: true, summary: "Let others see when you are typing (+typing).")
    }
    public static var inputSpellCheck: SettingKey<Bool> {
        .init("input.spellCheck", default: true, summary: "Check spelling while typing.")
    }
    public static var connectionAutoReconnect: SettingKey<Bool> {
        .init("connection.autoReconnect", default: true, summary: "Reconnect automatically after a dropped connection.")
    }
}

extension SettingKey where Value == [String] {
    public static var highlightWords: SettingKey<[String]> {
        .init("highlight.words", default: [],
              summary: "Extra words that count as highlights on every network (your nick always does).")
    }
}

extension SettingKey where Value == Int {
    public static var historyRetentionDays: SettingKey<Int> {
        .init("history.retentionDays", default: 0,
              summary: "Delete stored messages older than this many days. 0 keeps history forever.")
    }
}

// MARK: Catalog

extension SettingKey where Value == JSONValue {
    /// Documentation for every setting Vela knows about, in display order.
    public static var allKnownKeys: [SettingDescriptor] { SettingsCatalog.all }
}

/// The list of known settings plus helpers that render it as documentation.
public enum SettingsCatalog {
    public static var all: [SettingDescriptor] {
        [
            SettingKey.appearanceTheme.descriptor,
            SettingKey.appearancePreferredDarkTheme.descriptor,
            SettingKey.appearancePreferredLightTheme.descriptor,
            SettingKey.appearanceFollowSystem.descriptor,
            SettingKey.appearanceColorCustomizations.descriptor,

            SettingKey.chatLayout.descriptor,
            SettingKey.chatFontFamily.descriptor,
            SettingKey.chatFontSize.descriptor,
            SettingKey.chatMonospaceFontFamily.descriptor,
            SettingKey.chatLineSpacing.descriptor,
            SettingKey.chatMessageSpacing.descriptor,
            SettingKey.chatShowTimestamps.descriptor,
            SettingKey.chatTimestampFormat.descriptor,
            SettingKey.chatShowJoinPart.descriptor,
            SettingKey.chatColorNicks.descriptor,
            SettingKey.chatShowAvatars.descriptor,
            SettingKey.chatGroupingInterval.descriptor,
            SettingKey.chatColumnsNickWidth.descriptor,
            SettingKey.chatRenderFormatting.descriptor,
            SettingKey.chatLargeEmoji.descriptor,
            SettingKey.chatScrollbackInMemory.descriptor,

            SettingKey.sidebarCollapsed.descriptor,
            SettingKey.sidebarWidth.descriptor,
            SettingKey.sidebarRowHeight.descriptor,
            SettingKey.sidebarFontSize.descriptor,
            SettingKey.sidebarShowUnreadCounts.descriptor,
            SettingKey.memberListVisible.descriptor,
            SettingKey.memberListWidth.descriptor,

            SettingKey.mediaAutoLoad.descriptor,
            SettingKey.mediaShowLinkCards.descriptor,
            SettingKey.mediaLoadVideoEmbeds.descriptor,
            SettingKey.mediaBlockedDomains.descriptor,
            SettingKey.mediaAllowedDomains.descriptor,
            SettingKey.mediaRestrictToAllowed.descriptor,
            SettingKey.mediaMaxImageSizeMB.descriptor,
            SettingKey.mediaMaxImageHeight.descriptor,
            SettingKey.mediaDisabledBuffers.descriptor,

            SettingKey.notifyHighlights.descriptor,
            SettingKey.notifyPrivateMessages.descriptor,
            SettingKey.notifySound.descriptor,
            SettingKey.highlightWords.descriptor,
            SettingKey.inputSendTypingIndicators.descriptor,
            SettingKey.inputSpellCheck.descriptor,
            SettingKey.connectionAutoReconnect.descriptor,
            SettingKey.historyRetentionDays.descriptor,
        ]
    }

    public static func descriptor(forKey key: String) -> SettingDescriptor? {
        all.first { $0.key == key }
    }

    /// A JSON Schema (draft-07) describing settings.json, suitable for
    /// writing next to the file so editors offer completion and validation.
    public static func jsonSchema() -> JSONValue {
        var properties: [String: JSONValue] = [:]
        for descriptor in all {
            var property = descriptor.schema.objectValue ?? [:]
            property["default"] = descriptor.defaultValue
            if !descriptor.summary.isEmpty {
                property["description"] = .string(descriptor.summary)
            }
            properties[descriptor.key] = .object(property)
        }
        return .object([
            "$schema": .string("http://json-schema.org/draft-07/schema#"),
            "title": .string("Vela settings"),
            "type": .string("object"),
            "properties": .object(properties),
            "additionalProperties": .bool(true),
        ])
    }

    /// Writes ``jsonSchema()`` (pretty-printed) to `url`, e.g.
    /// `root/settings.schema.json`, atomically.
    public static func writeJSONSchema(to url: URL) throws {
        var data = try jsonSchema().prettyPrinted()
        data.append(0x0A)
        try FileSupport.writeAtomically(data, to: url)
    }

    /// A commented JSONC document listing every setting with its default,
    /// grouped by category (like VS Code's "Default Settings" view).
    public static func defaultSettingsDocument() -> String {
        var lines = ["// Vela default settings. Copy entries into settings.json to change them.", "{"]
        var lastCategory: String?
        let descriptors = all
        for (index, descriptor) in descriptors.enumerated() {
            if descriptor.category != lastCategory {
                if lastCategory != nil { lines.append("") }
                lines.append("    // \(descriptor.category)")
                lastCategory = descriptor.category
            }
            if !descriptor.summary.isEmpty {
                lines.append("    // \(descriptor.summary)")
            }
            let value = compactJSON(descriptor.defaultValue)
            let separator = index == descriptors.count - 1 ? "" : ","
            lines.append("    \(compactJSON(.string(descriptor.key))): \(value)\(separator)")
        }
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func compactJSON(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return "null" }
        return String(decoding: data, as: UTF8.self)
    }
}
