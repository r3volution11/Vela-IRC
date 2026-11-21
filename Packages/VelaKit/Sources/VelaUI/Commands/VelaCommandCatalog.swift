// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaIntelligence
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
    /// Apple Intelligence (Catch me up), where the builder has it: the
    /// palette does, the menu bar doesn't.
    var intelligence: IntelligenceServices? = nil
    /// The updater, for Check for Updates…, where the builder has it (the
    /// palette).
    var updates: AppUpdates? = nil
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
        /// Also opens "Go to Conversation…" (handled by `AlternateShortcuts`;
        /// a menu item can carry only one shortcut).
        static let goToConversationAlternate = KeyboardShortcut("k", modifiers: .command)
        static let selectTheme = KeyboardShortcut("t", modifiers: [.control, .command])
        static let toggleSidebar = KeyboardShortcut("s", modifiers: [.control, .command])
        static let toggleMemberList = KeyboardShortcut("m", modifiers: [.command, .shift])
        static let addNetwork = KeyboardShortcut("n", modifiers: [.command, .shift])
        static let joinChannel = KeyboardShortcut("j", modifiers: .command)
        /// Safari's Reopen Last Closed Tab.
        static let reopenClosed = KeyboardShortcut("t", modifiers: [.command, .shift])
        static let previousBuffer = KeyboardShortcut(.upArrow, modifiers: [.option, .command])
        static let nextBuffer = KeyboardShortcut(.downArrow, modifiers: [.option, .command])
        /// ⇧⌘[ / ⇧⌘], Safari's Show Previous/Next Tab. Written as the keys'
        /// shifted characters: a menu matches what the keys type, so "[" with
        /// ⇧ would never match. ⌃⇧Tab / ⌃Tab do the same (`AlternateShortcuts`).
        static let previousTab = KeyboardShortcut("{", modifiers: .command)
        static let nextTab = KeyboardShortcut("}", modifiers: .command)
        static let previousNetwork = KeyboardShortcut("[", modifiers: [.control, .command])
        static let nextNetwork = KeyboardShortcut("]", modifiers: [.control, .command])
        /// ⌥⇧⌘[ / ⌥⇧⌘]: the selected tab one place back or on (written with
        /// the shifted characters, like `previousTab`); ⌥⌃⌘[ / ⌥⌃⌘] its network.
        static let moveTabBack = KeyboardShortcut("{", modifiers: [.option, .command])
        static let moveTabForward = KeyboardShortcut("}", modifiers: [.option, .command])
        static let moveNetworkBack = KeyboardShortcut("[", modifiers: [.option, .control, .command])
        static let moveNetworkForward = KeyboardShortcut("]", modifiers: [.option, .control, .command])
        /// File → Close Tab, as in a browser; Close Window moves to ⇧⌘W.
        static let closeTab = KeyboardShortcut("w", modifiers: .command)
        static let closeWindow = KeyboardShortcut("w", modifiers: [.shift, .command])
        static let previousUnread = KeyboardShortcut(.upArrow, modifiers: [.shift, .option, .command])
        static let nextUnread = KeyboardShortcut(.downArrow, modifiers: [.shift, .option, .command])
        static let focusInput = KeyboardShortcut("l", modifiers: .command)
        /// ⌥⌘1–⌥⌘4: the window's areas in screen order (`FocusArea`), with
        /// ⌥⌘3, the message box, forwarded to ⌘L (`AlternateShortcuts`).
        /// F6 / ⇧F6 go round them, as in Slack.
        static let focusNavigation = KeyboardShortcut("1", modifiers: [.option, .command])
        static let focusMessages = KeyboardShortcut("2", modifiers: [.option, .command])
        static let focusInputAlternate = KeyboardShortcut("3", modifiers: [.option, .command])
        static let focusMembers = KeyboardShortcut("4", modifiers: [.option, .command])
        static let nextArea = KeyboardShortcut(f6, modifiers: [])
        static let previousArea = KeyboardShortcut(f6, modifiers: .shift)
        private static let f6 = KeyEquivalent(Character(Unicode.Scalar(0xF709)!))   // NSF6FunctionKey
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
            toggle("toggleNickColorsInText", "Toggle Nick Colors in Messages", .chatColorNicksInText, keywords: ["nickname", "mentions", "text"]),
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

    /// Opens Settings → Advanced with its search field focused (the
    /// current search is kept).
    var searchSettings: VelaCommand {
        VelaCommand(
            id: "settings.search", category: .settings, title: "Search…",
            menuTitle: "Search Settings…",
            keywords: ["preferences", "find", "settings editor", "advanced", "options", "filter"]
        ) { [context] in
            context.uiState.settingsEditor.openSearch()
            context.openSettings()
        }
    }

    var openSettingsJSON: VelaCommand {
        VelaCommand(
            id: "settings.openJSON", category: .settings, title: "Open settings.json",
            menuTitle: "Open settings.json", keywords: ["preferences", "file", "edit"]
        ) { [context] in ThemeFileActions.openSettingsFile(context.app.settings) }
    }

    // MARK: Help

    /// Opens "What's New in Vela" (Help menu and palette).
    var whatsNew: VelaCommand {
        VelaCommand(
            id: "help.whatsNew", category: .help, title: "What's New in Vela",
            keywords: ["changelog", "release notes", "update", "version", "news", "changes"]
        ) { [context] in context.openWindow(id: WindowID.whatsNew) }
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

    /// The selected network's previous tab (console, channels, then
    /// conversations), wrapping around; the same list in the sidebar.
    var previousTab: VelaCommand {
        let app = app
        return VelaCommand(
            id: "go.previousTab", category: .go, title: "Previous Tab", menuTitle: "Show Previous Tab",
            shortcut: Shortcuts.previousTab, keywords: ["channel", "conversation", "buffer", "left", "network"],
            isEnabled: hasOtherTabs
        ) { app.selectAdjacentTab(forward: false) }
    }

    var nextTab: VelaCommand {
        let app = app
        return VelaCommand(
            id: "go.nextTab", category: .go, title: "Next Tab", menuTitle: "Show Next Tab",
            shortcut: Shortcuts.nextTab, keywords: ["channel", "conversation", "buffer", "right", "network"],
            isEnabled: hasOtherTabs
        ) { app.selectAdjacentTab(forward: true) }
    }

    /// The previous network, on the tab you were last on there.
    var previousNetwork: VelaCommand {
        let app = app
        return VelaCommand(
            id: "go.previousNetwork", category: .go, title: "Previous Network",
            shortcut: Shortcuts.previousNetwork, keywords: ["server", "switch"], isEnabled: app.sessions.count > 1
        ) { app.selectAdjacentNetwork(forward: false) }
    }

    var nextNetwork: VelaCommand {
        let app = app
        return VelaCommand(
            id: "go.nextNetwork", category: .go, title: "Next Network",
            shortcut: Shortcuts.nextNetwork, keywords: ["server", "switch"], isEnabled: app.sessions.count > 1
        ) { app.selectAdjacentNetwork(forward: true) }
    }

    private var hasOtherTabs: Bool {
        ((app.selectedSession ?? app.sessions.first)?.allBuffers.count ?? 0) > 1
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

    // MARK: Focus

    /// ⌥⌘1: the sidebar (or its rail), or the tabs.
    var focusNavigation: VelaCommand {
        let uiState = uiState
        let usesSidebar = settings[.navigationStyle] == .sidebar
        return VelaCommand(
            id: "go.focusNavigation", category: .go, title: usesSidebar ? "Focus Sidebar" : "Focus Tabs",
            shortcut: Shortcuts.focusNavigation, keywords: ["keyboard", "sidebar", "tabs", "channel list", "rail"]
        ) { uiState.focus(.navigation) }
    }

    /// ⌥⌘2: the messages, to pick one and reply, react, copy…
    var focusMessages: VelaCommand {
        let uiState = uiState
        return VelaCommand(
            id: "go.focusMessages", category: .go, title: "Focus Messages", shortcut: Shortcuts.focusMessages,
            keywords: ["keyboard", "select message", "reply", "react", "chat"], isEnabled: app.selectedBuffer != nil
        ) { uiState.focus(.messages) }
    }

    /// ⌘L, or ⌥⌘3.
    var focusInput: VelaCommand {
        VelaCommand(
            id: "go.focusInput", category: .go, title: "Focus Message Box", shortcut: Shortcuts.focusInput,
            keywords: ["composer", "message", "type", "input", "keyboard"], isEnabled: app.selectedBuffer != nil
        ) { [context] in context.uiState.focusInput() }
    }

    /// ⌥⌘4: the member list, shown first if it's hidden.
    var focusMembers: VelaCommand {
        let uiState = uiState
        let settings = settings
        return VelaCommand(
            id: "go.focusMembers", category: .go, title: "Focus Member List", shortcut: Shortcuts.focusMembers,
            keywords: ["keyboard", "nick list", "user list", "people", "members"],
            isEnabled: app.selectedBuffer?.kind == .channel
        ) {
            if !settings[.memberListVisible] { settings[.memberListVisible] = true }
            uiState.focus(.members)
        }
    }

    /// F6.
    var nextArea: VelaCommand {
        let app = app
        let uiState = uiState
        let settings = settings
        return VelaCommand(
            id: "go.nextArea", category: .go, title: "Focus Next Area", shortcut: Shortcuts.nextArea,
            keywords: ["keyboard", "pane", "cycle", "f6"]
        ) { Self.focusAdjacentArea(forward: true, app: app, uiState: uiState, settings: settings) }
    }

    /// ⇧F6.
    var previousArea: VelaCommand {
        let app = app
        let uiState = uiState
        let settings = settings
        return VelaCommand(
            id: "go.previousArea", category: .go, title: "Focus Previous Area", shortcut: Shortcuts.previousArea,
            keywords: ["keyboard", "pane", "cycle", "f6"]
        ) { Self.focusAdjacentArea(forward: false, app: app, uiState: uiState, settings: settings) }
    }

    /// Worked out when the key is pressed, from where the focus is then.
    private static func focusAdjacentArea(forward: Bool, app: AppModel, uiState: UIState, settings: SettingsStore) {
        let buffer = app.selectedBuffer
        let available = FocusAreas.available(
            hasBuffer: buffer != nil,
            showsMembers: settings[.memberListVisible] && buffer?.kind == .channel
        )
        guard let area = FocusAreas.adjacent(to: uiState.focusedArea, forward: forward, in: available) else { return }
        uiState.focus(area)
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
        commands += Self.membershipCommands(buffer: buffer, session: session, app: app, uiState: uiState)
        return commands
    }

    /// Leave #vela (or Join #vela), Hide #vela (a detached bouncer channel)
    /// and Remove #vela for a channel; Close for a conversation. Leave and
    /// Remove ask first while their settings are on; through a bouncer,
    /// Leave detaches. Static so tests can build them without a window.
    static func membershipCommands(buffer: BufferModel, session: NetworkSession, app: AppModel, uiState: UIState) -> [VelaCommand] {
        guard buffer.kind == .channel else {
            return [VelaCommand(
                id: "buffer.close", category: .buffer, title: "Close",
                keywords: [buffer.name, "close conversation", "query"]
            ) { app.close(buffer) }]
        }
        var commands = [session.isIn(buffer)
            ? VelaCommand(
                id: "channel.leave", category: .channel, title: "Leave \(buffer.name)",
                keywords: session.isBouncer ? ["part", "detach", "bouncer"] : ["part"]
            ) { ChannelActions.leave(buffer, app: app, uiState: uiState) }
            : VelaCommand(
                id: "channel.rejoin", category: .channel, title: "Join \(buffer.name)",
                keywords: ["rejoin", "enter", "attach", "reattach"], isEnabled: session.isConnected
            ) { ChannelActions.join(buffer, app: app) }]
        if session.canHide(buffer) {
            commands.append(VelaCommand(
                id: "channel.hide", category: .channel, title: "Hide \(buffer.name)",
                keywords: ["close", "detached", "bouncer"]
            ) { ChannelActions.hide(buffer, app: app) })
        }
        commands.append(VelaCommand(
            id: "channel.remove", category: .channel, title: "Remove \(buffer.name)",
            keywords: ["close", "delete", "part", "auto-join"]
        ) { ChannelActions.remove(buffer, app: app, uiState: uiState) })
        return commands
    }

    /// "Show #vela (Libera.Chat)" for each hidden channel on every network,
    /// in the palette. One hidden this run is already there, as its Recently
    /// Closed command.
    var hiddenChannelCommands: [VelaCommand] { Self.hiddenChannelCommands(app: app) }

    static func hiddenChannelCommands(app: AppModel) -> [VelaCommand] {
        let inRecentlyClosed = Set(app.recentlyClosed.map(\.id))
        return app.hiddenChannels.compactMap { hidden, session in
            guard !inRecentlyClosed.contains(hidden.id) else { return nil }
            return VelaCommand(
                id: showCommandID(hidden.id), category: .channel,
                title: "Show \(hidden.name) (\(session.displayName))",
                keywords: ["hidden", "unhide", "detached", "bouncer"]
            ) { app.show(hidden) }
        }
    }

    private static func showCommandID(_ id: BufferID) -> String { "channel.show.\(id.description)" }

    /// Reopens the channel or conversation closed last; again goes further
    /// back. The menu names which kind it is.
    var reopenClosed: VelaCommand { Self.reopenClosed(app: app) }

    /// One command per recently closed channel or conversation, newest
    /// first: File → Recently Closed, and "Reopen #vela (Libera.Chat)" in
    /// the palette.
    var recentlyClosedCommands: [VelaCommand] { Self.recentlyClosedCommands(app: app) }

    /// Static so tests can build them without a window.
    static func reopenClosed(app: AppModel) -> VelaCommand {
        let latest = app.recentlyClosed.first
        return VelaCommand(
            id: "buffer.reopenClosed", category: .buffer, title: "Reopen Closed Channel",
            menuTitle: latest?.kind == .query ? "Reopen Closed Conversation" : "Reopen Closed Channel",
            shortcut: Shortcuts.reopenClosed,
            keywords: ["undo close", "recently closed", "restore", "removed", "conversation", "query", "tab"],
            isEnabled: latest != nil
        ) { app.reopenLastClosed() }
    }

    /// A hidden channel's is "Show #vela (Libera.Chat)" in the palette.
    static func recentlyClosedCommands(app: AppModel) -> [VelaCommand] {
        app.recentlyClosed.map { closed in
            let network = app.networkName(for: closed)
            if closed.wasHidden {
                return VelaCommand(
                    id: showCommandID(closed.id), category: .channel,
                    title: "Show \(closed.name) (\(network))",
                    menuTitle: app.menuTitle(for: closed),
                    keywords: ["recently closed", "hidden", "unhide", "detached", "restore", "undo hide"]
                ) { app.reopen(closed) }
            }
            return VelaCommand(
                id: "buffer.reopen.\(closed.id.description)", category: .buffer,
                title: "Reopen \(closed.name) (\(network))",
                menuTitle: app.menuTitle(for: closed),
                keywords: ["recently closed", "restore", "undo close"]
            ) { app.reopen(closed) }
        }
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
    // MARK: Closing and moving tabs

    /// File → Close Tab (⌘W). In the main window, what the selected tab's ×
    /// does (asking first where that asks): "Remove Channel…", "Leave
    /// Channel…", "Hide Channel" or "Close Conversation", and nothing on a
    /// server console. In any other window (Settings, the theme editor),
    /// it closes that window, as ⌘W does everywhere else.
    func closeTab(inMainWindow: Bool) -> VelaCommand {
        guard inMainWindow else {
            return VelaCommand(
                id: "file.close", category: .view, title: "Close", shortcut: Shortcuts.closeTab, showsInPalette: false
            ) { NSApp.keyWindow?.performClose(nil) }
        }
        let app = app
        let uiState = uiState
        let action = app.selectedBuffer.flatMap { buffer in
            app.session(for: buffer.id.networkID).flatMap { ChannelActions.closeAction(for: buffer, in: $0, app: app) }
        }
        let asks = switch action {
        case .remove: settings[.channelsConfirmRemove]
        case .detach: settings[.channelsConfirmLeave]
        default: false
        }
        return VelaCommand(
            id: "file.closeTab", category: .tabs, title: "Close Tab",
            menuTitle: action.map { asks ? "\($0.title)…" : $0.title } ?? "Close Tab",
            shortcut: Shortcuts.closeTab, isEnabled: action != nil,
            // The palette has Close, Leave, Remove and Hide already.
            showsInPalette: false
        ) {
            // The tab when it's pressed, not when the menu was drawn.
            guard let buffer = app.selectedBuffer else { return }
            ChannelActions.closeTab(buffer, app: app, uiState: uiState)
        }
    }

    /// File → Close Window (⇧⌘W).
    var closeWindow: VelaCommand {
        VelaCommand(
            id: "file.closeWindow", category: .view, title: "Close Window", shortcut: Shortcuts.closeWindow,
            showsInPalette: false
        ) { NSApp.keyWindow?.performClose(nil) }
    }

    /// The selected channel or conversation one place back or on among its
    /// siblings: "Left" and "Right" with tabs, "Up" and "Down" with the
    /// sidebar.
    func moveSelectedBuffer(forward: Bool) -> VelaCommand {
        let app = app
        let usesSidebar = settings[.navigationStyle] == .sidebar
        let direction = usesSidebar ? (forward ? "Down" : "Up") : (forward ? "Right" : "Left")
        let buffer = app.selectedBuffer
        var isEnabled = false
        if let buffer, buffer.kind != .server, let session = app.session(for: buffer.id.networkID) {
            let siblings = session.bufferSiblings(of: buffer)
            if let index = siblings.firstIndex(where: { $0.id == buffer.id }) {
                isEnabled = forward ? index < siblings.count - 1 : index > 0
            }
        }
        return VelaCommand(
            id: forward ? "tabs.moveForward" : "tabs.moveBack", category: .tabs,
            title: "Move \(buffer?.kind == .query ? "Conversation" : "Channel") \(direction)",
            shortcut: forward ? Shortcuts.moveTabForward : Shortcuts.moveTabBack,
            keywords: ["reorder", "arrange", "order", "tab"], isEnabled: isEnabled
        ) {
            guard let buffer = app.selectedBuffer, buffer.kind != .server,
                  let session = app.session(for: buffer.id.networkID) else { return }
            withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .snappy(duration: 0.25)) {
                session.moveBuffer(buffer, by: forward ? 1 : -1)
            }
        }
    }

    /// The selected network one place back or on among its siblings (a
    /// bouncer's networks among that bouncer's).
    func moveSelectedNetwork(forward: Bool) -> VelaCommand {
        let app = app
        let usesSidebar = settings[.navigationStyle] == .sidebar
        let direction = usesSidebar ? (forward ? "Down" : "Up") : (forward ? "Right" : "Left")
        var isEnabled = false
        if let session = app.selectedSession {
            let siblings = app.networkSiblings(of: session.id)
            if let index = siblings.firstIndex(where: { $0.id == session.id }) {
                isEnabled = forward ? index < siblings.count - 1 : index > 0
            }
        }
        return VelaCommand(
            id: forward ? "network.moveForward" : "network.moveBack", category: .network,
            title: "Move Network \(direction)",
            shortcut: forward ? Shortcuts.moveNetworkForward : Shortcuts.moveNetworkBack,
            keywords: ["reorder", "arrange", "order", "server"], isEnabled: isEnabled
        ) {
            guard let session = app.selectedSession else { return }
            withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .snappy(duration: 0.25)) {
                app.moveNetwork(session.id, by: forward ? 1 : -1)
            }
        }
    }

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
        commands += timestampPositionCommands
        commands += joinPartModes
        commands += unreadCommands
        commands += mediaCommands
        commands += [textBigger, textSmaller, textActualSize]
        commands += [selectTheme, toggleFollowSystem, themeEditor, importTheme, revealThemesFolder]
        commands += [openSettings, searchSettings, openSettingsJSON]
        commands += [previousBuffer, nextBuffer, previousTab, nextTab, previousNetwork, nextNetwork, previousUnread, nextUnread]
        commands += [focusNavigation, focusMessages, focusInput, focusMembers, nextArea, previousArea]
        commands.append(markAllAsRead)
        commands += selectedBufferCommands
        commands.append(reopenClosed)
        commands += recentlyClosedCommands
        commands += hiddenChannelCommands
        commands += typingCommands + messageBoxBorderCommands
        commands += catchUpCommands
        commands += translationCommands
        commands += historyCommands
        commands += chatLogCommands
        commands += accentCommands
        commands += appIconCommands
        commands += dockCommands
        commands += [addNetwork, joinChannel, sortChannels]
        commands += [moveSelectedBuffer(forward: false), moveSelectedBuffer(forward: true)]
        commands += [moveSelectedNetwork(forward: false), moveSelectedNetwork(forward: true)]
        for session in app.sessions {
            commands += networkCommands(for: session)
        }
        commands.append(whatsNew)
        commands += aboutCommands
        commands.append(commandPalette)
        return commands
    }
}
