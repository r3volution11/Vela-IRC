// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Observation
import VelaStore

/// The text options in System Settings → Keyboard → Text Input that Vela's
/// "follow macOS" settings track.
nonisolated struct SystemTextDefaults: Equatable, Sendable {
    var autocorrect: Bool
    var textReplacements: Bool
    var smartQuotes: Bool
    var smartDashes: Bool

    /// What macOS says right now.
    static var current: SystemTextDefaults {
        SystemTextDefaults(
            autocorrect: NSSpellChecker.isAutomaticSpellingCorrectionEnabled,
            textReplacements: NSSpellChecker.isAutomaticTextReplacementEnabled,
            smartQuotes: NSSpellChecker.isAutomaticQuoteSubstitutionEnabled,
            smartDashes: NSSpellChecker.isAutomaticDashSubstitutionEnabled
        )
    }

    /// Smart quotes and dashes are one setting in Vela; it reads as on when
    /// macOS substitutes either.
    var smartPunctuation: Bool { smartQuotes || smartDashes }
}

/// ``SystemTextDefaults``, kept current: changing them in System Settings
/// updates the composer, menus and Settings live.
@Observable
final class SystemTextSettings {
    private(set) var values: SystemTextDefaults

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    /// Fixed values, for tests and previews.
    init(values: SystemTextDefaults) {
        self.values = values
    }

    /// The live instance.
    static let shared: SystemTextSettings = {
        let settings = SystemTextSettings(values: .current)
        settings.startObserving()
        return settings
    }()

    private func startObserving() {
        let names: [Notification.Name] = [
            NSSpellChecker.didChangeAutomaticSpellingCorrectionNotification,
            NSSpellChecker.didChangeAutomaticTextReplacementNotification,
            NSSpellChecker.didChangeAutomaticQuoteSubstitutionNotification,
            NSSpellChecker.didChangeAutomaticDashSubstitutionNotification,
            // In case a change arrived while Vela wasn't listening.
            NSApplication.didBecomeActiveNotification,
        ]
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }

    func refresh() {
        let current = SystemTextDefaults.current
        if current != values { values = current }
    }
}

/// The composer's text checking, resolved from Vela's settings and macOS.
nonisolated struct TextCheckingOptions: Equatable, Sendable {
    var spelling: Bool
    var grammar: Bool
    var autocorrect: Bool
    var textReplacements: Bool
    var smartQuotes: Bool
    var smartDashes: Bool
    var writingTools: Bool

    /// Everything off, e.g. for text that holds IRC commands.
    static let off = TextCheckingOptions(
        spelling: false, grammar: false, autocorrect: false, textReplacements: false,
        smartQuotes: false, smartDashes: false, writingTools: false
    )

    init(
        spelling: Bool, grammar: Bool, autocorrect: Bool, textReplacements: Bool,
        smartQuotes: Bool, smartDashes: Bool, writingTools: Bool
    ) {
        self.spelling = spelling
        self.grammar = grammar
        self.autocorrect = autocorrect
        self.textReplacements = textReplacements
        self.smartQuotes = smartQuotes
        self.smartDashes = smartDashes
        self.writingTools = writingTools
    }

    /// Resolves the follow-macOS settings against `system`. While smart
    /// punctuation follows macOS, quotes and dashes each follow their own
    /// macOS switch; set in Vela, it turns both on or off.
    init(
        spellCheck: Bool,
        grammarCheck: Bool,
        autocorrect: SystemFollowingBool,
        textReplacements: SystemFollowingBool,
        smartPunctuation: SystemFollowingBool,
        writingTools: Bool,
        system: SystemTextDefaults
    ) {
        self.init(
            spelling: spellCheck,
            grammar: grammarCheck,
            autocorrect: autocorrect.resolved(system: system.autocorrect),
            textReplacements: textReplacements.resolved(system: system.textReplacements),
            smartQuotes: smartPunctuation.resolved(system: system.smartQuotes),
            smartDashes: smartPunctuation.resolved(system: system.smartDashes),
            writingTools: writingTools
        )
    }
}

extension TextCheckingOptions {
    @MainActor
    init(settings: SettingsStore, system: SystemTextDefaults) {
        self.init(
            spellCheck: settings[.inputSpellCheck],
            grammarCheck: settings[.inputGrammarCheck],
            autocorrect: settings[.inputAutocorrect],
            textReplacements: settings[.inputTextReplacements],
            smartPunctuation: settings[.inputSmartPunctuation],
            writingTools: settings[.inputWritingTools],
            system: system
        )
    }
}

/// One of the text-checking switches in Edit → Spelling and Grammar and
/// Edit → Substitutions (and the composer's right-click menu).
nonisolated enum TextCheckingToggle: CaseIterable, Sendable {
    case spelling
    case grammar
    case autocorrect
    case textReplacements
    case smartQuotes
    case smartDashes

    /// Saves a menu choice. It's always an explicit value, even when it
    /// matches macOS, as a menu choice should be. Quotes and dashes share
    /// `input.smartPunctuation`.
    @MainActor
    func write(_ isOn: Bool, to settings: SettingsStore) {
        switch self {
        case .spelling: settings[.inputSpellCheck] = isOn
        case .grammar: settings[.inputGrammarCheck] = isOn
        case .autocorrect: settings[.inputAutocorrect] = SystemFollowingBool(isOn)
        case .textReplacements: settings[.inputTextReplacements] = SystemFollowingBool(isOn)
        case .smartQuotes, .smartDashes: settings[.inputSmartPunctuation] = SystemFollowingBool(isOn)
        }
    }

    /// The switch's current effective state.
    func isOn(in options: TextCheckingOptions) -> Bool {
        switch self {
        case .spelling: options.spelling
        case .grammar: options.grammar
        case .autocorrect: options.autocorrect
        case .textReplacements: options.textReplacements
        case .smartQuotes: options.smartQuotes
        case .smartDashes: options.smartDashes
        }
    }
}
