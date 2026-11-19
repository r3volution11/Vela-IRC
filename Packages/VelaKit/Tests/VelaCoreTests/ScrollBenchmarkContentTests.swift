// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaCore

@Suite("Scroll benchmark channel")
struct ScrollBenchmarkContentTests {
    private func generate(_ mix: ScrollBenchmarkContent.Mix) -> (lines: [ChatLine], reactions: [ScrollBenchmarkContent.Reaction]) {
        var generator = ScrollBenchmarkContent.Generator(mix: mix, selfNick: "doug")
        return generator.lines(count: ScrollBenchmarkContent.defaultLineCount)
    }

    @Test func isTheSameEveryRun() {
        let first = generate(.full)
        let second = generate(.full)
        #expect(first.lines.map(\.text) == second.lines.map(\.text))
        #expect(first.lines.map(\.time) == second.lines.map(\.time))
        #expect(first.lines.map(\.nick) == second.lines.map(\.nick))
        #expect(first.reactions.map(\.msgid) == second.reactions.map(\.msgid))
    }

    @Test func hasEveryKindOfLine() {
        let lines = generate(.full).lines
        #expect(lines.count == ScrollBenchmarkContent.defaultLineCount)
        let texts = lines.map(\.text)
        for host in [
            "https://photos.example.org/p/", "https://media.example.org/gifs/", "https://media.giphy.com/media/",
            "https://www.youtube.com/watch?v=", "/articles/",
        ] {
            #expect(texts.contains { $0.contains(host) }, "no \(host) links")
        }
        #expect(lines.contains { $0.kind == .action })
        #expect(lines.contains { $0.replyTo != nil })
        #expect(lines.contains { $0.isHighlight })
        #expect(lines.contains { $0.isSelf })
        #expect(lines.contains { $0.kind == .join } && lines.contains { $0.kind == .part })
        #expect(lines.filter { $0.text.hasSuffix("(*.net *.split)") }.count == ScrollBenchmarkContent.Generator.nicks.count)
        #expect(texts.filter { $0.count > 300 }.count > 50, "long wrapped messages")
        #expect(Set(lines.map { Calendar.current.startOfDay(for: $0.time) }).count == 5, "five days, so four day dividers")
        #expect(lines.map(\.time) == lines.map(\.time).sorted())
        #expect(!generate(.full).reactions.isEmpty)
    }

    @Test func textMixHasNoLinks() {
        let lines = generate(.text).lines
        #expect(lines.count == ScrollBenchmarkContent.defaultLineCount)
        #expect(!lines.contains { $0.text.contains("https://") })
    }
}
