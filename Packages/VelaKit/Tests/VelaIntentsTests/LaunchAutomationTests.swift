// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Foundation
import Testing
@testable import VelaCore
@testable import VelaIntelligence
@testable import VelaIntents
import VelaStore

/// A link or a script that launches Vela arrives before its networks and
/// conversations are back from the message store (restoring them waits on
/// the store, and starts only once the window is up). A link is held until
/// they are; a script reading conversations gets them at once.
///
/// A real (not demo) app on an in-memory store, not started: one network,
/// Libera.Chat, that never connects, with #vela and a private conversation
/// with marisol saved from before. Serialized: the script objects read the
/// running app's automation (`VelaAutomation.shared`).
@MainActor
@Suite("Automation while Vela is launching", .serialized)
struct LaunchAutomationTests {
    private struct Launching {
        let app: AppModel
        let automation: VelaAutomation
        let presenter: FakeAutomationPresenter
        let folder: URL
    }

    private func launching() async throws -> Launching {
        let folder = FileManager.default.temporaryDirectory.appending(path: "VelaLaunch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let config = NetworkConfig(name: "Libera.Chat", host: "irc.example.invalid", nick: "doug", autoConnect: false)
        let database = try VelaDatabase.inMemory()
        for (name, kind, order) in [("#vela", "channel", 0), ("marisol", "query", 1)] {
            try await database.upsertBuffer(BufferRecord(networkID: config.id, name: name, foldedName: name, kind: kind, lastReadAt: nil, sortOrder: order))
        }
        let networks = NetworkConfigStore(fileURL: folder.appending(path: "networks.json"))
        networks.upsert(config)
        let settings = SettingsStore(fileURL: folder.appending(path: "settings.json"), watchForChanges: false)
        settings.saveDelay = .seconds(60)
        let app = AppModel(settings: settings, networkStore: networks, database: database, keychain: .inMemory(), notifier: SilentNotifier())
        let presenter = FakeAutomationPresenter()
        let automation = VelaAutomation(app: app, services: .demo(), presenter: presenter)
        return Launching(app: app, automation: automation, presenter: presenter, folder: folder)
    }

    @Test func aLinkThatLaunchesVelaWaitsForItsConversations() async throws {
        let launch = try await launching()
        defer { try? FileManager.default.removeItem(at: launch.folder) }
        #expect(!launch.app.isReady)
        let router = VelaLinkRouter(automation: launch.automation)
        let outcome = router.open(URL(string: "vela://open?network=Libera.Chat&channel=%23vela")!)
        #expect(outcome == .waiting)
        #expect(launch.presenter.notices.isEmpty)

        await launch.app.ready()
        let vela = try #require(launch.app.sessions.first?.buffer(named: "#vela"))
        #expect(await launch.app.waitUntil(timeout: .seconds(5)) { launch.app.showRequest != nil })
        #expect(launch.app.showRequest?.bufferID == vela.id)
        #expect(launch.presenter.notices.isEmpty)

        // Once Vela is ready, links are followed straight away.
        #expect(router.open(URL(string: "vela://open?network=Libera.Chat&nick=marisol")!) == .shown)
    }

    @Test func aScriptThatLaunchesVelaReadsItsConversations() async throws {
        let launch = try await launching()
        defer { try? FileManager.default.removeItem(at: launch.folder) }
        VelaAutomation.shared = launch.automation
        defer { VelaAutomation.shared = nil }
        #expect(!launch.app.isReady)

        // Read straight away, as Cocoa scripting does: no waiting.
        #expect(NSApplication.shared.velaNetworks.map(\.name) == ["Libera.Chat"])
        #expect(NSApplication.shared.velaConversations.map(\.name) == ["#vela", "marisol"])
        #expect(NSApplication.shared.valueInVelaConversations(withName: "vela")?.name == "#vela")
        let network = try #require(NSApplication.shared.velaNetworks.first)
        #expect(network.velaConversations.map(\.name) == ["#vela", "marisol"])

        // The rest of launching carries on as before, once.
        await launch.app.ready()
        #expect(launch.app.sessions.first?.buffers.map(\.name) == ["#vela", "marisol"])
        #expect(NSApplication.shared.velaConversations.map(\.name) == ["#vela", "marisol"])
    }
}
