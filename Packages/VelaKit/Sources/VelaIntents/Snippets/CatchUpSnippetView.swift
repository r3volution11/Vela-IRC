// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaIntelligence

/// A Catch me up summary: which channel, then the topics. Siri speaks the
/// overview, so the snippet doesn't repeat it.
struct CatchUpSnippetView: View {
    struct Header {
        var channel: String
        var network: String
    }

    enum Content {
        case caughtUp
        case nothingNew(Header)
        case summary(Header, CatchUpSummary)
    }

    let content: Content

    /// Topics shown before "N more".
    private static let topicLimit = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch content {
            case .caughtUp:
                Label("No unread messages", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            case .nothingNew(let header):
                headerView(header, count: nil)
                Text("Nothing new since you last read it.")
                    .foregroundStyle(.secondary)
            case .summary(let header, let summary):
                headerView(header, count: summary.messageCount)
                topics(summary)
                if !summary.addressedToYou.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("For you", systemImage: "at")
                            .font(.subheadline.weight(.semibold))
                        ForEach(summary.addressedToYou, id: \.self) { note in
                            Text(note)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Text("Summarized on this Mac by Apple Intelligence. May contain mistakes.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func headerView(_ header: Header, count: Int?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label(header.channel, systemImage: "sparkles")
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(count.map { "\(header.network) · \($0) \($0 == 1 ? "message" : "messages")" } ?? header.network)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func topics(_ summary: CatchUpSummary) -> some View {
        ForEach(summary.topics.prefix(Self.topicLimit)) { topic in
            VStack(alignment: .leading, spacing: 2) {
                Text(topic.title)
                    .font(.subheadline.weight(.semibold))
                Text(topic.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !topic.participants.isEmpty {
                    Text(IntentText.list(topic.participants))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        if summary.topics.count > Self.topicLimit {
            Text("\(summary.topics.count - Self.topicLimit) more topics in Vela")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
