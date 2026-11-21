// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaStore

/// The saved history a Recap reads: a network's (or one buffer's)
/// conversation after a time, optionally about one nick.
@Suite struct RecapQueryTests {
    let network = UUID()
    let other = UUID()

    private func record(_ buffer: String, _ nick: String, _ text: String, minute: Double, kind: String = "message", network: UUID? = nil, redacted: Bool = false) -> MessageRecord {
        MessageRecord(
            networkID: network ?? self.network, bufferName: buffer,
            time: Date(timeIntervalSince1970: 1_700_000_000 + minute * 60), kind: kind, nick: nick, text: text, isRedacted: redacted
        )
    }

    private func filled() async throws -> VelaDatabase {
        let db = try VelaDatabase.inMemory()
        try await db.append([
            record("#vela", "ada", "too old", minute: 0),
            record("#vela", "ada", "hello", minute: 10),
            record("#vela", "x", "joined", minute: 11, kind: "join"),
            record("#vela", "kenji", "deleted", minute: 12, redacted: true),
            record("#vela", "kenji", "* waves", minute: 13, kind: "action"),
            record("#swift", "mina", "alice_ should see this", minute: 14),
            record("#swift", "mina", "aliceXsmith is someone else", minute: 15),
            record("alice_", "alice_", "hi there", minute: 16),
            record("#vela", "Alice_", "theme notes", minute: 17),
            record("#vela", "bob", "elsewhere", minute: 18, network: other),
        ])
        return db
    }

    private var after: Date { Date(timeIntervalSince1970: 1_700_000_000 + 5 * 60) }

    @Test func aNetworksConversationAfterATime() async throws {
        let db = try await filled()
        let lines = try await db.conversation(networkID: network, after: after, limit: 100)
        #expect(lines.map(\.text) == ["hello", "* waves", "alice_ should see this", "aliceXsmith is someone else", "hi there", "theme notes"])
        let vela = try await db.conversation(networkID: network, bufferName: "#vela", after: after, limit: 100)
        #expect(vela.map(\.text) == ["hello", "* waves", "theme notes"])
    }

    @Test func theNewestUpToTheLimitOldestFirst() async throws {
        let db = try await filled()
        let lines = try await db.conversation(networkID: network, after: after, limit: 2)
        #expect(lines.map(\.text) == ["hi there", "theme notes"])
        #expect(try await db.conversation(networkID: network, after: after, limit: 0).isEmpty)
    }

    @Test func aboutOneNickMatchesLooselyAndLiterally() async throws {
        let db = try await filled()
        let lines = try await db.conversation(networkID: network, after: after, mentioning: "alice_", limit: 100)
        // "_" is a literal underscore, not LIKE's any character; the Recap
        // checks each line properly afterwards.
        #expect(lines.map(\.text) == ["alice_ should see this", "hi there", "theme notes"])
        let percent = try await db.conversation(networkID: network, after: after, mentioning: "%", limit: 100)
        #expect(percent.isEmpty)
    }

    @Test func theOldestSavedLineInEachBuffer() async throws {
        let db = try await filled()
        let oldest = try await db.oldestMessageTimes(networkID: network)
        #expect(oldest["#vela"] == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(oldest["#swift"] == Date(timeIntervalSince1970: 1_700_000_000 + 14 * 60))
        #expect(oldest.count == 3)
    }
}
