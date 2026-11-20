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

/// Where message times are drawn. Each layout keeps its own
/// (`chat.timestampPosition.classic`, `.grouped` and `.columns`).
public enum TimestampPosition: String, Codable, Sendable, CaseIterable, SettingValueConvertible {
    /// Before the message: the time column in classic and columns, the
    /// margin beside the text in grouped.
    case left
    /// At the right edge, level with the message's first line.
    case right
    /// Above the message; in grouped, beside the name.
    case top
    /// Below the message.
    case bottom
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

/// A kind of unread message the Dock badge counts (`dock.badgeCounts`).
/// The badge shows the total of the kinds chosen, counting each message
/// once: a mention in a channel counts once even with both `mentions` and
/// `channels` chosen. Muted channels and conversations never count.
public enum DockBadgeCount: String, Codable, Sendable, CaseIterable, SettingValueConvertible {
    /// Messages in channels that mention your nick or a highlight word.
    case mentions
    /// Messages in private conversations.
    case privateMessages
    /// Every message in channels, mentions included.
    case channels
}

/// How the Dock badge shows its count (`dock.badgeStyle`).
public enum DockBadgeStyle: String, Codable, Sendable, CaseIterable, SettingValueConvertible {
    /// The number, up to 99; more shows as "99+".
    case capped
    /// The exact number.
    case exact
    /// A dot (•) instead of a number.
    case dot
}

/// Whether and how long the Dock icon bounces for new messages while
/// Vela is in the background (`dock.bounce`).
public enum DockBounceStyle: String, Codable, Sendable, CaseIterable, SettingValueConvertible {
    case off
    /// Bounce once for each message.
    case once
    /// Keep bouncing until you switch to Vela.
    case untilActive
}

/// A kind of message that bounces the Dock icon (`dock.bounceFor`).
public enum DockBounceTrigger: String, Codable, Sendable, CaseIterable, SettingValueConvertible {
    /// Messages in channels that mention your nick or a highlight word.
    case mentions
    /// Messages in private conversations.
    case privateMessages
}

/// The mask Ban, Kick + Ban, Quiet and `/ban` use for someone, built from
/// their `nick!user@host` (`moderation.banMask`). Written in settings.json
/// as the mask's shape.
public enum BanMaskStyle: String, Codable, Sendable, CaseIterable, SettingValueConvertible {
    /// Anyone from their host, whatever their nick or user name.
    case host = "*!*@host"
    /// Their user name at their host.
    case userHost = "*!user@host"
    /// Their nick, from anywhere.
    case nick = "nick!*@*"
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

extension SettingKey where Value == TimestampPosition {
    public static var chatTimestampPositionClassic: SettingKey<TimestampPosition> {
        .init("chat.timestampPosition.classic", default: .left,
              summary: "Where times go in the classic layout: left (before the nick), right (at the right edge, level with the first line), top (on a small line above each message) or bottom (on a small line below it).")
    }
    public static var chatTimestampPositionGrouped: SettingKey<TimestampPosition> {
        .init("chat.timestampPosition.grouped", default: .top,
              summary: "Where times go in the grouped layout: top (beside the name), left (in the margin beside the text), right (at the right edge of the name line) or bottom (below the group's first message). Only a group's first message shows its time; hover the others to see theirs.")
    }
    public static var chatTimestampPositionColumns: SettingKey<TimestampPosition> {
        .init("chat.timestampPosition.columns", default: .left,
              summary: "Where times go in the columns layout: left (the time column before the nicks), right (a time column at the right edge), top (on a small line above the text) or bottom (on a small line below it).")
    }

    /// The timestamp position key for `layout`.
    public static func chatTimestampPosition(for layout: ChatLayout) -> SettingKey<TimestampPosition> {
        switch layout {
        case .classic: .chatTimestampPositionClassic
        case .grouped: .chatTimestampPositionGrouped
        case .columns: .chatTimestampPositionColumns
        }
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
    public static var mediaBrowserFallback: SettingKey<Bool> {
        .init("media.browserFallback", default: true,
              summary: "When a site answers with a bot check instead of the page, load it in a private Safari engine session (WebKit, thrown away afterwards; the page's scripts run) to read its title, description and image.")
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
    public static var channelsConfirmLeave: SettingKey<Bool> {
        .init("channels.confirmLeave", default: true,
              summary: "Ask before leaving a channel from its tab, its menu or the command palette. A channel you leave stays in the list so you can join it again. /part never asks.")
    }
    public static var channelsConfirmRemove: SettingKey<Bool> {
        .init("channels.confirmRemove", default: true,
              summary: "Ask before removing a channel from its tab, its menu or the command palette. Removing takes it out of the list and off its network's auto-join list; File → Recently Closed brings it back. /close never asks.")
    }
}

// MARK: Moderation

extension SettingKey where Value == BanMaskStyle {
    public static var moderationBanMask: SettingKey<BanMaskStyle> {
        .init("moderation.banMask", default: .host,
              summary: "The mask Ban, Kick + Ban, Quiet and /ban use for a nick: \"*!*@host\" (anyone from their host), \"*!user@host\" (their user name at their host) or \"nick!*@*\" (their nick, from anywhere). When Vela doesn't know someone's host it asks the server, and uses nick!*@* if it can't find out.")
    }
}

extension SettingKey where Value == String {
    public static var moderationKickReason: SettingKey<String> {
        .init("moderation.kickReason", default: "",
              summary: "The reason Kick and Kick + Ban give, and /kick and /kickban when you don't type one. Empty gives none, and most servers then show your nick as the reason.")
    }
}

// MARK: Dock

extension SettingKey where Value == Bool {
    public static var dockShowBadge: SettingKey<Bool> {
        .init("dock.showBadge", default: true,
              summary: "Show a badge on the Dock icon counting unread messages; dock.badgeCounts chooses which.")
    }
    public static var dockShowOffline: SettingKey<Bool> {
        .init("dock.showOffline", default: true,
              summary: "Draw a small offline mark on the Dock icon while a network Vela should be connected to has been disconnected for more than about 10 seconds. Networks you disconnect yourself don't count.")
    }
}

extension SettingKey where Value == [DockBadgeCount] {
    public static var dockBadgeCounts: SettingKey<[DockBadgeCount]> {
        .init("dock.badgeCounts", default: [.mentions, .privateMessages],
              summary: "What the Dock badge counts, in any combination: mentions (unread channel messages with your nick or a highlight word), privateMessages (unread messages in private conversations) and channels (every unread channel message). Each message counts once, and muted channels and conversations never count.")
    }
}

extension SettingKey where Value == DockBadgeStyle {
    public static var dockBadgeStyle: SettingKey<DockBadgeStyle> {
        .init("dock.badgeStyle", default: .capped,
              summary: "How the Dock badge shows its count: capped (the number, with 99+ for more), exact (the exact number) or dot (a dot instead of a number).")
    }
}

extension SettingKey where Value == DockBounceStyle {
    public static var dockBounce: SettingKey<DockBounceStyle> {
        .init("dock.bounce", default: .off,
              summary: "Bounce the Dock icon for the messages in dock.bounceFor while Vela is in the background: off, once (once for each message) or untilActive (until you switch to Vela). Muted channels and conversations never bounce it.")
    }
}

extension SettingKey where Value == [DockBounceTrigger] {
    public static var dockBounceFor: SettingKey<[DockBounceTrigger]> {
        .init("dock.bounceFor", default: [.mentions, .privateMessages],
              summary: "Which messages bounce the Dock icon when dock.bounce is on: mentions (your nick or a highlight word in a channel) and privateMessages.")
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

// MARK: Chat logs

extension SettingKey where Value == Bool {
    public static var loggingEnabled: SettingKey<Bool> {
        .init("logging.enabled", default: false,
              summary: "Save plain-text chat logs: one folder per network, one file per channel or conversation, holding only what was written (no previews, embeds or translations). The folder is chosen in Settings → Messages → Chat logs.")
    }
    public static var loggingIncludeEvents: SettingKey<Bool> {
        .init("logging.includeEvents", default: true,
              summary: "Also log joins, parts, quits, nick changes, kicks, topic changes and mode changes.")
    }
    public static var loggingIncludeServer: SettingKey<Bool> {
        .init("logging.includeServer", default: false,
              summary: "Also log each network's server messages (connection messages, the MOTD, notices from services) in server.log.")
    }
}

extension SettingKey where Value == Int {
    public static var loggingMaxFileSizeMB: SettingKey<Int> {
        .init("logging.maxFileSizeMB", default: 10,
              summary: "Start a new log file when one reaches this many megabytes. The full file is renamed with the dates it covers.")
    }
    public static var loggingKeepFiles: SettingKey<Int> {
        .init("logging.keepFiles", default: 5,
              summary: "Log files to keep per channel or conversation, counting the current one; older ones are deleted when a new file starts. 0 keeps every file.")
    }
}

extension SettingKey where Value == [String] {
    public static var loggingExcludedBuffers: SettingKey<[String]> {
        .init("logging.excludedBuffers", default: [],
              summary: "Buffers that are never logged: \"<networkUUID>/<foldedName>\" or \"<networkUUID>/*\".")
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
              summary: "Offer \"Catch me up\": an on-device Apple Intelligence summary of what you missed in a busy channel. Off hides it everywhere: the button on the New line, the right-click menu, the command palette and Siri.")
    }
    public static var intelligenceSpotlightChannels: SettingKey<Bool> {
        .init("intelligence.spotlightChannels", default: true,
              summary: "List your channels and conversations in Spotlight's results. Names only, never messages. Siri finds them by name either way.")
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
            SettingKey.chatTimestampPositionClassic.descriptor,
            SettingKey.chatTimestampPositionGrouped.descriptor,
            SettingKey.chatTimestampPositionColumns.descriptor,
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
            SettingKey.mediaBrowserFallback.descriptor,
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
            SettingKey.dockShowBadge.descriptor,
            SettingKey.dockBadgeCounts.descriptor,
            SettingKey.dockBadgeStyle.descriptor,
            SettingKey.dockShowOffline.descriptor,
            SettingKey.dockBounce.descriptor,
            SettingKey.dockBounceFor.descriptor,
            SettingKey.highlightWords.descriptor,
            SettingKey.inputSendTypingIndicators.descriptor,
            SettingKey.inputSpellCheck.descriptor,
            SettingKey.inputGrammarCheck.descriptor,
            SettingKey.inputAutocorrect.descriptor,
            SettingKey.inputTextReplacements.descriptor,
            SettingKey.inputSmartPunctuation.descriptor,
            SettingKey.inputWritingTools.descriptor,
            SettingKey.connectionAutoReconnect.descriptor,
            SettingKey.channelsConfirmLeave.descriptor,
            SettingKey.channelsConfirmRemove.descriptor,
            SettingKey.moderationBanMask.descriptor,
            SettingKey.moderationKickReason.descriptor,
            SettingKey.historyRetentionDays.descriptor,
            SettingKey.loggingEnabled.descriptor,
            SettingKey.loggingMaxFileSizeMB.descriptor,
            SettingKey.loggingKeepFiles.descriptor,
            SettingKey.loggingIncludeEvents.descriptor,
            SettingKey.loggingIncludeServer.descriptor,
            SettingKey.loggingExcludedBuffers.descriptor,

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
