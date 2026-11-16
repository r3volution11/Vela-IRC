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
    public var timestampFormat = "HH:mm"
    public var joinPart: JoinPartDisplay = .collapse
    public var colorNicks = true
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
    public var mediaPresentation: MediaPresentation = .full

    // Navigation
    public var navigationStyle: NavigationStyle = .sidebar
    public var tabPlacement: TabStackPlacement = .top
    public var tabRoundness: Double = 0.35
    public var tabHeight: Double = 28
    public var serverTabRow: ServerTabRowMode = .auto
    public var tabsShowUnreadBadges = true
    public var tabsShowCloseButtons = true

    public init() {}

    /// Corner radius for a tab of `height`, from square (0) to pill (1).
    public func tabCornerRadius(forHeight height: Double) -> Double {
        max(0, min(1, tabRoundness)) * height / 2
    }

    @MainActor
    public init(settings: SettingsStore) {
        layout = settings[.chatLayout]
        fontFamily = settings[.chatFontFamily]
        fontSize = settings[.chatFontSize]
        monospaceFontFamily = settings[.chatMonospaceFontFamily]
        lineSpacing = settings[.chatLineSpacing]
        messageSpacing = settings[.chatMessageSpacing]
        showTimestamps = settings[.chatShowTimestamps]
        timestampFormat = settings[.chatTimestampFormat]
        joinPart = settings[.chatShowJoinPart]
        colorNicks = settings[.chatColorNicks]
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
        mediaPresentation = settings[.mediaPresentation]
        navigationStyle = settings[.navigationStyle]
        tabPlacement = settings[.tabsPlacement]
        tabRoundness = settings[.tabsRoundness]
        tabHeight = settings[.tabsHeight]
        serverTabRow = settings[.tabsServerRow]
        tabsShowUnreadBadges = settings[.tabsShowUnreadBadges]
        tabsShowCloseButtons = settings[.tabsShowCloseButtons]
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

    public func timestamp(_ date: Date) -> String {
        Self.formatter(for: timestampFormat).string(from: date)
    }

    @MainActor private static var formatters: [String: DateFormatter] = [:]

    @MainActor
    private static func formatter(for format: String) -> DateFormatter {
        if let cached = formatters[format] { return cached }
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatters[format] = formatter
        return formatter
    }
}
