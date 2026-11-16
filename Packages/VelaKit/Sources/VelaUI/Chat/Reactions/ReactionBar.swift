// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaTheme

/// Reaction chips under a message. Only this view reads the buffer's
/// reactions, so a new reaction re-renders chips, not whole rows.
struct ReactionBar: View {
    @Environment(MessageListController.self) private var controller
    let line: ChatLine
    let isRowHovered: Bool

    @State private var showPicker = false

    var body: some View {
        let reactions = controller.canReact ? controller.buffer.reactions(for: line.msgid) : []
        if !reactions.isEmpty {
            FlowLayout(spacing: 4, lineSpacing: 4) {
                ForEach(reactions) { reaction in
                    ReactionChip(reaction: reaction, selfNick: controller.session.nick) {
                        controller.toggleReaction(reaction.emoji, on: line)
                    }
                }
                if controller.canReact(to: line) {
                    AddReactionChip(isPresented: $showPicker) { emoji in
                        controller.addReaction(emoji, to: line)
                    }
                    .opacity(isRowHovered || showPicker ? 1 : 0)
                }
            }
            .padding(.top, 4)
        }
    }
}

private struct ReactionChip: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    let reaction: ReactionSummary
    let selfNick: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        let mine = reaction.includesSelf
        Button(action: action) {
            HStack(spacing: 4) {
                Text(reaction.emoji)
                    .font(.system(size: style.fontSize + 1))
                Text("\(reaction.nicks.count)")
                    .font(.system(size: max(10, style.fontSize - 2), weight: .semibold).monospacedDigit())
                    .foregroundStyle(theme[mine ? ThemeKey.accentText : ThemeKey.reactionForeground])
            }
            .padding(.horizontal, 7)
            .frame(minHeight: style.fontSize + 11)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme[mine ? ThemeKey.reactionSelfBackground : ThemeKey.reactionBackground])
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering ? theme[ThemeKey.chatHoverBackground] : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(theme[mine || hovering ? ThemeKey.reactionSelfBorder : ThemeKey.reactionBorder], lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tooltip)
        .accessibilityLabel("\(reaction.emoji) \(reaction.nicks.count)")
        .accessibilityValue(tooltip)
        .accessibilityAddTraits(mine ? .isSelected : [])
        .accessibilityHint(mine ? "Removes your reaction" : "Adds your reaction")
    }

    private var tooltip: String {
        let names = reaction.nicks.map { $0.caseInsensitiveCompare(selfNick) == .orderedSame ? "you" : $0 }
        let list: String
        switch names.count {
        case 0: list = ""
        case 1: list = names[0]
        default: list = names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        }
        return "\(list) reacted with \(reaction.emoji)"
    }
}

/// The "+" chip that opens the emoji picker.
struct AddReactionChip: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    @Binding var isPresented: Bool
    let onPick: (String) -> Void

    @State private var hovering = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "face.smiling")
                .font(.system(size: style.fontSize - 1, weight: .medium))
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "plus")
                        .font(.system(size: 7, weight: .heavy))
                        .offset(x: 4, y: -3)
                }
                .foregroundStyle(theme[hovering ? ThemeKey.chatForeground : ThemeKey.chatSecondaryForeground])
                .padding(.horizontal, 8)
                .frame(minHeight: style.fontSize + 11)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(theme[ThemeKey.reactionBackground])
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(theme[ThemeKey.reactionBorder], lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Add Reaction")
        .accessibilityLabel("Add Reaction")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            EmojiPickerView(onPick: onPick)
        }
    }
}

/// Left-to-right layout that wraps onto new lines.
nonisolated struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: widest, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
