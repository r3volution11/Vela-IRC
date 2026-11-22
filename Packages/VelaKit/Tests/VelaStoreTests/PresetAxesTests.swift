// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Observation
import Testing
import VelaFoundation
@testable import VelaStore

/// Settings → Presets' three axes: what each choice writes, how the current
/// choice (or "Customized") is worked out, that choosing writes one axis in
/// one change, and how setups from before 1.5 map onto the axes.
@MainActor
@Suite("Preset axes")
struct PresetAxesTests {
    private func store(_ text: String? = nil, in directory: TemporaryDirectory) throws -> SettingsStore {
        let url = directory.file("settings.json")
        if let text { try writeString(text, to: url) }
        return SettingsStore(fileURL: url, watchForChanges: false)
    }

    private func axes(_ store: SettingsStore) -> [PresetAxis: String] {
        var result: [PresetAxis: String] = [:]
        for axis in PresetAxis.allCases {
            result[axis] = store.currentChoice(for: axis)?.id ?? "customized"
        }
        return result
    }

    private func axes(_ layout: String, _ style: String, _ density: String) -> [PresetAxis: String] {
        [.windowLayout: layout, .messageStyle: style, .density: density]
    }

    // MARK: The mapping

    /// The table the docs and the UI promise.
    @Test func everyChoiceWritesItsSettings() {
        let expected: [String: [String: JSONValue]] = [
            "windowLayout.sidebar": ["navigation.style": "sidebar"],
            "windowLayout.tabsOnTop": ["navigation.style": "tabs", "tabs.placement": "top"],
            "windowLayout.tabsInTitleBar": ["navigation.style": "tabs", "tabs.placement": "titleBar"],
            "windowLayout.focus": ["navigation.style": "focus"],
            "messageStyle.modern": ["chat.layout": "grouped", "chat.monospace": false],
            "messageStyle.classic": ["chat.layout": "classic", "chat.monospace": true],
            "messageStyle.columns": ["chat.layout": "columns", "chat.monospace": false],
            "density.compact": ["chat.lineSpacing": 1, "chat.messageSpacing": 2],
            "density.standard": ["chat.lineSpacing": 4, "chat.messageSpacing": 12],
            "density.comfortable": ["chat.lineSpacing": 6, "chat.messageSpacing": 18],
        ]
        let all = PresetAxis.allCases.flatMap(\.choices)
        #expect(Set(all.map(\.qualifiedID)) == Set(expected.keys))
        for choice in all {
            #expect(choice.values == expected[choice.qualifiedID], "\(choice.qualifiedID)")
        }
        #expect(PresetAxis.windowLayout.choices.map(\.name) == ["Sidebar", "Tabs on Top", "Tabs in Title Bar", "Focus"])
        #expect(PresetAxis.messageStyle.choices.map(\.name) == ["Modern", "Classic IRC", "Columns"])
        #expect(PresetAxis.density.choices.map(\.name) == ["Compact", "Standard", "Comfortable"])
    }

    @Test func axesOwnSeparateKnownSettings() {
        var seen: Set<String> = []
        for axis in PresetAxis.allCases {
            for key in axis.keys {
                #expect(SettingsCatalog.descriptor(forKey: key) != nil, "\(axis) writes unknown key \(key)")
                #expect(seen.insert(key).inserted, "\(key) belongs to two axes")
            }
            for choice in axis.choices {
                #expect(choice.axis == axis)
                #expect(Set(choice.values.keys).isSubset(of: axis.keys))
            }
        }
        #expect(PresetAxis.windowLayout.keys == ["navigation.style", "tabs.placement"])
        #expect(PresetAxis.messageStyle.keys == ["chat.layout", "chat.monospace"])
        #expect(PresetAxis.density.keys == ["chat.lineSpacing", "chat.messageSpacing"])
        // Density never touches the font size someone set by hand.
        #expect(!PresetAxis.allCases.flatMap(\.keys).contains("chat.fontSize"))
    }

    /// Standard is Vela's defaults, so nothing moves for anyone who never
    /// changed their spacing.
    @Test func standardIsTheDefaults() {
        #expect(PresetChoice.standard.values["chat.lineSpacing"] == SettingKey<Double>.chatLineSpacing.defaultJSONValue)
        #expect(PresetChoice.standard.values["chat.messageSpacing"] == SettingKey<Double>.chatMessageSpacing.defaultJSONValue)
        #expect(ModernChatSpacingMigration.newSpacing == (line: 4, message: 12))
    }

    @Test func aFreshInstallIsSidebarModernStandard() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        #expect(axes(try store(in: directory)) == axes("sidebar", "modern", "standard"))
    }

    @Test func choicesAreFoundByID() {
        #expect(PresetChoice.named("tabsOnTop") == .tabsOnTop)
        #expect(PresetChoice.named("density.compact") == .compact)
        #expect(PresetChoice.named("classic", on: .messageStyle) == .classicIRC)
        #expect(PresetChoice.named("classic", on: .density) == nil)
        #expect(PresetChoice.named("nope") == nil)
    }

    @Test func focusIsANavigationStyle() {
        #expect(SettingKey<NavigationStyle>.navigationStyle.value(from: "focus") == .focus)
        #expect(NavigationStyle.allCases == [.sidebar, .tabs, .focus])
    }

    // MARK: Choosing

    @Test(arguments: PresetAxis.allCases.flatMap(\.choices))
    func choosingIsDetectedAndTouchesOnlyItsAxis(_ choice: PresetChoice) throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let store = try store(#"""
        {
          "appearance.theme": "Nord",
          "chat.fontSize": 17,
          "media.videos": "compact",
          "memberList.visible": false,
          "tabs.roundness": 1,
          "navigation.style": "tabs",
          "tabs.placement": "bottom",
          "chat.layout": "columns",
          "chat.monospace": true,
          "chat.lineSpacing": 3,
          "chat.messageSpacing": 7
        }
        """#, in: directory)
        let before = store.values
        let otherAxes = PresetAxis.allCases.filter { $0 != choice.axis }
        let othersBefore = otherAxes.map { store.currentChoice(for: $0) }

        store.choose(choice)

        #expect(store.currentChoice(for: choice.axis) == choice)
        #expect(otherAxes.map { store.currentChoice(for: $0) } == othersBefore)
        let changed = Set(before.keys).union(store.values.keys).filter { before[$0] != store.values[$0] }
        #expect(changed.isSubset(of: choice.axis.keys), "\(choice.qualifiedID) changed \(changed.sorted())")
        for key in ["appearance.theme", "chat.fontSize", "media.videos", "memberList.visible", "tabs.roundness"] {
            #expect(store.values[key] == before[key], "\(key)")
        }
    }

    /// A value that's the default is removed, not written, so the choice
    /// follows the defaults if they change; picking Sidebar leaves the tab
    /// placement for the next time tabs are chosen.
    @Test func defaultsAreRemovedRatherThanWritten() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let store = try store(#"{"chat.lineSpacing": 1, "chat.messageSpacing": 2, "tabs.placement": "titleBar"}"#, in: directory)

        store.choose(.standard)
        #expect(store.values["chat.lineSpacing"] == nil)
        #expect(store.values["chat.messageSpacing"] == nil)

        store.choose(.tabsOnTop)
        #expect(store.values["navigation.style"] == "tabs")
        #expect(store.values["tabs.placement"] == nil, "top is the default")

        store.choose(.tabsInTitleBar)
        store.choose(.sidebar)
        #expect(store.values["navigation.style"] == nil, "the sidebar is the default")
        #expect(store.values["tabs.placement"] == "titleBar")
        #expect(axes(store) == axes("sidebar", "modern", "standard"))

        store.choose(.focus)
        store.flush()
        let text = try readString(directory.file("settings.json"))
        #expect(text.contains(#""navigation.style": "focus""#))
        #expect(!text.contains("chat.lineSpacing"))
    }

    // MARK: Customized

    @Test func handEditedAxesAreCustomized() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let store = try store(in: directory)

        store[.navigationStyle] = .tabs
        store[.tabsPlacement] = .bottom
        #expect(store.currentChoice(for: .windowLayout) == nil)
        // The rail is still the sidebar, and the placement is ignored there.
        store[.navigationStyle] = .sidebar
        store[.sidebarCollapsed] = true
        #expect(store.currentChoice(for: .windowLayout) == .sidebar)

        store[.chatMonospace] = true
        #expect(store.currentChoice(for: .messageStyle) == nil, "Modern in a monospaced font")
        store[.chatLayout] = .classic
        #expect(store.currentChoice(for: .messageStyle) == .classicIRC)
        store[.chatMonospace] = false
        #expect(store.currentChoice(for: .messageStyle) == nil, "Classic without the monospaced font")

        store[.chatLineSpacing] = 3
        #expect(store.currentChoice(for: .density) == nil)
        store[.chatLineSpacing] = 4
        #expect(store.currentChoice(for: .density) == .standard)
        store[.chatMessageSpacing] = 12.00001
        #expect(store.currentChoice(for: .density) == .standard, "numbers compare loosely")

        // The font size and everything else are outside every axis.
        store[.chatFontSize] = 18
        store[.tabsRoundness] = 0
        #expect(store.currentChoice(for: .density) == .standard)

        // Picking a choice resets just its axis.
        store[.chatLineSpacing] = 9
        store.choose(.classicIRC)
        #expect(store.currentChoice(for: .messageStyle) == .classicIRC)
        #expect(store.currentChoice(for: .density) == nil)
        #expect(store[.chatFontSize] == 18)
    }

    /// Settings are read the way the app reads them: an invalid value is
    /// its default.
    @Test func invalidValuesReadAsTheirDefaults() {
        #expect(PresetAxis.windowLayout.currentChoice(in: ["navigation.style": "bogus"]) == .sidebar)
        #expect(PresetAxis.windowLayout.currentChoice(in: ["navigation.style": "tabs"]) == .tabsOnTop)
        #expect(PresetAxis.windowLayout.currentChoice(in: ["navigation.style": "tabs", "tabs.placement": "bottom"]) == nil)
        #expect(PresetAxis.density.currentChoice(in: ["chat.lineSpacing": "1", "chat.messageSpacing": 12]) == .standard)
        #expect(PresetAxis.messageStyle.currentChoice(in: ["chat.monospace": "yes"]) == .modern)
    }

    // MARK: One change

    /// Choosing replaces the settings once, however many keys it writes:
    /// one update for the views watching settings, and one save.
    @Test func choosingIsOneChange() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let store = try store(in: directory)
        store.saveDelay = .milliseconds(20)

        let counter = ChangeCounter(store)

        // The counting works: two keys set one by one are two changes.
        store.setValue(5, forKey: "chat.lineSpacing")
        store.setValue(9, forKey: "chat.messageSpacing")
        #expect(counter.count == 2)

        store.choose(.tabsInTitleBar)  // two keys
        #expect(counter.count == 3)

        try await Task.sleep(for: .milliseconds(100))
        let revision = store.fileRevision
        store.choose(.compact)  // two more
        #expect(counter.count == 4)
        #expect(await waitUntil { store.fileRevision > revision })
        try await Task.sleep(for: .milliseconds(60))
        #expect(store.fileRevision == revision + 1, "one write to settings.json")

        // Choosing what's already chosen changes nothing.
        store.choose(.compact)
        #expect(counter.count == 4)
    }

    /// Counts every change to a store's `values`, tracking again after each.
    @MainActor
    private final class ChangeCounter {
        private let store: SettingsStore
        private(set) var count = 0

        init(_ store: SettingsStore) {
            self.store = store
            track()
        }

        private func track() {
            withObservationTracking {
                _ = store.values
            } onChange: { [weak self] in
                MainActor.assumeIsolated {
                    self?.count += 1
                    self?.track()
                }
            }
        }
    }

    @Test func setValuesWritesSeveralKeysAtOnce() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let store = try store(#"{"chat.fontSize": 15, "chat.layout": "classic"}"#, in: directory)
        store.setValues(["chat.fontSize": nil, "chat.monospace": true, "chat.layout": "classic"])
        store.flush()
        #expect(store.values == ["chat.layout": "classic", "chat.monospace": true])
        let reopened = SettingsStore(fileURL: directory.file("settings.json"), watchForChanges: false)
        #expect(reopened.values == store.values)
    }

    // MARK: Upgrading from presets before 1.5

    /// Each of Vela 1.0–1.4's presets lands on the axes it matches; the
    /// rest of it (font size, media, unread settings) stays as it was.
    @Test(arguments: [
        ("classic", "sidebar", "classic", "compact"),
        ("modern", "sidebar", "modern", "standard"),
        ("tabbed", "tabsOnTop", "modern", "customized"),
        ("focus", "tabsInTitleBar", "columns", "customized"),
    ])
    func oldPresetsMapOntoTheAxes(_ preset: String, _ layout: String, _ style: String, _ density: String) throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let store = try store(in: directory)
        store.apply(try #require(SettingsPreset.all.first { $0.id == preset }))
        let before = store.values

        // Nothing is migrated: no rule touches what the preset wrote.
        #expect(store.applyMigrations().isEmpty)
        #expect(store.values == before)
        #expect(axes(store) == axes(layout, style, density))
    }

    /// 1.0's Classic IRC, as written before the media keys were split:
    /// after the existing migration, Sidebar, Classic IRC and Compact.
    @Test func classicFromVela1MapsOntoTheAxes() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let store = try store(#"""
        {
          "navigation.style": "sidebar",
          "chat.layout": "classic",
          "chat.monospace": true,
          "chat.fontSize": 12,
          "chat.lineSpacing": 1,
          "chat.messageSpacing": 2,
          "chat.showAvatars": false,
          "chat.showJoinPart": "show",
          "chat.showTimestamps": true,
          "sidebar.rowHeight": 20,
          "sidebar.fontSize": 12,
          "memberList.visible": true,
          "media.presentation": "compact",
          "media.loadVideoEmbeds": false
        }
        """#, in: directory)
        store.applyMigrations()
        #expect(axes(store) == axes("sidebar", "classic", "compact"))
        #expect(store[.chatFontSize] == 12, "the font size stays")
    }

    /// 1.0's Modern Chat spacing (2 and 6) moves to Standard at launch, as
    /// before; until it has, the density is customized.
    @Test func modernFromVela1BecomesStandard() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let store = try store(#"{"chat.layout": "grouped", "chat.lineSpacing": 2, "chat.messageSpacing": 6}"#, in: directory)
        #expect(axes(store) == axes("sidebar", "modern", "customized"))
        ModernChatSpacingMigration.run(settings: store, record: LaunchRecord.inMemory(), version: "1.5.0")
        #expect(axes(store) == axes("sidebar", "modern", "standard"))
    }

    /// Setups of your own map onto whatever axes they match.
    @Test(arguments: [
        (#"{"navigation.style": "tabs", "tabs.placement": "bottom", "chat.layout": "columns"}"#, "customized", "columns", "standard"),
        (#"{"navigation.style": "tabs", "chat.layout": "grouped", "chat.monospace": true}"#, "tabsOnTop", "customized", "standard"),
        (#"{"sidebar.collapsed": true, "chat.layout": "classic", "chat.monospace": true, "chat.lineSpacing": 6, "chat.messageSpacing": 18}"#, "sidebar", "classic", "comfortable"),
        (#"{"chat.lineSpacing": 2, "chat.messageSpacing": 3, "chat.fontSize": 11}"#, "sidebar", "modern", "customized"),
        (#"{"tabs.placement": "titleBar"}"#, "sidebar", "modern", "standard"),
    ])
    func customSetupsMapOntoWhatTheyMatch(_ text: String, _ layout: String, _ style: String, _ density: String) throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let store = try store(text, in: directory)
        #expect(store.applyMigrations().isEmpty)
        #expect(axes(store) == axes(layout, style, density))
    }
}
