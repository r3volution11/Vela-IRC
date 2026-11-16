// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// String constants for every token in `ThemeRegistry`, so UI code gets
/// compile-time checked names: `theme[ThemeKey.chatBackground]`.
public enum ThemeKey {
    // Window
    public static let windowBackground = "window.background"
    public static let windowForeground = "window.foreground"
    public static let windowBorder = "window.border"
    public static let paneDivider = "pane.divider"

    // Title bar
    public static let titleBarBackground = "titleBar.background"
    public static let titleBarForeground = "titleBar.foreground"
    public static let titleBarSecondaryForeground = "titleBar.secondaryForeground"
    public static let titleBarBorder = "titleBar.border"

    // Sidebar
    public static let sidebarBackground = "sidebar.background"
    public static let sidebarForeground = "sidebar.foreground"
    public static let sidebarSecondaryForeground = "sidebar.secondaryForeground"
    public static let sidebarHeaderForeground = "sidebar.headerForeground"
    public static let sidebarHoverBackground = "sidebar.hoverBackground"
    public static let sidebarActiveBackground = "sidebar.activeBackground"
    public static let sidebarActiveForeground = "sidebar.activeForeground"
    public static let sidebarUnreadForeground = "sidebar.unreadForeground"
    public static let sidebarHighlightForeground = "sidebar.highlightForeground"
    public static let sidebarBadgeBackground = "sidebar.badgeBackground"
    public static let sidebarBadgeForeground = "sidebar.badgeForeground"
    public static let sidebarHighlightBadgeBackground = "sidebar.highlightBadgeBackground"
    public static let sidebarHighlightBadgeForeground = "sidebar.highlightBadgeForeground"
    public static let sidebarDisconnectedForeground = "sidebar.disconnectedForeground"
    public static let sidebarBorder = "sidebar.border"

    // Rail (collapsed sidebar)
    public static let railBackground = "rail.background"
    public static let railForeground = "rail.foreground"
    public static let railInactiveForeground = "rail.inactiveForeground"
    public static let railActiveBackground = "rail.activeBackground"
    public static let railActiveIndicator = "rail.activeIndicator"
    public static let railBadgeBackground = "rail.badgeBackground"
    public static let railBadgeForeground = "rail.badgeForeground"
    public static let railBorder = "rail.border"

    // Tabs
    public static let tabBarBackground = "tab.barBackground"
    public static let tabBorder = "tab.border"
    public static let tabForeground = "tab.foreground"
    public static let tabUnreadForeground = "tab.unreadForeground"
    public static let tabHighlightForeground = "tab.highlightForeground"
    public static let tabInactiveForeground = "tab.inactiveForeground"
    public static let tabHoverBackground = "tab.hoverBackground"
    public static let tabActiveBackground = "tab.activeBackground"
    public static let tabActiveForeground = "tab.activeForeground"
    public static let tabActiveIndicator = "tab.activeIndicator"
    public static let tabPillBackground = "tab.pillBackground"
    public static let tabPillForeground = "tab.pillForeground"
    public static let tabSeparator = "tab.separator"
    public static let tabServerBackground = "tab.serverBackground"
    public static let tabServerActiveBackground = "tab.serverActiveBackground"
    public static let tabGroupBackground = "tab.groupBackground"

    // Chat
    public static let chatBackground = "chat.background"
    public static let chatForeground = "chat.foreground"
    public static let chatSecondaryForeground = "chat.secondaryForeground"
    public static let chatTimestamp = "chat.timestamp"
    public static let chatLink = "chat.link"
    public static let chatSelfNick = "chat.selfNick"
    public static let chatSelfMessageBackground = "chat.selfMessageBackground"
    public static let chatHighlightBackground = "chat.highlightBackground"
    public static let chatHighlightBorder = "chat.highlightBorder"
    public static let chatMention = "chat.mention"
    public static let chatNotice = "chat.notice"
    public static let chatAction = "chat.action"
    public static let chatEvent = "chat.event"
    public static let chatEventJoin = "chat.event.join"
    public static let chatEventPart = "chat.event.part"
    public static let chatEventQuit = "chat.event.quit"
    public static let chatEventNick = "chat.event.nick"
    public static let chatEventMode = "chat.event.mode"
    public static let chatEventTopic = "chat.event.topic"
    public static let chatError = "chat.error"
    public static let chatServerMessage = "chat.serverMessage"
    public static let chatDayDivider = "chat.dayDivider"
    public static let chatDayDividerForeground = "chat.dayDividerForeground"
    public static let chatUnreadMarker = "chat.unreadMarker"
    public static let chatHoverBackground = "chat.hoverBackground"
    public static let chatSelectionBackground = "chat.selectionBackground"
    public static let chatFindMatchBackground = "chat.findMatchBackground"
    public static let chatCodeBackground = "chat.codeBackground"
    public static let chatCodeForeground = "chat.codeForeground"

    // Input
    public static let inputContainerBackground = "input.containerBackground"
    public static let inputBackground = "input.background"
    public static let inputForeground = "input.foreground"
    public static let inputPlaceholder = "input.placeholder"
    public static let inputBorder = "input.border"
    public static let inputFocusBorder = "input.focusBorder"
    public static let inputIconForeground = "input.iconForeground"

    // Member list
    public static let memberListBackground = "memberList.background"
    public static let memberListForeground = "memberList.foreground"
    public static let memberListHeaderForeground = "memberList.headerForeground"
    public static let memberListPrefixForeground = "memberList.prefixForeground"
    public static let memberListAwayForeground = "memberList.awayForeground"
    public static let memberListHoverBackground = "memberList.hoverBackground"
    public static let memberListBorder = "memberList.border"

    // Embeds
    public static let embedBackground = "embed.background"
    public static let embedBorder = "embed.border"
    public static let embedAccent = "embed.accent"
    public static let embedTitle = "embed.title"
    public static let embedDescription = "embed.description"
    public static let embedSiteName = "embed.siteName"
    public static let embedPlaceholderBackground = "embed.placeholderBackground"

    // Reactions, replies, typing
    public static let reactionBackground = "reaction.background"
    public static let reactionForeground = "reaction.foreground"
    public static let reactionBorder = "reaction.border"
    public static let reactionSelfBackground = "reaction.selfBackground"
    public static let reactionSelfBorder = "reaction.selfBorder"
    public static let replyQuoteBar = "reply.quoteBar"
    public static let replyForeground = "reply.foreground"
    public static let replyBackground = "reply.background"
    public static let typingForeground = "typing.foreground"

    // Controls
    public static let accent = "accent"
    public static let accentText = "accentText"
    public static let accentForeground = "accentForeground"
    public static let focusBorder = "focusBorder"
    public static let buttonBackground = "button.background"
    public static let buttonForeground = "button.foreground"
    public static let buttonHoverBackground = "button.hoverBackground"
    public static let buttonSecondaryBackground = "button.secondaryBackground"
    public static let buttonSecondaryForeground = "button.secondaryForeground"
    public static let scrollbarThumb = "scrollbar.thumb"
    public static let scrollbarThumbHover = "scrollbar.thumbHover"
    public static let popoverBackground = "popover.background"
    public static let popoverForeground = "popover.foreground"
    public static let popoverBorder = "popover.border"

    // Status
    public static let statusSuccess = "status.success"
    public static let statusWarning = "status.warning"
    public static let statusError = "status.error"

    // Settings window
    public static let settingsBackground = "settings.background"
    public static let settingsSidebarBackground = "settings.sidebarBackground"
    public static let settingsForeground = "settings.foreground"
    public static let settingsSecondaryForeground = "settings.secondaryForeground"
    public static let settingsBorder = "settings.border"
    public static let settingsControlBackground = "settings.controlBackground"
}
