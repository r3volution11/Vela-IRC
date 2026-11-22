// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaStore

/// Every user-tunable aspect of how chat renders, resolved from settings.json.
/// Views read it from `@Environment(\.chatStyle)`.
public struct ChatStyle: Equatable {
    public var layout: ChatLayout = .grouped
    public var fontFamily: String = ""
    public var fontSize: Double = 13
    public var monospaceFontFamily: String = "SF Mono"
    public var lineSpacing: Double = 2
    public var messageSpacing: Double = 6
    public var showTimestamps = true
    /// The Unicode date pattern timestamps are drawn with: the custom
    /// `chat.timestampFormat`, or one derived from `chat.clock` and
    /// `chat.timestampSeconds` (see ``TimestampFormat``).
    public var timestampPattern = TimestampFormat.pattern(clock: .system, seconds: false, locale: .autoupdatingCurrent)
    /// Language and region timestamps are written in (AM/PM symbols).
    public var timestampLocaleIdentifier = Locale.autoupdatingCurrent.identifier
    /// Where each layout draws times (`chat.timestampPosition.*`).
    public var classicTimestampPosition: TimestampPosition = .left
    public var groupedTimestampPosition: TimestampPosition = .top
    public var columnsTimestampPosition: TimestampPosition = .left
    public var joinPart: JoinPartDisplay = .collapse
    public var colorNicks = true
    /// Color the nicks of people here where messages mention them
    /// (`chat.colorNicksInText`); only with `colorNicks`.
    public var colorNicksInText = true
    public var showAvatars = false
    public var groupingInterval: TimeInterval = 300
    public var columnsNickWidth: Double = 120
    public var renderFormatting = true
    public var largeEmoji = true
    public var maxImageHeight: Double = 320
    public var sidebarRowHeight: Double = 22
    public var sidebarFontSize: Double = 12
    public var sidebarShowUnreadCounts = true
    /// Render chat text in the monospace font (Classic preset).
    public var monospace = false
    /// Where a channel with unread messages opens (`chat.openAt`).
    public var openAt: ChatOpenPosition = .firstUnread
    /// Draw the New line above the first unread message (`chat.showUnreadMarker`).
    public var showUnreadMarker = true

    // Navigation
    public var navigationStyle: NavigationStyle = .sidebar
    public var tabPlacement: TabStackPlacement = .top
    public var tabRoundness: Double = 0.35
    public var tabHeight: Double = 28
    public var serverTabRow: ServerTabRowMode = .auto
    public var tabsShowUnreadBadges = true
    public var tabsShowCloseButtons = true

    /// How much of a row's padding goes under its text rather than over it
    /// for the two to look the same: a font has more room over its lowercase
    /// letters (ascender above the x-height) than under its baseline
    /// (descender), so equal padding looks low. Half the difference, from
    /// `bodyNSFont`; set with the fonts (`init(settings:)`).
    public var rowOpticalShift: CGFloat = ChatStyle.opticalShift(for: .systemFont(ofSize: 13))

    public init() {}

    static func opticalShift(for font: NSFont) -> CGFloat {
        let above = font.ascender - font.xHeight
        let below = -font.descender
        return max(0, (above - below) / 2)
    }

    /// Corner radius for a tab of `height`, from square (0) to pill (1).
    public func tabCornerRadius(forHeight height: Double) -> Double {
        max(0, min(1, tabRoundness)) * height / 2
    }

    /// `locale` resolves the System clock; with the default, a new style
    /// picks up changes to the Mac's 24-hour time setting.
    @MainActor
    public init(settings: SettingsStore, locale: Locale = .autoupdatingCurrent) {
        layout = settings[.chatLayout]
        fontFamily = settings[.chatFontFamily]
        fontSize = settings[.chatFontSize]
        monospaceFontFamily = settings[.chatMonospaceFontFamily]
        lineSpacing = settings[.chatLineSpacing]
        messageSpacing = settings[.chatMessageSpacing]
        showTimestamps = settings[.chatShowTimestamps]
        timestampPattern = TimestampFormat.pattern(
            clock: settings[.chatClock],
            seconds: settings[.chatTimestampSeconds],
            custom: settings[.chatTimestampFormat],
            locale: locale
        )
        timestampLocaleIdentifier = locale.identifier
        classicTimestampPosition = settings[.chatTimestampPositionClassic]
        groupedTimestampPosition = settings[.chatTimestampPositionGrouped]
        columnsTimestampPosition = settings[.chatTimestampPositionColumns]
        joinPart = settings[.chatShowJoinPart]
        colorNicks = settings[.chatColorNicks]
        colorNicksInText = settings[.chatColorNicksInText]
        showAvatars = settings[.chatShowAvatars]
        groupingInterval = settings[.chatGroupingInterval]
        columnsNickWidth = settings[.chatColumnsNickWidth]
        renderFormatting = settings[.chatRenderFormatting]
        largeEmoji = settings[.chatLargeEmoji]
        maxImageHeight = settings[.mediaMaxImageHeight]
        sidebarRowHeight = settings[.sidebarRowHeight]
        sidebarFontSize = settings[.sidebarFontSize]
        sidebarShowUnreadCounts = settings[.sidebarShowUnreadCounts]
        monospace = settings[.chatMonospace]
        openAt = settings[.chatOpenAt]
        showUnreadMarker = settings[.chatShowUnreadMarker]
        navigationStyle = settings[.navigationStyle]
        tabPlacement = settings[.tabsPlacement]
        tabRoundness = settings[.tabsRoundness]
        tabHeight = settings[.tabsHeight]
        serverTabRow = settings[.tabsServerRow]
        tabsShowUnreadBadges = settings[.tabsShowUnreadBadges]
        tabsShowCloseButtons = settings[.tabsShowCloseButtons]
        rowOpticalShift = Self.opticalShift(for: bodyNSFont)
    }

    // MARK: Fonts

    /// The main chat font (system font when `fontFamily` is empty).
    public var bodyFont: Font { font(size: fontSize) }

    public func font(size: Double, weight: Font.Weight = .regular) -> Font {
        if monospace {
            return monospaceFont(size: size).weight(weight)
        }
        if fontFamily.isEmpty {
            return .system(size: size, weight: weight)
        }
        return .custom(fontFamily, size: size).weight(weight)
    }

    public var monospaceFont: Font { monospaceFont(size: fontSize) }

    public func monospaceFont(size: Double) -> Font {
        if monospaceFontFamily.isEmpty || monospaceFontFamily == "SF Mono" {
            return .system(size: size, design: .monospaced)
        }
        return .custom(monospaceFontFamily, size: size)
    }

    public var nickFont: Font { font(size: fontSize, weight: .semibold) }
    public var metaFont: Font { font(size: max(9, fontSize - 2)) }
    public var timestampFont: Font { .system(size: max(9, fontSize - 2)).monospacedDigit() }

    /// AppKit font matching `bodyFont`, for text views and measurements.
    public var bodyNSFont: NSFont {
        if monospace {
            if monospaceFontFamily.isEmpty || monospaceFontFamily == "SF Mono" {
                return .monospacedSystemFont(ofSize: fontSize, weight: .regular)
            }
            if let font = NSFont(name: monospaceFontFamily, size: fontSize) { return font }
        }
        if !fontFamily.isEmpty, let font = NSFont(name: fontFamily, size: fontSize) { return font }
        return .systemFont(ofSize: fontSize)
    }

    // MARK: Timestamps

    /// Where `layout` draws times.
    public func timestampPosition(for layout: ChatLayout) -> TimestampPosition {
        switch layout {
        case .classic: classicTimestampPosition
        case .grouped: groupedTimestampPosition
        case .columns: columnsTimestampPosition
        }
    }

    /// Where the current layout draws times.
    public var timestampPosition: TimestampPosition { timestampPosition(for: layout) }

    public func timestamp(_ date: Date) -> String {
        Self.formatter(pattern: timestampPattern, localeIdentifier: timestampLocaleIdentifier).string(from: date)
    }

    private struct FormatterKey: Hashable {
        var pattern: String
        var localeIdentifier: String
    }

    /// Keyed by locale and pattern, so a changed clock or 24-hour setting
    /// gets a fresh formatter instead of reusing the old one.
    @MainActor private static var formatters: [FormatterKey: DateFormatter] = [:]
    /// The last one used: rows ask for times several at a time, nearly
    /// always in the same format.
    @MainActor private static var lastFormatter: (key: FormatterKey, formatter: DateFormatter)?

    @MainActor
    private static func formatter(pattern: String, localeIdentifier: String) -> DateFormatter {
        let key = FormatterKey(pattern: pattern, localeIdentifier: localeIdentifier)
        if let lastFormatter, lastFormatter.key == key { return lastFormatter.formatter }
        let formatter: DateFormatter
        if let cached = formatters[key] {
            formatter = cached
        } else {
            // Typing a custom pattern creates one per keystroke; don't keep them all.
            if formatters.count >= 16 { formatters.removeAll() }
            formatter = TimestampFormat.formatter(pattern: pattern, locale: Locale(identifier: localeIdentifier))
            formatters[key] = formatter
        }
        lastFormatter = (key, formatter)
        return formatter
    }
}
