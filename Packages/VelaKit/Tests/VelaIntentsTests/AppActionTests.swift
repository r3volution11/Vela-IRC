// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaCore
@testable import VelaIntents

/// What Siri and Shortcuts do to the model: sending, joining, away and
/// back, read state and mentions. Demo networks: Libera.Chat and Ergo are
/// connected, OFTC isn't.
@MainActor
@Suite("App actions")
struct AppActionTests {
    private func demo() async throws -> (AppModel, libera: NetworkSession, oftc: NetworkSession) {
        let app = AppModel.demo()
        await app.ready()
        let libera = try #require(app.sessions.first { $0.displayName == "Libera.Chat" })
        let oftc = try #require(app.sessions.first { $0.displayName == "OFTC" })
        return (app, libera, oftc)
    }

    /// The demo, with the actions' waits for a connection on a
    /// ``ManualActionClock``: they take the clock's time, not the
    /// machine's, so a busy test run can't stretch them, and a test makes
    /// its changes while the action is known to be waiting.
    private func demoOnAClock() async throws -> (AppModel, ManualActionClock, libera: NetworkSession, oftc: NetworkSession) {
        let (app, libera, oftc) = try await demo()
        let clock = ManualActionClock()
        app.actionClock = clock.actionClock
        return (app, clock, libera, oftc)
    }

    // MARK: Sending

    @Test func sendsTextAsIsEvenWithASlash() async throws {
        let (app, libera, _) = try await demo()
        let vela = try #require(libera.buffer(named: "#vela"))
        try await app.send("/help is not a command", to: vela.id)
        let last = try #require(vela.lines.last)
        #expect(last.isSelf)
        #expect(last.kind == .message)
        #expect(last.text == "/help is not a command")
    }

    @Test func unknownBuffer() async throws {
        let (app, libera, _) = try await demo()
        await #expect(throws: AppActionError.unknownBuffer) {
            try await app.send("hi", to: BufferID(networkID: libera.id, foldedName: "#nowhere"))
        }
    }

    @Test func consolesTakeNoMessages() async throws {
        let (app, libera, _) = try await demo()
        await #expect(throws: AppActionError.serverBuffer(network: "Libera.Chat")) {
            try await app.send("hi", to: libera.serverBuffer.id)
        }
    }

    @Test func emptyMessages() async throws {
        let (app, libera, _) = try await demo()
        let vela = try #require(libera.buffer(named: "#vela"))
        await #expect(throws: AppActionError.emptyMessage) {
            try await app.send(" \n ", to: vela.id)
        }
    }

    /// A network that isn't connecting gets a moment (Vela may be about to
    /// connect it), then sending gives up, well before the 10 s timeout.
    @Test func notConnectedGivesUpQuickly() async throws {
        let (app, clock, _, oftc) = try await demoOnAClock()
        let debian = try #require(oftc.buffer(named: "#debian"))
        let sent = await clock.run { try await app.send("hi", to: debian.id) }
        #expect(throws: AppActionError.notConnected(network: "OFTC")) { try sent.result.get() }
        #expect(sent.took >= .milliseconds(1500) && sent.took < .seconds(10))
    }

    @Test func notJoined() async throws {
        let (app, libera, _) = try await demo()
        let left = libera.ensureBuffer(name: "#left", kind: .channel, persist: false)
        await #expect(throws: AppActionError.notJoined(channel: "#left", network: "Libera.Chat")) {
            try await app.send("hi", to: left.id)
        }
    }

    @Test func waitsForAConnectionInProgress() async throws {
        let (app, clock, _, oftc) = try await demoOnAClock()
        let debian = try #require(oftc.buffer(named: "#debian"))
        oftc.connectionState = .connecting
        let sent = await clock.run({ try await app.send("back online", to: debian.id, connectionTimeout: .seconds(5)) }, changes: [
            (.milliseconds(300), {
                // Still waiting: nothing sent while OFTC connects.
                #expect(debian.lines.last?.text != "back online")
                oftc.connectionState = .connected
                debian.isJoined = true
            }),
        ])
        try sent.result.get()
        #expect(debian.lines.last?.text == "back online")
        // Sent once connected and joined, not at the timeout.
        #expect(sent.took >= .milliseconds(300) && sent.took < .seconds(5))
    }

    @Test func privateConversationsNeedNoJoin() async throws {
        let (app, libera, _) = try await demo()
        let marisol = try #require(libera.buffer(named: "marisol"))
        try await app.send("on my way", to: marisol.id)
        #expect(marisol.lines.last?.text == "on my way")
    }

    // MARK: Joining

    @Test func joinAddsTheHash() async throws {
        let (app, libera, _) = try await demo()
        let buffer = try await app.join("swift-dev", on: libera.id, key: nil)
        #expect(buffer.name == "#swift-dev")
        #expect(buffer.kind == .channel)
        #expect(libera.buffer(named: "#swift-dev") === buffer)
        // Joining doesn't switch channels.
        #expect(app.selectedBuffer?.name == "#vela")
    }

    @Test func joinErrors() async throws {
        let (app, libera, oftc) = try await demo()
        await #expect(throws: AppActionError.invalidChannelName("two words")) {
            try await app.join("two words", on: libera.id, key: nil)
        }
        await #expect(throws: AppActionError.unknownNetwork) {
            try await app.join("#vela", on: UUID(), key: nil)
        }
        await #expect(throws: AppActionError.notConnected(network: "OFTC")) {
            try await app.join("#tor", on: oftc.id, key: nil, connectionTimeout: .milliseconds(200))
        }
    }

    @Test(arguments: [("vela", "#vela"), ("#vela", "#vela"), ("  #vela ", "#vela"), ("&local", "&local")])
    func channelNames(_ input: String, _ expected: String) throws {
        let name = try AppModel.channelName(input, isChannel: { "#&".contains($0.first ?? " ") })
        #expect(name == expected)
    }

    // MARK: Away

    @Test func awayGoesToConnectedNetworks() async throws {
        let (app, _, _) = try await demo()
        #expect(try await app.setAway("lunch").map(\.displayName) == ["Libera.Chat", "Ergo Testnet"])
        #expect(try await app.setBack().map(\.displayName) == ["Libera.Chat", "Ergo Testnet"])
    }

    @Test func awayNeedsAConnection() async throws {
        let (app, clock, _, _) = try await demoOnAClock()
        for session in app.sessions { session.connectionState = .disconnected }
        let away = await clock.run { try await app.setAway(nil) }
        let back = await clock.run { try await app.setBack() }
        #expect(throws: AppActionError.noConnectedNetworks) { try away.result.get() }
        #expect(throws: AppActionError.noConnectedNetworks) { try back.result.get() }
        // Nothing was connecting, so nothing was waited for.
        #expect(away.took == .zero)
        #expect(back.took == .zero)
    }

    /// Siri may have just launched Vela: networks still connecting get a
    /// few seconds before away is set.
    @Test func awayWaitsForNetworksStillConnecting() async throws {
        let (app, clock, _, oftc) = try await demoOnAClock()
        oftc.connectionState = .connecting
        let away = await clock.run({ try await app.setAway("lunch", connectionTimeout: .seconds(5)).map(\.displayName) }, changes: [
            (.milliseconds(300), { oftc.connectionState = .registering }),
            (.milliseconds(500), { oftc.connectionState = .connected }),
        ])
        #expect(Set(try away.result.get()) == ["Libera.Chat", "Ergo Testnet", "OFTC"])
        // Through registering until OFTC was connected, not to the timeout.
        #expect(away.took >= .milliseconds(500) && away.took < .seconds(5))
    }

    @Test func awayStopsWaitingForAConnectionThatFails() async throws {
        let (app, clock, _, oftc) = try await demoOnAClock()
        oftc.connectionState = .connecting
        let back = await clock.run({ try await app.setBack(connectionTimeout: .seconds(5)).map(\.displayName) }, changes: [
            (.milliseconds(200), { oftc.connectionState = .disconnected }),
        ])
        #expect(try back.result.get() == ["Libera.Chat", "Ergo Testnet"])
        // Because the connection failed (after the moment a network that
        // isn't connecting gets), not at the 5 s timeout.
        #expect(back.took >= .milliseconds(200) && back.took < .seconds(5))
    }

    @Test func awayWaitsNoLongerThanTheTimeout() async throws {
        let (app, clock, _, oftc) = try await demoOnAClock()
        oftc.connectionState = .connecting
        let away = await clock.run { try await app.setAway(nil, connectionTimeout: .milliseconds(400)).map(\.displayName) }
        #expect(try away.result.get() == ["Libera.Chat", "Ergo Testnet"])
        #expect(oftc.connectionState == .connecting)
        // Its own 400 ms, not the 10 s default.
        #expect(away.took >= .milliseconds(400) && away.took < .seconds(1))
    }

    // MARK: Read state and mentions

    /// Siri's "mark as read" on one message: what came after stays unread.
    @Test func markingAMessageReadKeepsLaterOnesUnread() async throws {
        let (app, libera, _) = try await demo()
        let vela = try #require(libera.buffer(named: "#vela"))
        // Off screen (leaving it marks it read), so new lines count as unread.
        app.select(libera.serverBuffer)
        let base = (vela.lines.last?.time ?? Date()).addingTimeInterval(60)
        let lines = (0..<4).map { index in
            ChatLine(time: base.addingTimeInterval(Double(index)), kind: .message, nick: "kenji", text: "line \(index)",
                     isHighlight: index == 3)
        }
        for line in lines { libera.add(line, to: vela) }
        #expect(vela.unreadCount == 4)
        #expect(vela.highlightCount == 1)

        try app.markRead(upTo: lines[1].id, in: vela.id)
        #expect(vela.lastReadAt == lines[1].time)
        #expect(vela.unreadCount == 2)
        #expect(vela.highlightCount == 1)

        // Never backwards.
        try app.markRead(upTo: lines[0].id, in: vela.id)
        #expect(vela.lastReadAt == lines[1].time)
        #expect(vela.unreadCount == 2)

        try app.markRead(upTo: lines[3].id, in: vela.id)
        #expect(vela.unreadCount == 0)
        #expect(vela.highlightCount == 0)
    }

    @Test func markingAMessageNoLongerLoadedChangesNothing() async throws {
        let (app, libera, _) = try await demo()
        let swift = try #require(libera.buffer(named: "#swift"))
        let unread = swift.unreadCount
        #expect(throws: AppActionError.messageNotFound(buffer: "#swift")) {
            try app.markRead(upTo: UUID(), in: swift.id)
        }
        #expect(swift.unreadCount == unread)
        #expect(throws: AppActionError.unknownBuffer) {
            try app.markRead(upTo: UUID(), in: BufferID(networkID: libera.id, foldedName: "#nowhere"))
        }
    }

    @Test func markAllReadClearsEverything() async throws {
        let (app, _, _) = try await demo()
        #expect(app.markAllRead() > 0)
        #expect(app.sessions.allSatisfy { $0.totalUnread == 0 && $0.totalHighlights == 0 })
        #expect(app.markAllRead() == 0)
    }

    @Test func mentionsInSidebarOrder() async throws {
        let (app, libera, _) = try await demo()
        let vela = try #require(libera.buffer(named: "#vela"))
        vela.highlightCount = 2
        vela.unreadCount = 5
        let summary = app.mentionSummary
        #expect(summary.entries.map(\.name) == ["#vela", "marisol"])
        #expect(summary.totalMentions == 3)
        #expect(summary.entries.last?.isPrivate == true)
        #expect(summary.entries.first?.networkName == "Libera.Chat")
    }

    @Test func busiestUnreadBufferSkipsMuted() async throws {
        let (app, libera, _) = try await demo()
        #expect(app.busiestUnreadBuffer?.name == "#swift")
        let swift = try #require(libera.buffer(named: "#swift"))
        swift.isMuted = true
        #expect(app.busiestUnreadBuffer?.name == "#macdev")
        _ = app.markAllRead()
        #expect(app.busiestUnreadBuffer == nil)
    }

    @Test func mentionsDialog() {
        let network = UUID()
        func entry(_ name: String, _ mentions: Int, isPrivate: Bool = false) -> MentionSummary.Entry {
            .init(bufferID: BufferID(networkID: network, foldedName: name), name: name, networkName: "Libera.Chat",
                  isPrivate: isPrivate, mentions: mentions, unread: mentions)
        }
        #expect(MentionsSpeech.dialog(for: MentionSummary(entries: [])) == "You have no new mentions.")
        #expect(MentionsSpeech.dialog(for: MentionSummary(entries: [entry("#vela", 1)])) == "You have 1 mention in #vela.")
        #expect(MentionsSpeech.dialog(for: MentionSummary(entries: [entry("#vela", 3)])) == "You have 3 mentions in #vela.")
        #expect(MentionsSpeech.dialog(for: MentionSummary(entries: [entry("marisol", 2, isPrivate: true)]))
            == "You have 2 new messages from marisol.")
        let many = MentionSummary(entries: [entry("#vela", 2), entry("#swift", 1), entry("marisol", 1, isPrivate: true)])
        #expect(MentionsSpeech.dialog(for: many).hasPrefix("You have 4 mentions in #vela, #swift"))
        #expect(MentionsSpeech.dialog(for: many).hasSuffix("marisol."))
        let lots = MentionSummary(entries: (1...6).map { entry("#c\($0)", 1) })
        #expect(MentionsSpeech.dialog(for: lots) == "You have 6 mentions in 6 channels and conversations.")
    }

    // MARK: Composer and show requests

    @Test func composerMessagesAreReported() async throws {
        let (app, libera, _) = try await demo()
        let vela = try #require(libera.buffer(named: "#vela"))
        var reported: [String] = []
        app.onComposerMessage = { buffer, _ in reported.append(buffer.name) }
        libera.submit("hello", in: vela)
        libera.submit("//not a command", in: vela)
        libera.submit("/me waves", in: vela)
        libera.submit("/join #swift", in: vela)
        libera.submit("/whois kenji", in: libera.serverBuffer)
        #expect(reported == ["#vela", "#vela"])
    }

    @Test func showRequestsCarryDrafts() async throws {
        let (app, libera, _) = try await demo()
        let swift = try #require(libera.buffer(named: "#swift"))
        app.requestShow(swift.id, draft: "draft text")
        #expect(app.showRequest?.bufferID == swift.id)
        #expect(app.showRequest?.draft == "draft text")
        app.requestShow(swift.id)
        #expect(app.showRequest?.draft == nil)
    }
}
