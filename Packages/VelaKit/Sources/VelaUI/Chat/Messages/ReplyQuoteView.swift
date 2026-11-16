// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaIRC
import VelaTheme

/// The compact quote above a reply. Clicking it scrolls to the parent.
struct ReplyQuoteView: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    @Environment(UIState.self) private var uiState
    @Environment(\.nickColorBuffer) private var nickColorBuffer
    let reply: ReplyTarget
    /// Draw a leading reply arrow (classic and columns layouts; the grouped
    /// layout draws a connector from the avatar instead).
    var showsArrow = true

    var body: some View {
        switch reply {
        case .resolved(let parent):
            Button {
                uiState.scrollTarget = parent.id
            } label: {
                quote {
                    Text(parent.nick ?? "")
                        .font(style.font(size: smallSize, weight: .semibold))
                        .foregroundStyle(theme.nickDisplayColor(parent.nick, isSelf: parent.isSelf, colorNicks: style.colorNicks, in: nickColorBuffer))
                        .lineLimit(1)
                        .layoutPriority(1)
                    Text(Self.snippet(for: parent))
                        .font(style.font(size: smallSize))
                        .italic(parent.isRedacted)
                        .foregroundStyle(theme[ThemeKey.replyForeground])
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .buttonStyle(.plain)
            .help("Jump to the original message")
            .accessibilityLabel("In reply to \(parent.nick ?? "someone"): \(Self.snippet(for: parent))")
            .accessibilityHint("Shows the original message")
        case .unresolved:
            quote {
                Text("Replying to an earlier message")
                    .font(style.font(size: smallSize))
                    .italic()
                    .foregroundStyle(theme[ThemeKey.replyForeground])
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var smallSize: Double { max(10, style.fontSize - 1.5) }

    private func quote<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 5) {
            if showsArrow {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.system(size: smallSize - 3, weight: .semibold))
                    .foregroundStyle(theme[ThemeKey.replyQuoteBar])
                    .scaleEffect(x: -1)
            }
            content()
        }
        .padding(.leading, 7)
        .padding(.trailing, 8)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(theme[ThemeKey.replyBackground])
        )
        .overlay(alignment: .leading) {
            if showsArrow {
                RoundedRectangle(cornerRadius: 1)
                    .fill(theme[ThemeKey.replyQuoteBar])
                    .frame(width: 2)
                    .padding(.vertical, 1)
            }
        }
        .contentShape(Rectangle())
    }

    static func snippet(for line: ChatLine) -> String {
        if line.isRedacted { return "Message deleted" }
        let text = IRCFormatting.strip(line.text)
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return line.kind == .action ? "* \(line.nick ?? "") \(firstLine)" : firstLine
    }
}

/// The curved line from a reply's avatar up to its quote (grouped layout).
nonisolated struct ReplyConnector: Shape {
    /// How far the line reaches past the trailing edge, into the gap before the quote.
    var overshoot: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius: CGFloat = 6
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY + 2))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.midY + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX + radius, y: rect.midY),
            control: CGPoint(x: rect.midX, y: rect.midY)
        )
        path.addLine(to: CGPoint(x: rect.maxX + overshoot, y: rect.midY))
        return path
    }
}
