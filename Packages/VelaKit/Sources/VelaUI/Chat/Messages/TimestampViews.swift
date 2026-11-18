// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaStore
import VelaTheme

// The pieces message and event rows draw their times with when
// `chat.timestampPosition.*` moves them off the usual spot. VoiceOver reads
// each row's time from the row's own label, so these are hidden from it.

extension TimestampMetrics {
    /// Between the text and the right-edge time column.
    static let trailingGap: CGFloat = 12

    /// The right-edge time column (Right): wide enough for the widest time
    /// in `style.timestampFont`, so times line up whatever the format.
    static func trailingColumnWidth(style: ChatStyle) -> CGFloat {
        columnWidth(style: style, bracketed: false)
    }

    /// How far the hover toolbar moves left so it doesn't cover the
    /// right-edge times (rows have `rowHorizontalPadding` on the right; the
    /// toolbar normally sits 14 pt in).
    static func toolbarInset(style: ChatStyle) -> CGFloat {
        trailingColumnWidth(style: style) + style.rowHorizontalPadding - 14 + 4
    }
}

/// A row's time on its own small line, above or below the text (Top and
/// Bottom). It sits a point closer to its text than the stacks' usual
/// spacing, and rows with one get a little more room on that side (see
/// `MessageRow`), so it reads as belonging to its own message rather than
/// the neighbor's.
struct TimestampLine: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    let time: Date
    let edge: VerticalEdge

    var body: some View {
        Text(style.timestamp(time))
            .font(style.gutterTimestampFont)
            .foregroundStyle(theme[ThemeKey.chatTimestamp])
            .lineLimit(1)
            .fixedSize()
            .padding(edge == .top ? .bottom : .top, -1)
            .accessibilityHidden(true)
    }

    /// Extra room a row gives a time line, on the line's side.
    static let rowInset: CGFloat = 3
}

/// An event's time right after its text.
struct InlineTimestamp: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    let time: Date

    var body: some View {
        Text(style.timestamp(time))
            .font(style.gutterTimestampFont)
            .foregroundStyle(theme[ThemeKey.chatTimestamp])
            .fixedSize()
    }
}

/// Content with its time in a fixed-width column at the right edge, level
/// with the content's first line of text (Right).
private struct TrailingTimestampModifier: ViewModifier {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    let time: Date
    let isVisible: Bool

    func body(content: Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: TimestampMetrics.trailingGap) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(style.timestamp(time))
                .font(style.timestampFont)
                .foregroundStyle(theme[ThemeKey.chatTimestamp])
                .lineLimit(1)
                .frame(width: TimestampMetrics.trailingColumnWidth(style: style), alignment: .trailing)
                .opacity(isVisible ? 1 : 0)
                .accessibilityHidden(true)
        }
    }
}

extension View {
    /// Adds the right-edge time column when `placement` puts the time
    /// there; otherwise returns the view as it is.
    @ViewBuilder
    func trailingTimestamp(_ time: Date, _ placement: TimestampPlacement) -> some View {
        if placement.slot == .trailingColumn {
            modifier(TrailingTimestampModifier(time: time, isVisible: placement.isVisible))
        } else {
            self
        }
    }
}
