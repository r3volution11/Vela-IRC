// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaTheme

/// A Tagify-style input: values as chips with ×, a text field after them,
/// and suggestions that filter as you type.
///
/// - Pick a suggestion with the arrows and Return or Tab, or click it.
/// - Return (or a comma, with several values) adds the text as typed;
///   `resolve` can refuse it or turn it into the value to store.
/// - ⌫ in the empty field removes the last chip. Duplicates are refused.
/// - A single-value field holds one chip; picking or typing replaces it.
///
/// It keeps no copy of the values: it shows `values` and reports every
/// change through `onChange`. The logic lives in ``TokenFieldModel``.
struct TokenField: View {
    @Environment(\.theme) private var theme

    let values: [String]
    var allowsMultiple = true
    /// Everything to offer; the field filters it.
    var suggestions: [TokenSuggestion] = []
    var placeholder = "Add…"
    /// What the field holds, for VoiceOver ("Chat: Font Family").
    var accessibilityLabel: String
    /// The chip text for a value (defaults to the value).
    var label: (String) -> String = { $0 }
    /// Secondary chip text, e.g. a timestamp pattern's preview.
    var detail: (String) -> String? = { _ in nil }
    /// Turns typed text into a value, or refuses it with nil.
    var resolve: (String) -> String? = { $0 }
    var rejectionMessage = "That isn't a value this setting accepts."
    var monospaced = false
    /// Open the suggestions as soon as the field has focus.
    var showsSuggestionsOnFocus = true
    let onChange: ([String]) -> Void

    @State private var text = ""
    @State private var isFocused = false
    @State private var focusRequest = 0
    @State private var anchor = SuggestionAnchor()
    @State private var problem: String?

    var body: some View {
        let filtered = TokenFieldModel.filter(suggestions, query: text, excluding: allowsMultiple ? values : [])
        VStack(alignment: .leading, spacing: 4) {
            // A single value's chip steps aside while typing a replacement,
            // so the text gets the whole field.
            let chips = allowsMultiple || text.isEmpty ? values : []
            TokenFlowLayout(spacing: 4, lineSpacing: 4, minimumLastWidth: allowsMultiple ? 90 : 24) {
                ForEach(chips, id: \.self) { value in
                    TokenChip(
                        label: label(value),
                        detail: detail(value),
                        rawValue: value,
                        monospaced: monospaced,
                        remove: { remove(value) }
                    )
                }
                SuggestionTextField(
                    text: typedText,
                    placeholder: values.isEmpty ? placeholder : (allowsMultiple ? "Add…" : ""),
                    accessibilityLabel: allowsMultiple ? "Add to \(accessibilityLabel)" : accessibilityLabel,
                    suggestions: filtered,
                    autoHighlight: TokenFieldModel.autoHighlight(query: text, in: filtered),
                    showsOnFocus: showsSuggestionsOnFocus,
                    anchor: anchor,
                    monospaced: monospaced,
                    fontSize: 12.5,
                    focusRequest: focusRequest,
                    onPick: pick,
                    onSubmit: commitText,
                    onDeleteBackwardWhenEmpty: removeLast,
                    onCancel: {
                        guard !text.isEmpty else { return false }
                        text = ""
                        problem = nil
                        return true
                    },
                    onFocusChange: { focused in
                        isFocused = focused
                        if !focused, !text.allSatisfy(\.isWhitespace) { commitText() }
                    }
                )
                .frame(height: 20)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
            .frame(minHeight: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(theme[ThemeKey.settingsBackground])
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        problem != nil ? theme[ThemeKey.statusError] : (isFocused ? theme[ThemeKey.focusBorder] : theme[ThemeKey.settingsBorder]),
                        lineWidth: isFocused ? 1.5 : 1
                    )
            )
            .contentShape(Rectangle())
            .onTapGesture { focusRequest &+= 1 }
            .suggestionAnchor(anchor)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(values.isEmpty ? "Empty" : values.map(label).joined(separator: ", "))

            if let problem {
                Text(problem)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme[ThemeKey.statusError])
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .onChange(of: values) { problem = nil }
    }

    /// The typed text; with several values, commas commit what's before them.
    private var typedText: Binding<String> {
        Binding(
            get: { text },
            set: { newValue in
                problem = nil
                guard allowsMultiple, newValue.contains(",") else {
                    text = newValue
                    return
                }
                let (pieces, remainder) = TokenFieldModel.split(newValue)
                var model = TokenFieldModel(values: values, allowsMultiple: true)
                var rejected: [String] = []
                for piece in pieces where model.commit(piece, suggestions: suggestions, resolve: resolve) == .rejected {
                    rejected.append(piece)
                }
                if model.values != values { onChange(model.values) }
                if !rejected.isEmpty { problem = rejectionMessage }
                text = rejected.isEmpty ? remainder : rejected.joined(separator: ", ") + (remainder.isEmpty ? "" : ", " + remainder)
            }
        )
    }

    private func commitText() {
        var model = TokenFieldModel(values: values, allowsMultiple: allowsMultiple)
        switch model.commit(text, suggestions: suggestions, resolve: resolve) {
        case .added, .replaced:
            onChange(model.values)
            text = ""
            problem = nil
        case .duplicate:
            text = ""
            problem = nil
        case .rejected:
            problem = rejectionMessage
        case .empty:
            text = ""
        }
    }

    private func pick(_ suggestion: TokenSuggestion) {
        var model = TokenFieldModel(values: values, allowsMultiple: allowsMultiple)
        model.add(suggestion.value)
        if model.values != values { onChange(model.values) }
        text = ""
        problem = nil
    }

    private func remove(_ value: String) {
        var model = TokenFieldModel(values: values, allowsMultiple: allowsMultiple)
        model.remove(value)
        onChange(model.values)
        focusRequest &+= 1
    }

    private func removeLast() {
        var model = TokenFieldModel(values: values, allowsMultiple: allowsMultiple)
        guard model.removeLast() != nil else { return }
        onChange(model.values)
    }
}

/// One value in a ``TokenField``.
private struct TokenChip: View {
    @Environment(\.theme) private var theme
    let label: String
    let detail: String?
    let rawValue: String
    let monospaced: Bool
    let remove: () -> Void

    @State private var isHoveringRemove = false

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(monospaced ? .system(size: 11.5, design: .monospaced) : .system(size: 12))
                .foregroundStyle(theme[ThemeKey.accentText])
                .lineLimit(1)
                .truncationMode(.middle)
            if let detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    .lineLimit(1)
            }
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(isHoveringRemove ? theme[ThemeKey.settingsForeground] : theme[ThemeKey.accentText].opacity(0.75))
                    .frame(width: 14, height: 14)
                    .background(Circle().fill(isHoveringRemove ? theme[ThemeKey.accent].opacity(0.25) : .clear))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { isHoveringRemove = $0 }
            .help("Remove \(label)")
            .accessibilityHidden(true)
        }
        .padding(.leading, 7)
        .padding(.trailing, 3)
        .frame(height: 20)
        .frame(maxWidth: 280, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(theme[ThemeKey.accent].opacity(0.16))
        )
        .fixedSize(horizontal: true, vertical: false)
        .help(rawValue == label ? label : "\(label)\n\(rawValue)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([label, detail].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Remove", remove)
    }
}

/// Wraps chips onto lines and gives the last subview (the text field) the
/// rest of its line, or a line of its own when less than
/// `minimumLastWidth` is left. Items on a line are centered vertically.
nonisolated struct TokenFlowLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 4
    var minimumLastWidth: CGFloat = 90

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(width: bounds.width, subviews: subviews).frames
        for (subview, frame) in zip(subviews, frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(width: CGFloat?, subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        let maxWidth = width ?? .infinity
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, lineStart = 0, widest: CGFloat = 0

        func finishLine(upTo end: Int) {
            for index in lineStart..<end {
                frames[index].origin.y = y + (lineHeight - frames[index].height) / 2
            }
        }

        for (index, subview) in subviews.enumerated() {
            let isLast = index == subviews.count - 1
            var size = subview.sizeThatFits(.unspecified)
            let needsBreak = isLast
                ? x > 0 && maxWidth - x < minimumLastWidth
                : x > 0 && x + min(size.width, maxWidth) > maxWidth
            if needsBreak {
                finishLine(upTo: index)
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
                lineStart = index
            }
            if isLast {
                size.width = maxWidth.isFinite ? maxWidth - x : max(size.width, minimumLastWidth)
            } else {
                size.width = min(size.width, maxWidth)
            }
            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        finishLine(upTo: frames.count)
        let totalWidth = maxWidth.isFinite ? maxWidth : widest
        return (frames, CGSize(width: totalWidth, height: y + lineHeight))
    }
}
