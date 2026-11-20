// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaCore
import VelaStore

@MainActor
@Suite("What's New")
struct WhatsNewTests {
    // MARK: When it opens

    @Test func newInstallDoesntSeeItButRemembersTheVersion() {
        let record = LaunchRecord.inMemory()
        #expect(!WhatsNewTrigger.shouldShowAtLaunch(version: "1.1.0", isExistingInstall: false, record: record))
        #expect(record.lastWhatsNewVersion == "1.1.0")
        // Relaunching the same version: still nothing.
        #expect(!WhatsNewTrigger.shouldShowAtLaunch(version: "1.1.0", isExistingInstall: true, record: record))
        // The next update shows it.
        #expect(WhatsNewTrigger.shouldShowAtLaunch(version: "1.2.0", isExistingInstall: true, record: record))
        #expect(record.lastWhatsNewVersion == "1.2.0")
    }

    @Test func upgradeFromBeforeWhatsNewSeesIt() {
        // 1.0.0 recorded nothing; its database is what marks an upgrade.
        let record = LaunchRecord.inMemory()
        #expect(WhatsNewTrigger.shouldShowAtLaunch(version: "1.1.0", isExistingInstall: true, record: record))
        #expect(record.lastWhatsNewVersion == "1.1.0")
        #expect(!WhatsNewTrigger.shouldShowAtLaunch(version: "1.1.0", isExistingInstall: true, record: record))
    }

    @Test func onlyANewerVersionOpensIt() {
        let record = LaunchRecord.inMemory(["Vela.whatsNew.lastVersion": "1.10.0"])
        #expect(!WhatsNewTrigger.shouldShowAtLaunch(version: "1.10.0", isExistingInstall: true, record: record))
        // A downgrade: nothing, and the newer version stays recorded.
        #expect(!WhatsNewTrigger.shouldShowAtLaunch(version: "1.9.2", isExistingInstall: true, record: record))
        #expect(record.lastWhatsNewVersion == "1.10.0")
        #expect(WhatsNewTrigger.shouldShowAtLaunch(version: "1.10.1", isExistingInstall: true, record: record))
        #expect(WhatsNewTrigger.isNewer("2.0.0", than: "1.99.9"))
        #expect(!WhatsNewTrigger.isNewer("1.0", than: "1.0.0"))
    }

    // MARK: Notices

    private func context(version: String, save: Bool?, keptIn keptVersion: String?) throws -> (WhatsNewContext, URL) {
        let directory = FileManager.default.temporaryDirectory.appending(path: "VelaWhatsNew-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let settings = SettingsStore(fileURL: directory.appending(path: "settings.json"), watchForChanges: false)
        if let save { settings[.historySave] = save }
        let record = LaunchRecord.inMemory()
        if let keptVersion { record.recordEvent(HistorySaveMigration.keptHistoryEvent, version: keptVersion) }
        return (WhatsNewContext(version: version, settings: settings, record: record), directory)
    }

    @Test func historyNoticeForAnUpgraderWhoseHistoryWasKept() throws {
        let (context, directory) = try context(version: "1.1.0", save: true, keptIn: "1.1.0")
        defer { try? FileManager.default.removeItem(at: directory) }
        let notices = WhatsNewNotice.current(in: context)
        #expect(notices.map(\.id) == ["history.keptOnUpgrade"])
        #expect(notices.first?.message == "Vela now asks before saving your chat history. Yours is still being saved, as before. You can turn it off in Settings → Messages → History.")
        #expect(notices.first?.settingsPane == "messages")
    }

    @Test func historyNoticeOnlyWhileItApplies() throws {
        // A new install: nothing was kept.
        let (fresh, freshDirectory) = try context(version: "1.1.0", save: nil, keptIn: nil)
        defer { try? FileManager.default.removeItem(at: freshDirectory) }
        #expect(WhatsNewNotice.current(in: fresh).isEmpty)

        // Kept, then turned off since: "Yours is still being saved" isn't true.
        let (off, offDirectory) = try context(version: "1.1.0", save: false, keptIn: "1.1.0")
        defer { try? FileManager.default.removeItem(at: offDirectory) }
        #expect(WhatsNewNotice.current(in: off).isEmpty)

        // A later release's What's New doesn't repeat it.
        let (later, laterDirectory) = try context(version: "1.2.0", save: true, keptIn: "1.1.0")
        defer { try? FileManager.default.removeItem(at: laterDirectory) }
        #expect(WhatsNewNotice.current(in: later).isEmpty)
    }

    @Test func noticesAreDataDriven() throws {
        let (context, directory) = try context(version: "2.0.0", save: nil, keptIn: nil)
        defer { try? FileManager.default.removeItem(at: directory) }
        let always = WhatsNewNotice(id: "a", title: "A", message: "Shown in 2.0.0.") { $0.version == "2.0.0" }
        let never = WhatsNewNotice(id: "b", title: "B", message: "Never.") { _ in false }
        #expect(WhatsNewNotice.current(in: context, from: [never, always]).map(\.id) == ["a"])
    }
}
