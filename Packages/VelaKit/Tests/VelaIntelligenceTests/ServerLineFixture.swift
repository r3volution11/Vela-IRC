// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaCore
@testable import VelaIntelligence
import VelaIRC
import VelaStore

/// A channel where the server itself has spoken, as Catch me up and Recap
/// find it: a real (not demo) app with one network, PoliticsNet at
/// irc.politicsnet.example, whose server calls itself `politicsd` (no dot,
/// so only its welcome gives it away), and #secret-project with people's
/// messages among:
///
/// - a NOTICE and a PRIVMSG from the server's address, one naming another
///   server in its text;
/// - a NOTICE from `politicsd`, the name the server gave itself;
/// - a message from a nick that's the network's name;
/// - ZNC's `*buffextras` relaying a join, with a server in the host.
///
/// None of those names may reach a prompt.
@MainActor
struct ServerLineFixture {
    static let channel = "#secret-project"
    static let network = "PoliticsNet"
    static let host = "irc.politicsnet.example"
    /// What the server calls itself, and another server named in a notice.
    static let servers = [host, "politicsd", "irc.example.org", "znc.in"]
    static var names: [String] { [channel, network] + servers }

    /// What people said, in order: all a prompt may quote.
    static let peoplesLines = [
        "alice: doug, can you look at the build?",
        "bob: it failed at the linker step",
        "alice: thanks, looking now",
    ]

    let app: AppModel
    let session: NetworkSession
    let buffer: BufferModel
    private let folder: URL

    static func make() async throws -> ServerLineFixture {
        let folder = FileManager.default.temporaryDirectory.appending(path: "VelaServerLines-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let config = NetworkConfig(name: network, host: host, nick: "doug", autoConnect: false)
        let networks = NetworkConfigStore(fileURL: folder.appending(path: "networks.json"))
        networks.upsert(config)
        let settings = SettingsStore(fileURL: folder.appending(path: "settings.json"), watchForChanges: false)
        settings.saveDelay = .seconds(60)
        let app = AppModel(settings: settings, networkStore: networks, database: nil, keychain: .inMemory(), notifier: SilentNotifier())
        await app.ready()
        let session = try #require(app.sessions.first)
        session.nick = "doug"
        session.connectionState = .connected
        var support = ISupport()
        support.apply(["PREFIX=(ov)@+", "CHANTYPES=#", "CASEMAPPING=rfc1459"])
        session.isupport = support

        let start = Date().addingTimeInterval(-600)
        let lines = [
            ":politicsd 001 doug :Welcome to the PoliticsNet IRC Network doug",
            ":doug!d@host JOIN \(channel)",
            ":alice!a@host PRIVMSG \(channel) :doug, can you look at the build?",
            ":\(host) NOTICE \(channel) :*** This channel moves to irc.example.org at midnight",
            ":bob!b@host PRIVMSG \(channel) :it failed at the linker step",
            ":\(host) PRIVMSG \(channel) :\(host) restarts for maintenance in 10 minutes",
            ":politicsd NOTICE \(channel) :politicsd is going down for maintenance",
            ":\(network)!bot@services.politicsnet.example PRIVMSG \(channel) :\(network) services restart tonight",
            ":*buffextras!buffextras@znc.in PRIVMSG \(channel) :carol!c@irc.example.org joined",
            ":alice!a@host PRIVMSG \(channel) :thanks, looking now",
        ]
        for (index, line) in lines.enumerated() {
            // Server time, a second apart, so the lines keep their order.
            let stamp = ISO8601DateFormatter.string(from: start.addingTimeInterval(Double(index)), timeZone: .gmt, formatOptions: [.withInternetDateTime])
            session.handle(.message(IRCMessage(line: "@time=\(stamp) \(line)")!, batch: nil))
        }
        let buffer = try #require(session.buffer(named: channel))
        // Everything it got is unread.
        buffer.lastReadAt = start.addingTimeInterval(-1)
        return ServerLineFixture(app: app, session: session, buffer: buffer, folder: folder)
    }

    /// The server's lines really are in the channel, where you see them.
    func expectServerLinesShown() {
        let nicks = buffer.lines.filter(\.kind.isConversation).compactMap(\.nick)
        for nick in [Self.host, "politicsd", Self.network, "*buffextras"] {
            #expect(nicks.contains(nick), "\(nick) isn't in the channel")
        }
    }

    /// Catch me up's request for the channel.
    var catchUpRequest: CatchUpRequest {
        CatchUpRequest(buffer: buffer, session: session, since: .distantPast)
    }

    /// A Recap of the channel, gathered as its window gathers it.
    func recapInput() async -> RecapInput {
        await RecapGatherer(app: app).gather(RecapScope(place: .buffer(buffer.id), span: .last(minutes: 60)))
    }

    func remove() {
        try? FileManager.default.removeItem(at: folder)
    }
}
