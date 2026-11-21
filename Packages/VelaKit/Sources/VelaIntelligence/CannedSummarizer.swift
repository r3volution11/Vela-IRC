// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Fixed summaries for demo mode, screenshots and tests; works on any Mac.
///
/// The demo channels (`DemoContent`) get hand-written summaries: each topic
/// is included only when its messages are among the lines asked about, and
/// links to the first of them. Anything else gets a plain summary built
/// from the request (who spoke, how much, who mentioned you). Results
/// stream in three steps, like the real model's.
public final class CannedSummarizer: ConversationSummarizer {
    let stepDelay: Duration

    /// - Parameter stepDelay: The pause before each streamed step.
    public init(stepDelay: Duration = .milliseconds(350)) {
        self.stepDelay = stepDelay
    }

    public nonisolated func summarize(_ request: CatchUpRequest) -> AsyncThrowingStream<CatchUpSummary, Error> {
        let delay = stepDelay
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let steps = try Self.steps(for: request)
                    for step in steps {
                        if delay > .zero { try await Task.sleep(for: delay) }
                        continuation.yield(step)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The snapshots streamed for `request`: half the overview, then all of
    /// it with the topics, then the finished summary.
    nonisolated static func steps(for request: CatchUpRequest) throws -> [CatchUpSummary] {
        let final = try summary(for: request)
        let words = final.overview.split(separator: " ")
        let half = words.prefix(max(1, words.count / 2)).joined(separator: " ")
        var first = final
        first.overview = half
        first.topics = []
        first.addressedToYou = []
        first.isComplete = false
        var second = final
        second.addressedToYou = []
        second.isComplete = false
        return [first, second, final]
    }

    /// The finished summary for `request`.
    nonisolated static func summary(for request: CatchUpRequest) throws -> CatchUpSummary {
        let lines = request.lines.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { throw CatchUpError.nothingToSummarize }
        if let script = DemoScript.scripts[request.bufferName.lowercased()],
           let summary = script.summary(for: lines, request: request) {
            return summary
        }
        return generic(lines, request: request)
    }

    /// "12 messages from kenji, ada and 2 others." with one topic covering
    /// it all and a note for each line that mentions you.
    nonisolated static func generic(_ lines: [CatchUpLine], request: CatchUpRequest) -> CatchUpSummary {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for line in lines where !line.nick.isEmpty {
            if counts[line.nick] == nil { order.append(line.nick) }
            counts[line.nick, default: 0] += 1
        }
        let speakers = order.sorted { (counts[$0] ?? 0) > (counts[$1] ?? 0) }
        let messages = lines.count == 1 ? "1 message" : "\(lines.count) messages"
        var overview = speakers.isEmpty ? "\(messages)." : "\(messages) from \(nameList(speakers))."
        if speakers.count > 2, let top = speakers.first, let count = counts[top], count * 3 >= lines.count {
            overview += " \(top) said the most."
        }
        let topic = CatchUpTopic(
            id: CatchUpEngine.topicID(0),
            title: isChannel(request.bufferName) ? "Conversation in \(request.bufferName)" : "Conversation with \(request.bufferName)",
            summary: "\(nameList(Array(order.prefix(4)))) talked.",
            participants: Array(order.prefix(6)),
            firstLineID: lines.first?.id
        )
        let transcript = CatchUpTranscript(lines: lines, ownNick: request.ownNick)
        return CatchUpSummary(
            overview: overview,
            topics: [topic],
            addressedToYou: CatchUpEngine.mentionNotes(in: transcript),
            messageCount: transcript.entries.count,
            isComplete: true
        )
    }

    /// `#vela` and the like, rather than a private conversation's nick.
    nonisolated static func isChannel(_ name: String) -> Bool {
        name.first.map { "#&+!".contains($0) } ?? false
    }

    /// "a", "a and b", "a, b and c", "a, b and 3 others".
    nonisolated static func nameList(_ names: [String]) -> String {
        switch names.count {
        case 0: ""
        case 1: names[0]
        case 2: "\(names[0]) and \(names[1])"
        case 3: "\(names[0]), \(names[1]) and \(names[2])"
        default: "\(names[0]), \(names[1]) and \(names.count - 2) others"
        }
    }
}

// MARK: - Demo channels

/// Hand-written summaries of the demo channels' conversations.
nonisolated private struct DemoScript {
    struct Topic {
        /// Words from the topic's first message; the topic is shown only
        /// when a line containing them is being summarized.
        let anchor: String
        let title: String
        let summary: String
        let participants: [String]
        /// A phrase for the overview: "the new theme engine".
        let gist: String
    }

    struct Mention {
        let anchor: String
        let note: String
    }

    var topics: [Topic]
    var mentions: [Mention] = []

    func summary(for lines: [CatchUpLine], request: CatchUpRequest) -> CatchUpSummary? {
        func firstLine(containing anchor: String) -> CatchUpLine? {
            lines.first { $0.text.localizedCaseInsensitiveContains(anchor) }
        }
        var included: [(Topic, CatchUpLine)] = []
        for topic in topics {
            if let line = firstLine(containing: topic.anchor) { included.append((topic, line)) }
        }
        guard !included.isEmpty else { return nil }
        let notes = mentions.filter { firstLine(containing: $0.anchor) != nil }.map(\.note)

        let gists = included.map(\.0.gist)
        var overview = gists.count > 3
            ? "Talk was about \(gists.prefix(3).joined(separator: ", ")) and more."
            : "Talk was about \(CannedSummarizer.nameList(gists))."
        if let first = notes.first { overview += " \(first)" }

        return CatchUpSummary(
            overview: overview,
            topics: included.prefix(CatchUpPrompts.maximumTopics).enumerated().map { index, pair in
                CatchUpTopic(
                    id: CatchUpEngine.topicID(index),
                    title: pair.0.title,
                    summary: pair.0.summary,
                    participants: pair.0.participants,
                    firstLineID: pair.1.id
                )
            },
            addressedToYou: notes,
            messageCount: min(lines.count, CatchUpTranscript.maximumLines),
            isComplete: true
        )
    }

    static let scripts: [String: DemoScript] = [
        "#vela": DemoScript(
            topics: [
                Topic(
                    anchor: "theme engine landed",
                    title: "New theme engine",
                    summary: "kenji says the token-based theme engine is on main, down to the title bar. ada likes Palenight with the grouped layout.",
                    participants: ["kenji", "ada"],
                    gist: "the new theme engine"
                ),
                Topic(
                    anchor: "Crab Nebula",
                    title: "Ocean theme inspiration",
                    summary: "theo shared a Crab Nebula photo, and priya thinks it's the look for the Ocean theme.",
                    participants: ["theo", "priya"],
                    gist: "ideas for the Ocean theme"
                ),
                Topic(
                    anchor: "IRCv3 spec notes",
                    title: "IRCv3 notes",
                    summary: "doug pushed notes on the IRCv3 specs. lukas cares most about chathistory and reactions.",
                    participants: ["doug", "lukas"],
                    gist: "IRCv3 support"
                ),
                Topic(
                    anchor: "Blender open movie",
                    title: "Inline video",
                    summary: "marisol asked about the Blender movie embed. kenji said it plays inline and loads nothing until you press play.",
                    participants: ["marisol", "kenji"],
                    gist: "inline video"
                ),
                Topic(
                    anchor: "sidebar rail PR",
                    title: "Sidebar rail review",
                    summary: "wren asked doug to review the sidebar rail pull request, and doug agreed to do it.",
                    participants: ["wren", "doug"],
                    gist: "a pull request review"
                ),
                Topic(
                    anchor: "concurrency defaults",
                    title: "Swift concurrency post",
                    summary: "theo linked a Swift blog post about the new concurrency defaults.",
                    participants: ["theo"],
                    gist: "Swift concurrency"
                ),
            ],
            mentions: [
                Mention(anchor: "doug: can you review", note: "wren asked you to review the sidebar rail PR."),
            ]
        ),
        "#swift": DemoScript(topics: [
            Topic(
                anchor: "struct nonisolated",
                title: "Nonisolated structs",
                summary: "felix asked how to opt a struct out of MainActor by default. mina said nonisolated struct works since Swift 6.2, and hana pointed to SE-0466.",
                participants: ["felix", "mina", "hana"],
                gist: "making a struct nonisolated"
            ),
        ]),
        "#macdev": DemoScript(topics: [
            Topic(
                anchor: "Liquid Glass sidebar",
                title: "Liquid Glass sidebars",
                summary: "irene sees the new sidebar clash with custom backgrounds. sam suggests a custom split view for full control.",
                participants: ["irene", "sam"],
                gist: "Liquid Glass sidebars"
            ),
        ]),
        "#vela-offtopic": DemoScript(topics: [
            Topic(
                anchor: "talking about themes",
                title: "Theme week",
                summary: "wren noticed #vela only talks about themes; marisol says it's theme week every week.",
                participants: ["wren", "marisol"],
                gist: "theme week"
            ),
            Topic(
                anchor: "geomagnetic storm",
                title: "Aurora watch",
                summary: "priya stayed up for the storm alerts. lukas had clouds and shared an aurora photo instead.",
                participants: ["priya", "lukas", "wren"],
                gist: "the aurora alerts"
            ),
            Topic(
                anchor: "Madrid",
                title: "Skies around the world",
                summary: "marisol, kenji and lukas compared the night sky in Madrid, Hokkaido and Hamburg, and wren noticed the channel went international.",
                participants: ["marisol", "kenji", "lukas", "wren"],
                gist: "skies around the world"
            ),
        ]),
        "#media": DemoScript(topics: [
            Topic(
                anchor: "preview sizes are split up",
                title: "Separate preview sizes",
                summary: "kenji says links, videos and images now each have their own size setting.",
                participants: ["kenji"],
                gist: "preview sizes"
            ),
            Topic(
                anchor: "on Vimeo",
                title: "Vimeo player",
                summary: "ada posted a Vimeo video, and kenji explained the inline player and Expand.",
                participants: ["ada", "kenji"],
                gist: "the Vimeo player"
            ),
            Topic(
                anchor: "no idea what it is",
                title: "Filtered links",
                summary: "The adult-site filter stopped a link wren got, and doug added a site rule for a returning spam domain.",
                participants: ["wren", "doug", "kenji"],
                gist: "link filtering"
            ),
            Topic(
                anchor: "star cluster in Vela",
                title: "ESO star cluster",
                summary: "theo shared ESO's new image of a star cluster in Vela.",
                participants: ["theo"],
                gist: "an ESO image"
            ),
            Topic(
                anchor: "link cards come in",
                title: "Link card sizes",
                summary: "marisol notes link cards come in Minimal, Standard and Large, with Standard as the default.",
                participants: ["marisol"],
                gist: "link card sizes"
            ),
        ]),
    ]
}
