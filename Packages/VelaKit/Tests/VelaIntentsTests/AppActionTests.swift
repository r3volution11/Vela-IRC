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

    @Test func notConnectedGivesUpQuickly() async throws {
        let (app, _, oftc) = try await demo()
        let debian = try #require(oftc.buffer(named: "#debian"))
        let start = Date()
        await #expect(throws: AppActionError.notConnected(network: "OFTC")) {
            try await app.send("hi", to: debian.id, connectionTimeout: .milliseconds(300))
        }
        // Well short of the 10 s default; loose enough for a busy test run,
        // where the main actor is shared with every other test.
        #expect(Date().timeIntervalSince(start) < 5)
    }

    @Test func notJoined() async throws {
        let (app, libera, _) = try await demo()
        let left = libera.ensureBuffer(name: "#left", kind: .channel, persist: false)
        await #expect(throws: AppActionError.notJoined(channel: "#left", network: "Libera.Chat")) {
            try await app.send("hi", to: left.id)
        }
    }

    @Test func waitsForAConnectionInProgress() async throws {
        let (app, _, oftc) = try await demo()
        let debian = try #require(oftc.buffer(named: "#debian"))
        oftc.connectionState = .connecting
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            oftc.connectionState = .connected
            debian.isJoined = true
        }
        try await app.send("back online", to: debian.id, connectionTimeout: .seconds(5))
        #expect(debian.lines.last?.text == "back online")
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
        let (app, _, _) = try await demo()
        for session in app.sessions { session.connectionState = .disconnected }
        let start = Date()
        await #expect(throws: AppActionError.noConnectedNetworks) { try await app.setAway(nil) }
        await #expect(throws: AppActionError.noConnectedNetworks) { try await app.setBack() }
        // Nothing was connecting, so nothing was waited for. (A wait would
        // take the 10 s connection timeout, twice; the margin is for a busy
        // machine running other tests.)
        #expect(Date().timeIntervalSince(start) < 5)
    }

    /// Siri may have just launched Vela: networks still connecting get a
    /// few seconds before away is set.
    @Test func awayWaitsForNetworksStillConnecting() async throws {
        let (app, _, oftc) = try await demo()
        oftc.connectionState = .connecting
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            oftc.connectionState = .registering
            try? await Task.sleep(for: .milliseconds(200))
            oftc.connectionState = .connected
        }
        let names = try await app.setAway("lunch", connectionTimeout: .seconds(5)).map(\.displayName)
        #expect(Set(names) == ["Libera.Chat", "Ergo Testnet", "OFTC"])
    }

    @Test func awayStopsWaitingForAConnectionThatFails() async throws {
        let (app, _, oftc) = try await demo()
        oftc.connectionState = .connecting
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            oftc.connectionState = .disconnected
        }
        let start = Date()
        let names = try await app.setBack(connectionTimeout: .seconds(5)).map(\.displayName)
        #expect(names == ["Libera.Chat", "Ergo Testnet"])
        #expect(Date().timeIntervalSince(start) < 3)
    }

    @Test func awayWaitsNoLongerThanTheTimeout() async throws {
        let (app, _, oftc) = try await demo()
        oftc.connectionState = .connecting
        let start = Date()
        let names = try await app.setAway(nil, connectionTimeout: .milliseconds(400)).map(\.displayName)
        #expect(names == ["Libera.Chat", "Ergo Testnet"])
        // Well short of the 10 s default (see notConnectedGivesUpQuickly).
        #expect(Date().timeIntervalSince(start) < 5)
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
