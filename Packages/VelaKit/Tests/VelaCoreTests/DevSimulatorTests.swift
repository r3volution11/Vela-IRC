// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Vela Dev's state simulator exists only in Debug builds, and so do its tests.
#if DEBUG

import Foundation
import Testing
@testable import VelaCore
import VelaIRC
import VelaStore

@MainActor
@Suite("Developer state simulator", .serialized)
struct DevSimulatorTests {
    @MainActor
    private final class RecordingNotifier: Notifier {
        var posts: [(title: String, body: String)] = []
        func post(title: String, subtitle: String, body: String, bufferID: BufferID, lineID: UUID?, playSound: Bool) {
            posts.append((title, body))
        }
    }

    @MainActor
    private struct Fixture {
        let app: AppModel
        let simulator: DevSimulator
        let notifier: RecordingNotifier
        let folder: TemporaryFolder
        let real: NetworkSession

        var session: NetworkSession { simulator.session! }
        var channel: BufferModel { session.buffer(named: DevSimulator.channelName)! }
        var networksFile: URL { folder.url.appending(path: "networks.json") }
    }

    /// A real (not demo) app with one real network, so what the simulator
    /// must leave alone is there to be left alone. No Dock, no keychain.
    private func makeFixture() -> Fixture {
        let folder = TemporaryFolder()
        let notifier = RecordingNotifier()
        let settings = SettingsStore(fileURL: folder.url.appending(path: "settings.json"), watchForChanges: false)
        // Chat logs on: the simulator must still write none.
        settings[.loggingEnabled] = true
        let app = AppModel(
            settings: settings,
            networkStore: NetworkConfigStore(fileURL: folder.url.appending(path: "networks.json")),
            database: nil,
            keychain: .inMemory(),
            notifier: notifier
        )
        app.stopDockUpdates()
        let real = NetworkSession(config: NetworkConfig(name: "Libera.Chat", host: "irc.test", nick: "doug"), database: nil)
        real.nick = "doug"
        real.connectionState = .connected
        app.installDemoSessions([real])
        app.select(real.serverBuffer)
        return Fixture(app: app, simulator: DevSimulator(app: app), notifier: notifier, folder: folder, real: real)
    }

    @Test func theSimulatorNetworkComesUpConnectedInItsChannel() throws {
        let fixture = makeFixture()
        defer { fixture.simulator.removeNetwork() }
        fixture.simulator.goOnline()
        let session = try #require(fixture.simulator.session)
        #expect(session.displayName == DevSimulator.networkName)
        #expect(session.connectionState == .connected)
        #expect(session.nick == DevSimulator.nick)
        #expect(fixture.app.sessions.map(\.id) == [fixture.real.id, session.id])
        #expect(fixture.channel.isJoined)
        #expect(fixture.channel.memberCount == 37)
        #expect(fixture.channel.topic?.contains("simulator") == true)
        #expect(DevSimulator.isSimulated(session.id))
        #expect(!DevSimulator.isSimulated(fixture.real.id))
    }

    @Test func offlineConnectingAndOnlineGoThroughTheSessionsOwnHandling() throws {
        let fixture = makeFixture()
        defer { fixture.simulator.removeNetwork() }
        fixture.simulator.goOffline()
        #expect(fixture.session.connectionState == .disconnected)
        #expect(fixture.session.lastError?.contains("simulated") == true)
        #expect(!fixture.channel.isJoined)
        #expect(fixture.channel.memberCount == 0)
        #expect(fixture.channel.lines.last?.text == "Disconnected")
        // It doesn't reconnect by itself.
        #expect(!fixture.session.isAwaitingConnection)

        fixture.simulator.startConnecting()
        #expect(fixture.session.connectionState == .connecting)
        #expect(fixture.session.serverBuffer.lines.last?.text.hasPrefix("Connecting to simulator.invalid") == true)

        fixture.simulator.goOnline()
        #expect(fixture.session.connectionState == .connected)
        #expect(fixture.channel.isJoined)
        // Its people come back.
        #expect(fixture.channel.memberCount == 37)
        // The real network never noticed.
        #expect(fixture.real.connectionState == .connected)
    }

    @Test func aMentionHighlightsCountsAndNotifies() throws {
        let fixture = makeFixture()
        defer { fixture.simulator.removeNetwork() }
        let line = try #require(fixture.simulator.mention())
        #expect(line.isHighlight)
        #expect(line.text.contains(DevSimulator.nick))
        #expect(fixture.channel.highlightCount == 1)
        #expect(fixture.channel.unreadCount >= 1)
        #expect(fixture.notifier.posts.count == 1)
        #expect(fixture.notifier.posts.first?.title.hasSuffix("in \(DevSimulator.channelName)") == true)
        // Each one is new.
        let next = try #require(fixture.simulator.mention())
        #expect(next.id != line.id)
        #expect(fixture.channel.highlightCount == 2)
        #expect(fixture.notifier.posts.count == 2)
    }

    @Test func aVeryLongNickAndMessageAreSelected() throws {
        let fixture = makeFixture()
        defer { fixture.simulator.removeNetwork() }
        let line = try #require(fixture.simulator.longMessage())
        #expect((line.nick?.count ?? 0) >= 60)
        #expect(line.text.count > 1_000)
        #expect(line.text.contains(String(repeating: "unbroken", count: 25)))
        #expect(fixture.app.selectedBufferID == fixture.channel.id)
        #expect(fixture.channel.member(named: DevSimulator.longNick) != nil)
    }

    @Test func aHugeChannelHasThousandsOfMembersAndMessages() throws {
        let fixture = makeFixture()
        defer { fixture.simulator.removeNetwork() }
        let huge = try #require(fixture.simulator.hugeChannel(members: 5_000, lines: 10_000))
        #expect(huge.memberCount == 5_001)
        #expect(huge.lines.count >= 10_000)
        #expect(huge.isJoined)
        #expect(!huge.hasMoreHistory)
        #expect(fixture.app.selectedBufferID == huge.id)
        // Lines that arrive later don't trim it to the usual scrollback.
        fixture.simulator.goOffline()
        fixture.simulator.goOnline()
        #expect(huge.lines.count >= 10_000)
        #expect(huge.memberCount == 5_001)
    }

    @Test func aReconnectStormCyclesAndEndsConnected() async throws {
        let fixture = makeFixture()
        defer { fixture.simulator.removeNetwork() }
        fixture.simulator.goOnline()
        let before = fixture.session.serverBuffer.lines.filter { $0.text.hasPrefix("Connected as") }.count
        fixture.simulator.startReconnectStorm(cycles: 4, interval: .milliseconds(30))
        #expect(fixture.simulator.isStorming)
        await fixture.simulator.waitForStorm()
        #expect(!fixture.simulator.isStorming)
        #expect(fixture.session.connectionState == .connected)
        let after = fixture.session.serverBuffer.lines.filter { $0.text.hasPrefix("Connected as") }.count
        #expect(after - before == 4)
        #expect(fixture.session.serverBuffer.lines.filter { $0.text.contains("simulated storm") }.count == 4)
        #expect(fixture.channel.isJoined)
        #expect(fixture.channel.memberCount == 37)
    }

    @Test func stoppingAStormLeavesItWhereItWas() async throws {
        let fixture = makeFixture()
        defer { fixture.simulator.removeNetwork() }
        fixture.simulator.startReconnectStorm(cycles: 50, interval: .milliseconds(60))
        try await Task.sleep(for: .milliseconds(30))
        fixture.simulator.stopReconnectStorm()
        #expect(!fixture.simulator.isStorming)
        fixture.simulator.goOnline()
        #expect(fixture.session.connectionState == .connected)
    }

    @Test func nothingIsSavedAndNothingIsHandedOn() throws {
        let fixture = makeFixture()
        let saved = UserDefaults.standard.string(forKey: "Vela.lastSelectedBuffer")
        fixture.simulator.goOnline()
        fixture.simulator.mention()
        fixture.simulator.longMessage()
        fixture.simulator.hugeChannel(members: 50, lines: 100)
        fixture.simulator.goOffline()
        fixture.simulator.goOnline()
        // Not a network Vela knows: networks.json has no entry for it.
        #expect(fixture.app.networkStore.networks.isEmpty)
        if let data = try? Data(contentsOf: fixture.networksFile) {
            #expect(!String(decoding: data, as: UTF8.self).contains(DevSimulator.networkName))
        }
        // Never the channel Vela reopens at launch.
        #expect(UserDefaults.standard.string(forKey: "Vela.lastSelectedBuffer") == saved)
        // No chat logs, though logging is on.
        let logs = fixture.folder.url.appending(path: "Logs")
        let logged = (try? FileManager.default.subpathsOfDirectory(atPath: logs.path)) ?? []
        #expect(logged.allSatisfy { !$0.contains("Simulator") && !$0.contains("simulator") })
        // Not offered to Spotlight, Siri or Shortcuts.
        #expect(fixture.app.conversationBuffers.allSatisfy { !DevSimulator.isSimulated($0.id.networkID) })
        // Connecting for real goes nowhere: the transport fails at once.
        #expect(fixture.session.config.host == DevSimulator.host)
        #expect(!fixture.session.config.autoConnect)
        fixture.simulator.removeNetwork()
    }

    @Test func removingTheNetworkSelectsSomethingElse() throws {
        let fixture = makeFixture()
        let id = try #require(fixture.simulator.longMessage().map { _ in fixture.session.id })
        #expect(fixture.app.selectedBufferID?.networkID == id)
        fixture.simulator.removeNetwork()
        #expect(fixture.simulator.session == nil)
        #expect(fixture.app.sessions.map(\.id) == [fixture.real.id])
        #expect(fixture.app.selectedBufferID?.networkID == fixture.real.id)
        #expect(!DevSimulator.isSimulated(id))
    }
}

#endif
