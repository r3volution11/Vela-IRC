// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaCore
import VelaStore
@testable import VelaIntelligence

/// What your own providers are sent: the same prompts as Apple's model
/// (``CatchUpPrompts``, ``RecapPrompts``), so message text, nicks and your
/// own nick, and never a channel's, network's or server's name. Checked on
/// the wire, for every provider: the URL, every header and the body of
/// every request, through one pass, chunked passes and merges, a Recap
/// across conversations and More detail.
@Suite("Providers are never sent channel, network or server names")
@MainActor
struct ProviderPrivacyTests {
    static let channels = ["##politicalfun", "#secret-project"]
    static let networks = ["PoliticsNet", "Example IRC"]
    static let servers = ["irc.politicsnet.example", "irc.example.org"]

    var names: [String] { Self.channels + Self.networks + Self.servers }

    func check(_ requests: [StubServer.Request], kind: AIProviderKind, names: [String]? = nil) {
        #expect(!requests.isEmpty, "no requests to \(kind)")
        for request in requests {
            let headers = request.headers.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
            for text in [request.url.absoluteString, headers, request.bodyText] {
                for name in names ?? self.names {
                    #expect(!text.localizedCaseInsensitiveContains(name), "\(name) sent to \(kind): \(text.prefix(300))")
                }
            }
        }
        // The reader's nick is there, to say "you".
        #expect(requests.contains { $0.bodyText.contains("doug") })
    }

    func catchUpRequest(lines: Int) -> CatchUpRequest {
        // A line that mentions the reader, so instructions have something to say.
        var chatter = CatchUpFixtures.chatter(lines)
        chatter.append(CatchUpFixtures.line("alice", "doug: can you look at this?", minute: lines + 1))
        return CatchUpRequest(
            bufferID: CatchUpFixtures.bufferID,
            bufferName: Self.channels[0],
            networkName: Self.networks[0],
            ownNick: "doug",
            lines: chatter
        )
    }

    @Test(arguments: AIProviderKind.allCases)
    func catchUp(kind: AIProviderKind) async throws {
        let harness = RoutingHarness(reply: { prompt in
            let numbers = lineNumbers(in: prompt)
            return CatchUpReply.render(CatchUpDraft(
                overview: "Talk about the build.",
                topics: [.init(title: "Build", participants: ["alice"], firstLine: numbers.first)]
            ))
        })
        // A custom server with a small context: read in parts, then merged.
        let entry = harness.add(kind, context: kind == .openAICompatible ? 2_048 : nil)
        harness.settings[.intelligenceCatchUpModel] = "\(entry.id)/\(kind.recommendedModels.first?.id ?? "llama3")"
        for lines in [3, 240] {
            _ = try await harness.summarizer.summary(for: catchUpRequest(lines: lines))
        }
        if kind == .openAICompatible { #expect(harness.requests(kind).count > 3) }
        check(harness.requests(kind), kind: kind)
        // Nobody else was asked.
        #expect(harness.allRequests.count == harness.requests(kind).count)
    }

    @Test(arguments: AIProviderKind.allCases)
    func recapAndMoreDetail(kind: AIProviderKind) async throws {
        let harness = RoutingHarness(reply: { prompt in
            if prompt.hasPrefix("Recaps of consecutive parts") { return "OVERVIEW: Merged.\nTOPIC: T1, T2 | Merged | Combined. | alice" }
            let numbers = lineNumbers(in: prompt)
            guard let first = numbers.first, let last = numbers.last else { return "POINT: Talk." }
            return "OVERVIEW: Part \(first).\nTOPIC: [\(first)-\(last)] | Part \(first) | Talked about the build. | alice, bob\nPOINT: Talk."
        })
        let entry = harness.add(kind, context: kind == .openAICompatible ? 2_048 : nil)
        harness.settings[.intelligenceRecapModel] = "\(entry.id)/\(kind.recommendedModels.first?.id ?? "llama3")"
        let cast = ["alice", "quillfeather", "bob"]
        let first = RecapFixtures.conversation(Self.channels[0], RecapFixtures.chatter(200, cast: cast), networkName: Self.networks[0])
        let second = RecapFixtures.conversation(
            Self.channels[1],
            RecapFixtures.chatter(200, from: 200, cast: cast),
            network: RecapFixtures.otherNetwork,
            networkName: Self.networks[1]
        )
        let input = RecapFixtures.input([first, second], place: .everywhere)
        for try await _ in harness.summarizer.recap(input) {}
        let detail = RecapDetailRequest(lines: Array(first.lines.prefix(20)), ownNick: "doug", focus: "Release plans", model: .provider(providerID: entry.id, modelID: "m"))
        for try await _ in harness.summarizer.detail(detail) {}
        if kind == .openAICompatible { #expect(harness.requests(kind).count > 3) }
        check(harness.requests(kind), kind: kind)
        #expect(harness.allRequests.count == harness.requests(kind).count)
    }

    /// What the server (or the network, or a bouncer) sends a channel
    /// itself is shown there but never sent: its name stands where a nick
    /// would, and its words name servers. Catch me up and Recap gather
    /// people's lines only, from a real session (``ServerLineFixture``).
    @Test(arguments: AIProviderKind.allCases)
    func serverLinesNeverReachAProvider(kind: AIProviderKind) async throws {
        let fixture = try await ServerLineFixture.make()
        defer { fixture.remove() }
        fixture.expectServerLinesShown()

        // Catch me up.
        let request = fixture.catchUpRequest
        #expect(request.lines.map { "\($0.nick): \($0.text)" } == ServerLineFixture.peoplesLines)
        let catchUp = RoutingHarness(reply: { prompt in
            CatchUpReply.render(CatchUpDraft(overview: "Talk about the build.", topics: [.init(title: "Build", participants: ["alice"], firstLine: lineNumbers(in: prompt).first)]))
        })
        let catchUpEntry = catchUp.add(kind)
        catchUp.settings[.intelligenceCatchUpModel] = "\(catchUpEntry.id)/\(kind.recommendedModels.first?.id ?? "llama3")"
        _ = try await catchUp.summarizer.summary(for: request)
        check(catchUp.requests(kind), kind: kind, names: ServerLineFixture.names)

        // Recap.
        let input = await fixture.recapInput()
        #expect(input.conversations.flatMap(\.lines).map { "\($0.nick): \($0.text)" } == ServerLineFixture.peoplesLines)
        let recap = RoutingHarness(reply: { prompt in
            let numbers = lineNumbers(in: prompt)
            guard let first = numbers.first, let last = numbers.last else { return "POINT: Talk." }
            return "OVERVIEW: Talk.\nTOPIC: [\(first)-\(last)] | Build | Talked about the build. | alice, bob"
        })
        let recapEntry = recap.add(kind)
        recap.settings[.intelligenceRecapModel] = "\(recapEntry.id)/\(kind.recommendedModels.first?.id ?? "llama3")"
        for try await _ in recap.summarizer.recap(input) {}
        check(recap.requests(kind), kind: kind, names: ServerLineFixture.names)
    }

    /// The consent sheet promises exactly this; the prompt builders are
    /// shared by Apple's model and every provider, so it holds for all.
    @Test func promptBuildersAreShared() {
        let transcript = CatchUpTranscript(catchUpRequest(lines: 10))
        let prompt = CatchUpPrompts.single(transcript)
        for name in names {
            #expect(!prompt.localizedCaseInsensitiveContains(name))
        }
    }
}
