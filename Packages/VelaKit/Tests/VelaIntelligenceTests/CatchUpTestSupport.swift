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

    /// An invented, heated political argument: strong opinions on both
    /// sides, some name-calling, nothing extreme. Two lines name doug.
    static let heatedPolitics: [(String, String)] = [
        ("maple_", "did everyone see the minimum wage vote last night?"),
        ("redfern", "yeah, raising it to $20 is going to kill small businesses, plain and simple"),
        ("bluejay", "lol that's the same line they used in 1996. businesses survived just fine"),
        ("redfern", "survived? half the diners on my street closed after the last hike"),
        ("bluejay", "that was the pandemic, you genius"),
        ("konrad", "the budget office estimate said something like 1.4 million jobs lost though"),
        ("libby", "and 900k people lifted out of poverty in the same report. funny how you skip that part"),
        ("redfern", "because a job at $0 an hour doesn't lift anyone out of anything"),
        ("greenleaf", "can we at least agree it should be indexed to inflation so we stop having this fight every 10 years"),
        ("konrad", "indexing is the one sane idea in this whole bill"),
        ("bluejay", "sure, index it, but from $20 not from the current joke of a number"),
        ("redfern", "you people want to price teenagers out of their first job"),
        ("libby", "\"you people\" lmao"),
        ("maple_", "ok ok. different topic: the voter ID bill passed the state house"),
        ("orwell_fan", "good. you need ID to buy cold medicine, you should need it to vote"),
        ("libby", "cold medicine isn't a constitutional right"),
        ("orwell_fan", "neither is voting without proving who you are"),
        ("bluejay", "there were like 3 cases of in-person voter fraud in the whole state last cycle. it's a solution looking for a problem"),
        ("orwell_fan", "3 that they caught"),
        ("bluejay", "that's not evidence, that's a vibe"),
        ("greenleaf", "the real issue is whether the free ID is actually easy to get. if the DMV is 2 hours away for rural people that's a problem"),
        ("konrad", "the bill funds mobile ID offices, I read it"),
        ("libby", "funds them for two years, then nothing"),
        ("orwell_fan", "so fund them longer, don't kill the bill"),
        ("libby", "wow, actual compromise from orwell_fan, screenshot this"),
        ("orwell_fan", "don't get used to it"),
        ("redfern", "honestly the whole election system is a clown show from top to bottom"),
        ("maple_", "doug: you worked the polls last year, was ID ever an issue?"),
        ("bluejay", "let's ask someone who's actually done it instead of arguing from youtube videos"),
        ("redfern", "imagine thinking poll workers know anything about fraud"),
        ("bluejay", "imagine thinking you do"),
        ("konrad", "anyway, the carbon tax debate is tomorrow, anyone watching?"),
        ("greenleaf", "yes. it's revenue neutral this time, every cent goes back as a dividend"),
        ("redfern", "\"revenue neutral\" until they need money for something else. it's a cash grab"),
        ("greenleaf", "it's literally written into the bill that the dividend can't be redirected"),
        ("redfern", "bills get amended, sweetheart"),
        ("libby", "don't call people sweetheart, that's gross"),
        ("redfern", "fine. bills get amended, greenleaf"),
        ("konrad", "the dividend makes the bottom 60% better off on net according to the treasury model"),
        ("orwell_fan", "models said a lot of things. gas is up 40 cents and you want to add more"),
        ("greenleaf", "the tax is 12 cents in year one. the 40 cents is refinery margins"),
        ("orwell_fan", "tell that to someone who drives 80 miles a day for work"),
        ("bluejay", "who gets a dividend check bigger than that 12 cents, which is the whole point"),
        ("orwell_fan", "the whole point is to make driving miserable so you guys can force everyone onto trains"),
        ("bluejay", "you're unhinged. nobody is coming for your truck"),
        ("orwell_fan", "says the guy who wants to ban gas stoves"),
        ("bluejay", "I have never once said that, you absolute muppet"),
        ("maple_", "lol \"muppet\""),
        ("konrad", "can we keep it civil, the ops are gonna mute everyone again"),
        ("redfern", "civil discourse died with cable news"),
        ("greenleaf", "my point stands: price carbon, give the money back, let people choose"),
        ("orwell_fan", "and my point stands that it hits rural people hardest"),
        ("konrad", "that's fair actually, the bill has a rural rebate but it's small"),
        ("libby", "then argue for a bigger rural rebate instead of torching the whole idea"),
        ("orwell_fan", "I'd take a bigger rebate. still think it's dumb"),
        ("maple_", "progress!"),
        ("redfern", "has anyone seen the polling for the governor's race? Hartley is up 6"),
        ("bluejay", "Hartley is a corporate puppet with a nice haircut"),
        ("redfern", "better than Dunmore, who's never had a real job in her life"),
        ("libby", "she ran a hospital for 11 years, what are you talking about"),
        ("redfern", "a public hospital. that's government, not a real job"),
        ("libby", "this is the dumbest take I've read all week and I read your posts daily"),
        ("konrad", "polls 5 months out don't mean much anyway"),
        ("greenleaf", "the debate is on the 14th, that'll move things more than any poll"),
        ("maple_", "doug, are you hosting the debate watch party again?"),
        ("redfern", "if doug is hosting I'm bringing the good chips"),
        ("bluejay", "bring your own fact checker while you're at it"),
        ("redfern", "bring your own sense of humor"),
        ("greenleaf", "alright, I'm heading out. good arguing with you all, even the muppets"),
        ("orwell_fan", "later. still wrong about the carbon tax though"),
        ("libby", "night all"),
        ("konrad", "night. read the bills before you yell about them, people"),
    ]

    static func heatedPoliticsLines() -> [CatchUpLine] {
        heatedPolitics.enumerated().map { index, pair in line(pair.0, pair.1, minute: index) }
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
/// and `final` decide each answer from the prompt. Answers given as drafts
/// are written out in the reply format (``CatchUpReply/render(_:)``), so
/// the engine reads them as it reads the real model's text.
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

    /// One step of a streamed final answer: the reply so far (a draft
    /// written out, or text as it is), or a failure after the steps before.
    enum Step: Sendable {
        case draft(CatchUpDraft)
        case text(String)
        case fail(CatchUpModelError)
    }

    let context: Int
    let counts: Bool
    let digestAnswer: @Sendable (String) throws -> String
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
        self.digestAnswer = { CatchUpReply.render(try digest($0)) }
        self.finalSteps = Self.steps { try final($0).map(Step.draft) }
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
        self.digestAnswer = { CatchUpReply.render(try digest($0)) }
        self.finalSteps = steps
    }

    /// A model that replies with text as it is: `final` gives the reply
    /// so far at each step of the stream.
    init(
        context: Int = 4096,
        digestText: @escaping @Sendable (String) throws -> String = { _ in "OVERVIEW: A part." },
        finalText: @escaping @Sendable (String) throws -> [String]
    ) {
        self.context = context
        self.counts = false
        self.digestAnswer = digestText
        self.finalSteps = Self.steps { try finalText($0).map(Step.text) }
    }

    private static func steps(_ make: @escaping @Sendable (String) throws -> [Step]) -> @Sendable (String) -> [Step] {
        { prompt in
            do {
                return try make(prompt)
            } catch let error as CatchUpModelError {
                return [.fail(error)]
            } catch {
                return [.fail(.failed(error.localizedDescription))]
            }
        }
    }

    var digestCalls: [Call] { calls.value.filter(\.isDigest) }
    var summarizeCalls: [Call] { calls.value.filter { !$0.isDigest } }

    func contextSize() async -> Int { context }

    func tokenCount(_ text: String) async -> Int? {
        // A stand-in for the real tokenizer: four characters a token.
        counts ? text.count / 4 + 1 : nil
    }

    /// The answer, cut at the first line where it's `enough`, as the live
    /// model stops there.
    func digest(
        prompt: String,
        instructions: String,
        maximumResponseTokens: Int,
        until enough: @escaping @Sendable (String) -> Bool
    ) async throws -> String {
        calls.update { $0.append(.digest(prompt: prompt, instructions: instructions, limit: maximumResponseTokens)) }
        let answer = try digestAnswer(prompt)
        var end = answer.startIndex
        while let newline = answer[end...].firstIndex(of: "\n") {
            end = answer.index(after: newline)
            if enough(String(answer[..<end])) { return String(answer[..<end]) }
        }
        return answer
    }

    func summarize(prompt: String, instructions: String, maximumResponseTokens: Int) -> AsyncThrowingStream<String, Error> {
        calls.update { $0.append(.summarize(prompt: prompt, instructions: instructions, limit: maximumResponseTokens)) }
        let steps = finalSteps(prompt)
        return AsyncThrowingStream { continuation in
            for step in steps {
                switch step {
                case .draft(let draft):
                    continuation.yield(CatchUpReply.render(draft))
                case .text(let text):
                    continuation.yield(text)
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
