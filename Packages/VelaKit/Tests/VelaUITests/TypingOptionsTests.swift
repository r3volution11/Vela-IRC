// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaStore
@testable import VelaUI

private func makeSettings() -> SettingsStore {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "VelaUITests-\(UUID().uuidString)", directoryHint: .isDirectory)
        .appending(path: "settings.json")
    return SettingsStore(fileURL: url, watchForChanges: false)
}

private let macOSAllOn = SystemTextDefaults(autocorrect: true, textReplacements: true, smartQuotes: true, smartDashes: true)
private let macOSAllOff = SystemTextDefaults(autocorrect: false, textReplacements: false, smartQuotes: false, smartDashes: false)
/// Quotes on, dashes off, as System Settings allows.
private let macOSMixed = SystemTextDefaults(autocorrect: false, textReplacements: true, smartQuotes: true, smartDashes: false)

@MainActor
@Suite("Typing options")
struct TypingOptionsTests {
    @Test func defaultsFollowMacOS() {
        let settings = makeSettings()
        let on = TextCheckingOptions(settings: settings, system: macOSAllOn)
        #expect(on.spelling)
        #expect(!on.grammar)
        #expect(on.autocorrect && on.textReplacements && on.smartQuotes && on.smartDashes)
        #expect(on.writingTools)

        let off = TextCheckingOptions(settings: settings, system: macOSAllOff)
        #expect(!off.autocorrect && !off.textReplacements && !off.smartQuotes && !off.smartDashes)
    }

    @Test func quotesAndDashesFollowTheirOwnMacOSSwitch() {
        let options = TextCheckingOptions(settings: makeSettings(), system: macOSMixed)
        #expect(options.smartQuotes)
        #expect(!options.smartDashes)
        #expect(!options.autocorrect)
        #expect(options.textReplacements)
    }

    @Test func valuesSetInVelaOverrideMacOS() {
        let settings = makeSettings()
        settings[.inputAutocorrect] = .off
        settings[.inputTextReplacements] = .on
        settings[.inputSmartPunctuation] = .on
        settings[.inputSpellCheck] = false
        settings[.inputGrammarCheck] = true
        settings[.inputWritingTools] = false

        let options = TextCheckingOptions(settings: settings, system: macOSMixed)
        #expect(!options.autocorrect)
        #expect(options.textReplacements)
        #expect(options.smartQuotes && options.smartDashes)
        #expect(!options.spelling)
        #expect(options.grammar)
        #expect(!options.writingTools)

        settings[.inputSmartPunctuation] = .off
        let off = TextCheckingOptions(settings: settings, system: macOSAllOn)
        #expect(!off.smartQuotes && !off.smartDashes)
    }

    @Test func resettingFollowsMacOSAgain() {
        let settings = makeSettings()
        settings[.inputAutocorrect] = .off
        settings.reset(.inputAutocorrect)
        #expect(!settings.isSet(.inputAutocorrect))
        #expect(TextCheckingOptions(settings: settings, system: macOSAllOn).autocorrect)
    }

    @Test func smartPunctuationReadsOnWhenMacOSDoesEither() {
        #expect(macOSMixed.smartPunctuation)
        #expect(!macOSAllOff.smartPunctuation)
    }
}

@MainActor
@Suite("Menu toggles to settings")
struct TextCheckingToggleTests {
    @Test func eachToggleWritesItsSetting() {
        let settings = makeSettings()
        TextCheckingToggle.spelling.write(false, to: settings)
        #expect(settings[.inputSpellCheck] == false)
        TextCheckingToggle.grammar.write(true, to: settings)
        #expect(settings[.inputGrammarCheck] == true)
        TextCheckingToggle.autocorrect.write(true, to: settings)
        #expect(settings[.inputAutocorrect] == .on)
        TextCheckingToggle.textReplacements.write(false, to: settings)
        #expect(settings[.inputTextReplacements] == .off)
    }

    @Test func quotesAndDashesShareSmartPunctuation() {
        let settings = makeSettings()
        TextCheckingToggle.smartQuotes.write(false, to: settings)
        #expect(settings[.inputSmartPunctuation] == .off)
        TextCheckingToggle.smartDashes.write(true, to: settings)
        #expect(settings[.inputSmartPunctuation] == .on)
        let options = TextCheckingOptions(settings: settings, system: macOSAllOff)
        #expect(options.smartQuotes && options.smartDashes)
    }

    @Test func aMenuChoiceIsExplicitEvenWhenItMatchesMacOS() {
        let settings = makeSettings()
        // macOS has autocorrect on; choosing "on" in the menu still pins it.
        TextCheckingToggle.autocorrect.write(true, to: settings)
        #expect(settings.isSet(.inputAutocorrect))
        #expect(settings.value(forKey: "input.autocorrect") == .bool(true))
    }

    @Test func toggleReadsTheEffectiveState() {
        let options = TextCheckingOptions(settings: makeSettings(), system: macOSMixed)
        #expect(TextCheckingToggle.smartQuotes.isOn(in: options))
        #expect(!TextCheckingToggle.smartDashes.isOn(in: options))
        #expect(!TextCheckingToggle.autocorrect.isOn(in: options))
    }
}

@MainActor
@Suite("Typing commands")
struct TypingCommandTests {
    @Test func paletteListsTheSwitches() {
        let commands = VelaCommandCatalog.typingCommands(makeSettings(), system: macOSAllOn)
        #expect(commands.filter(\.showsInPalette).map(\.id) == [
            "input.toggleSpellCheck", "input.toggleGrammar", "input.toggleAutocorrect",
            "input.toggleTextReplacements", "input.toggleSmartPunctuation", "input.toggleWritingTools",
        ])
        #expect(commands.allSatisfy { $0.category == .typing })
        #expect(commands.first?.paletteTitle == "Typing: Check Spelling While Typing")
    }

    @Test func checkmarksShowWhatsInEffect() throws {
        let settings = makeSettings()
        let commands = VelaCommandCatalog.typingCommands(settings, system: macOSMixed)
        let autocorrect = try #require(commands.first { $0.id == "input.toggleAutocorrect" })
        let replacements = try #require(commands.first { $0.id == "input.toggleTextReplacements" })
        let smart = try #require(commands.first { $0.id == "input.toggleSmartPunctuation" })
        #expect(autocorrect.isChecked == false)
        #expect(replacements.isChecked == true)
        #expect(smart.isChecked == true)
    }

    @Test func performingWritesAnExplicitValue() throws {
        let settings = makeSettings()
        let autocorrect = try #require(
            VelaCommandCatalog.typingCommands(settings, system: macOSAllOff).first { $0.id == "input.toggleAutocorrect" }
        )
        autocorrect.perform()
        #expect(settings[.inputAutocorrect] == .on)

        let smart = try #require(
            VelaCommandCatalog.typingCommands(settings, system: macOSMixed).first { $0.id == "input.toggleSmartPunctuation" }
        )
        smart.perform()
        #expect(settings[.inputSmartPunctuation] == .off)

        let writingTools = try #require(
            VelaCommandCatalog.typingCommands(settings, system: macOSAllOn).first { $0.id == "input.toggleWritingTools" }
        )
        writingTools.perform()
        #expect(settings[.inputWritingTools] == false)
    }

    @Test func menuItemsUseMacOSTitles() {
        let settings = makeSettings()
        let title = { (toggle: TextCheckingToggle) in
            VelaCommandCatalog.typingCommand(toggle, settings: settings, system: macOSAllOn).resolvedMenuTitle
        }
        #expect(title(.grammar) == "Check Grammar With Spelling")
        #expect(title(.smartQuotes) == "Smart Quotes")
        #expect(title(.smartDashes) == "Smart Dashes")
        #expect(title(.textReplacements) == "Text Replacement")
        #expect(!VelaCommandCatalog.typingCommand(.smartQuotes, settings: settings, system: macOSAllOn).showsInPalette)
    }

    @Test func smartDashesMenuItemTurnsBothOn() {
        let settings = makeSettings()
        let dashes = VelaCommandCatalog.typingCommand(.smartDashes, settings: settings, system: macOSMixed)
        #expect(dashes.isChecked == false)
        dashes.perform()
        #expect(settings[.inputSmartPunctuation] == .on)
    }
}
