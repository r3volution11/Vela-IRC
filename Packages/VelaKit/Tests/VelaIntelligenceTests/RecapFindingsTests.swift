// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaCore
@testable import VelaIntelligence

@Suite("Recap findings: for you, links, people")
struct RecapFindingsTests {
    typealias F = RecapFixtures

    // MARK: For you

    @Test func mentionsAndHighlightsAreForYou() {
        let lines = [
            F.line("wren", "doug: can you review the sidebar PR?", minute: 0, msgid: "a"),
            F.line("kenji", "the dougnut shop is closed", minute: 1),
            F.line("ada", "ping about the build", minute: 2, highlight: true),
            F.line("doug", "doug: talking to myself", minute: 3, isSelf: true),
        ]
        let findings = RecapFindings(F.input([F.conversation("#vela", lines)]))
        #expect(findings.forYou.map(\.nick) == ["wren", "ada"])
        let wren = findings.forYou[0]
        #expect(wren.quote == "can you review the sidebar PR?")
        #expect(wren.isRequest)
        #expect(wren.reference.lineID == lines[0].id)
        #expect(!wren.isPrivate)
        #expect(!findings.forYou[1].isRequest)
    }

    @Test func whetherYouAnswered() {
        let asked = F.line("wren", "doug: can you review the PR?", minute: 0, msgid: "q")
        func answered(by yours: RecapLine) -> Bool {
            let conversation = F.conversation("#vela", [asked, yours])
            return RecapFindings.isAnswered(asked, in: conversation)
        }
        // A reply to it, at any time.
        #expect(answered(by: F.line("doug", "done", minute: 300, isSelf: true, replyTo: "q")))
        // Naming them, at any time.
        #expect(answered(by: F.line("doug", "wren: merged", minute: 300, isSelf: true)))
        // Speaking there soon after.
        #expect(answered(by: F.line("doug", "on it", minute: 10, isSelf: true)))
        // Speaking there much later, about something else, doesn't count.
        #expect(!answered(by: F.line("doug", "good night all", minute: 120, isSelf: true)))
        // Only after it.
        #expect(!answered(by: F.line("doug", "wren: hi", minute: -5, isSelf: true)))
        // Nothing from you.
        #expect(!RecapFindings.isAnswered(asked, in: F.conversation("#vela", [asked])))
    }

    @Test func privateConversationsCountEachRunOnce() {
        let lines = [
            F.line("marisol", "hey!", minute: 0),
            F.line("marisol", "do you have a minute to look at the credits doc?", minute: 1),
            F.line("doug", "sure", minute: 2, isSelf: true),
            F.line("marisol", "thank you", minute: 3),
            F.line("marisol", "back again with another thing", minute: 200),
        ]
        let findings = RecapFindings(F.input([F.conversation("marisol", lines)]))
        #expect(findings.forYou.count == 3)
        #expect(findings.forYou[0].followingMessages == 1)
        #expect(findings.forYou[0].isRequest)
        #expect(findings.forYou[0].isAnswered)
        #expect(findings.forYou[0].isPrivate)
        #expect(!findings.forYou[2].isAnswered)
        #expect(findings.unansweredCount == 2)
    }

    @Test func atMostSoManyForYouTheNewest() {
        let lines = (0..<50).map { F.line("wren", "doug: number \($0)", minute: Double($0)) }
        let findings = RecapFindings(F.input([F.conversation("#vela", lines)]))
        #expect(findings.forYou.count == RecapFindings.maximumForYou)
        #expect(findings.forYou.last?.quote == "number 49")
    }

    // MARK: Links

    @Test func linksAreGroupedAndCounted() {
        let lines = [
            F.line("marisol", "the Blender movie https://www.youtube.com/watch?v=aqz-KE-bpKQ", minute: 0),
            F.line("theo", "nebula https://upload.wikimedia.org/wikipedia/commons/0/00/Crab_Nebula.jpg", minute: 1),
            F.line("ada", "issue https://github.com/r3volution11/Vela-IRC/issues/1", minute: 2),
            F.line("ada", "pr https://github.com/r3volution11/Vela-IRC/pull/2", minute: 3),
            F.line("kenji", "commit https://github.com/r3volution11/Vela-IRC/commit/3", minute: 4),
            F.line("lukas", "spec https://ircv3.net/irc/", minute: 5),
            F.line("wren", "again https://www.youtube.com/watch?v=aqz-KE-bpKQ", minute: 6),
            F.line("nadia", "no links here", minute: 7),
        ]
        var findings = RecapFindings(F.input([F.conversation("#vela", lines)]))
        #expect(findings.links.map(\.title) == ["Videos", "Images", "github.com", "Other pages"])
        #expect(findings.linkCount == 6)
        let video = findings.links[0].links[0]
        #expect(video.shares == 2)
        #expect(video.nick == "marisol")
        #expect(video.host == "youtube.com")
        #expect(video.reference.lineID == lines[0].id)
        #expect(findings.links[3].links.first?.displayTitle == "ircv3.net/irc")

        findings.applyTitles([URL(string: "https://ircv3.net/irc/")!: "IRCv3 Specifications"])
        #expect(findings.links[3].links.first?.displayTitle == "IRCv3 Specifications")
    }

    @Test func fewLinksFromOneSiteStayInPages() {
        let lines = [F.line("ada", "https://example.com/a"), F.line("ada", "https://example.org/b", minute: 1)]
        let findings = RecapFindings(F.input([F.conversation("#vela", lines)]))
        #expect(findings.links.map(\.title) == ["Pages"])
    }

    // MARK: People

    @Test func speakersMostFirstWithoutYou() {
        let lines = [
            F.line("ada", "a"), F.line("kenji", "b", minute: 1), F.line("kenji", "c", minute: 2),
            F.line("doug", "d", minute: 3, isSelf: true), F.line("wren", "e", minute: 4),
        ]
        let findings = RecapFindings(F.input([F.conversation("#vela", lines)]))
        #expect(findings.speakers.map(\.nick) == ["kenji", "ada", "wren"])
        #expect(findings.speakers.first?.messages == 2)
    }
}

@Suite("Recap Markdown")
struct RecapMarkdownTests {
    typealias F = RecapFixtures

    let format = RecapFormat(now: RecapFixtures.start, locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!)

    @Test func summaryHasEverySection() {
        let lines = [
            F.line("kenji", "the *new* theme engine landed", minute: 0),
            F.line("wren", "doug: can you review https://github.com/x/y/pull/1 ?", minute: 1),
            F.line("priya", "I'll do the contrast pass", minute: 2),
        ]
        let input = F.input([F.conversation("#vela", lines)])
        let findings = RecapFindings(input)
        let reference = RecapReference(conversation: F.id("#vela"), lineID: lines[0].id, time: lines[0].time)
        let summary = RecapSummary(
            overview: ["kenji landed the *theme* engine."],
            topics: [RecapTopic(id: "topic-0", title: "Theme engine", summary: "It landed.", participants: ["kenji"], start: reference, lineIDs: [lines[0].id])],
            notes: [
                RecapNote(id: "d", kind: .decision, text: "Palenight is the default.", reference: reference),
                RecapNote(id: "f", kind: .followUp, text: "Do the contrast pass.", owner: "priya", reference: nil),
            ],
            notesForYou: [lines[1].id: "wren asked you to review the PR."],
            isComplete: true
        )
        let markdown = RecapMarkdown.summary(
            header: RecapMarkdown.Header(title: "Recap of #vela", subtitle: "Libera.Chat · Last hour", notes: ["Vela has #vela back to 2:14 PM."]),
            findings: findings,
            summary: summary,
            details: ["topic-0": RecapDetail(points: ["kenji said it reads tokens."], isComplete: true)],
            format: format
        )
        #expect(markdown.hasPrefix("# Recap of #vela\n\nLibera.Chat · Last hour\n\n> Vela has #vela back to 2:14 PM.\n\n## Overview\n\n- kenji landed the \\*theme\\* engine.\n"))
        #expect(markdown.contains("## Topics\n\n### Theme engine\n\nIt landed.\n\n*kenji · "))
        #expect(markdown.contains("- kenji said it reads tokens."))
        #expect(markdown.contains("## For you\n\n- **wren** asked you to review the PR. ("))
        #expect(markdown.contains("No reply yet"))
        #expect(markdown.contains("## Decisions and follow-ups\n\n### Decided\n\n- Palenight is the default. ("))
        #expect(markdown.contains("### Follow-ups\n\n- **priya**: Do the contrast pass.\n"))
        #expect(markdown.contains("## Links shared\n\n### Pages\n\n- [github.com/x/y/pull/1](https://github.com/x/y/pull/1) — wren, "))
        #expect(markdown.contains("---\n\nSummarized on this Mac by Apple Intelligence. May contain mistakes."))
        #expect(!markdown.contains("Overview\n\n\n"))
    }

    @Test func logIsGroupedByConversationAndDay() {
        let input = F.input([
            F.conversation("#vela", [
                F.line("kenji", "hi", minute: -490),
                F.line("nadia", "reads the notes", minute: 5, kind: .action),
            ]),
            F.conversation("#swift", [F.line("mina", "# not a heading", minute: 1)]),
        ])
        let markdown = RecapMarkdown.log(header: RecapMarkdown.Header(title: "Recap of Libera.Chat", subtitle: ""), input: input, format: format)
            .replacingOccurrences(of: "\u{202F}", with: " ")
        #expect(markdown.contains("## #vela\n\n### Yesterday\n\n- 11:50 PM **kenji**: hi\n\n### Today\n\n- 8:05 AM \\* **nadia** reads the notes\n"))
        #expect(markdown.contains("## #swift\n\n### Today\n\n- 8:01 AM **mina**: # not a heading\n"))
    }

    @Test func escaping() {
        #expect(RecapMarkdown.escape("a_b*c [d](e) `f` <g>") == "a\\_b\\*c \\[d\\](e) \\`f\\` \\<g\\>")
        #expect(RecapMarkdown.escape("# heading") == "\\# heading")
        #expect(RecapMarkdown.escape("- item") == "\\- item")
        #expect(RecapMarkdown.escape("1. first") == "1\\. first")
        #expect(RecapMarkdown.escape("line\nbreak") == "line break")
    }

    @Test func durations() {
        #expect(RecapFormat.duration(10) == "A few seconds")
        #expect(RecapFormat.duration(30) == "Under a minute")
        #expect(RecapFormat.duration(70) == "About a minute")
        #expect(RecapFormat.duration(130) == "About 2 minutes")
        #expect(RecapScope.Span.last(minutes: 240).title == "Last 4 hours")
        #expect(RecapScope.Span.last(minutes: 60).title == "Last hour")
        #expect(RecapScope.Span.last(minutes: 10_080).title == "Last week")
        #expect(RecapScope.Span.last(3, .days) == .last(minutes: 4_320))
    }
}
