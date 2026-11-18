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

/// Where a channel opens when it has messages you haven't read.
public enum ChatOpenPosition: String, Codable, Sendable, CaseIterable, SettingValueConvertible {
    /// At the New line, where you stopped reading.
    case firstUnread
    /// At the bottom, with the newest messages in view.
    case newest
}

/// Which clock timestamps use, unless `chat.timestampFormat` sets a
/// custom pattern.
public enum TimestampClock: String, Codable, Sendable, CaseIterable, SettingValueConvertible {
    /// Follow the Mac's 24-hour time setting (and the region's convention).
    case system
    case twelveHour = "12h"
    case twentyFourHour = "24h"
}

/// How much a link preview shows.
public enum LinkPreviewSize: String, Codable, Sendable, CaseIterable, SettingValueConvertible {
    /// One line: site, title and a small thumbnail.
    case minimal
    /// Title, a short description and a medium thumbnail beside them.
    case standard
    /// The full card: a longer description and a large image below.
    case large
}

/// How video links (YouTube, Vimeo, Twitch, Streamable, video files) show.
public enum VideoEmbedStyle: String, Codable, Sendable, CaseIterable, SettingValueConvertible {
    /// A large thumbnail with ▶; the player loads in place when pressed.
    case player
    /// One line; ▶ opens the player under it.
    case compact
    /// No player: the link shows as a link preview.
    case off
}

/// How inline images show.
public enum InlineImageSize: String, Codable, Sendable, CaseIterable, SettingValueConvertible {
    /// Up to `media.maxImageHeight` tall.
    case full
    /// A small thumbnail; click to open the viewer.
    case thumbnail
}

/// How the message box's border is drawn. Its color is the theme's
/// `input.border` (and `input.focusBorder`), which Settings → Appearance can
/// change per theme.
public enum MessageBoxBorder: String, Codable, Sendable, CaseIterable, SettingValueConvertible {
    /// No border, just the field's background.
    case none
    /// A quiet 1 pt line that stays the same while you type.
    case subtle
    /// The quiet line, turning the accent color while the field has focus.
    case accent
}

/// The icon Vela shows in the Dock and the app switcher while it's open.
/// Finder, Spotlight and the Apps list always show the standard icon, which
/// follows the Mac's Icon & widget style; macOS has no way for an app to
/// change those.
public enum AppIcon: String, Codable, Sendable, CaseIterable, SettingValueConvertible {
    /// The standard icon: navy with a cyan V.
    case vela
    /// Near-black, with a pale ice V.
    case midnight
    /// Charcoal, with a silver V.
    case graphite
    /// Deep plum, with a peach-to-coral V and a warm star.
    case sunrise
    /// White, with a deep blue V.
    case paper
    /// Bright blue, with a white V.
    case vivid
}

/// A switch that follows a macOS setting until it's changed in Vela, such
/// as autocorrect following System Settings → Keyboard → Text Input.
///
/// In settings.json it's `true` or `false` once set; a missing key (or
/// `"system"`) follows macOS. `on`/`off` never appear in the file.
public enum SystemFollowingBool: String, Codable, Sendable, CaseIterable, SettingValueConvertible {
    /// Follow the macOS setting.
    case system
    case on
    case off

    public init?(settingJSON: JSONValue) {
        if let value = settingJSON.boolValue {
            self = value ? .on : .off
        } else if settingJSON.stringValue == Self.system.rawValue {
            self = .system
        } else {
            return nil
        }
    }

    public var settingJSON: JSONValue {
        switch self {
        case .system: .string(Self.system.rawValue)
        case .on: .bool(true)
        case .off: .bool(false)
        }
    }

    public static var settingSchema: JSONValue {
        .object(["oneOf": .array([
            .object(["type": "boolean"]),
            .object(["type": "string", "enum": .array([.string(Self.system.rawValue)])]),
        ])])
    }

    /// The effective value, given what macOS currently says.
    public func resolved(system: Bool) -> Bool {
        switch self {
        case .system: system
        case .on: true
        case .off: false
        }
    }

    /// The explicit value for `enabled`.
    public init(_ enabled: Bool) {
        self = enabled ? .on : .off
    }
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
              summary: "Overrides for theme color tokens, for every theme or for one (\"[Palenight]\": {…}), e.g. {\"chat.background\": \"#1e1e2e\"}. The accent color and message box border color pickers in Settings → Appearance save their choices here too.")
    }
}

extension SettingKey where Value == MessageBoxBorder {
    public static var appearanceMessageBoxBorder: SettingKey<MessageBoxBorder> {
        .init("appearance.messageBoxBorder", default: .subtle,
              summary: "Border around the message box: none (just its background), subtle (a quiet line that stays the same while you type) or accent (the line turns the accent color while you type). Settings → Appearance also sets its color per theme.")
    }
}

extension SettingKey where Value == AppIcon {
    public static var appearanceAppIcon: SettingKey<AppIcon> {
        .init("appearance.appIcon", default: .vela,
              summary: "Icon in the Dock and app switcher while Vela is open: vela (the standard icon), midnight, graphite, sunrise, paper or vivid. Finder and Spotlight always show the standard icon, which follows your Icon & widget style.")
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

extension SettingKey where Value == ChatOpenPosition {
    public static var chatOpenAt: SettingKey<ChatOpenPosition> {
        .init("chat.openAt", default: .firstUnread,
              summary: "Where channels with unread messages open: firstUnread (at the New line, where you stopped reading) or newest (at the bottom, so there's nothing to scroll down to). With newest, coming back to Vela also shows the newest messages.")
    }
}

extension SettingKey where Value == TimestampClock {
    public static var chatClock: SettingKey<TimestampClock> {
        .init("chat.clock", default: .system,
              summary: "Timestamp clock: system (follow the Mac's 24-hour time setting), 12h or 24h. Ignored when chat.timestampFormat is set.")
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
        .init("chat.timestampFormat", default: "",
              summary: "Custom timestamp format (Unicode date pattern, e.g. \"HH:mm:ss\"). Empty uses chat.clock and chat.timestampSeconds.")
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
    public static var chatTimestampSeconds: SettingKey<Bool> {
        .init("chat.timestampSeconds", default: false,
              summary: "Include seconds in timestamps. Ignored when chat.timestampFormat is set.")
    }
    public static var chatColorNicks: SettingKey<Bool> {
        .init("chat.colorNicks", default: true, summary: "Color nicks from the theme's nick palette; people talking in the same channel get different colors.")
    }
    public static var chatShowAvatars: SettingKey<Bool> {
        .init("chat.showAvatars", default: false, summary: "Show initials avatars next to message groups in the grouped layout and member list.")
    }
    public static var chatRenderFormatting: SettingKey<Bool> {
        .init("chat.renderFormatting", default: true,
              summary: "Render mIRC formatting (colors, bold, italics). Off strips it.")
    }
    public static var chatLargeEmoji: SettingKey<Bool> {
        .init("chat.largeEmoji", default: true, summary: "Show emoji-only messages larger.")
    }
    public static var chatShowUnreadMarker: SettingKey<Bool> {
        .init("chat.showUnreadMarker", default: true,
              summary: "Draw the New line above the first message you haven't read. Off shows messages just as they came in. Unread counts still work, and Catch me up is still in a channel's right-click menu and the command palette.")
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
        .init("media.autoLoad", default: true,
              summary: "Fetch previews (link cards, images, video thumbnails) automatically. Off shows a button to load each one.")
    }
    public static var mediaShowLinkCards: SettingKey<Bool> {
        .init("media.showLinkCards", default: true, summary: "Show preview cards for links.")
    }
    public static var mediaRestrictToAllowed: SettingKey<Bool> {
        .init("media.restrictToAllowed", default: false,
              summary: "Only show previews from sites with an allow or textOnly rule in media.siteRules.")
    }
    public static var mediaFilterAdultSites: SettingKey<Bool> {
        .init("media.filterAdultSites", default: true,
              summary: "Hide previews from adult sites (a list bundled with Vela) and pages that label themselves adult. Links stay clickable.")
    }
    public static var mediaBlurImages: SettingKey<Bool> {
        .init("media.blurImages", default: false,
              summary: "Blur images, GIFs, thumbnails and video posters until clicked, everywhere.")
    }
}

extension SettingKey where Value == LinkPreviewSize {
    public static var mediaLinkPreviewSize: SettingKey<LinkPreviewSize> {
        .init("media.linkPreviewSize", default: .standard,
              summary: "Link preview size: minimal (one line), standard (title, description and a thumbnail) or large (full card with a large image).")
    }
}

extension SettingKey where Value == VideoEmbedStyle {
    public static var mediaVideos: SettingKey<VideoEmbedStyle> {
        .init("media.videos", default: .player,
              summary: "Video links: player (a large thumbnail that plays in place), compact (one line) or off (shown as a link preview).")
    }
}

extension SettingKey where Value == InlineImageSize {
    public static var mediaImageSize: SettingKey<InlineImageSize> {
        .init("media.imageSize", default: .full,
              summary: "Inline images and GIFs: full (up to media.maxImageHeight) or thumbnail.")
    }
}

extension SettingKey where Value == [String: JSONValue] {
    public static var mediaSiteRules: SettingKey<[String: JSONValue]> {
        .init("media.siteRules", default: [:],
              summary: "Per-site preview rules: domain to \"allow\", \"textOnly\" or \"block\". The most specific domain wins.")
    }
}

extension SettingKey where Value == [String] {
    public static var mediaDisabledBuffers: SettingKey<[String]> {
        .init("media.disabledBuffers", default: [],
              summary: "Buffers without inline media: \"<networkUUID>/<foldedName>\" or \"<networkUUID>/*\".")
    }
    public static var mediaBlurredBuffers: SettingKey<[String]> {
        .init("media.blurredBuffers", default: [],
              summary: "Buffers whose images, GIFs, thumbnails and video posters stay blurred until clicked: \"<networkUUID>/<foldedName>\" or \"<networkUUID>/*\".")
    }
}

extension SettingKey where Value == Double {
    public static var mediaMaxImageSizeMB: SettingKey<Double> {
        .init("media.maxImageSizeMB", default: 10, summary: "Skip auto-loading images and GIFs larger than this many megabytes.")
    }
    public static var mediaMaxImageHeight: SettingKey<Double> {
        .init("media.maxImageHeight", default: 320, summary: "Maximum height of inline images and GIFs, in points.")
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
    public static var inputGrammarCheck: SettingKey<Bool> {
        .init("input.grammarCheck", default: false, summary: "Check grammar while typing (underlines only; nothing is changed for you).")
    }
    public static var inputWritingTools: SettingKey<Bool> {
        .init("input.writingTools", default: true,
              summary: "Offer Apple Intelligence Writing Tools (Proofread, Rewrite) in the message box, where Apple Intelligence is available.")
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

// MARK: Typing (follow macOS)

extension SettingKey where Value == SystemFollowingBool {
    public static var inputAutocorrect: SettingKey<SystemFollowingBool> {
        .init("input.autocorrect", default: .system,
              summary: "Correct spelling automatically. true or false, or \"system\" to follow System Settings → Keyboard. Commands, nicks, channel names, links and code are never changed.")
    }
    public static var inputTextReplacements: SettingKey<SystemFollowingBool> {
        .init("input.textReplacements", default: .system,
              summary: "Use your macOS text replacements. true or false, or \"system\" to follow System Settings → Keyboard.")
    }
    public static var inputSmartPunctuation: SettingKey<SystemFollowingBool> {
        .init("input.smartPunctuation", default: .system,
              summary: "Use smart quotes and dashes. true or false, or \"system\" to follow System Settings → Keyboard. Commands and code are never changed.")
    }
}

// MARK: Apple Intelligence & translation

extension SettingKey where Value == Bool {
    public static var intelligenceCatchUp: SettingKey<Bool> {
        .init("intelligence.catchUp", default: true,
              summary: "Offer \"Catch me up\": an on-device Apple Intelligence summary of what you missed in a busy channel.")
    }
    public static var intelligenceSpotlightChannels: SettingKey<Bool> {
        .init("intelligence.spotlightChannels", default: true,
              summary: "List your channels and conversations in Spotlight. Names only, never messages.")
    }
}

extension SettingKey where Value == Int {
    public static var intelligenceCatchUpThreshold: SettingKey<Int> {
        .init("intelligence.catchUpThreshold", default: 25,
              summary: "Show the Catch me up button when a channel has at least this many new messages.")
    }
}

extension SettingKey where Value == String {
    public static var translationLanguage: SettingKey<String> {
        .init("translation.language", default: "",
              summary: "Language to translate messages into, as a language code such as \"en\" or \"pt-BR\". Empty uses your Mac's language.")
    }
}

extension SettingKey where Value == [String] {
    public static var translationAutoTranslate: SettingKey<[String]> {
        .init("translation.autoTranslate", default: [],
              summary: "Buffers whose messages in other languages are translated automatically: \"<networkUUID>/<foldedName>\" or \"<networkUUID>/*\".")
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
            SettingKey.appearanceMessageBoxBorder.descriptor,
            SettingKey.appearanceAppIcon.descriptor,

            SettingKey.chatLayout.descriptor,
            SettingKey.chatFontFamily.descriptor,
            SettingKey.chatFontSize.descriptor,
            SettingKey.chatMonospaceFontFamily.descriptor,
            SettingKey.chatLineSpacing.descriptor,
            SettingKey.chatMessageSpacing.descriptor,
            SettingKey.chatShowTimestamps.descriptor,
            SettingKey.chatClock.descriptor,
            SettingKey.chatTimestampSeconds.descriptor,
            SettingKey.chatTimestampFormat.descriptor,
            SettingKey.chatShowJoinPart.descriptor,
            SettingKey.chatColorNicks.descriptor,
            SettingKey.chatShowAvatars.descriptor,
            SettingKey.chatGroupingInterval.descriptor,
            SettingKey.chatColumnsNickWidth.descriptor,
            SettingKey.chatRenderFormatting.descriptor,
            SettingKey.chatLargeEmoji.descriptor,
            SettingKey.chatOpenAt.descriptor,
            SettingKey.chatShowUnreadMarker.descriptor,
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
            SettingKey.mediaLinkPreviewSize.descriptor,
            SettingKey.mediaVideos.descriptor,
            SettingKey.mediaImageSize.descriptor,
            SettingKey.mediaRestrictToAllowed.descriptor,
            SettingKey.mediaFilterAdultSites.descriptor,
            SettingKey.mediaBlurImages.descriptor,
            SettingKey.mediaSiteRules.descriptor,
            SettingKey.mediaMaxImageSizeMB.descriptor,
            SettingKey.mediaMaxImageHeight.descriptor,
            SettingKey.mediaDisabledBuffers.descriptor,
            SettingKey.mediaBlurredBuffers.descriptor,

            SettingKey.notifyHighlights.descriptor,
            SettingKey.notifyPrivateMessages.descriptor,
            SettingKey.notifySound.descriptor,
            SettingKey.highlightWords.descriptor,
            SettingKey.inputSendTypingIndicators.descriptor,
            SettingKey.inputSpellCheck.descriptor,
            SettingKey.inputGrammarCheck.descriptor,
            SettingKey.inputAutocorrect.descriptor,
            SettingKey.inputTextReplacements.descriptor,
            SettingKey.inputSmartPunctuation.descriptor,
            SettingKey.inputWritingTools.descriptor,
            SettingKey.connectionAutoReconnect.descriptor,
            SettingKey.historyRetentionDays.descriptor,

            SettingKey.intelligenceCatchUp.descriptor,
            SettingKey.intelligenceCatchUpThreshold.descriptor,
            SettingKey.intelligenceSpotlightChannels.descriptor,
            SettingKey.translationLanguage.descriptor,
            SettingKey.translationAutoTranslate.descriptor,
        ] + NavigationSettingsCatalog.descriptors
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
