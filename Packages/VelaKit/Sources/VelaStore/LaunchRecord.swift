// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Small facts Vela remembers between launches, in user defaults rather
/// than settings.json: they describe this Mac's install, not preferences.
///
/// - The version What's New was last shown for (``lastWhatsNewVersion``).
/// - One-time migrations that have run (``hasRun(_:)``).
/// - Events a migration recorded for a What's New notice, with the version
///   they happened in (``event(_:)``).
///
/// Tests and demo mode use ``inMemory()``.
@MainActor
public final class LaunchRecord {
    private let read: (String) -> String?
    private let write: (String, String?) -> Void

    public init(read: @escaping (String) -> String?, write: @escaping (String, String?) -> Void) {
        self.read = read
        self.write = write
    }

    /// Backed by `defaults` (the app's standard user defaults).
    public static func userDefaults(_ defaults: UserDefaults = .standard) -> LaunchRecord {
        LaunchRecord(
            read: { defaults.string(forKey: $0) },
            write: { key, value in
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        )
    }

    /// Kept in memory only, for as long as the record lives.
    public static func inMemory(_ initial: [String: String] = [:]) -> LaunchRecord {
        let storage = Storage(initial)
        return LaunchRecord(read: { storage.values[$0] }, write: { storage.values[$0] = $1 })
    }

    private final class Storage {
        var values: [String: String]
        init(_ values: [String: String]) { self.values = values }
    }

    // MARK: What's New

    /// The app version What's New last opened for, or that a new install
    /// started at. Nil before this version of Vela first ran.
    public var lastWhatsNewVersion: String? {
        get { read(Keys.lastWhatsNewVersion) }
        set { write(Keys.lastWhatsNewVersion, newValue) }
    }

    // MARK: Migrations

    /// Whether the one-time migration `id` has run on this Mac.
    public func hasRun(_ id: String) -> Bool {
        read(Keys.migration(id)) != nil
    }

    /// Records that migration `id` ran, in `version`.
    public func markRun(_ id: String, version: String) {
        write(Keys.migration(id), version)
    }

    // MARK: Events

    /// The version event `name` happened in, if it did.
    public func event(_ name: String) -> String? {
        read(Keys.event(name))
    }

    /// Records event `name` as happening in `version`, for a What's New
    /// notice (see `WhatsNewNotice` in VelaCore).
    public func recordEvent(_ name: String, version: String) {
        write(Keys.event(name), version)
    }

    enum Keys {
        static let lastWhatsNewVersion = "Vela.whatsNew.lastVersion"
        static func migration(_ id: String) -> String { "Vela.migrations.\(id)" }
        static func event(_ name: String) -> String { "Vela.events.\(name)" }
    }
}

/// Decides `history.save` on a Mac that has never set it, once.
///
/// Before the setting existed Vela saved every message. A Mac whose
/// database already holds messages, and whose settings.json doesn't set
/// `history.save`, gets `true` written explicitly, so nothing changes for
/// it; a new install keeps the default, off. It runs once per Mac (see
/// ``LaunchRecord/hasRun(_:)``), so resetting the setting to its default
/// later isn't undone at the next launch.
public enum HistorySaveMigration {
    /// The ``LaunchRecord`` migration id.
    public static let id = "historySave"
    /// The ``LaunchRecord`` event recorded when history was kept, which
    /// the What's New notice about it looks for.
    public static let keptHistoryEvent = "history.keptOnUpgrade"

    /// Runs the migration unless it has run before. `savedHistory` is nil
    /// when the database couldn't be read; it then waits for a launch where
    /// it can be. Returns true when it set `history.save` to true.
    @MainActor
    @discardableResult
    public static func run(
        settings: SettingsStore,
        savedHistory: SavedHistory?,
        record: LaunchRecord,
        version: String
    ) -> Bool {
        guard !record.hasRun(id), let savedHistory else { return false }
        record.markRun(id, version: version)
        guard !settings.isSet(.historySave), savedHistory.hasMessages else { return false }
        settings[.historySave] = true
        settings.flush()
        record.recordEvent(keptHistoryEvent, version: version)
        return true
    }
}
