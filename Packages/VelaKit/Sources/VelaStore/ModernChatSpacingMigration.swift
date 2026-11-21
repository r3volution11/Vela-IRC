// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaFoundation

/// Moves Vela 1.0's Modern Chat spacing to Vela 1.1's, once.
///
/// Vela 1.1 gave the Modern Chat preset (and the defaults) more room: line
/// spacing 4 pt and message spacing 12 pt, up from 2 and 6. Applying the
/// preset in 1.0 wrote 2 and 6 into settings.json, so Settings → Presets
/// would show those Macs as Custom. A settings.json with exactly
/// `chat.lineSpacing: 2` and `chat.messageSpacing: 6` gets 4 and 12
/// instead, written explicitly as the preset writes them. Any other
/// spacing, or none (a new install, where the defaults are already the new
/// ones), is left alone.
///
/// It runs once per Mac (see ``LaunchRecord/hasRun(_:)``), so spacing set
/// to 2 and 6 by hand later stays, and waits for a launch where
/// settings.json can be read.
public enum ModernChatSpacingMigration {
    /// The ``LaunchRecord`` migration id.
    public static let id = "modernChatSpacing"
    /// The ``LaunchRecord`` event recorded when the spacing moved, which
    /// the What's New notice about it looks for.
    public static let movedEvent = "chat.modernSpacingMoved"

    /// Vela 1.0's Modern Chat spacing, in points.
    public static let oldSpacing = (line: 2.0, message: 6.0)
    /// Vela 1.1's, which is also the default.
    public static let newSpacing = (line: 4.0, message: 12.0)

    /// Runs the migration unless it has run before. Returns true when it
    /// moved the spacing.
    @MainActor
    @discardableResult
    public static func run(settings: SettingsStore, record: LaunchRecord, version: String) -> Bool {
        // An unreadable settings.json reads as all defaults: wait for one
        // that can be read rather than miss the old values.
        guard !record.hasRun(id), settings.lastError == nil else { return false }
        record.markRun(id, version: version)
        guard settings.value(forKey: SettingKey<Double>.chatLineSpacing.key) == .number(oldSpacing.line),
              settings.value(forKey: SettingKey<Double>.chatMessageSpacing.key) == .number(oldSpacing.message)
        else { return false }
        settings[.chatLineSpacing] = newSpacing.line
        settings[.chatMessageSpacing] = newSpacing.message
        settings.flush()
        record.recordEvent(movedEvent, version: version)
        return true
    }
}
