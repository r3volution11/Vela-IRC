// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaStore

// MARK: - When What's New opens

/// Decides whether "What's New in Vela" opens at launch: on the first
/// launch of a newer version on a Mac where Vela ran before. Never for a
/// new install, a version seen before, or an older version (a downgrade).
///
/// The scene layer asks only for real launches: demo, screenshot,
/// benchmark and test runs never get here, and never record a version.
public enum WhatsNewTrigger {
    /// Whether to open What's New for `version` now. Remembers `version` as
    /// seen when it's newer than the last one, or when Vela starts for the
    /// first time with this record (a new install starts there).
    public static func shouldShowAtLaunch(version: String, isExistingInstall: Bool, record: LaunchRecord) -> Bool {
        guard let last = record.lastWhatsNewVersion else {
            record.lastWhatsNewVersion = version
            // No record: a new install, or an upgrade from a version
            // before What's New, which only an existing install can be.
            return isExistingInstall
        }
        guard isNewer(version, than: last) else { return false }
        record.lastWhatsNewVersion = version
        return true
    }

    /// `1.10.0` is newer than `1.9.2`.
    public static func isNewer(_ version: String, than other: String) -> Bool {
        version.compare(other, options: .numeric) == .orderedDescending
    }
}

// MARK: - Notices

/// What a notice is shown for.
public struct WhatsNewContext {
    /// The version What's New is about (the app's).
    public var version: String
    public var settings: SettingsStore
    /// Events one-time migrations recorded (``LaunchRecord/event(_:)``).
    public var record: LaunchRecord

    public init(version: String, settings: SettingsStore, record: LaunchRecord) {
        self.version = version
        self.settings = settings
        self.record = record
    }
}

/// An important, one-off message at the top of What's New, before the
/// release notes: something an update changed for you in particular.
///
/// To add one, append it to ``all`` with a condition. Usually a one-time
/// migration records a ``LaunchRecord`` event with the version it ran in,
/// and the notice shows while What's New is about that version (also when
/// reopened from the Help menu), as long as it still applies.
public struct WhatsNewNotice: Identifiable {
    public let id: String
    public let title: String
    public let message: String
    /// A Settings pane to offer a button for (`SettingsPane.rawValue`).
    public var settingsPane: String?
    /// The button's title, when there's a pane.
    public var settingsButtonTitle: String?
    public let applies: (WhatsNewContext) -> Bool

    public init(
        id: String,
        title: String,
        message: String,
        settingsPane: String? = nil,
        settingsButtonTitle: String? = nil,
        applies: @escaping (WhatsNewContext) -> Bool
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.settingsPane = settingsPane
        self.settingsButtonTitle = settingsButtonTitle
        self.applies = applies
    }

    /// Every notice Vela knows, in the order they're shown.
    public static let all: [WhatsNewNotice] = [
        .historyKeptOnUpgrade,
    ]

    /// The notices that apply in `context`.
    public static func current(in context: WhatsNewContext, from notices: [WhatsNewNotice] = all) -> [WhatsNewNotice] {
        notices.filter { $0.applies(context) }
    }

    /// For a Mac that saved history before `history.save` existed: it still
    /// does (``HistorySaveMigration``), unless it's been turned off since.
    public static let historyKeptOnUpgrade = WhatsNewNotice(
        id: "history.keptOnUpgrade",
        title: "Your chat history is still saved",
        message: "Vela now asks before saving your chat history. Yours is still being saved, as before. You can turn it off in Settings → Messages → History.",
        settingsPane: "messages",
        settingsButtonTitle: "Open History Settings"
    ) { context in
        context.record.event(HistorySaveMigration.keptHistoryEvent) == context.version
            && context.settings[.historySave]
    }
}
