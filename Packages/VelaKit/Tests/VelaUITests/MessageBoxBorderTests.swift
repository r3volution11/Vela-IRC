// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaFoundation
import VelaStore
import VelaTheme
@testable import VelaUI

@Suite("Message box border")
struct MessageBoxBorderTests {
    @Test func noneDrawsNothing() {
        #expect(MessageBoxBorder.none.stroke(isFocused: false) == nil)
        #expect(MessageBoxBorder.none.stroke(isFocused: true) == nil)
        #expect(!MessageBoxBorder.none.changesWithFocus)
    }

    @Test func subtleIsTheQuietLineFocusedOrNot() {
        let expected = MessageBoxBorderStroke(token: ThemeKey.inputBorder, width: 1)
        #expect(MessageBoxBorder.subtle.stroke(isFocused: false) == expected)
        #expect(MessageBoxBorder.subtle.stroke(isFocused: true) == expected)
        #expect(!MessageBoxBorder.subtle.changesWithFocus)
    }

    @Test func accentTurnsTheFocusBorderWhileTyping() {
        #expect(MessageBoxBorder.accent.stroke(isFocused: false) == MessageBoxBorderStroke(token: ThemeKey.inputBorder, width: 1))
        #expect(MessageBoxBorder.accent.stroke(isFocused: true) == MessageBoxBorderStroke(token: ThemeKey.inputFocusBorder, width: 1.5))
        #expect(MessageBoxBorder.accent.changesWithFocus)
    }

    @MainActor
    @Test func paletteCommandsSetTheStyle() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "VelaUITests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "settings.json")
        let settings = SettingsStore(fileURL: url, watchForChanges: false)

        var commands = VelaCommandCatalog.messageBoxBorderCommands(settings)
        #expect(commands.map(\.paletteTitle) == [
            "Typing: Message Box Border: None",
            "Typing: Message Box Border: Subtle",
            "Typing: Message Box Border: Accent When Typing",
        ])
        #expect(commands.map(\.isChecked) == [false, true, false], "Subtle by default")
        #expect(Set(commands.map(\.id)).count == 3)

        try #require(commands.first).perform()
        #expect(settings[.appearanceMessageBoxBorder] == MessageBoxBorder.none)
        commands = VelaCommandCatalog.messageBoxBorderCommands(settings)
        #expect(commands.map(\.isChecked) == [true, false, false])

        commands[2].perform()
        #expect(settings[.appearanceMessageBoxBorder] == .accent)
    }

    @MainActor
    @Test func layoutPreviewFollowsTheStyle() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "VelaUITests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "settings.json")
        let settings = SettingsStore(fileURL: url, watchForChanges: false)
        #expect(LayoutSchematicConfig(settings: settings).messageBoxBorder == .subtle)
        settings[.appearanceMessageBoxBorder] = .none
        #expect(LayoutSchematicConfig(settings: settings).messageBoxBorder == MessageBoxBorder.none)
    }
}

@Suite("Message box border in the settings editor")
struct MessageBoxBorderEditorTests {
    let customizations: [String: JSONValue] = [
        "[Palenight]": .object([
            "input.border": "#4A4F6A",
            "input.focusBorder": "#4A4F6A",
            "chat.link": "#FF0000",
            "$borderPicker": .array(["input.border", "input.focusBorder"]),
        ]),
    ]

    @Test func markerIsNotAnEntry() throws {
        let model = ColorCustomizationsModel(customizations)
        let scope = try #require(model.scope("[Palenight]"))
        #expect(scope.entries.map(\.token) == ["chat.link", "input.border", "input.focusBorder"])
        #expect(model.count == 3)
    }

    @Test func editingByHandMakesItYours() throws {
        let edited = ColorCustomizationsModel.setting("input.border", to: "#000000", inScope: "[Palenight]", of: customizations)
        let scope = try #require(edited["[Palenight]"]?.objectValue)
        #expect(scope["$borderPicker"] == .array(["input.focusBorder"]))
        let both = ColorCustomizationsModel.setting("input.focusBorder", to: "#000000", inScope: "[Palenight]", of: edited)
        #expect(both["[Palenight]"]?.objectValue?["$borderPicker"] == nil)
    }
}
