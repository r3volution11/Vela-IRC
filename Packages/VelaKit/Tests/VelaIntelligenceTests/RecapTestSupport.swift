// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaCore
@testable import VelaIntelligence

/// Lines, conversations and inputs for the Recap tests.
enum RecapFixtures {
    static let network = UUID(uuidString: "6B1F7F0E-61A4-4C6B-9D55-0C3E2A1F0002")!
    static let otherNetwork = UUID(uuidString: "6B1F7F0E-61A4-4C6B-9D55-0C3E2A1F0003")!
    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    static func id(_ name: String, network: UUID = network) -> BufferID {
        BufferID(networkID: network, foldedName: name.lowercased())
    }

    static func line(
        _ nick: String,
        _ text: String,
        minute: Double = 0,
        kind: RecapLine.Kind = .message,
        isSelf: Bool = false,
        highlight: Bool = false,
        msgid: String? = nil,
        replyTo: String? = nil
    ) -> RecapLine {
        RecapLine(
            time: start.addingTimeInterval(minute * 60),
            nick: nick,
            text: text,
            kind: kind,
            isSelf: isSelf,
            isHighlight: highlight,
            msgid: msgid,
            replyTo: replyTo
        )
    }

    static func conversation(
        _ name: String,
        _ lines: [RecapLine],
        network: UUID = network,
        networkName: String = "Libera.Chat",
        ownNick: String = "doug",
        unread: Int = 0
    ) -> RecapConversation {
        RecapConversation(
            id: id(name, network: network),
            name: name,
            networkName: networkName,
            isChannel: name.hasPrefix("#"),
            ownNick: ownNick,
            lines: lines,
            yourLines: lines.filter(\.isSelf),
            unreadLines: unread
        )
    }

    static func input(_ conversations: [RecapConversation], place: RecapScope.Place? = nil, person: String? = nil) -> RecapInput {
        RecapInput(
            scope: RecapScope(place: place ?? .buffer(conversations.first?.id ?? id("#vela")), person: person),
            conversations: conversations,
            requestedStart: nil,
            end: start.addingTimeInterval(86_400)
        )
    }

    /// `count` lines from a rotating cast, a minute apart.
    static func chatter(_ count: Int, from minute: Double = 0, cast: [String] = ["alice", "bob", "carol", "dave"]) -> [RecapLine] {
        (0..<count).map { index in
            line(cast[index % cast.count], "message number \(index) about the release plan and the build", minute: minute + Double(index))
        }
    }
}

/// A Recap summarizer for session tests: each recap streams what
/// `steps` says, waiting on ``gate`` first when it's set.
final class FakeRecapSummarizer: RecapSummarizer {
    enum Step: Sendable {
        case summary(RecapSummary)
        case fail(CatchUpError)
    }

    var nextPlan = RecapPlan(passes: 1, transcriptTokens: 100, estimatedSeconds: 5)
    var steps: [Step] = [.summary(RecapSummary(overview: ["All of it."], isComplete: true))]
    var detailPoints = ["kenji said the theme engine landed."]
    /// Recaps hold here until it's opened.
    let gate = Gate()
    let recaps = Recorder<[RecapInput]>([])
    let details = Recorder<[RecapDetailRequest]>([])
    let terminations = Recorder(0)

    nonisolated func plan(_ input: RecapInput) async -> RecapPlan {
        await MainActor.run { nextPlan }
    }

    nonisolated func recap(_ input: RecapInput) -> AsyncThrowingStream<RecapSummary, Error> {
        recaps.update { $0.append(input) }
        let gate = gate
        let terminations = terminations
        return AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                await gate.wait()
                for step in self.steps {
                    switch step {
                    case .summary(let summary): continuation.yield(summary)
                    case .fail(let error):
                        continuation.finish(throwing: error)
                        return
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                terminations.update { $0 += 1 }
                task.cancel()
            }
        }
    }

    nonisolated func detail(_ request: RecapDetailRequest) -> AsyncThrowingStream<RecapDetail, Error> {
        details.update { $0.append(request) }
        return AsyncThrowingStream { continuation in
            Task { @MainActor in
                continuation.yield(RecapDetail(points: self.detailPoints))
                continuation.finish()
            }
        }
    }
}

/// Opens once; waiters wait until then.
final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = true
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func close() { lock.withLock { isOpen = false } }

    func open() {
        let waiting = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            isOpen = true
            defer { waiters = [] }
            return waiters
        }
        waiting.forEach { $0.resume() }
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            let resumeNow = lock.withLock { () -> Bool in
                if isOpen { return true }
                waiters.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }
}
