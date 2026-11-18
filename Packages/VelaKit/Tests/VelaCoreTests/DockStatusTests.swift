// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaCore
import VelaIRC
import VelaStore

// MARK: - Badge

@Suite("Dock badge")
struct DockBadgeTests {
    /// Two channels, a muted channel, a conversation, a muted conversation
    /// and a server buffer.
    let buffers = [
        DockBadgeBuffer(kind: .channel, unread: 5, mentions: 2),
        DockBadgeBuffer(kind: .channel, unread: 3, mentions: 0),
        DockBadgeBuffer(kind: .channel, unread: 4, mentions: 1, isMuted: true),
        DockBadgeBuffer(kind: .query, unread: 2),
        DockBadgeBuffer(kind: .query, unread: 7, isMuted: true),
        DockBadgeBuffer(kind: .server, unread: 9),
    ]

    @Test(arguments: [
        ([], 0),
        ([.mentions], 2),
        ([.privateMessages], 2),
        ([.channels], 8),
        ([.mentions, .privateMessages], 4),
        // A mention is one of the channel's messages: never counted twice.
        ([.mentions, .channels], 8),
        ([.privateMessages, .channels], 10),
        ([.mentions, .privateMessages, .channels], 10),
    ] as [([DockBadgeCount], Int)])
    func countsEachChosenKindOnce(_ kinds: [DockBadgeCount], _ expected: Int) {
        #expect(DockBadge.count(buffers, counting: Set(kinds)) == expected)
    }

    @Test func mutedBuffersNeverCount() {
        let muted = [
            DockBadgeBuffer(kind: .channel, unread: 10, mentions: 10, isMuted: true),
            DockBadgeBuffer(kind: .query, unread: 3, isMuted: true),
        ]
        #expect(DockBadge.count(muted, counting: Set(DockBadgeCount.allCases)) == 0)
    }

    @Test func serverBuffersNeverCount() {
        let server = [DockBadgeBuffer(kind: .server, unread: 12, mentions: 3)]
        #expect(DockBadge.count(server, counting: Set(DockBadgeCount.allCases)) == 0)
    }

    @Test func cappedStopsAt99() {
        #expect(DockBadge.label(count: 0, style: .capped) == nil)
        #expect(DockBadge.label(count: 1, style: .capped) == "1")
        #expect(DockBadge.label(count: 99, style: .capped) == "99")
        #expect(DockBadge.label(count: 100, style: .capped) == "99+")
        #expect(DockBadge.label(count: 12_345, style: .capped) == "99+")
    }

    @Test func exactAndDot() {
        #expect(DockBadge.label(count: 100, style: .exact) == "100")
        #expect(DockBadge.label(count: 12_345, style: .exact) == "12345")
        #expect(DockBadge.label(count: 0, style: .exact) == nil)
        #expect(DockBadge.label(count: 1, style: .dot) == "•")
        #expect(DockBadge.label(count: 500, style: .dot) == "•")
        #expect(DockBadge.label(count: 0, style: .dot) == nil, "nothing unread: no dot")
    }

    @Test func turnedOffShowsNothing() {
        #expect(DockBadge.label(for: buffers, isEnabled: false, counting: Set(DockBadgeCount.allCases), style: .exact) == nil)
        #expect(DockBadge.label(for: buffers, isEnabled: true, counting: [.channels], style: .exact) == "8")
        #expect(DockBadge.label(for: buffers, isEnabled: true, counting: [], style: .exact) == nil)
    }
}

// MARK: - Badge from a real session

@MainActor
@Suite("Dock badge from sessions")
struct DockBadgeSessionTests {
    private func makeSession() -> (NetworkSession, FakeHost) {
        let host = FakeHost()
        let config = NetworkConfig(name: "Test", host: "irc.test", nick: "doug")
        let session = NetworkSession(config: config, database: nil)
        session.host = host
        session.nick = "doug"
        session.connectionState = .connected
        var support = ISupport()
        support.apply(["PREFIX=(ov)@+", "CHANTYPES=#", "CASEMAPPING=rfc1459"])
        session.isupport = support
        return (session, host)
    }

    private func feed(_ session: NetworkSession, _ lines: String...) {
        for line in lines { session.handle(.message(IRCMessage(line: line)!, batch: nil)) }
    }

    private func count(_ session: NetworkSession, _ kinds: Set<DockBadgeCount>) -> Int {
        DockBadge.count(session.allBuffers.map { DockBadgeBuffer($0) }, counting: kinds)
    }

    @Test func onlyConversationLinesCount() {
        let (session, _) = makeSession()
        feed(session,
             ":doug!d@host JOIN #vela",
             ":alice!a@host JOIN #vela",
             ":bob!b@host PART #vela :bye",
             ":carol!c@host NICK :caroline",
             ":alice!a@host PRIVMSG #vela :hello",
             ":alice!a@host PRIVMSG #vela :\u{1}ACTION waves\u{1}",
             ":alice!a@host NOTICE #vela :a channel notice",
             ":alice!a@host PRIVMSG #vela :doug: are you there?")
        #expect(count(session, [.channels]) == 4, "a message, an action, a notice and a mention; no joins or parts")
        #expect(count(session, [.mentions]) == 1)
        #expect(count(session, [.mentions, .channels]) == 4)
    }

    @Test func privateMessagesCountMessagesActionsAndNotices() {
        let (session, _) = makeSession()
        feed(session,
             ":alice!a@host PRIVMSG doug :hi",
             ":alice!a@host PRIVMSG doug :\u{1}ACTION waves\u{1}",
             ":alice!a@host NOTICE doug :a notice in the open conversation")
        #expect(count(session, [.privateMessages]) == 3)
        #expect(count(session, [.mentions, .channels]) == 0, "a conversation isn't a channel")
    }

    @Test func mutingAndReadingClearTheCount() throws {
        let (session, _) = makeSession()
        feed(session, ":doug!d@host JOIN #vela", ":alice!a@host PRIVMSG #vela :doug!", ":bob!b@host PRIVMSG doug :psst")
        #expect(count(session, [.mentions, .privateMessages]) == 2)
        let vela = try #require(session.buffer(named: "#vela"))
        session.setMuted(true, for: vela)
        #expect(count(session, [.mentions, .privateMessages]) == 1, "mentions in a muted channel don't count")
        let query = try #require(session.buffer(named: "bob"))
        session.markRead(query)
        #expect(count(session, [.mentions, .privateMessages]) == 0)
    }

    @Test func appModelLabelFollowsTheSettings() throws {
        let app = AppModel.demo()
        for session in app.sessions {
            for buffer in session.allBuffers {
                buffer.unreadCount = 0
                buffer.highlightCount = 0
                buffer.isMuted = false
            }
        }
        #expect(app.dockBadgeLabel == nil)
        let libera = try #require(app.sessions.first)
        let swift = try #require(libera.buffer(named: "#swift"))
        swift.unreadCount = 150
        swift.highlightCount = 2
        let query = try #require(libera.queries.first)
        query.unreadCount = 3

        #expect(app.dockBadgeLabel == "5", "default: mentions and private messages")
        app.settings[.dockBadgeCounts] = [.channels, .privateMessages]
        #expect(app.dockBadgeLabel == "99+")
        app.settings[.dockBadgeStyle] = .exact
        #expect(app.dockBadgeLabel == "153")
        app.settings[.dockBadgeStyle] = .dot
        #expect(app.dockBadgeLabel == "•")
        swift.isMuted = true
        app.settings[.dockBadgeStyle] = .capped
        #expect(app.dockBadgeLabel == "3")
        app.settings[.dockShowBadge] = false
        #expect(app.dockBadgeLabel == nil)
    }
}

// MARK: - Offline mark

@Suite("Dock offline mark")
struct DockOfflineTrackerTests {
    let start = Date(timeIntervalSinceReferenceDate: 1_000_000)
    let a = UUID()
    let b = UUID()

    private func status(_ id: UUID, connected: Bool, expected: Bool = true) -> DockNetworkStatus {
        DockNetworkStatus(id: id, isConnected: connected, expectsConnection: expected)
    }

    @Test func showsOnlyAfterTheGracePeriod() {
        var tracker = DockOfflineTracker()
        #expect(tracker.grace == 10)
        tracker.update([status(a, connected: false)], now: start)
        #expect(!tracker.showsMark(now: start))
        #expect(!tracker.showsMark(now: start + 9.9))
        #expect(tracker.nextChange(after: start) == start + 10)
        #expect(tracker.showsMark(now: start + 10))
        #expect(tracker.offlineNetworks(now: start + 10) == [a])
        #expect(tracker.nextChange(after: start + 10) == nil, "nothing left to wait for")
    }

    @Test func aQuickReconnectNeverShows() {
        var tracker = DockOfflineTracker()
        tracker.update([status(a, connected: false)], now: start)
        tracker.update([status(a, connected: false)], now: start + 3)  // Connecting…
        tracker.update([status(a, connected: true)], now: start + 6)
        #expect(!tracker.showsMark(now: start + 20))
        #expect(tracker.nextChange(after: start + 6) == nil)
        // Dropping again starts a new grace period.
        tracker.update([status(a, connected: false)], now: start + 30)
        #expect(!tracker.showsMark(now: start + 39))
        #expect(tracker.showsMark(now: start + 40))
    }

    @Test func stillUpdatingKeepsWhenItWentOffline() {
        var tracker = DockOfflineTracker()
        tracker.update([status(a, connected: false)], now: start)
        // Reconnect attempts (connecting, then waiting again) keep the clock running.
        tracker.update([status(a, connected: false)], now: start + 5)
        tracker.update([status(a, connected: false)], now: start + 8)
        #expect(tracker.offlineSince[a] == start)
        #expect(tracker.showsMark(now: start + 10))
    }

    @Test func clearsWhenTheNetworkIsBack() {
        var tracker = DockOfflineTracker()
        tracker.update([status(a, connected: false), status(b, connected: false)], now: start)
        #expect(tracker.showsMark(now: start + 15))
        tracker.update([status(a, connected: true), status(b, connected: false)], now: start + 15)
        #expect(tracker.showsMark(now: start + 15), "b is still offline")
        tracker.update([status(a, connected: true), status(b, connected: true)], now: start + 16)
        #expect(!tracker.showsMark(now: start + 16))
        #expect(tracker.offlineSince.isEmpty)
    }

    @Test func clearsWhenYouDisconnect() {
        var tracker = DockOfflineTracker()
        tracker.update([status(a, connected: false)], now: start)
        #expect(tracker.showsMark(now: start + 12))
        tracker.update([status(a, connected: false, expected: false)], now: start + 12)
        #expect(!tracker.showsMark(now: start + 12))
    }

    @Test func clearsWhenTheNetworkIsRemoved() {
        var tracker = DockOfflineTracker()
        tracker.update([status(a, connected: false), status(b, connected: true)], now: start)
        #expect(tracker.showsMark(now: start + 12))
        tracker.update([status(b, connected: true)], now: start + 12)
        #expect(!tracker.showsMark(now: start + 12))
    }

    @Test func networksVelaDoesNotExpectNeverShow() {
        var tracker = DockOfflineTracker()
        tracker.update([status(a, connected: false, expected: false)], now: start)
        #expect(!tracker.showsMark(now: start + 3600))
        #expect(tracker.nextChange(after: start) == nil)
    }

    @Test func nextChangeIsTheEarliestPendingDeadline() {
        var tracker = DockOfflineTracker(grace: 10)
        tracker.update([status(a, connected: false)], now: start)
        tracker.update([status(a, connected: false), status(b, connected: false)], now: start + 4)
        #expect(tracker.nextChange(after: start + 4) == start + 10)
        #expect(tracker.nextChange(after: start + 10) == start + 14)
    }
}

// MARK: - Which networks Vela expects

@MainActor
@Suite("Expected connections")
struct ExpectedConnectionTests {
    /// Records connection changes; never connects anywhere.
    final class Host: SessionHost {
        var connectionChanges = 0
        var behavior = SessionBehavior()
        func clientConfig(for session: NetworkSession) -> IRCClientConfig {
            IRCClientConfig(host: "irc.test", port: 6667, useTLS: false, nick: "doug")
        }
        func isBufferVisible(_ id: BufferID) -> Bool { false }
        func activeBuffer(in session: NetworkSession) -> BufferModel? { nil }
        func session(_ session: NetworkSession, didReceiveNotable line: ChatLine, in buffer: BufferModel) {}
        func session(_ session: NetworkSession, didUpdateBouncerNetworks networks: [BouncerNetwork]) {}
        func sessionDidChangeConfig(_ session: NetworkSession) {}
        func sessionDidChangeUnreadCounts(_ session: NetworkSession) {}
        func sessionDidChangeConnection(_ session: NetworkSession) { connectionChanges += 1 }
    }

    private func makeSession(autoConnect: Bool) -> NetworkSession {
        var config = NetworkConfig(name: "Test", host: "irc.test", nick: "doug")
        config.autoConnect = autoConnect
        return NetworkSession(config: config, database: nil)
    }

    @Test func autoConnectNetworksAreExpectedUntilYouDisconnect() {
        let session = makeSession(autoConnect: true)
        #expect(session.expectsConnection)
        session.disconnect()
        #expect(!session.expectsConnection)
        session.connect()  // No host: records the wish, opens nothing.
        #expect(session.expectsConnection)
    }

    @Test func otherNetworksAreExpectedOnceConnected() {
        let session = makeSession(autoConnect: false)
        #expect(!session.expectsConnection, "never connected, doesn't connect automatically")
        session.connect()
        #expect(session.expectsConnection)
        session.disconnect()
        #expect(!session.expectsConnection)
    }

    @Test func aDroppedConnectionIsStillExpected() {
        let session = makeSession(autoConnect: false)
        let host = Host()
        session.connect()
        session.host = host
        session.handle(.stateChanged(.connected))
        session.handle(.disconnected(reason: "Connection reset by peer"))
        #expect(!session.isConnected)
        #expect(session.expectsConnection, "waiting to reconnect is still offline")
        #expect(host.connectionChanges == 2)
        session.disconnect()
        #expect(!session.expectsConnection)
        #expect(host.connectionChanges == 3)
    }

    @Test func appModelListsBouncerNetworksButNotOrphans() throws {
        let app = AppModel.demo()
        let parent = NetworkConfig(name: "soju", host: "bouncer.test", nick: "doug")
        app.networkStore.upsert(parent)
        var child = NetworkConfig(name: "Libera", host: "bouncer.test", nick: "doug")
        child.parentNetworkID = parent.id
        child.bouncerNetworkID = "1"
        var orphan = NetworkConfig(name: "Gone", host: "bouncer.test", nick: "doug")
        orphan.parentNetworkID = UUID()
        orphan.bouncerNetworkID = "2"
        let sessions = app.sessions + [child, orphan].map { NetworkSession(config: $0, database: nil) }
        app.installDemoSessions(sessions)

        let statuses = app.dockNetworkStatuses
        #expect(statuses.contains { $0.id == child.id && !$0.isConnected && $0.expectsConnection })
        #expect(!statuses.contains { $0.id == orphan.id }, "a bouncer network without its bouncer never connects")
        // The demo's OFTC is disconnected, but demo mode never shows the mark.
        app.updateOfflineMark()
        #expect(!app.showsOfflineMark)
    }
}

// MARK: - Bouncing

@Suite("Dock bounce")
struct DockBounceTests {
    @Test func whatBounces() {
        #expect(DockBounce.trigger(isHighlight: true, lineKind: .message, bufferKind: .channel) == .mentions)
        #expect(DockBounce.trigger(isHighlight: true, lineKind: .action, bufferKind: .channel) == .mentions)
        #expect(DockBounce.trigger(isHighlight: false, lineKind: .message, bufferKind: .channel) == nil)
        #expect(DockBounce.trigger(isHighlight: false, lineKind: .message, bufferKind: .query) == .privateMessages)
        #expect(DockBounce.trigger(isHighlight: false, lineKind: .notice, bufferKind: .query) == .privateMessages)
        #expect(DockBounce.trigger(isHighlight: false, lineKind: .join, bufferKind: .query) == nil)
        #expect(DockBounce.trigger(isHighlight: true, lineKind: .join, bufferKind: .channel) == nil)
        #expect(DockBounce.trigger(isHighlight: false, lineKind: .notice, bufferKind: .server) == nil)
    }

    private func attention(
        _ trigger: DockBounceTrigger?,
        muted: Bool = false,
        active: Bool = false,
        style: DockBounceStyle = .once,
        triggers: Set<DockBounceTrigger> = [.mentions, .privateMessages]
    ) -> DockAttention? {
        DockBounce.attention(for: trigger, isMuted: muted, appIsActive: active, style: style, triggers: triggers)
    }

    @Test func styles() {
        #expect(attention(.mentions, style: .off) == nil)
        #expect(attention(.mentions, style: .once) == .once)
        #expect(attention(.privateMessages, style: .untilActive) == .untilActive)
    }

    @Test func onlyWhileVelaIsInTheBackground() {
        #expect(attention(.mentions, active: true) == nil)
        #expect(attention(.privateMessages, active: true, style: .untilActive) == nil)
        #expect(attention(.mentions, active: false) == .once)
    }

    @Test func neverForMutedBuffers() {
        #expect(attention(.mentions, muted: true) == nil)
        #expect(attention(.privateMessages, muted: true, style: .untilActive) == nil)
    }

    @Test func onlyTheChosenKinds() {
        #expect(attention(.mentions, triggers: [.privateMessages]) == nil)
        #expect(attention(.privateMessages, triggers: [.privateMessages]) == .once)
        #expect(attention(.privateMessages, triggers: []) == nil)
        #expect(attention(nil) == nil)
    }
}
