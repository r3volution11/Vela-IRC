// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaCore
import VelaIRC

/// Where the "New" marker goes, driven through the demo model so focus
/// changes and selection run the real `AppModel` paths.
@MainActor
@Suite("Unread marker")
struct UnreadMarkerTests {
    /// A server-time stamp `seconds` from now (after the demo's lines).
    private func stamp(_ seconds: TimeInterval) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date().addingTimeInterval(seconds))
    }

    private func say(_ text: String, in channel: String, at seconds: TimeInterval, to session: NetworkSession) {
        let line = "@time=\(stamp(seconds)) :alice!a@host PRIVMSG \(channel) :\(text)"
        session.handle(.message(IRCMessage(line: line)!, batch: nil))
    }

    private func newLines(in buffer: BufferModel) -> [String]? {
        guard let marker = buffer.unreadMarkerAfter else { return nil }
        return buffer.lines.filter { $0.time > marker }.map(\.text)
    }

    @Test func markerAppearsWhileTheWindowIsUnfocused() throws {
        let app = AppModel.demo()
        let session = try #require(app.sessions.first)
        let vela = try #require(session.buffer(named: "#vela"))
        #expect(app.selectedBufferID == vela.id)

        say("seen while focused", in: "#vela", at: 60, to: session)
        app.isWindowActive = false
        say("first new", in: "#vela", at: 120, to: session)
        say("second new", in: "#vela", at: 180, to: session)

        #expect(vela.unreadCount == 2)
        #expect(newLines(in: vela) == ["first new", "second new"])

        // Focusing reads them but keeps the marker where it was.
        let marker = vela.unreadMarkerAfter
        app.isWindowActive = true
        #expect(vela.unreadCount == 0)
        #expect(vela.unreadMarkerAfter == marker)
    }

    @Test func leavingABufferReadsItToTheEnd() throws {
        let app = AppModel.demo()
        let session = try #require(app.sessions.first)
        let vela = try #require(session.buffer(named: "#vela"))
        let swift = try #require(session.buffer(named: "#swift"))

        say("seen while open", in: "#vela", at: 60, to: session)
        app.select(swift)
        say("arrived later", in: "#vela", at: 120, to: session)

        #expect(vela.unreadCount == 1)
        #expect(newLines(in: vela) == ["arrived later"])
        app.select(vela)
        #expect(newLines(in: vela) == ["arrived later"])
    }
}
