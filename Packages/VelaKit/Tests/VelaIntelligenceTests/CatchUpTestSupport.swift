// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaCore
@testable import VelaIntelligence

/// Lines and requests for the Catch me up tests.
enum CatchUpFixtures {
    static let bufferID = BufferID(networkID: UUID(uuidString: "6B1F7F0E-61A4-4C6B-9D55-0C3E2A1F0001")!, foldedName: "#vela")

    static func line(_ nick: String, _ text: String, action: Bool = false, minute: Int = 0) -> CatchUpLine {
        CatchUpLine(
            id: UUID(),
            time: Date(timeIntervalSince1970: 1_800_000_000 + Double(minute) * 60),
            nick: nick,
            text: text,
            isAction: action
        )
    }

    static func request(_ lines: [CatchUpLine], ownNick: String = "doug", bufferID: BufferID = bufferID, name: String = "#vela") -> CatchUpRequest {
        CatchUpRequest(bufferID: bufferID, bufferName: name, networkName: "Libera.Chat", ownNick: ownNick, lines: lines)
    }

    /// `count` short lines from a rotating cast.
    static func chatter(_ count: Int, ownNick: String = "doug") -> [CatchUpLine] {
        let cast = ["alice", "bob", "carol", "dave"]
        return (0..<count).map { index in
            line(cast[index % cast.count], "message number \(index) about the release plan and the build", minute: index)
        }
    }
}

/// Polls `condition` on the main actor until it holds or `timeout` passes.
@MainActor
func eventually(timeout: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

/// A thread-safe box for recording what fakes were asked.
nonisolated final class Recorder<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value { lock.withLock { storage } }

    func update<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.withLock { body(&storage) }
    }
}

/// A language model for the engine tests. Prompts are recorded; `digest`
/// and `final` decide each answer from the prompt.
nonisolated final class FakeCatchUpModel: CatchUpLanguageModel {
    enum Call: Equatable, Sendable {
        case digest(prompt: String, instructions: String, limit: Int)
        case summarize(prompt: String, instructions: String, limit: Int)

        var prompt: String {
            switch self {
            case .digest(let prompt, _, _), .summarize(let prompt, _, _): prompt
            }
        }

        /// The `maximumResponseTokens` it was asked with.
        var limit: Int {
            switch self {
            case .digest(_, _, let limit), .summarize(_, _, let limit): limit
            }
        }

        var isDigest: Bool {
            if case .digest = self { true } else { false }
        }
    }

    /// One step of a streamed final answer: a snapshot, or a failure
    /// after the snapshots before it.
    enum Step: Sendable {
        case draft(CatchUpDraft)
        case fail(CatchUpModelError)
    }

    let context: Int
    let counts: Bool
    let digestAnswer: @Sendable (String) throws -> CatchUpDraft
    let finalSteps: @Sendable (String) -> [Step]
    let calls = Recorder<[Call]>([])

    init(
        context: Int = 4096,
        counts: Bool = false,
        digest: @escaping @Sendable (String) throws -> CatchUpDraft = { _ in CatchUpDraft(overview: "A part.") },
        final: @escaping @Sendable (String) throws -> [CatchUpDraft] = { _ in [CatchUpDraft(overview: "All of it.")] }
    ) {
        self.context = context
        self.counts = counts
        self.digestAnswer = digest
        self.finalSteps = { prompt in
            do {
                return try final(prompt).map(Step.draft)
            } catch let error as CatchUpModelError {
                return [.fail(error)]
            } catch {
                return [.fail(.failed(error.localizedDescription))]
            }
        }
    }

    /// A model whose final answers stream `steps`, which can fail after
    /// writing something.
    init(
        context: Int = 4096,
        digest: @escaping @Sendable (String) throws -> CatchUpDraft = { _ in CatchUpDraft(overview: "A part.") },
        steps: @escaping @Sendable (String) -> [Step]
    ) {
        self.context = context
        self.counts = false
        self.digestAnswer = digest
        self.finalSteps = steps
    }

    var digestCalls: [Call] { calls.value.filter(\.isDigest) }
    var summarizeCalls: [Call] { calls.value.filter { !$0.isDigest } }

    func contextSize() async -> Int { context }

    func tokenCount(_ text: String) async -> Int? {
        // A stand-in for the real tokenizer: four characters a token.
        counts ? text.count / 4 + 1 : nil
    }

    func schemaTokenCount(for pass: CatchUpPrompts.Pass) async -> Int? {
        counts ? 300 : nil
    }

    func digest(prompt: String, instructions: String, maximumResponseTokens: Int) async throws -> CatchUpDraft {
        calls.update { $0.append(.digest(prompt: prompt, instructions: instructions, limit: maximumResponseTokens)) }
        return try digestAnswer(prompt)
    }

    func summarize(prompt: String, instructions: String, maximumResponseTokens: Int) -> AsyncThrowingStream<CatchUpDraft, Error> {
        calls.update { $0.append(.summarize(prompt: prompt, instructions: instructions, limit: maximumResponseTokens)) }
        let steps = finalSteps(prompt)
        return AsyncThrowingStream { continuation in
            for step in steps {
                switch step {
                case .draft(let draft):
                    continuation.yield(draft)
                case .fail(let error):
                    continuation.finish(throwing: error)
                    return
                }
            }
            continuation.finish()
        }
    }
}

/// The transcript line numbers in a digest or single-pass prompt.
nonisolated func lineNumbers(in prompt: String) -> [Int] {
    prompt.split(separator: "\n").compactMap { line in
        guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return nil }
        return Int(line[line.index(after: line.startIndex)..<close])
    }
}
