// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Contrast checks for a resolved theme, used by `vela-theme-tool check`,
/// the tests, and (later) the theme editor.
public enum ThemeAudit {
    public struct Check: Sendable, Hashable {
        public let foreground: String
        public let background: String
        /// Minimum contrast ratio to pass.
        public let minimum: Double
    }

    public struct Finding: Sendable, Hashable, CustomStringConvertible {
        public let foreground: String
        public let background: String
        public let ratio: Double
        public let minimum: Double
        public var passes: Bool { ratio >= minimum }

        public var description: String {
            String(format: "%@ on %@: %.2f:1 (needs %.1f)", foreground, background, ratio, minimum)
        }
    }

    /// Text-on-surface pairs and the contrast each needs. Body and UI text
    /// aim for WCAG AA (4.5:1); secondary text, events and badges for 3:1;
    /// timestamps, placeholders and away members may be dimmer.
    public static let checks: [Check] = [
        .init(foreground: ThemeKey.chatForeground, background: ThemeKey.chatBackground, minimum: 4.5),
        .init(foreground: ThemeKey.chatForeground, background: ThemeKey.chatHighlightBackground, minimum: 4.5),
        .init(foreground: ThemeKey.chatForeground, background: ThemeKey.chatSelfMessageBackground, minimum: 4.5),
        .init(foreground: ThemeKey.chatSecondaryForeground, background: ThemeKey.chatBackground, minimum: 3),
        .init(foreground: ThemeKey.chatTimestamp, background: ThemeKey.chatBackground, minimum: 2.5),
        .init(foreground: ThemeKey.chatLink, background: ThemeKey.chatBackground, minimum: 4.5),
        .init(foreground: ThemeKey.chatSelfNick, background: ThemeKey.chatBackground, minimum: 4.5),
        .init(foreground: ThemeKey.chatMention, background: ThemeKey.chatHighlightBackground, minimum: 4.5),
        .init(foreground: ThemeKey.chatNotice, background: ThemeKey.chatBackground, minimum: 4.5),
        .init(foreground: ThemeKey.chatAction, background: ThemeKey.chatBackground, minimum: 4.5),
        .init(foreground: ThemeKey.chatError, background: ThemeKey.chatBackground, minimum: 4.5),
        .init(foreground: ThemeKey.chatEvent, background: ThemeKey.chatBackground, minimum: 3),
        .init(foreground: ThemeKey.chatEventJoin, background: ThemeKey.chatBackground, minimum: 3),
        .init(foreground: ThemeKey.chatEventPart, background: ThemeKey.chatBackground, minimum: 3),
        .init(foreground: ThemeKey.chatEventQuit, background: ThemeKey.chatBackground, minimum: 3),
        .init(foreground: ThemeKey.chatServerMessage, background: ThemeKey.chatBackground, minimum: 3),
        .init(foreground: ThemeKey.chatDayDividerForeground, background: ThemeKey.chatBackground, minimum: 3),
        .init(foreground: ThemeKey.chatCodeForeground, background: ThemeKey.chatCodeBackground, minimum: 4.5),
        .init(foreground: ThemeKey.titleBarForeground, background: ThemeKey.titleBarBackground, minimum: 4.5),
        .init(foreground: ThemeKey.titleBarSecondaryForeground, background: ThemeKey.titleBarBackground, minimum: 3),
        .init(foreground: ThemeKey.sidebarForeground, background: ThemeKey.sidebarBackground, minimum: 4.5),
        .init(foreground: ThemeKey.sidebarUnreadForeground, background: ThemeKey.sidebarBackground, minimum: 4.5),
        .init(foreground: ThemeKey.sidebarSecondaryForeground, background: ThemeKey.sidebarBackground, minimum: 3),
        .init(foreground: ThemeKey.sidebarHeaderForeground, background: ThemeKey.sidebarBackground, minimum: 3),
        .init(foreground: ThemeKey.sidebarHighlightForeground, background: ThemeKey.sidebarBackground, minimum: 4.5),
        .init(foreground: ThemeKey.sidebarActiveForeground, background: ThemeKey.sidebarActiveBackground, minimum: 4.5),
        .init(foreground: ThemeKey.sidebarBadgeForeground, background: ThemeKey.sidebarBadgeBackground, minimum: 3),
        .init(foreground: ThemeKey.sidebarHighlightBadgeForeground, background: ThemeKey.sidebarHighlightBadgeBackground, minimum: 3),
        .init(foreground: ThemeKey.railForeground, background: ThemeKey.railBackground, minimum: 3),
        .init(foreground: ThemeKey.inputForeground, background: ThemeKey.inputBackground, minimum: 4.5),
        .init(foreground: ThemeKey.inputPlaceholder, background: ThemeKey.inputBackground, minimum: 2.5),
        .init(foreground: ThemeKey.memberListForeground, background: ThemeKey.memberListBackground, minimum: 4.5),
        .init(foreground: ThemeKey.memberListHeaderForeground, background: ThemeKey.memberListBackground, minimum: 3),
        .init(foreground: ThemeKey.memberListAwayForeground, background: ThemeKey.memberListBackground, minimum: 2.5),
        .init(foreground: ThemeKey.embedTitle, background: ThemeKey.embedBackground, minimum: 4.5),
        .init(foreground: ThemeKey.embedDescription, background: ThemeKey.embedBackground, minimum: 4.5),
        .init(foreground: ThemeKey.embedSiteName, background: ThemeKey.embedBackground, minimum: 3),
        .init(foreground: ThemeKey.reactionForeground, background: ThemeKey.reactionBackground, minimum: 4.5),
        .init(foreground: ThemeKey.reactionForeground, background: ThemeKey.reactionSelfBackground, minimum: 4.5),
        .init(foreground: ThemeKey.replyForeground, background: ThemeKey.chatBackground, minimum: 3),
        .init(foreground: ThemeKey.typingForeground, background: ThemeKey.chatBackground, minimum: 3),
        .init(foreground: ThemeKey.accentForeground, background: ThemeKey.accent, minimum: 4.5),
        .init(foreground: ThemeKey.buttonForeground, background: ThemeKey.buttonBackground, minimum: 4.5),
        .init(foreground: ThemeKey.buttonSecondaryForeground, background: ThemeKey.buttonSecondaryBackground, minimum: 4.5),
        .init(foreground: ThemeKey.popoverForeground, background: ThemeKey.popoverBackground, minimum: 4.5),
        .init(foreground: ThemeKey.settingsForeground, background: ThemeKey.settingsBackground, minimum: 4.5),
        .init(foreground: ThemeKey.settingsSecondaryForeground, background: ThemeKey.settingsBackground, minimum: 3),
    ]

    /// Minimum contrast for nick colors on `chat.background`.
    public static let nickMinimum = 3.0

    /// Runs every check. Translucent backgrounds are composited over the
    /// surface they're drawn on (chat, sidebar or member list). With
    /// vibrancy, a surface on a material is measured as its tint over
    /// `ThemeVibrancy.materialStandIn(for:)`, the least favorable desktop.
    public static func audit(_ theme: ResolvedTheme) -> [Finding] {
        var findings = checks.map { check in
            let background = surface(check.background, in: theme)
            let ratio = theme.color(check.foreground).contrastRatio(against: background)
            return Finding(foreground: check.foreground, background: check.background, ratio: ratio, minimum: check.minimum)
        }
        let chat = surface(ThemeKey.chatBackground, in: theme)
        for (index, color) in theme.nickColors.enumerated() {
            findings.append(Finding(
                foreground: "nickColors[\(index)]",
                background: ThemeKey.chatBackground,
                ratio: color.contrastRatio(against: chat),
                minimum: nickMinimum
            ))
        }
        return findings
    }

    /// The opaque color a (possibly translucent) background token produces.
    static func surface(_ key: String, in theme: ResolvedTheme) -> ThemeColor {
        let color = theme.color(key)
        if let material = materialSurface(key, in: theme) {
            return material
        }
        if let base = ThemeVibrancy.rowTokens[key], let material = materialSurface(base, in: theme) {
            return ThemeVibrancy.tint(color).composited(over: material)
        }
        guard color.alpha < 1 else { return color }
        let base: String = switch key {
        case _ where key.hasPrefix("sidebar."): ThemeKey.sidebarBackground
        case _ where key.hasPrefix("memberList."): ThemeKey.memberListBackground
        case _ where key.hasPrefix("rail."): ThemeKey.railBackground
        case _ where key.hasPrefix("input."): ThemeKey.inputContainerBackground
        case _ where key.hasPrefix("settings."): ThemeKey.settingsBackground
        default: ThemeKey.chatBackground
        }
        if let material = materialSurface(base, in: theme) {
            return color.composited(over: material)
        }
        let window = theme.color(ThemeKey.windowBackground)
        // A translucent surface (sidebar.background, say) is drawn over the window.
        guard base != key else { return color.composited(over: window) }
        let baseColor = theme.color(base)
        return color.composited(over: baseColor.alpha < 1 ? baseColor.composited(over: window) : baseColor)
    }

    /// A surface token that the theme's vibrancy puts on a material, as it
    /// looks over the stand-in for the material; `nil` for anything else.
    private static func materialSurface(_ key: String, in theme: ResolvedTheme) -> ThemeColor? {
        guard let surface = ThemeVibrancy.surfaceTokens[key], theme.vibrancy.material(for: surface) != nil else { return nil }
        return ThemeVibrancy.tint(theme.color(key)).composited(over: ThemeVibrancy.materialStandIn(for: theme.kind))
    }
}
