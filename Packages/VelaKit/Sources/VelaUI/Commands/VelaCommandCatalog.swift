// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaStore
import VelaTheme

/// What commands act on. Menu item views and the palette build one from
/// their environment.
struct VelaCommandContext {
    let app: AppModel
    let themeStore: ThemeStore
    let uiState: UIState
    let openWindow: OpenWindowAction
    let openSettings: OpenSettingsAction
}

/// Every command Vela offers, built from the current state. Menus pick the
/// ones they show by name; the palette lists ``all``.
///
/// Reading a command reads the observable state behind its title, enabled
/// and checked state, so a menu view that builds commands in `body` stays
/// current.
struct VelaCommandCatalog {
    let context: VelaCommandContext

    init(_ context: VelaCommandContext) {
        self.context = context
    }

    private var app: AppModel { context.app }
    private var settings: SettingsStore { context.app.settings }
    private var uiState: UIState { context.uiState }

    // MARK: Shortcuts

    /// Every shortcut Vela binds, in one place so conflicts are easy to spot.
    /// Avoids the standard macOS ones (⌘H, ⌘M, ⌥⌘M, ⌘W, ⌘Q, ⌘,, ⌘`, ⌥⌘T…).
    enum Shortcuts {
        static let commandPalette = KeyboardShortcut("p", modifiers: [.command, .shift])
        static let goToConversation = KeyboardShortcut("p", modifiers: .command)
        /// Also opens "Go to Conversation…" (handled by `PaletteHotKeys`; a
        /// menu item can carry only one shortcut).
        static let goToConversationAlternate = KeyboardShortcut("k", modifiers: .command)
        static let selectTheme = KeyboardShortcut("t", modifiers: [.control, .command])
        static let toggleSidebar = KeyboardShortcut("s", modifiers: [.control, .command])
        static let toggleMemberList = KeyboardShortcut("m", modifiers: [.command, .shift])
        static let addNetwork = KeyboardShortcut("n", modifiers: [.command, .shift])
        static let joinChannel = KeyboardShortcut("j", modifiers: .command)
        static let previousBuffer = KeyboardShortcut(.upArrow, modifiers: [.option, .command])
        static let nextBuffer = KeyboardShortcut(.downArrow, modifiers: [.option, .command])
        static let previousUnread = KeyboardShortcut(.upArrow, modifiers: [.shift, .option, .command])
        static let nextUnread = KeyboardShortcut(.downArrow, modifiers: [.shift, .option, .command])
        static let focusInput = KeyboardShortcut("l", modifiers: .command)
        static let textBigger = KeyboardShortcut("+", modifiers: .command)
        static let textSmaller = KeyboardShortcut("-", modifiers: .command)
        static let textActualSize = KeyboardShortcut("0", modifiers: .command)
        /// Owned by the system's Settings… item; shown in the palette.
        static let settings = KeyboardShortcut(",", modifiers: .command)
    }

    // MARK: Palette

    /// Opens the palette in `mode`, or closes it when it's already showing
    /// that mode (pressing the shortcut again toggles, like Spotlight).
    static func togglePalette(_ mode: CommandPaletteMode, uiState: UIState, openWindow: OpenWindowAction) {
        if uiState.commandPalette == mode {
            uiState.commandPalette = nil
            return
        }
        uiState.commandPalette = mode
        // The palette lives in the main window; bring it forward when the
        // shortcut is used from Settings or the theme editor.
        openWindow(id: WindowID.main)
    }

    var commandPalette: VelaCommand {
        VelaCommand(
            id: "view.commandPalette", category: .view, title: "Command Palette…",
            shortcut: Shortcuts.commandPalette, showsInPalette: false
        ) { [context] in
            Self.togglePalette(.commands, uiState: context.uiState, openWindow: context.openWindow)
        }
    }

    var goToConversation: VelaCommand {
        VelaCommand(
            id: "go.conversation", category: .go, title: "Go to Conversation…",
            shortcut: Shortcuts.goToConversation,
            keywords: ["quick open", "switch", "channel", "buffer", "jump"]
        ) { [context] in
            Self.togglePalette(.buffers, uiState: context.uiState, openWindow: context.openWindow)
        }
    }

    // MARK: View

    var toggleSidebar: VelaCommand {
        let collapsed = settings[.sidebarCollapsed]
        let settings = settings
        return VelaCommand(
            id: "view.toggleSidebar", category: .view, title: "Toggle Sidebar",
            menuTitle: collapsed ? "Expand Sidebar" : "Collapse Sidebar",
            shortcut: Shortcuts.toggleSidebar,
            keywords: ["rail", "collapse", "expand"],
            isEnabled: settings[.navigationStyle] == .sidebar
        ) {
            settings[.sidebarCollapsed].toggle()
        }
    }

    var toggleMemberList: VelaCommand {
        let visible = settings[.memberListVisible]
        let settings = settings
        return VelaCommand(
            id: "view.toggleMemberList", category: .view, title: "Toggle Member List",
            menuTitle: visible ? "Hide Member List" : "Show Member List",
            shortcut: Shortcuts.toggleMemberList,
            keywords: ["nick list", "user list", "people", "members"]
        ) {
            settings[.memberListVisible].toggle()
        }
    }

    var toggleFullScreen: VelaCommand {
        VelaCommand(
            id: "view.toggleFullScreen", category: .view, title: "Toggle Full Screen",
            keywords: ["maximize", "zoom"]
        ) {
            (NSApp.mainWindow ?? NSApp.keyWindow)?.toggleFullScreen(nil)
        }
    }

    // MARK: Navigation & tabs

    var navigationStyles: [VelaCommand] {
        let current = settings[.navigationStyle]
        let settings = settings
        return [
            VelaCommand(
                id: "navigation.sidebar", category: .navigation, title: "Use Sidebar",
                menuTitle: "Sidebar", keywords: ["tree"], isChecked: current == .sidebar
            ) { settings[.navigationStyle] = .sidebar },
            VelaCommand(
                id: "navigation.tabs", category: .navigation, title: "Use Tabs",
                menuTitle: "Tabs", keywords: ["tab stacks"], isChecked: current == .tabs
            ) { settings[.navigationStyle] = .tabs },
        ]
    }

    var tabPlacements: [VelaCommand] {
        let usesTabs = settings[.navigationStyle] == .tabs
        let current = settings[.tabsPlacement]
        let settings = settings
        func command(_ placement: TabStackPlacement, _ id: String, _ title: String, _ menuTitle: String) -> VelaCommand {
            VelaCommand(
                id: "tabs.\(id)", category: .tabs, title: title, menuTitle: menuTitle,
                keywords: ["placement", "position"],
                isChecked: usesTabs && current == placement
            ) {
                settings[.tabsPlacement] = placement
                settings[.navigationStyle] = .tabs
            }
        }
        return [
            command(.top, "moveToTop", "Move to Top", "Tabs at Top"),
            command(.titleBar, "moveToTitleBar", "Move to Title Bar", "Tabs in Title Bar"),
            command(.bottom, "moveToBottom", "Move to Bottom", "Tabs at Bottom"),
        ]
    }

    var toggleServerTabRow: VelaCommand {
        let always = settings[.tabsServerRow] == .always
        let settings = settings
        return VelaCommand(
            id: "tabs.toggleServerRow", category: .tabs, title: "Always Show Server Row",
            keywords: ["networks"], isChecked: always
        ) {
            settings[.tabsServerRow] = always ? .auto : .always
        }
    }

    // MARK: Layout & presets

    var chatLayouts: [VelaCommand] {
        let current = settings[.chatLayout]
        let settings = settings
        func command(_ layout: ChatLayout, _ title: String, keywords: [String]) -> VelaCommand {
            VelaCommand(
                id: "layout.\(layout.rawValue)", category: .layout, title: title,
                keywords: ["message layout"] + keywords, isChecked: current == layout
            ) { settings[.chatLayout] = layout }
        }
        return [
            command(.classic, "Classic", keywords: ["irc", "one line"]),
            command(.grouped, "Modern Grouped", keywords: ["slack", "discord"]),
            command(.columns, "Compact Columns", keywords: ["aligned"]),
        ]
    }

    var presets: [VelaCommand] {
        let matching = settings.matchingPreset()?.id
        let settings = settings
        return SettingsPreset.all.map { preset in
            VelaCommand(
                id: "preset.\(preset.id)", category: .preset, title: preset.name,
                keywords: ["configuration", "setup"], isChecked: matching == preset.id
            ) { settings.apply(preset) }
        }
    }

    // MARK: Chat & media

    var chatToggles: [VelaCommand] {
        let settings = settings
        func toggle(_ id: String, _ title: String, _ key: SettingKey<Bool>, keywords: [String] = []) -> VelaCommand {
            VelaCommand(
                id: "chat.\(id)", category: .chat, title: title, keywords: keywords, isChecked: settings[key]
            ) { settings[key].toggle() }
        }
        return [
            toggle("toggleTimestamps", "Toggle Timestamps", .chatShowTimestamps, keywords: ["time"]),
            toggle("toggleMonospace", "Toggle Monospace Font", .chatMonospace, keywords: ["terminal", "fixed width"]),
            toggle("toggleNickColors", "Toggle Nick Colors", .chatColorNicks, keywords: ["nickname"]),
            toggle("toggleAvatars", "Toggle Avatars", .chatShowAvatars, keywords: ["initials"]),
            toggle("toggleFormatting", "Toggle mIRC Formatting", .chatRenderFormatting, keywords: ["colors", "bold"]),
        ]
    }

    var joinPartModes: [VelaCommand] {
        let current = settings[.chatShowJoinPart]
        let settings = settings
        func command(_ mode: JoinPartDisplay, _ title: String) -> VelaCommand {
            VelaCommand(
                id: "chat.joinPart.\(mode.rawValue)", category: .chat, title: title,
                keywords: ["join", "part", "quit", "events", "noise"], isChecked: current == mode
            ) { settings[.chatShowJoinPart] = mode }
        }
        return [
            command(.show, "Show Join/Part Messages"),
            command(.collapse, "Collapse Join/Part Messages"),
            command(.hide, "Hide Join/Part Messages"),
        ]
    }

    var mediaCommands: [VelaCommand] { Self.mediaCommands(settings) }

    /// Static so tests can build them from a bare settings store.
    static func mediaCommands(_ settings: SettingsStore) -> [VelaCommand] {
        let linkSize = settings[.mediaLinkPreviewSize]
        let videos = settings[.mediaVideos]
        let imageSize = settings[.mediaImageSize]
        func link(_ size: LinkPreviewSize, _ title: String, keywords: [String]) -> VelaCommand {
            VelaCommand(
                id: "media.links.\(size.rawValue)", category: .media, title: title,
                keywords: ["link cards", "embeds", "size"] + keywords, isChecked: linkSize == size
            ) { settings[.mediaLinkPreviewSize] = size }
        }
        func video(_ style: VideoEmbedStyle, _ title: String, keywords: [String]) -> VelaCommand {
            VelaCommand(
                id: "media.videos.\(style.rawValue)", category: .media, title: title,
                keywords: ["youtube", "vimeo", "embeds"] + keywords, isChecked: videos == style
            ) { settings[.mediaVideos] = style }
        }
        func image(_ size: InlineImageSize, _ title: String, keywords: [String]) -> VelaCommand {
            VelaCommand(
                id: "media.images.\(size.rawValue)", category: .media, title: title,
                keywords: ["photos", "size"] + keywords, isChecked: imageSize == size
            ) { settings[.mediaImageSize] = size }
        }
        return [
            // The id predates the title: this switches every automatic
            // preview, not just images.
            VelaCommand(
                id: "media.toggleAutoLoad", category: .media, title: "Load Previews Automatically",
                keywords: ["toggle", "inline images", "pictures", "auto"], isChecked: settings[.mediaAutoLoad]
            ) { settings[.mediaAutoLoad].toggle() },
            VelaCommand(
                id: "media.toggleLinkCards", category: .media, title: "Toggle Link Previews",
                keywords: ["cards", "embeds"], isChecked: settings[.mediaShowLinkCards]
            ) { settings[.mediaShowLinkCards].toggle() },
            VelaCommand(
                id: "media.toggleAdultFilter", category: .media, title: "Hide Adult Site Previews",
                keywords: ["nsfw", "adult", "porn", "filter", "safe"], isChecked: settings[.mediaFilterAdultSites]
            ) { settings[.mediaFilterAdultSites].toggle() },
            VelaCommand(
                id: "media.toggleBlur", category: .media, title: "Blur Images Until Clicked",
                keywords: ["blur", "spoiler", "hide images", "click to show", "thumbnails", "everywhere"],
                isChecked: settings[.mediaBlurImages]
            ) { settings[.mediaBlurImages].toggle() },
            link(.minimal, "Minimal Link Previews", keywords: ["compact", "small", "one line"]),
            link(.standard, "Standard Link Previews", keywords: ["medium", "default"]),
            link(.large, "Large Link Previews", keywords: ["full", "big"]),
            video(.player, "Play Videos Inline", keywords: ["player", "large", "full"]),
            video(.compact, "Compact Videos", keywords: ["small", "one line"]),
            video(.off, "Videos as Links", keywords: ["no player", "off", "disable"]),
            image(.full, "Full-Size Images", keywords: ["large", "big"]),
            image(.thumbnail, "Image Thumbnails", keywords: ["small", "compact"]),
        ]
    }

    // MARK: Text size

    static let fontSizes: ClosedRange<Double> = 9...28

    var textBigger: VelaCommand {
        let size = settings[.chatFontSize]
        let settings = settings
        return VelaCommand(
            id: "text.bigger", category: .text, title: "Bigger", shortcut: Shortcuts.textBigger,
            keywords: ["zoom in", "font size", "increase"], isEnabled: size < Self.fontSizes.upperBound
        ) { Self.setFontSize(size + 1, in: settings) }
    }

    var textSmaller: VelaCommand {
        let size = settings[.chatFontSize]
        let settings = settings
        return VelaCommand(
            id: "text.smaller", category: .text, title: "Smaller", shortcut: Shortcuts.textSmaller,
            keywords: ["zoom out", "font size", "decrease"], isEnabled: size > Self.fontSizes.lowerBound
        ) { Self.setFontSize(size - 1, in: settings) }
    }

    var textActualSize: VelaCommand {
        let settings = settings
        return VelaCommand(
            id: "text.actualSize", category: .text, title: "Actual Size", shortcut: Shortcuts.textActualSize,
            keywords: ["reset zoom", "font size", "default"],
            isEnabled: settings[.chatFontSize] != SettingKey<Double>.chatFontSize.defaultValue
        ) { settings.reset(.chatFontSize) }
    }

    private static func setFontSize(_ size: Double, in settings: SettingsStore) {
        settings[.chatFontSize] = min(fontSizes.upperBound, max(fontSizes.lowerBound, size.rounded()))
    }

    // MARK: Theme

    var selectTheme: VelaCommand {
        VelaCommand(
            id: "theme.select", category: .theme, title: "Select Theme…",
            shortcut: Shortcuts.selectTheme, keywords: ["color theme", "appearance", "dark", "light"]
        ) { [context] in
            Self.togglePalette(.themes, uiState: context.uiState, openWindow: context.openWindow)
        }
    }

    var toggleFollowSystem: VelaCommand {
        let follows = settings[.appearanceFollowSystem]
        let settings = settings
        return VelaCommand(
            id: "theme.toggleFollowSystem", category: .theme, title: "Toggle Match System Appearance",
            menuTitle: "Match System Appearance", keywords: ["dark mode", "light mode", "auto"],
            isChecked: follows
        ) { settings[.appearanceFollowSystem].toggle() }
    }

    var themeEditor: VelaCommand {
        VelaCommand(
            id: "theme.editor", category: .theme, title: "Open Theme Editor", menuTitle: "Theme Editor…",
            keywords: ["customize", "colors"]
        ) { [context] in context.openWindow(id: WindowID.themeEditor) }
    }

    var importTheme: VelaCommand {
        VelaCommand(
            id: "theme.import", category: .theme, title: "Import Theme…",
            keywords: ["vs code", "vsix", "json", "install"]
        ) { [context] in
            ThemeFileActions.importThemes(into: context.themeStore, settings: context.app.settings)
        }
    }

    var revealThemesFolder: VelaCommand {
        VelaCommand(
            id: "theme.revealFolder", category: .theme, title: "Reveal Themes Folder",
            keywords: ["finder", "files", "show"]
        ) { [context] in ThemeFileActions.revealThemesFolder(of: context.themeStore) }
    }

    // MARK: Settings

    var openSettings: VelaCommand {
        VelaCommand(
            id: "settings.open", category: .settings, title: "Open Settings", shortcut: Shortcuts.settings,
            keywords: ["preferences", "options"]
        ) { [context] in context.openSettings() }
    }

    var openSettingsJSON: VelaCommand {
        VelaCommand(
            id: "settings.openJSON", category: .settings, title: "Open settings.json",
            menuTitle: "Open settings.json", keywords: ["preferences", "file", "edit"]
        ) { [context] in ThemeFileActions.openSettingsFile(context.app.settings) }
    }

    // MARK: Go

    var previousBuffer: VelaCommand {
        let app = app
        return VelaCommand(
            id: "go.previousBuffer", category: .go, title: "Previous Conversation",
            menuTitle: "Previous Buffer", shortcut: Shortcuts.previousBuffer,
            keywords: ["buffer", "channel", "up"], isEnabled: !app.sessions.isEmpty
        ) { app.selectAdjacentBuffer(forward: false) }
    }

    var nextBuffer: VelaCommand {
        let app = app
        return VelaCommand(
            id: "go.nextBuffer", category: .go, title: "Next Conversation",
            menuTitle: "Next Buffer", shortcut: Shortcuts.nextBuffer,
            keywords: ["buffer", "channel", "down"], isEnabled: !app.sessions.isEmpty
        ) { app.selectAdjacentBuffer(forward: true) }
    }

    var previousUnread: VelaCommand {
        let app = app
        return VelaCommand(
            id: "go.previousUnread", category: .go, title: "Previous Unread",
            shortcut: Shortcuts.previousUnread, keywords: ["buffer", "channel"], isEnabled: hasOtherUnread
        ) { app.selectAdjacentBuffer(forward: false, unreadOnly: true) }
    }

    var nextUnread: VelaCommand {
        let app = app
        return VelaCommand(
            id: "go.nextUnread", category: .go, title: "Next Unread",
            shortcut: Shortcuts.nextUnread, keywords: ["buffer", "channel"], isEnabled: hasOtherUnread
        ) { app.selectAdjacentBuffer(forward: true, unreadOnly: true) }
    }

    var focusInput: VelaCommand {
        VelaCommand(
            id: "go.focusInput", category: .go, title: "Focus Input", shortcut: Shortcuts.focusInput,
            keywords: ["composer", "message", "type"], isEnabled: app.selectedBuffer != nil
        ) { [context] in context.uiState.focusInput() }
    }

    private var hasOtherUnread: Bool {
        app.orderedBuffers.contains { $0.id != app.selectedBufferID && ($0.unreadCount > 0 || $0.highlightCount > 0) }
    }

    // MARK: Buffers

    var markAllAsRead: VelaCommand {
        let app = app
        let hasUnread = app.sessions.contains { $0.totalUnread > 0 || $0.totalHighlights > 0 }
        return VelaCommand(
            id: "buffer.markAllRead", category: .buffer, title: "Mark All as Read",
            keywords: ["clear", "unread", "mentions"], isEnabled: hasUnread
        ) {
            for session in app.sessions {
                for buffer in session.allBuffers where buffer.unreadCount > 0 || buffer.highlightCount > 0 {
                    session.markRead(buffer)
                }
            }
        }
    }

    /// Commands for the selected buffer (mark read, mute, media, leave, close).
    var selectedBufferCommands: [VelaCommand] {
        guard let buffer = app.selectedBuffer, let session = app.selectedSession else { return [] }
        let app = app
        var commands: [VelaCommand] = [
            VelaCommand(
                id: "buffer.markRead", category: .buffer, title: "Mark as Read",
                keywords: ["clear", "unread"], isEnabled: buffer.unreadCount > 0 || buffer.highlightCount > 0
            ) { session.markRead(buffer) },
        ]
        guard buffer.kind != .server else { return commands }
        let mediaOn = app.isMediaEnabled(for: buffer.id)
        commands += [
            VelaCommand(
                id: "buffer.toggleMute", category: .buffer, title: buffer.isMuted ? "Unmute" : "Mute",
                keywords: ["silence", "notifications"]
            ) { session.setMuted(!buffer.isMuted, for: buffer) },
            VelaCommand(
                id: "buffer.toggleMedia", category: .buffer,
                title: mediaOn ? "Disable Inline Media" : "Enable Inline Media",
                keywords: ["images", "previews"]
            ) { app.setMediaEnabled(!mediaOn, for: buffer.id) },
            Self.blurCommand(app: app, bufferID: buffer.id),
        ]
        if buffer.kind == .channel, buffer.isJoined {
            commands.append(VelaCommand(
                id: "channel.leave", category: .channel, title: "Leave \(buffer.name)",
                keywords: ["part"], isEnabled: session.isConnected
            ) { session.submit("/part \(buffer.name)", in: buffer) })
        }
        commands.append(VelaCommand(
            id: "buffer.close", category: .buffer, title: "Close",
            keywords: [buffer.name, buffer.kind == .channel ? "leave channel" : "close conversation"]
        ) { app.close(buffer) })
        return commands
    }

    /// "Blur Images" for one buffer, in the palette (the selected buffer)
    /// and buffer context menus. Checked while its images stay blurred until
    /// clicked; disabled (and checked) while a wider setting blurs them
    /// anyway, everywhere or on its whole network, which this can't undo.
    static func blurCommand(app: AppModel, bufferID: BufferID) -> VelaCommand {
        let inherited = app.settings[.mediaBlurImages] || app.isBlurred(forNetwork: bufferID.networkID)
        let blurred = app.isBlurred(for: bufferID)
        return VelaCommand(
            id: "buffer.toggleBlur", category: .buffer, title: "Blur Images",
            keywords: ["blur", "spoiler", "hide images", "click to show", "thumbnails", "channel"],
            isEnabled: !inherited, isChecked: inherited || blurred
        ) { app.setBlurred(!blurred, for: bufferID) }
    }

    /// "Blur Images on This Network", for network context menus.
    static func networkBlurCommand(app: AppModel, networkID: UUID) -> VelaCommand {
        let everywhere = app.settings[.mediaBlurImages]
        let blurred = app.isBlurred(forNetwork: networkID)
        return VelaCommand(
            id: "network.toggleBlur.\(networkID.uuidString)", category: .network, title: "Blur Images on This Network",
            keywords: ["blur", "spoiler", "hide images"],
            isEnabled: !everywhere, isChecked: everywhere || blurred, showsInPalette: false
        ) { app.setBlurred(!blurred, forNetwork: networkID) }
    }

    // MARK: Networks & channels

    var addNetwork: VelaCommand {
        VelaCommand(
            id: "network.add", category: .network, title: "Add Network…", shortcut: Shortcuts.addNetwork,
            keywords: ["server", "bouncer", "znc", "soju", "new"]
        ) { [context] in context.uiState.networkEditor = .new }
    }

    var joinChannel: VelaCommand {
        let target = app.selectedSession.flatMap { session in
            session.isConnected && !session.isBouncerControl ? session : nil
        }
        return VelaCommand(
            id: "channel.join", category: .channel, title: "Join…", menuTitle: "Join Channel…",
            shortcut: Shortcuts.joinChannel, keywords: ["enter", "channel"], isEnabled: target != nil
        ) { [context] in
            if let target { context.uiState.joinChannelNetwork = target.id }
        }
    }

    /// Puts the selected network's channels and private conversations back
    /// in alphabetical order after they've been dragged around.
    var sortChannels: VelaCommand {
        let session = app.selectedSession
        return VelaCommand(
            id: "network.sortChannels", category: .network, title: "Sort Channels A–Z",
            keywords: ["sort", "alphabetical", "order", "reorder", "abc", "conversations", "queries"]
                + (session.map { [$0.displayName] } ?? []),
            isEnabled: session.map { !$0.isBufferOrderAlphabetical } ?? false
        ) {
            guard let session else { return }
            withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .snappy(duration: 0.25)) {
                session.sortBuffersAlphabetically()
            }
        }
    }

    /// Connect / Disconnect / Reconnect / Edit / Remove for one network.
    /// Menu titles are short ("Disconnect") since the Network menu acts on
    /// the selected network; palette titles name it.
    func networkCommands(for session: NetworkSession) -> [VelaCommand] {
        let state = session.connectionState
        let name = session.displayName
        let uiState = uiState
        let networkID = session.config.parentNetworkID ?? session.id
        let suffix = session.id.uuidString
        return [
            VelaCommand(
                id: "network.connect.\(suffix)", category: .network, title: "Connect \(name)",
                menuTitle: "Connect to \(name)", keywords: ["online"], isEnabled: state == .disconnected
            ) { session.connect() },
            VelaCommand(
                id: "network.disconnect.\(suffix)", category: .network, title: "Disconnect \(name)",
                menuTitle: "Disconnect", keywords: ["offline", "quit"], isEnabled: state != .disconnected
            ) { session.disconnect() },
            VelaCommand(
                id: "network.reconnect.\(suffix)", category: .network, title: "Reconnect \(name)",
                menuTitle: "Reconnect", keywords: ["restart"]
            ) { session.reconnect() },
            VelaCommand(
                id: "network.edit.\(suffix)", category: .network, title: "Edit \(name)…",
                menuTitle: "Edit Network…", keywords: ["settings", "configure", "server"]
            ) { uiState.networkEditor = .existing(networkID) },
            VelaCommand(
                id: "network.remove.\(suffix)", category: .network, title: "Remove \(name)…",
                menuTitle: "Remove Network…", keywords: ["delete"]
            ) { uiState.networkPendingRemoval = networkID },
        ]
    }

    /// The Network menu's items when no network is selected: all disabled.
    static let placeholderNetworkTitles = ["Connect", "Disconnect", "Reconnect", "Edit Network…", "Remove Network…"]

    // MARK: All

    /// Every command, for the palette (which hides disabled ones).
    var all: [VelaCommand] {
        var commands: [VelaCommand] = [
            goToConversation,
            toggleSidebar, toggleMemberList, toggleFullScreen,
        ]
        commands += navigationStyles
        commands += tabPlacements
        commands.append(toggleServerTabRow)
        commands += chatLayouts
        commands += presets
        commands += chatToggles
        commands += joinPartModes
        commands += mediaCommands
        commands += [textBigger, textSmaller, textActualSize]
        commands += [selectTheme, toggleFollowSystem, themeEditor, importTheme, revealThemesFolder]
        commands += [openSettings, openSettingsJSON]
        commands += [previousBuffer, nextBuffer, previousUnread, nextUnread, focusInput]
        commands.append(markAllAsRead)
        commands += selectedBufferCommands
        commands += [addNetwork, joinChannel, sortChannels]
        for session in app.sessions {
            commands += networkCommands(for: session)
        }
        commands.append(commandPalette)
        return commands
    }
}
