// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import Testing
import VelaCore
import VelaFoundation
import VelaIntelligence
import VelaStore
import VelaTheme
@testable import VelaUI

/// Settings → Presets in an offscreen window: the Settings window with the
/// pane open, in a theme, never shown or made key.
@MainActor
final class PresetsPaneHost {
    private static let paneKey = "Vela.settingsPane"

    let app: AppModel
    let window: NSWindow
    let host: NSView
    private let savedPane: String?
    private let themesDirectory: URL

    init(
        theme: String? = nil,
        size: CGSize = CGSize(width: 820, height: 1250),
        configure: (SettingsStore) -> Void = { _ in },
        contrast: ColorSchemeContrast? = nil,
        pane: SettingsPane = .presets
    ) async throws {
        savedPane = UserDefaults.standard.string(forKey: Self.paneKey)
        themesDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("VelaPresets-\(UUID().uuidString)")
        app = AppModel.demo()
        if let theme {
            app.settings[.appearanceFollowSystem] = false
            app.settings[.appearanceTheme] = theme
        }
        configure(app.settings)
        let themeStore = ThemeStore(userThemesDirectory: themesDirectory, settings: ThemeSettings(settings: app.settings))
        themeStore.reload()
        var view = AnyView(
            SettingsRootView(initialPane: pane)
                .velaEnvironment(
                    app: app,
                    themeStore: themeStore,
                    uiState: UIState(),
                    services: SceneServices(intelligence: .demo()),
                    isPrimary: false
                )
                .frame(width: size.width, height: size.height)
        )
        if let contrast { view = AnyView(view.environment(\._colorSchemeContrast, contrast)) }
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -9000, y: -9000), size: size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        self.host = host
        try await settle()
    }

    func close() {
        window.orderOut(nil)
        window.contentView = nil
        UserDefaults.standard.set(savedPane, forKey: Self.paneKey)
        try? FileManager.default.removeItem(at: themesDirectory)
    }

    func settle() async throws {
        for _ in 0..<3 {
            try await Task.sleep(for: .milliseconds(60))
            window.contentView?.layoutSubtreeIfNeeded()
        }
    }

    /// The window as drawn, as PNG data.
    func png() throws -> Data {
        window.contentView?.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    // MARK: Accessibility

    /// Every accessibility element under the window, depth first.
    func elements() -> [AnyObject] {
        let enhancedInterface = NSSelectorFromString("accessibilitySetEnhancedUserInterfaceAttribute:")
        NSApp.perform(enhancedInterface, with: NSNumber(value: true))
        defer { NSApp.perform(enhancedInterface, with: NSNumber(value: false)) }
        var found: [AnyObject] = []
        func walk(_ object: AnyObject) {
            found.append(object)
            for child in (object.accessibilityChildren?() ?? nil) ?? [] {
                walk(child as AnyObject)
            }
        }
        walk(window)
        return found
    }

    /// The element labeled `label` (the first, depth first).
    func element(labeled label: String) -> AnyObject? {
        elements().first { ($0.accessibilityLabel?() ?? nil) == label }
    }

    func isSelected(_ element: AnyObject) -> Bool {
        (element.isAccessibilitySelected?() ?? false)
    }

    /// Whether a row's heading says it's customized ("Message style,
    /// customized"), as VoiceOver reads it.
    func saysCustomized(_ axis: PresetAxis) -> Bool {
        element(labeled: "\(axis.title), customized") != nil
    }
}

/// Renders Settings → Presets in several themes, for looking at
/// (`VELA_PRESETS_SNAPSHOTS=<folder> swift test --filter PresetsPaneSnapshots`).
@MainActor
@Suite("Presets pane snapshots", .serialized, .enabled(if: ProcessInfo.processInfo.environment["VELA_PRESETS_SNAPSHOTS"] != nil))
struct PresetsPaneSnapshots {
    private var folder: URL {
        get throws {
            let path = try #require(ProcessInfo.processInfo.environment["VELA_PRESETS_SNAPSHOTS"])
            let url = URL(filePath: path, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
    }

    private func shoot(
        _ name: String,
        theme: String,
        size: CGSize = CGSize(width: 820, height: 1250),
        contrast: ColorSchemeContrast? = nil,
        pane: SettingsPane = .presets,
        configure: (SettingsStore) -> Void = { _ in }
    ) async throws {
        let host = try await PresetsPaneHost(theme: theme, size: size, configure: configure, contrast: contrast, pane: pane)
        defer { host.close() }
        try host.png().write(to: try folder.appending(path: "\(name).png"))
    }

    /// The other places the presets show: the quick menus at the top of
    /// Appearance, and the Focus card in Layout.
    @Test func appearanceAndLayoutPanes() async throws {
        try await shoot("appearance-quick-presets-palenight", theme: "Palenight", size: CGSize(width: 820, height: 600), pane: .appearance)
        try await shoot("appearance-quick-presets-customized-lighter", theme: "Lighter", size: CGSize(width: 820, height: 600), pane: .appearance) { settings in
            settings[.chatLineSpacing] = 3
        }
        try await shoot("layout-pane-focus-palenight", theme: "Palenight", size: CGSize(width: 820, height: 700), pane: .layout) { settings in
            settings.choose(.focus)
        }
    }

    @Test func defaultsInLightAndDarkThemes() async throws {
        for theme in ["Palenight", "Lighter", "Vela Graphite", "Vela Paper", "Dracula", "Catppuccin Latte", "Solarized Light", "Tokyo Night"] {
            let file = theme.lowercased().replacingOccurrences(of: " ", with: "-")
            try await shoot("presets-\(file)", theme: theme)
        }
    }

    @Test func otherChoicesAndCustomized() async throws {
        try await shoot("presets-focus-classic-compact-palenight", theme: "Palenight") { settings in
            settings.choose(.focus)
            settings.choose(.classicIRC)
            settings.choose(.compact)
        }
        try await shoot("presets-titlebar-columns-comfortable-lighter", theme: "Lighter") { settings in
            settings.choose(.tabsInTitleBar)
            settings.choose(.columns)
            settings.choose(.comfortable)
        }
        try await shoot("presets-customized-palenight", theme: "Palenight") { settings in
            settings[.navigationStyle] = .tabs
            settings[.tabsPlacement] = .bottom
            settings[.chatMonospace] = true
            settings[.chatLineSpacing] = 3
            settings[.chatMessageSpacing] = 8
        }
        try await shoot("presets-increased-contrast-lighter", theme: "Lighter", contrast: .increased)
        try await shoot("presets-narrow-palenight", theme: "Palenight", size: CGSize(width: 720, height: 1400))
    }

    /// Every message style at every density, side by side: the preview the
    /// pane shows, for judging the densities.
    @Test func densityMatrix() async throws {
        for themeName in ["Palenight", "Lighter"] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("VelaPresets-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            let store = SettingsStore(fileURL: root.appending(path: "settings.json"), watchForChanges: false)
            store[.appearanceFollowSystem] = false
            store[.appearanceTheme] = themeName
            let themeStore = ThemeStore(userThemesDirectory: root.appending(path: "Themes"), settings: ThemeSettings(settings: store))
            themeStore.reload()
            let theme = themeStore.current
            // Worked out before the view: writing settings while it's built
            // would build it again and again.
            var styles: [String: ChatStyle] = [:]
            for message in PresetAxis.messageStyle.choices {
                for density in PresetAxis.density.choices {
                    store.choose(message)
                    store.choose(density)
                    styles[message.id + density.id] = ChatStyle(settings: store)
                }
            }
            let finished = styles
            func style(_ message: PresetChoice, _ density: PresetChoice) -> ChatStyle {
                finished[message.id + density.id] ?? ChatStyle()
            }
            let matrix = Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                ForEach(PresetAxis.density.choices) { density in
                    GridRow {
                        ForEach(PresetAxis.messageStyle.choices) { message in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(message.name) · \(density.name)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(theme[ThemeKey.settingsForeground])
                                MessageSamplePreview()
                                    .environment(\.chatStyle, style(message, density))
                            }
                            .frame(width: 420, alignment: .top)
                        }
                    }
                }
            }
            .padding(16)
            .background(theme[ThemeKey.settingsBackground])
            .environment(\.theme, theme)
            let size = CGSize(width: 1324, height: 1150)
            let host = NSHostingView(rootView: matrix.frame(width: size.width, height: size.height, alignment: .topLeading))
            let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -9000, y: -9000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer { window.contentView = nil }
            try await Task.sleep(for: .milliseconds(150))
            host.layoutSubtreeIfNeeded()
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let file = try folder.appending(path: "density-matrix-\(themeName.lowercased()).png")
            try #require(rep.representation(using: .png, properties: [:])).write(to: file)
        }
    }
}

// MARK: - Logic

@MainActor
@Suite("Presets pane and commands")
struct PresetsPaneLogicTests {
    private func makeSettings(_ values: [String: JSONValue] = [:]) -> SettingsStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("VelaPresets-\(UUID().uuidString)/settings.json")
        let settings = SettingsStore(fileURL: url, watchForChanges: false)
        settings.setValues(values.mapValues { Optional($0) })
        return settings
    }

    @Test func arrowsMoveWithinARowAndStopAtTheEnds() {
        #expect(PresetKeyboard.target(.next, from: 0, count: 4) == 1)
        #expect(PresetKeyboard.target(.next, from: 3, count: 4) == 3)
        #expect(PresetKeyboard.target(.previous, from: 0, count: 4) == 0)
        #expect(PresetKeyboard.target(.previous, from: 2, count: 4) == 1)
        #expect(PresetKeyboard.target(.first, from: 2, count: 4) == 0)
        #expect(PresetKeyboard.target(.last, from: 0, count: 3) == 2)
        #expect(PresetKeyboard.target(.next, from: nil, count: 3) == 0)
        #expect(PresetKeyboard.target(.previous, from: nil, count: 3) == 2)
        #expect(PresetKeyboard.target(.next, from: 0, count: 0) == nil)
        #expect(PresetKeyboard.move(for: .leftArrow) == .previous)
        #expect(PresetKeyboard.move(for: .upArrow) == .previous)
        #expect(PresetKeyboard.move(for: .rightArrow) == .next)
        #expect(PresetKeyboard.move(for: .downArrow) == .next)
        #expect(PresetKeyboard.move(for: .home) == .first)
        #expect(PresetKeyboard.move(for: .end) == .last)
        #expect(PresetKeyboard.move(for: .space) == nil)
    }

    /// Four layouts in a row when they fit, else two rows of two.
    @Test func cardsWrapToHalfAsManyColumns() {
        let grid = PresetCardGrid(minimumItemWidth: 112, spacing: 10)
        #expect(grid.columns(forWidth: 563, count: 4) == 4)
        #expect(grid.columns(forWidth: 478, count: 4) == 4)
        #expect(grid.columns(forWidth: 463, count: 4) == 2)
        #expect(grid.columns(forWidth: 200, count: 4) == 1)
        #expect(grid.columns(forWidth: 563, count: 3) == 3)
        #expect(grid.columns(forWidth: 300, count: 3) == 2)
        #expect(grid.columns(forWidth: 100, count: 1) == 1)
    }

    @Test func customizedNotesSayWhatWasChanged() {
        let settings = makeSettings(["navigation.style": "tabs", "tabs.placement": "bottom", "chat.monospace": true, "chat.lineSpacing": 3, "chat.messageSpacing": 8.5])
        #expect(PresetCustomization.note(for: .windowLayout, settings: settings) == "Customized: tabs at the bottom of the window. Pick a layout to switch to it.")
        #expect(PresetCustomization.note(for: .messageStyle, settings: settings) == "Customized: the Modern layout in a monospaced font. Picking a style sets both the layout and the font.")
        #expect(PresetCustomization.note(for: .density, settings: settings) == "Customized: 3 pt between lines and 8.5 pt between messages. Picking a density sets both.")
        #expect(PresetCustomization.pane(for: .windowLayout) == .layout)
        #expect(PresetCustomization.pane(for: .density) == .messages)
    }

    // MARK: Palette and menus

    @Test func paletteHasACommandForEveryChoice() {
        let commands = VelaCommandCatalog.presetCommands(makeSettings())
        #expect(commands.map(\.paletteTitle) == [
            "Layout: Sidebar", "Layout: Tabs on Top", "Layout: Tabs in Title Bar", "Layout: Focus",
            "Message Style: Modern", "Message Style: Classic IRC", "Message Style: Columns",
            "Density: Compact", "Density: Standard", "Density: Comfortable",
        ])
        #expect(Set(commands.map(\.id)).count == commands.count)
        #expect(commands.map(\.id).contains("layout.tabsOnTop"))
        #expect(commands.map(\.id).contains("messageStyle.columns"))
        #expect(commands.map(\.id).contains("density.compact"))
        // The defaults are checked.
        #expect(commands.filter { $0.isChecked == true }.map(\.paletteTitle) == ["Layout: Sidebar", "Message Style: Modern", "Density: Standard"])
    }

    @Test func aCommandWritesOnlyItsAxis() throws {
        let settings = makeSettings(["chat.fontSize": 16, "chat.lineSpacing": 2, "chat.messageSpacing": 4, "memberList.visible": false])
        let before = settings.values
        let focus = try #require(VelaCommandCatalog.presetCommands(settings).first { $0.id == "layout.focus" })
        focus.perform()
        #expect(settings[.navigationStyle] == .focus)
        let changed = Set(before.keys).union(settings.values.keys).filter { before[$0] != settings.values[$0] }
        #expect(changed == ["navigation.style"])
        let checked = VelaCommandCatalog.presetCommands(settings).filter { $0.isChecked == true }.map(\.id)
        #expect(checked == ["layout.focus", "messageStyle.modern", "density.compact"])

        let columns = try #require(VelaCommandCatalog.presetCommands(for: .messageStyle, settings: settings).first { $0.title == "Columns" })
        columns.perform()
        #expect(settings[.chatLayout] == .columns)
        #expect(settings[.chatFontSize] == 16)
    }

    @Test func aCustomizedAxisHasNothingChecked() {
        let settings = makeSettings(["navigation.style": "tabs", "tabs.placement": "bottom", "chat.lineSpacing": 3])
        let commands = VelaCommandCatalog.presetCommands(settings)
        #expect(commands.filter { $0.category == .layout && $0.isChecked == true }.isEmpty)
        #expect(commands.filter { $0.category == .density && $0.isChecked == true }.isEmpty)
        #expect(commands.filter { $0.category == .messageStyle && $0.isChecked == true }.map(\.title) == ["Modern"])
    }

    @Test func paletteFindsChoicesByNameAndKeyword() throws {
        let items = PaletteSource.commandItems(VelaCommandCatalog.presetCommands(makeSettings()), history: [])
        for (query, id) in [
            ("tabs on top", "layout.tabsOnTop"), ("tabs in title", "layout.tabsInTitleBar"), ("layout focus", "layout.focus"),
            ("distraction", "layout.focus"), ("message style columns", "messageStyle.columns"), ("classic irc", "messageStyle.classic"),
            ("density compact", "density.compact"), ("comfortable", "density.comfortable"),
        ] {
            let first = try #require(PaletteRanker.rows(for: items, query: query, list: .commands).first, "\(query)")
            #expect(first.id == id, "query \(query)")
        }
    }

    // MARK: Focus

    /// With neither a sidebar nor tabs, there's no navigation to move the
    /// keyboard to, and the title bar leaves room for the window buttons.
    @Test func focusHasNoNavigationArea() {
        #expect(FocusAreas.available(hasBuffer: true, showsMembers: true, hasNavigation: false) == [.messages, .messageBox, .members])
        #expect(FocusAreas.available(hasBuffer: false, showsMembers: false, hasNavigation: false).isEmpty)
        var style = ChatStyle()
        style.navigationStyle = .focus
        #expect(trafficLightInset(style: style, sidebarCollapsed: false) == 80)
        style.navigationStyle = .sidebar
        #expect(trafficLightInset(style: style, sidebarCollapsed: false) == 16)
    }

    /// What a layout doesn't show can't be changed from the menus: in
    /// Focus, moving a channel or network is dimmed (and out of the
    /// palette), and Always Show Server Row is for tabs only.
    @MainActor
    @Test func commandsFollowTheLayout() async throws {
        let app = AppModel.demo()
        await app.ready()
        let themes = FileManager.default.temporaryDirectory.appending(path: "VelaLayoutCommands-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: themes) }
        func catalog() -> VelaCommandCatalog {
            VelaCommandCatalog(VelaCommandContext(
                app: app, themeStore: ThemeStore(userThemesDirectory: themes), uiState: UIState(),
                openWindow: EnvironmentValues().openWindow,
                openSettings: EnvironmentValues().openSettings
            ))
        }
        // A channel in the middle of its network's, so both ways can move.
        let session = try #require(app.selectedSession)
        let siblings = session.bufferSiblings(of: try #require(app.selectedBuffer))
        try #require(siblings.count >= 3)
        app.select(siblings[1])
        func moves(_ catalog: VelaCommandCatalog) -> [Bool] {
            [catalog.moveSelectedBuffer(forward: false), catalog.moveSelectedBuffer(forward: true),
             catalog.moveSelectedNetwork(forward: false), catalog.moveSelectedNetwork(forward: true)].map(\.isEnabled)
        }

        app.settings[.navigationStyle] = .tabs
        var commands = catalog()
        #expect(moves(commands).prefix(2) == [true, true])
        #expect(commands.moveSelectedBuffer(forward: true).title == "Move Channel Right")
        #expect(commands.toggleServerTabRow.isEnabled)

        app.settings[.navigationStyle] = .sidebar
        commands = catalog()
        #expect(moves(commands).prefix(2) == [true, true])
        #expect(commands.moveSelectedBuffer(forward: true).title == "Move Channel Down")
        #expect(!commands.toggleServerTabRow.isEnabled)

        app.settings[.navigationStyle] = .focus
        commands = catalog()
        #expect(moves(commands) == [false, false, false, false])
        #expect(!commands.toggleServerTabRow.isEnabled)
        let ids = Set(commands.all.filter(\.isEnabled).map(\.id))
        #expect(!ids.contains("tabs.moveForward") && !ids.contains("tabs.toggleServerRow"))
    }
}

// MARK: - Hosted

extension LinkSelectionTests {
    /// Settings → Presets in an offscreen window, used as VoiceOver would.
    ///
    /// Nested in the serialized `LinkSelectionTests` with the other suites
    /// that use offscreen windows.
    @MainActor
    @Suite("Presets pane, hosted", .serialized)
    struct PresetsPaneHostedTests {
        @Test func everyChoiceIsALabeledButtonAndTheCurrentOnesAreSelected() async throws {
            let host = try await PresetsPaneHost(theme: "Palenight")
            defer { host.close() }
            for axis in PresetAxis.allCases {
                _ = try #require(host.element(labeled: axis.title), "\(axis.title)")
                #expect(!host.saysCustomized(axis))
                for choice in axis.choices {
                    let card = try #require(host.element(labeled: choice.name), "\(choice.name)")
                    #expect(host.isSelected(card) == ["sidebar", "modern", "standard"].contains(choice.id), "\(choice.name)")
                }
            }
        }

        @Test func pressingACardWritesOnlyItsAxis() async throws {
            let host = try await PresetsPaneHost(theme: "Lighter") { settings in
                settings[.chatFontSize] = 15
                settings.choose(.compact)
            }
            defer { host.close() }
            let settings = host.app.settings
            let before = settings.values

            let tabs = try #require(host.element(labeled: "Tabs on Top"))
            #expect(tabs.accessibilityPerformPress?() == true)
            #expect(settings.currentChoice(for: .windowLayout) == .tabsOnTop)
            #expect(settings[.chatFontSize] == 15)
            #expect(settings.currentChoice(for: .density) == .compact)
            let changed = Set(before.keys).union(settings.values.keys).filter { before[$0] != settings.values[$0] }
            #expect(changed.isSubset(of: PresetAxis.windowLayout.keys))

            try await host.settle()
            #expect(host.isSelected(try #require(host.element(labeled: "Tabs on Top"))))
            #expect(!host.isSelected(try #require(host.element(labeled: "Sidebar"))))

            let comfortable = try #require(host.element(labeled: "Comfortable"))
            #expect(comfortable.accessibilityPerformPress?() == true)
            #expect(settings[.chatLineSpacing] == 6)
            #expect(settings[.chatMessageSpacing] == 18)
            #expect(settings.currentChoice(for: .windowLayout) == .tabsOnTop)
        }

        /// A hand-edited row reads Customized, and picking a choice resets
        /// just that row.
        @Test func aCustomizedRowResetsWhenAChoiceIsPicked() async throws {
            let host = try await PresetsPaneHost(theme: "Palenight") { settings in
                settings[.chatMonospace] = true
                settings[.chatLineSpacing] = 3
            }
            defer { host.close() }
            let settings = host.app.settings
            #expect(host.saysCustomized(.messageStyle))
            #expect(host.saysCustomized(.density))
            #expect(!host.saysCustomized(.windowLayout))
            for choice in PresetAxis.messageStyle.choices {
                #expect(!host.isSelected(try #require(host.element(labeled: choice.name))), "\(choice.name)")
            }

            let modern = try #require(host.element(labeled: "Modern"))
            #expect(modern.accessibilityPerformPress?() == true)
            #expect(settings.currentChoice(for: .messageStyle) == .modern)
            #expect(!settings[.chatMonospace])
            #expect(settings.currentChoice(for: .density) == nil, "the density stays customized")
            try await host.settle()
            #expect(!host.saysCustomized(.messageStyle))
            #expect(host.saysCustomized(.density))
            #expect(host.isSelected(try #require(host.element(labeled: "Modern"))))
        }

        /// The Focus layout shows no sidebar and no tabs, and the keyboard
        /// has no navigation area to go to. (The sidebar and the tabs each
        /// have a keyboard area, a `KeyboardFocusView`; with the member list
        /// hidden, nothing else does.)
        @Test(arguments: [PresetChoice.sidebar, .tabsOnTop, .tabsInTitleBar, .focus])
        func focusShowsJustTheConversation(_ layout: PresetChoice) async throws {
            let hosted = try await KeyboardHostedWindow.show { app in
                app.settings.choose(layout)
                app.settings[.memberListVisible] = false
            }
            defer { hosted.close() }
            #expect(Self.keyboardAreas(in: hosted.host) == (layout == .focus ? 0 : 1))
            hosted.uiState.focus(.navigation)
            try await hosted.settle()
            #expect((hosted.focusedArea != nil) == (layout != .focus))
        }

        private static func keyboardAreas(in view: NSView) -> Int {
            view.subviews.reduce(view is KeyboardFocusView ? 1 : 0) { $0 + keyboardAreas(in: $1) }
        }
    }
}
