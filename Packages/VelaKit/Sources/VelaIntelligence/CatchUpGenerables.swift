// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import FoundationModels

// The shapes Foundation Models generates for Catch me up. Property order is
// generation order: the overview comes first so it can stream in while the
// topics are still being written.

@Generable(description: "One thread of conversation.")
nonisolated struct GeneratedTopic {
    @Guide(description: "A short title of two to six words.")
    var title: String
    @Guide(description: "One sentence on what was said or decided.")
    var summary: String
    @Guide(description: "Nicks of the people who took part, exactly as written in the transcript.", .maximumCount(6))
    var participants: [String]
    @Guide(description: "The number of the transcript line where this topic starts.")
    var firstLine: Int
}

@Generable(description: "A summary of one part of an IRC conversation.")
nonisolated struct ChunkDigest {
    @Guide(description: "At most two sentences on what happened in this part.")
    var overview: String
    @Guide(description: "The threads of conversation, in the order they came up.", .maximumCount(4))
    var topics: [GeneratedTopic]
    @Guide(description: "Notes like “wren asked you to review the PR”, each starting with the nick of someone who named the reader. Empty if nobody did.", .maximumCount(3))
    var addressedToYou: [String]
}

@Generable(description: "What the reader missed in an IRC conversation.")
nonisolated struct GeneratedCatchUp {
    @Guide(description: "At most two sentences on the whole conversation.")
    var overview: String
    @Guide(description: "The threads of conversation, in the order they came up.", .maximumCount(6))
    var topics: [GeneratedTopic]
    @Guide(description: "Notes like “wren asked you to review the PR”, each starting with the nick of someone who named the reader. Empty if nobody did.", .maximumCount(3))
    var addressedToYou: [String]
}

extension CatchUpDraft {
    nonisolated init(_ digest: ChunkDigest) {
        self.init(
            overview: digest.overview,
            topics: digest.topics.map(Topic.init),
            addressedToYou: digest.addressedToYou
        )
    }

    nonisolated init(_ result: GeneratedCatchUp) {
        self.init(
            overview: result.overview,
            topics: result.topics.map(Topic.init),
            addressedToYou: result.addressedToYou
        )
    }

    /// A summary still being generated: whatever has arrived so far.
    nonisolated init(_ partial: GeneratedCatchUp.PartiallyGenerated) {
        self.init(
            overview: partial.overview ?? "",
            topics: (partial.topics ?? []).compactMap(Topic.init),
            addressedToYou: partial.addressedToYou ?? []
        )
    }

    /// A digest as far as it got: all of it once generation finishes, or
    /// what was written before the response limit cut it off.
    nonisolated init(_ partial: ChunkDigest.PartiallyGenerated) {
        self.init(
            overview: partial.overview ?? "",
            topics: (partial.topics ?? []).compactMap(Topic.init),
            addressedToYou: partial.addressedToYou ?? []
        )
    }
}

extension CatchUpDraft.Topic {
    /// Nil until the topic has a title.
    nonisolated init?(_ topic: GeneratedTopic.PartiallyGenerated) {
        guard let title = topic.title else { return nil }
        self.init(
            title: title,
            summary: topic.summary ?? "",
            participants: topic.participants ?? [],
            firstLine: topic.firstLine
        )
    }
}

extension CatchUpDraft.Topic {
    nonisolated init(_ topic: GeneratedTopic) {
        self.init(title: topic.title, summary: topic.summary, participants: topic.participants, firstLine: topic.firstLine)
    }
}
