// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore

// Snippets appear in Siri and Shortcuts, outside Vela's window, so they use
// the system's colors rather than Vela's theme.

/// The channels and conversations that mention you.
struct MentionsSnippetView: View {
    let entries: [MentionSummary.Entry]

    /// Enough to scan at a glance; the dialog gives the total.
    private static let limit = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if entries.isEmpty {
                Label("No new mentions", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries.prefix(Self.limit)) { entry in
                    HStack(spacing: 10) {
                        Image(systemName: entry.isPrivate ? "person.crop.circle" : "number")
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.name)
                                .font(.headline)
                                .lineLimit(1)
                            Text(entry.networkName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Text("\(entry.mentions)")
                            .font(.callout.monospacedDigit().weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.tint.opacity(0.18), in: Capsule())
                            .accessibilityLabel(entry.isPrivate ? "\(entry.mentions) new messages" : "\(entry.mentions) mentions")
                    }
                    .accessibilityElement(children: .combine)
                }
                if entries.count > Self.limit {
                    Text("\(entries.count - Self.limit) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
