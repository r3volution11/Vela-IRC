// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaIntelligence

@Suite("Catch me up reply format")
struct CatchUpReplyTests {
    typealias Topic = CatchUpDraft.Topic

    static let nicks = ["kenji", "ada", "wren", "doug|away", "orwell_fan", "maple_"]

    private func parse(_ text: String, isComplete: Bool = true) -> CatchUpDraft {
        CatchUpReply.parse(text, isComplete: isComplete, nicks: Self.nicks)
    }

    // MARK: The format

    @Test func readsTheFormat() {
        let draft = parse("""
        OVERVIEW: kenji and ada talked about the theme engine; wren asked you for a review.
        TOPIC: [2] | Theme engine | kenji said it landed and ada liked Palenight. | kenji, ada
        TOPIC: [13] | Sidebar review | wren asked for a review of the sidebar PR. | wren
        YOU: wren asked you to review the sidebar PR.
        """)
        #expect(draft == CatchUpDraft(
            overview: "kenji and ada talked about the theme engine; wren asked you for a review.",
            topics: [
                Topic(title: "Theme engine", summary: "kenji said it landed and ada liked Palenight.", participants: ["kenji", "ada"], firstLine: 2),
                Topic(title: "Sidebar review", summary: "wren asked for a review of the sidebar PR.", participants: ["wren"], firstLine: 13),
            ],
            addressedToYou: ["wren asked you to review the sidebar PR."]
        ))
    }

    @Test func writesWhatItReads() {
        let draft = CatchUpDraft(
            overview: "Theme talk.",
            topics: [
                Topic(title: "Theme engine", summary: "It landed.", participants: ["kenji", "ada"], firstLine: 2),
                Topic(title: "No line", summary: "", participants: ["wren"]),
                Topic(title: "A | pipe", summary: "One | two", participants: ["doug|away"], firstLine: 5),
            ],
            addressedToYou: ["wren asked you to review the PR."]
        )
        let text = CatchUpReply.render(draft)
        #expect(text == """
        OVERVIEW: Theme talk.
        TOPIC: [2] | Theme engine | It landed. | kenji, ada
        TOPIC: No line |  | wren
        TOPIC: [5] | A / pipe | One / two | doug|away
        YOU: wren asked you to review the PR.
        """)
        var expected = draft
        expected.topics[2].title = "A / pipe"
        expected.topics[2].summary = "One / two"
        #expect(parse(text) == expected)
    }

    // MARK: Quirks

    @Test func toleratesWhitespaceAndBlankLines() {
        let draft = parse("\n\n   OVERVIEW:    Theme talk.   \r\n\n  TOPIC:   2   |   Theme engine  |  It landed.  |  kenji ,  ada  \n\n")
        #expect(draft.overview == "Theme talk.")
        #expect(draft.topics == [Topic(title: "Theme engine", summary: "It landed.", participants: ["kenji", "ada"], firstLine: 2)])
    }

    @Test func toleratesMarkdownBulletsAndNumbering() {
        let draft = parse("""
        ## Summary
        **OVERVIEW:** Theme **talk** and `code`.
        - **TOPIC:** 2 | **Theme engine** | It landed. | kenji
        1. TOPIC: 3 | Review | wren asked. | wren
        2) Topic 3: 4 | Release notes | Notes are up. | ada
        • topic - 5 | Builds | Builds pass. | kenji
        > *You*: wren asked you to review the PR.
        """)
        #expect(draft.overview == "Theme talk and code.")
        #expect(draft.topics.map(\.title) == ["Theme engine", "Review", "Release notes", "Builds"])
        #expect(draft.topics.map(\.firstLine) == [2, 3, 4, 5])
        #expect(draft.addressedToYou == ["wren asked you to review the PR."])
    }

    @Test func readsLabelsOnTheirOwnLines() {
        let draft = parse("""
        Overview
        kenji and ada talked about themes.
        Topics:
        - 2 | Theme engine | It landed. | kenji
        - 9 | Review | wren asked. | wren
        Addressed to you:
        - wren asked you to review the PR.
        - None
        """)
        #expect(draft.overview == "kenji and ada talked about themes.")
        #expect(draft.topics.map(\.title) == ["Theme engine", "Review"])
        #expect(draft.addressedToYou == ["wren asked you to review the PR."])
    }

    @Test func readsTopicsWrittenAsBlocks() {
        let draft = parse("""
        OVERVIEW: Two topics.
        TOPIC: Theme engine
        Line: 2
        Summary: It landed.
        Nicks: kenji, ada
        Title: Review
        Lines: 9-12
        People: wren
        """)
        #expect(draft.topics == [
            Topic(title: "Theme engine", summary: "It landed.", participants: ["kenji", "ada"], firstLine: 2),
            Topic(title: "Review", participants: ["wren"], firstLine: 9),
        ])
    }

    @Test func readsLineNumbersHoweverWritten() {
        for (field, line) in [("12", 12), ("[12]", 12), ("(12)", 12), ("#12", 12), ("L12", 12), ("line 12", 12), ("Line: 12", 12),
                              ("lines 12–15", 12), ("12-15", 12), ("[line 12]", 12), ("first line 12", 12)] {
            #expect(parse("TOPIC: \(field) | Title | Summary. | kenji").topics.first?.firstLine == line, "\(field)")
        }
        // At the end, labeled, or leading the title.
        #expect(parse("TOPIC: Title | Summary. | kenji | 12").topics.first?.firstLine == 12)
        #expect(parse("TOPIC: Title | Summary. | kenji | line: 12").topics.first?.firstLine == 12)
        #expect(parse("TOPIC: [12] Title | Summary. | kenji").topics.first == Topic(title: "Title", summary: "Summary.", participants: ["kenji"], firstLine: 12))
        #expect(parse("TOPIC: Line 12: Title | Summary. | kenji").topics.first == Topic(title: "Title", summary: "Summary.", participants: ["kenji"], firstLine: 12))
        // Not line numbers.
        #expect(parse("TOPIC: Title | Summary. | kenji").topics.first?.firstLine == nil)
        #expect(parse("TOPIC: 2024 budget | Summary. | kenji").topics.first == Topic(title: "2024 budget", summary: "Summary.", participants: ["kenji"]))
        #expect(parse("TOPIC: 12 people | Summary. | kenji").topics.first?.firstLine == nil)
        #expect(parse("TOPIC: Later | Summary. | kenji").topics.first?.title == "Later")
    }

    @Test func toleratesMissingFields() {
        #expect(parse("TOPIC: 2 | Theme engine").topics == [Topic(title: "Theme engine", firstLine: 2)])
        #expect(parse("TOPIC: Theme engine").topics == [Topic(title: "Theme engine")])
        #expect(parse("TOPIC: 2 | Theme engine | It landed.").topics == [Topic(title: "Theme engine", summary: "It landed.", firstLine: 2)])
        #expect(parse("TOPIC: 2 | Theme engine | kenji, ada").topics == [Topic(title: "Theme engine", participants: ["kenji", "ada"], firstLine: 2)])
        #expect(parse("TOPIC: 2 | Theme engine |  | kenji").topics == [Topic(title: "Theme engine", participants: ["kenji"], firstLine: 2)])
        // No title, no topic.
        #expect(parse("TOPIC: 2 |  | It landed.").topics.isEmpty)
        #expect(parse("TOPIC:").topics.isEmpty)
        // A summary that merely starts with a nick isn't a list of nicks.
        #expect(parse("TOPIC: 2 | Theme engine | kenji disagreed").topics.first?.summary == "kenji disagreed")
        // A field that's just a label's word is a title or a summary.
        #expect(parse("TOPIC: 3 | Overview | Summary. | kenji").topics == [Topic(title: "Overview", summary: "Summary.", participants: ["kenji"], firstLine: 3)])
    }

    @Test func toleratesFieldsOutOfOrder() {
        #expect(parse("TOPIC: Theme engine | kenji and ada | It landed. | 2").topics
            == [Topic(title: "Theme engine", summary: "It landed.", participants: ["kenji", "ada"], firstLine: 2)])
        #expect(parse("TOPIC: Title: Theme engine | Who: @kenji, +ada | What: It landed. | Line: 2").topics
            == [Topic(title: "Theme engine", summary: "It landed.", participants: ["kenji", "ada"], firstLine: 2)])
    }

    @Test func keepsPipesInsideNicks() {
        #expect(parse("TOPIC: 4 | Away | doug|away left. | doug|away, kenji").topics
            == [Topic(title: "Away", summary: "doug|away left.", participants: ["doug|away", "kenji"], firstLine: 4)])
        // Pipes without spaces at all still split.
        #expect(parse("TOPIC: 4|Theme engine|It landed.|kenji").topics
            == [Topic(title: "Theme engine", summary: "It landed.", participants: ["kenji"], firstLine: 4)])
    }

    @Test func readsTopicsInTheModelsOwnShape() {
        #expect(parse("TOPIC: Theme engine: kenji said it landed (kenji, ada).").topics
            == [Topic(title: "Theme engine", summary: "kenji said it landed.", participants: ["kenji", "ada"])])
        #expect(parse("TOPIC: Theme engine — kenji said it landed").topics
            == [Topic(title: "Theme engine", summary: "kenji said it landed")])
        #expect(parse("TOPIC: \"Theme engine.\" | It landed. | kenji").topics.first?.title == "Theme engine")
    }

    @Test func removesLineReferencesFromText() {
        let draft = parse("""
        OVERVIEW: kenji [2] said the engine landed (line 3); it was the 1996 plan (1996).
        TOPIC: 2 | Theme engine | It landed [2]. | kenji
        """)
        #expect(draft.overview == "kenji said the engine landed; it was the 1996 plan (1996).")
        #expect(draft.topics.first?.summary == "It landed.")
    }

    @Test func skipsPreamblesAndHeadings() {
        let draft = parse("""
        Sure! Here's a summary of the conversation.
        Here is the summary:
        OVERVIEW: Theme talk.
        Part 2, lines 41–80:
        TOPIC: 2 | Theme engine | It landed. | kenji
        """)
        #expect(draft.overview == "Theme talk.")
        #expect(draft.topics.count == 1)
    }

    @Test func readsAnUnlabeledOverview() {
        let draft = parse("""
        kenji and ada talked about the theme engine.
        TOPIC: 2 | Theme engine | It landed. | kenji
        """)
        #expect(draft.overview == "kenji and ada talked about the theme engine.")
        #expect(draft.topics.count == 1)
        // An overview that wraps onto a second line.
        #expect(parse("OVERVIEW: kenji and ada talked\nabout the theme engine.\nTOPIC: 2 | Theme engine").overview
            == "kenji and ada talked about the theme engine.")
    }

    /// Seen on the live model: an overview or a note written with a topic's
    /// fields keeps its first part.
    @Test func readsAnOverviewOrNoteWrittenLikeATopic() {
        let draft = parse("""
        OVERVIEW: Talk about themes. | kenji said it landed. | kenji, ada | 2
        YOU: wren: doug: can you review the PR? | wren, ada
        """)
        #expect(draft.overview == "Talk about themes.")
        #expect(draft.addressedToYou == ["wren: doug: can you review the PR?"])
    }

    @Test func dropsEmptyNotesAndRepeatedTopics() {
        let draft = parse("""
        OVERVIEW: Talk.
        TOPIC: 2 | Theme engine | It landed. | kenji
        TOPIC: 7 | theme engine | Again. | ada
        YOU: None.
        YOU: n/a
        YOU: (none)
        """)
        #expect(draft.topics.count == 1)
        #expect(draft.addressedToYou.isEmpty)
    }

    // MARK: Refusals

    @Test func recognizesRefusals() {
        for text in ["I'm sorry, but I can't help with that.", "I’m sorry, I cannot summarize this.", "Sorry, but I can't do that.",
                     "As an AI, I won't.", "I cannot assist with this request.", "Unfortunately, I am unable to help."] {
            #expect(CatchUpReply.isRefusal(text), "\(text)")
            #expect(CatchUpReply.isDeclined(parse(text)), "\(text)")
            #expect(CatchUpReply.isDeclined(parse("OVERVIEW: " + text)), "\(text)")
        }
        #expect(!CatchUpReply.isRefusal("In the channel, kenji said sorry."))
        #expect(CatchUpReply.isDeclined(parse("")))
        #expect(CatchUpReply.isDeclined(parse("   \n\n")))
        #expect(!CatchUpReply.isDeclined(parse("OVERVIEW: Theme talk.")))
        #expect(!CatchUpReply.isDeclined(parse("TOPIC: 2 | Theme engine")))
    }

    // MARK: Streaming

    static let streamed = """
    **OVERVIEW:** kenji and ada (the maintainers) talked about the engine [2]; wren asked you for a review.
    TOPIC: 2 | Theme engine | kenji said it landed. | kenji, ada
    TOPIC: [13] | Sidebar review | wren asked for a review. | wren
    YOU: wren asked you to review the sidebar PR.
    """

    /// Every prefix of a reply, as it streams: nothing read from one is
    /// missing from the next, labels and line references never show half
    /// written, and topics appear whole.
    @Test func partialRepliesNeverTakeTextBack() {
        let final = parse(Self.streamed)
        #expect(final.overview == "kenji and ada (the maintainers) talked about the engine; wren asked you for a review.")
        let reply = Self.streamed + "\n"
        var previous = CatchUpDraft()
        for end in 0...reply.count {
            let draft = parse(String(reply.prefix(end)), isComplete: false)
            #expect(draft.overview.hasPrefix(previous.overview), "\(previous.overview) → \(draft.overview)")
            #expect(final.overview.hasPrefix(draft.overview), "\(draft.overview)")
            #expect(Array(draft.topics.prefix(previous.topics.count)) == previous.topics)
            #expect(Array(final.topics.prefix(draft.topics.count)) == draft.topics)
            #expect(Array(final.addressedToYou.prefix(draft.addressedToYou.count)) == draft.addressedToYou)
            for fragment in ["OVER", "*", "[", "TOPIC"] {
                #expect(!draft.overview.contains(fragment), "\(draft.overview)")
            }
            previous = draft
        }
        #expect(previous == final)
    }

    @Test func topicsAppearWhenTheirLineIsDone() {
        let firstTopic = Self.streamed.split(separator: "\n")[0...1].joined(separator: "\n")
        // The topic's line is all there but not yet ended.
        #expect(parse(firstTopic, isComplete: false).topics.isEmpty)
        #expect(parse(firstTopic + "\n", isComplete: false).topics.map(\.title) == ["Theme engine"])
        // At the end of the reply, the last line counts.
        #expect(parse(firstTopic, isComplete: true).topics.map(\.title) == ["Theme engine"])
    }

    @Test func aStreamedOverviewOnItsOwnLine() {
        #expect(parse("OVERVIEW:\nkenji and", isComplete: false).overview == "kenji and")
        #expect(parse("OVERVIEW:\nTOP", isComplete: false).overview.isEmpty)
        #expect(parse("OVERVIEW: Done.\nAnd more", isComplete: false).overview == "Done.")
    }

    @Test func aStreamedRefusalIsNeverShown() {
        let refusal = "I'm sorry, but I can't summarize this conversation."
        for end in 0...refusal.count {
            #expect(parse(String(refusal.prefix(end)), isComplete: false).overview.isEmpty)
            #expect(parse("OVERVIEW: " + String(refusal.prefix(end)), isComplete: false).overview.isEmpty)
        }
        #expect(parse(refusal + "\n", isComplete: false).overview.isEmpty)
    }

    /// Reading every prefix of a long reply (each snapshot is the reply
    /// so far) stays cheap: the final pass parses on every token.
    @Test func parsingEverySnapshotIsCheap() {
        let topic = "TOPIC: 12 | Minimum wage | redfern said a $20 minimum hurts small businesses; bluejay and libby disagreed. | redfern, bluejay, libby\n"
        let reply = "OVERVIEW: People argued about the minimum wage, voter ID and a carbon tax; maple_ asked you about the polls.\n"
            + String(repeating: topic, count: 6) + "YOU: maple_ asked whether ID was an issue when you worked the polls.\n"
        // About a token per four characters: one snapshot each.
        let snapshots = stride(from: 4, through: reply.count, by: 4).map { String(reply.prefix($0)) }
        let clock = ContinuousClock()
        let whole = clock.measure {
            for snapshot in snapshots { _ = CatchUpReply.parse(snapshot, isComplete: false, nicks: Self.nicks) }
        }
        var reader = CatchUpReply.Reader(nicks: Self.nicks)
        let incremental = clock.measure {
            for snapshot in snapshots { _ = reader.read(snapshot, isComplete: false) }
        }
        print("Read \(snapshots.count) snapshots of a \(reply.utf8.count)-byte reply: \(incremental) as they stream, \(whole) parsing each whole")
        #expect(incremental < .seconds(1))
    }

    /// The streaming reader reads every snapshot as a fresh parse would,
    /// and starts over when a snapshot doesn't continue the last.
    @Test func theReaderMatchesAFreshParse() {
        let reply = Self.streamed + "\nTOPIC: 20 | Builds | kenji said builds pass. | kenji\r\nYOU: ada asked you about builds.\n"
        var reader = CatchUpReply.Reader(nicks: Self.nicks)
        for end in 0...reply.count {
            let snapshot = String(reply.prefix(end))
            #expect(reader.read(snapshot, isComplete: false) == parse(snapshot, isComplete: false), "\(end)")
        }
        #expect(reader.read(reply, isComplete: true) == parse(reply))
        // A different reply on the same reader.
        let other = "OVERVIEW: Something else.\nTOPIC: 3 | Other | Other talk. | ada\n"
        #expect(reader.read(other, isComplete: true) == parse(other))
        #expect(reader.read(Self.streamed, isComplete: true) == parse(Self.streamed))
    }
}
