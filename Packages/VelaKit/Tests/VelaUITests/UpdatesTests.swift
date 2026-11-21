// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Observation
import Testing
import VelaStore
@testable import VelaUI

/// An updater that behaves like Sparkle's `SPUUpdater` where Vela relies on
/// it: automatic installs read false and can't be changed while automatic
/// checks are off, and each change is recorded.
@MainActor
@Observable
final class FakeUpdater: AppUpdater {
    var unavailableReason: UpdatesUnavailableReason?
    var status: UpdateStatus = .idle
    var lastCheckDate: Date?
    var canCheckForUpdates = true
    /// What `start()`, `checkForUpdates()` and the setters did, in order.
    private(set) var events: [String] = []
    /// Sparkle's own preferences: checks on (Info.plist's
    /// SUEnableAutomaticChecks), installs off.
    private var storedChecks = true
    private var storedDownloads = false

    init(reason: UpdatesUnavailableReason? = nil) {
        unavailableReason = reason
    }

    var automaticallyChecks: Bool {
        get { storedChecks }
        set {
            storedChecks = newValue
            events.append("checks=\(newValue)")
        }
    }

    var automaticallyDownloads: Bool {
        get { storedChecks && storedDownloads }
        set {
            guard storedChecks else { return }
            storedDownloads = newValue
            events.append("downloads=\(newValue)")
        }
    }

    func start() { events.append("start") }
    func checkForUpdates() { events.append("check") }

    /// The update window's "Automatically download and install updates in
    /// the future" box, which Sparkle saves itself.
    func tickAutomaticInstallsInUpdateWindow(_ value: Bool) {
        storedDownloads = value
    }
}

@MainActor
@Suite("Updates: settings and status", .serialized)
struct UpdatesTests {
    private func makeSettings(_ json: String = "{}") throws -> (SettingsStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VelaUpdatesTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("settings.json")
        try Data(json.utf8).write(to: url)
        return (SettingsStore(fileURL: url, watchForChanges: false), directory)
    }

    /// Lets the sync's observation tasks run until `condition` holds.
    private func settle(until condition: () -> Bool) async {
        for _ in 0..<400 where !condition() {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: Settings → updater

    @Test func defaultsCheckButDontInstall() throws {
        let (settings, directory) = try makeSettings()
        defer { try? FileManager.default.removeItem(at: directory) }
        let updater = FakeUpdater()
        AppUpdates(updater: updater).start(settings: settings)
        #expect(updater.automaticallyChecks)
        #expect(!updater.automaticallyDownloads)
        // Nothing differed from Sparkle's own defaults, so nothing was set.
        #expect(updater.events == ["start"])
    }

    @Test func settingsApplyBeforeTheUpdaterStarts() throws {
        let (settings, directory) = try makeSettings(#"{ "updates.checkAutomatically": false }"#)
        defer { try? FileManager.default.removeItem(at: directory) }
        let updater = FakeUpdater()
        AppUpdates(updater: updater).start(settings: settings)
        // Off before Sparkle starts, so no check runs at launch.
        #expect(updater.events == ["checks=false", "start"])
        #expect(!updater.automaticallyChecks)
    }

    @Test func automaticInstallsApplyWithChecks() throws {
        let (settings, directory) = try makeSettings(#"{ "updates.installAutomatically": true }"#)
        defer { try? FileManager.default.removeItem(at: directory) }
        let updater = FakeUpdater()
        AppUpdates(updater: updater).start(settings: settings)
        #expect(updater.events == ["downloads=true", "start"])
        #expect(updater.automaticallyDownloads)
    }

    @Test func followsSettingsChanges() async throws {
        let (settings, directory) = try makeSettings()
        defer { try? FileManager.default.removeItem(at: directory) }
        let updater = FakeUpdater()
        let updates = AppUpdates(updater: updater)
        updates.start(settings: settings)

        settings[.updatesInstallAutomatically] = true
        await settle { updater.automaticallyDownloads }
        #expect(updater.automaticallyDownloads)

        // Checks off: Sparkle stops installing on its own too, and the
        // setting isn't touched.
        settings[.updatesCheckAutomatically] = false
        await settle { !updater.automaticallyChecks }
        #expect(!updater.automaticallyChecks)
        #expect(!updater.automaticallyDownloads)
        try await Task.sleep(for: .milliseconds(50))
        #expect(settings[.updatesInstallAutomatically])

        // Checks back on: installs follow the setting again.
        settings[.updatesCheckAutomatically] = true
        await settle { updater.automaticallyDownloads }
        #expect(updater.automaticallyChecks)
        #expect(updater.automaticallyDownloads)
        #expect(updater.events.filter { $0 == "start" }.count == 1)
    }

    // MARK: Updater → settings

    @Test func theUpdateWindowsBoxIsWrittenBack() async throws {
        let (settings, directory) = try makeSettings()
        defer { try? FileManager.default.removeItem(at: directory) }
        let updater = FakeUpdater()
        // Kept, as SceneServices keeps it: the sync lives as long as it.
        let updates = AppUpdates(updater: updater)
        updates.start(settings: settings)
        #expect(!settings[.updatesInstallAutomatically])

        updater.tickAutomaticInstallsInUpdateWindow(true)
        await settle { settings[.updatesInstallAutomatically] }
        #expect(settings[.updatesInstallAutomatically])
        #expect(settings.isSet(.updatesInstallAutomatically))

        updater.tickAutomaticInstallsInUpdateWindow(false)
        await settle { !settings[.updatesInstallAutomatically] }
        #expect(!settings[.updatesInstallAutomatically])
    }

    /// A settings pass that runs late (after the box in the update window
    /// changed again) doesn't undo the newer choice.
    @Test func aLatePassKeepsTheNewestChoice() throws {
        let (settings, directory) = try makeSettings()
        defer { try? FileManager.default.removeItem(at: directory) }
        let updater = FakeUpdater()
        let sync = UpdateSettingsSync(settings: settings, updater: updater)
        sync.apply()

        updater.tickAutomaticInstallsInUpdateWindow(true)
        sync.updaterChanged()
        #expect(settings[.updatesInstallAutomatically])
        // Unticked before the pass for the setting written above runs.
        updater.tickAutomaticInstallsInUpdateWindow(false)
        sync.apply()
        #expect(!updater.automaticallyDownloads)
        sync.updaterChanged()
        #expect(!settings[.updatesInstallAutomatically])

        // A real change to the setting still reaches the updater.
        settings[.updatesInstallAutomatically] = true
        sync.apply()
        #expect(updater.automaticallyDownloads)
    }

    @Test func disabledUpdatersNeverStart() throws {
        let (settings, directory) = try makeSettings(#"{ "updates.checkAutomatically": false }"#)
        defer { try? FileManager.default.removeItem(at: directory) }
        let updater = FakeUpdater(reason: .developmentBuild)
        let updates = AppUpdates(updater: updater)
        updates.start(settings: settings)
        #expect(updater.events.isEmpty)
        #expect(!updates.isAvailable)
        #expect(!updates.canCheck)
        updates.checkForUpdates()
        #expect(updater.events.isEmpty)
    }

    @Test func startsOnce() throws {
        let (settings, directory) = try makeSettings()
        defer { try? FileManager.default.removeItem(at: directory) }
        let updater = FakeUpdater()
        let updates = AppUpdates(updater: updater)
        updates.start(settings: settings)
        updates.start(settings: settings)
        #expect(updater.events == ["start"])
    }

    @Test func checkForUpdatesWaitsForTheUpdater() {
        let updater = FakeUpdater()
        let updates = AppUpdates(updater: updater)
        updater.canCheckForUpdates = false
        #expect(!updates.canCheck)
        updates.checkForUpdates()
        #expect(updater.events.isEmpty)
        updater.canCheckForUpdates = true
        updates.checkForUpdates()
        #expect(updater.events == ["check"])
    }

    // MARK: Status line

    @Test func statusLines() {
        let updater = FakeUpdater()
        let now = Date()
        func line(_ status: UpdateStatus) -> String {
            updater.status = status
            return UpdateStatusText.line(for: updater, now: now)
        }
        #expect(line(.checking) == "Checking for updates…")
        #expect(line(.upToDate) == "Vela is up to date.")
        #expect(line(.available(version: "1.2.0")) == "Version 1.2.0 is available.")
        #expect(line(.readyToInstall(version: "1.2.0")) == "Version 1.2.0 will be installed when you quit Vela.")
        #expect(line(.needsNewerMacOS(version: "2.0.0")) == "Version 2.0.0 needs a newer version of macOS.")
        #expect(line(.failed(message: "The update server couldn't be reached.")) == "The update server couldn't be reached.")
        #expect(line(.idle) == "Vela hasn't checked for updates yet.")
        updater.lastCheckDate = now.addingTimeInterval(-20)
        #expect(line(.idle) == "Last checked just now.")
        updater.lastCheckDate = now.addingTimeInterval(-3 * 3600)
        #expect(line(.idle).hasPrefix("Last checked "))
        #expect(line(.idle).contains("3"))
        updater.lastCheckDate = nil
        updater.automaticallyChecks = false
        #expect(line(.idle) == "Automatic update checks are off.")
    }

    @Test func unavailableStatusLines() {
        #expect(UpdateStatusText.line(for: DisabledUpdater(reason: .developmentBuild)) == "Updates are turned off in development builds.")
        #expect(UpdateStatusText.line(for: DisabledUpdater(reason: .notConfigured)) == "Updates aren't set up in this build.")
        // Whatever the updater says, a development build's line is the reason.
        let updater = FakeUpdater(reason: .developmentBuild)
        updater.status = .available(version: "9.0.0")
        #expect(UpdateStatusText.line(for: updater) == UpdateStatusText.developmentBuild)
        #expect(UpdateStatusText.systemImage(for: updater) == "info.circle")
    }

    @Test func aboutFacts() {
        #expect(AboutInfo.credits.contains("Vela was made with the help of AI."))
        #expect(AboutInfo.credits.contains { $0.contains("Sparkle") })
        #expect(AboutInfo.versionLine.hasPrefix("Version "))
        #expect(AboutInfo.licenseURL.absoluteString == "https://velairc.app/help/license")
        #expect(AboutInfo.acknowledgementsURL.absoluteString == "https://velairc.app/help/license#built-with")
    }

    @Test func updatesPaneIsInSettings() {
        #expect(SettingsPane.updates.title == "Updates")
        #expect(SettingsPane.groups.flatMap { $0 } == SettingsPane.allCases)
        // "Show in settings editor" on the pane filters to its two settings.
        #expect(SettingsCategory.categories(forPane: SettingsPane.updates.rawValue) == [.updates])
    }
}
