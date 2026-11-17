// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaStore

extension VelaCommandCatalog {
    /// Spelling, grammar, autocorrect and the other typing options, for the
    /// palette. Checkmarks show what's in effect, including settings that
    /// follow macOS.
    var typingCommands: [VelaCommand] {
        Self.typingCommands(context.app.settings, system: SystemTextSettings.shared.values)
    }

    /// One switch, for the Edit menu.
    func typingCommand(_ toggle: TextCheckingToggle) -> VelaCommand {
        Self.typingCommand(toggle, settings: context.app.settings, system: SystemTextSettings.shared.values)
    }

    /// Static so tests can build them from a bare settings store and fake
    /// macOS values.
    static func typingCommands(_ settings: SettingsStore, system: SystemTextDefaults) -> [VelaCommand] {
        let options = TextCheckingOptions(settings: settings, system: system)
        var commands = [TextCheckingToggle.spelling, .grammar, .autocorrect, .textReplacements].map {
            typingCommand($0, settings: settings, system: system)
        }
        // One palette switch for both; it reads as on while either is.
        let smart = options.smartQuotes || options.smartDashes
        commands.append(VelaCommand(
            id: "input.toggleSmartPunctuation", category: .typing, title: "Use Smart Quotes and Dashes",
            keywords: ["curly quotes", "em dash", "typography", "substitutions", "toggle"], isChecked: smart
        ) { settings[.inputSmartPunctuation] = SystemFollowingBool(!smart) })
        let writingTools = settings[.inputWritingTools]
        commands.append(VelaCommand(
            id: "input.toggleWritingTools", category: .typing, title: "Use Writing Tools",
            keywords: ["apple intelligence", "proofread", "rewrite", "ai", "toggle"], isChecked: writingTools
        ) { settings[.inputWritingTools].toggle() })
        return commands
    }

    static func typingCommand(_ toggle: TextCheckingToggle, settings: SettingsStore, system: SystemTextDefaults) -> VelaCommand {
        let isOn = toggle.isOn(in: TextCheckingOptions(settings: settings, system: system))
        let (id, title, menuTitle, keywords): (String, String, String?, [String]) = switch toggle {
        case .spelling:
            ("input.toggleSpellCheck", "Check Spelling While Typing", nil, ["spell checker", "underline", "misspelled", "toggle"])
        case .grammar:
            ("input.toggleGrammar", "Check Grammar", "Check Grammar With Spelling", ["grammar", "underline", "toggle"])
        case .autocorrect:
            ("input.toggleAutocorrect", "Correct Spelling Automatically", nil, ["autocorrect", "auto-correct", "spelling", "toggle"])
        case .textReplacements:
            ("input.toggleTextReplacements", "Use Text Replacements", "Text Replacement", ["shortcuts", "expand", "substitutions", "toggle"])
        case .smartQuotes:
            ("input.toggleSmartQuotes", "Smart Quotes", nil, [])
        case .smartDashes:
            ("input.toggleSmartDashes", "Smart Dashes", nil, [])
        }
        // Quotes and dashes share one setting; the palette has a single switch for them.
        let inPalette = toggle != .smartQuotes && toggle != .smartDashes
        return VelaCommand(
            id: id, category: .typing, title: title, menuTitle: menuTitle,
            keywords: keywords, isChecked: isOn, showsInPalette: inPalette
        ) { toggle.write(!isOn, to: settings) }
    }
}

/// Edit → Spelling and Grammar and Edit → Substitutions. SwiftUI leaves them
/// out (its `TextEditingCommands` would also add a Find menu Vela doesn't
/// use, and a ⌘J that clashes with Join Channel). The switches are Vela's
/// typing settings, so they stick and apply to every conversation.
struct TypingMenuItems: View {
    let commands: VelaCommandCatalog

    var body: some View {
        Menu("Spelling and Grammar") {
            Button("Show Spelling and Grammar") {
                NSApp.sendAction(#selector(NSText.showGuessPanel(_:)), to: nil, from: nil)
            }
            .keyboardShortcut(":", modifiers: .command)
            Button("Check Document Now") {
                NSApp.sendAction(#selector(NSText.checkSpelling(_:)), to: nil, from: nil)
            }
            .keyboardShortcut(";", modifiers: .command)
            Divider()
            CommandMenuToggle(commands.typingCommand(.spelling))
            CommandMenuToggle(commands.typingCommand(.grammar))
            CommandMenuToggle(commands.typingCommand(.autocorrect))
        }
        Menu("Substitutions") {
            Button("Show Substitutions") {
                NSApp.sendAction(#selector(NSTextView.orderFrontSubstitutionsPanel(_:)), to: nil, from: nil)
            }
            Divider()
            CommandMenuToggle(commands.typingCommand(.smartQuotes))
            CommandMenuToggle(commands.typingCommand(.smartDashes))
            CommandMenuToggle(commands.typingCommand(.textReplacements))
        }
    }
}
