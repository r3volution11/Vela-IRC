// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaIntelligence

@Suite("Recap reply")
struct RecapReplyTests {
    let nicks = ["kenji", "ada", "wren", "priya", "doug"]

    @Test func readsEveryKindOfLine() {
        let draft = RecapReply.parse("""
        OVERVIEW: kenji landed the theme engine.
        TOPIC: [2-9] | Theme engine | It's on main. | kenji, ada
        DECISION: [14] | The rail's width is global.
        QUESTION: [20] | Does Ocean ship next?
        TODO: [21] | priya | review the contrast pass
        YOU: [12] | wren | asked you to review the PR
        """, nicks: nicks)
        #expect(draft.overview == ["kenji landed the theme engine."])
        #expect(draft.topics == [RecapDraft.Topic(lines: 2...9, title: "Theme engine", summary: "It's on main.", participants: ["kenji", "ada"])])
        #expect(draft.notes == [
            RecapDraft.Note(kind: .decision, line: 14, text: "The rail's width is global."),
            RecapDraft.Note(kind: .question, line: 20, text: "Does Ocean ship next?"),
            RecapDraft.Note(kind: .followUp, line: 21, text: "review the contrast pass", owner: "priya"),
        ])
        #expect(draft.you == [RecapDraft.YouNote(line: 12, nick: "wren", text: "asked you to review the PR")])
    }

    @Test func toleratesWhatModelsWrite() {
        let draft = RecapReply.parse("""
        Sure! Here's the recap:

        **Overview:** Busy afternoon.
        - **Topic 1** - [lines 3 to 7] Theme engine | kenji says it landed. | kenji
        * Decided: (line 4) Palenight is the default
        1. follow-up: [9] | ada | write the docs
        TOPIC [10–12] | Review | wren asked. | wren
        Open question: [11] | who reviews?
        """, nicks: nicks)
        #expect(draft.overview == ["Busy afternoon."])
        #expect(draft.topics.map(\.title) == ["Theme engine", "Review"])
        #expect(draft.topics.map(\.lines) == [3...7, 10...12])
        #expect(draft.notes.map(\.kind) == [.decision, .followUp, .question])
        #expect(draft.notes[0].line == 4)
        #expect(draft.notes[0].text == "Palenight is the default")
        #expect(draft.notes[1].owner == "ada")
    }

    /// What the live model wrote: a list after one label, a summary on a
    /// line of its own, the number after the title, copied lines.
    @Test func readsTheLiveModelsHabits() {
        let draft = RecapReply.parse("""
        OVERVIEW: Theme updates and a review request.
        TOPIC: [2] | Theme engine | It landed. | kenji, ada
        [13] | Sidebar PR review | doug asked to review it | wren, doug
        TOPIC: Release notes | [22] | nadia asked for bits. | nadia, theo
        TOPIC: [30] Token reading
        kenji said every surface reads from tokens now
        TOPIC: [40] kenji: the theme engine landed | [41] ada: agreed | [42] wren: ok
        DECISION: [18] | Global rail width preferred | ada, kenji
        QUESTION: [19] priya: any chance the Ocean theme ships?
        TODO: [20] | priya | review the contrast pass tonight
        Let me know if you need anything else.
        """, nicks: nicks)
        #expect(draft.topics.map(\.title) == ["Theme engine", "Sidebar PR review", "Release notes", "Token reading"])
        #expect(draft.topics.map(\.lines) == [2...2, 13...13, 22...22, 30...30])
        #expect(draft.topics[3].summary == "kenji said every surface reads from tokens now")
        #expect(draft.notes.map(\.text) == ["Global rail width preferred", "any chance the Ocean theme ships?", "review the contrast pass tonight"])
        #expect(draft.notes.map(\.owner) == [nil, nil, "priya"])
    }

    @Test func mergeTopicsNameThePartsTheyCombine() {
        let draft = RecapReply.parse("""
        OVERVIEW: All of it.
        TOPIC: T2, T5 | Release | Planned. | ada
        TOPIC: [T3 and T4] | Build | Fixed. | kenji
        TOPIC: T1: Greetings | Said hi.
        """, nicks: nicks)
        #expect(draft.topics.map(\.parts) == [[2, 5], [3, 4], [1]])
        #expect(draft.topics.map(\.title) == ["Release", "Build", "Greetings"])
    }

    @Test func lineRanges() {
        #expect(RecapReply.lineRange("[12-40]") == 12...40)
        #expect(RecapReply.lineRange("12–40") == 12...40)
        #expect(RecapReply.lineRange("lines 12 to 40") == 12...40)
        #expect(RecapReply.lineRange("(line 7)") == 7...7)
        #expect(RecapReply.lineRange("[40-12]") == 12...40)
        #expect(RecapReply.lineRange("12 cases") == nil)
        #expect(RecapReply.lineRange("Release") == nil)
        #expect(RecapReply.topicReferences("T2, T5") == [2, 5])
        #expect(RecapReply.topicReferences("Release date") == nil)
    }

    @Test func streamingReadsOnlyFinishedLines() {
        var reader = RecapReply.Reader(nicks: nicks)
        #expect(reader.read("OVERVIEW: Busy", isComplete: false).overview.isEmpty)
        #expect(reader.read("OVERVIEW: Busy day.\nTOPIC: [1-2] | The", isComplete: false).overview == ["Busy day."])
        let partial = reader.read("OVERVIEW: Busy day.\nTOPIC: [1-2] | The", isComplete: false)
        #expect(partial.topics.isEmpty)
        let done = reader.read("OVERVIEW: Busy day.\nTOPIC: [1-2] | Theme | Landed. | kenji", isComplete: true)
        #expect(done.topics.map(\.title) == ["Theme"])
    }

    @Test func refusalsAndNothingAreEmpty() {
        #expect(RecapReply.isDeclined(RecapReply.parse("I'm sorry, but I can't help with that.")))
        #expect(RecapReply.isDeclined(RecapReply.parse("")))
        let draft = RecapReply.parse("OVERVIEW: Talk.\nDECISION: none\nYOU: N/A")
        #expect(draft.notes.isEmpty)
        #expect(draft.you.isEmpty)
    }

    @Test func detailPointsAcceptPlainBullets() {
        let draft = RecapReply.parse("Here are the points:\n- kenji landed it.\nPOINT: ada likes it.\n• wren asked for a review.", bulletsArePoints: true)
        #expect(draft.points == ["kenji landed it.", "ada likes it.", "wren asked for a review."])
    }
}
