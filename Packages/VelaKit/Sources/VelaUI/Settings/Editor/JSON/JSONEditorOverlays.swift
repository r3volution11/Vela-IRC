// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaStore
import VelaTheme

// Popups drawn over the JSON view's text in SwiftUI, placed from rects
// the session reports in each pane's (flipped) coordinates. They never
// take keyboard focus: the text view keeps it and drives the list.

/// The editor pane's completion list and hover card.
struct JSONEditorOverlay: View {
    let session: SettingsJSONSession

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Color.clear.allowsHitTesting(false)
                if let state = session.completion {
                    let layout = JSONCompletionPopup.layout(for: state, in: geometry.size)
                    JSONCompletionPopup(session: session, state: state, rowsHeight: layout.rowsHeight, showsFooter: layout.showsFooter)
                        .frame(width: layout.frame.width, height: layout.frame.height)
                        .offset(x: layout.frame.minX, y: layout.frame.minY)
                        .transition(.opacity)
                }
                if let hover = session.hover, hover.pane == .editor {
                    JSONHoverCard(session: session, hover: hover, paneSize: geometry.size)
                }
            }
        }
    }
}

/// The defaults pane's ✎ button and hover card.
struct JSONDefaultsOverlay: View {
    @Environment(\.theme) private var theme
    let session: SettingsJSONSession

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Color.clear.allowsHitTesting(false)
                if let keyHover = session.defaultsKeyHover {
                    JSONCopyDefaultButton(key: keyHover.key) { session.copyDefault(key: keyHover.key) }
                        .offset(x: keyHover.textStart + 4, y: keyHover.lineRect.minY + 1)
                }
                if let hover = session.hover, hover.pane == .defaults {
                    JSONHoverCard(session: session, hover: hover, paneSize: geometry.size)
                }
            }
        }
    }
}

private struct JSONCopyDefaultButton: View {
    @Environment(\.theme) private var theme
    let key: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "pencil")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isHovered ? theme[ThemeKey.accentForeground] : theme[ThemeKey.accentText])
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isHovered ? theme[ThemeKey.accent] : theme[ThemeKey.settingsControlBackground])
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(isHovered ? .clear : theme[ThemeKey.settingsBorder])
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Copy “\(key)” to settings.json")
        .accessibilityLabel("Copy \(key) to settings.json")
    }
}

// MARK: - Completion list

struct JSONCompletionPopup: View {
    @Environment(\.theme) private var theme
    let session: SettingsJSONSession
    let state: JSONCompletionState
    let rowsHeight: CGFloat
    let showsFooter: Bool

    static let rowHeight: CGFloat = 24
    static let maxRows = 8
    static let footerHeight: CGFloat = 58
    static let preferredWidth: CGFloat = 460

    struct Layout {
        var frame: CGRect
        var rowsHeight: CGFloat
        var showsFooter: Bool
    }

    /// Below the text being completed, or above it when there's more room there.
    static func layout(for state: JSONCompletionState, in size: CGSize) -> Layout {
        let rows = min(state.items.count, maxRows)
        let rowsHeight = CGFloat(rows) * rowHeight + 8
        let showsFooter = state.items.contains { footerText(for: $0) != nil }
        let height = rowsHeight + (showsFooter ? footerHeight + 1 : 0)
        let width = min(preferredWidth, max(220, size.width - 16))
        let x = min(max(8, state.anchor.minX - 28), max(8, size.width - width - 8))
        let below = state.anchor.maxY + 3
        let above = state.anchor.minY - 3 - height
        let y = below + height <= size.height - 4 || above < 4 ? below : above
        return Layout(frame: CGRect(x: x, y: y, width: width, height: height), rowsHeight: rowsHeight, showsFooter: showsFooter)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(state.items.enumerated()), id: \.element.id) { index, item in
                            JSONCompletionRow(item: item, isSelected: index == state.selectedIndex)
                                .id(item.id)
                                .onTapGesture { session.acceptCompletion(at: index) }
                        }
                    }
                    .padding(4)
                }
                .scrollIndicators(.automatic)
                .frame(height: rowsHeight)
                .onChange(of: state.selectedIndex, initial: true) {
                    if let item = state.selectedItem { proxy.scrollTo(item.id) }
                }
            }
            if showsFooter {
                Rectangle().fill(theme[ThemeKey.popoverBorder]).frame(height: 1)
                footer
                    .frame(height: Self.footerHeight, alignment: .topLeading)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme[ThemeKey.popoverBackground])
                .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme[ThemeKey.popoverBorder])
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggestions")
    }

    private var footer: some View {
        let item = state.selectedItem
        return VStack(alignment: .leading, spacing: 3) {
            if let item, let text = Self.footerText(for: item) {
                if let title = text.title {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(theme[ThemeKey.popoverForeground])
                            .lineLimit(1)
                        if let badge = text.badge {
                            SettingsPill(text: badge, tinted: true)
                        }
                    }
                }
                if let body = text.body {
                    Text(body)
                        .font(.system(size: 11))
                        .foregroundStyle(theme[ThemeKey.popoverForeground].opacity(0.75))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    struct FooterText {
        var title: String?
        var body: String?
        var badge: String?
    }

    static func footerText(for item: SettingsCompletionItem) -> FooterText? {
        switch item.kind {
        case .setting:
            let descriptor = item.descriptor
            let defaultText = descriptor.map { "Default: " + JSONHoverDocs.display($0.defaultValue) }
            let body = [descriptor?.summary, defaultText].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            return FooterText(title: item.title ?? item.label, body: body.isEmpty ? nil : body, badge: item.isSet ? "In settings.json" : nil)
        case .key, .value:
            guard item.detail != nil || item.title != nil else { return nil }
            return FooterText(title: item.title ?? item.label, body: item.detail, badge: item.isDefault ? "Default" : nil)
        }
    }
}

private struct JSONCompletionRow: View {
    @Environment(\.theme) private var theme
    let item: SettingsCompletionItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(isSelected ? theme[ThemeKey.accentForeground] : theme[ThemeKey.accentText])
                .frame(width: 16)
            Text(primary)
                .font(.system(size: 12).monospaced())
                .foregroundStyle(isSelected ? theme[ThemeKey.accentForeground] : theme[ThemeKey.popoverForeground])
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
            Spacer(minLength: 6)
            if item.isSet {
                Image(systemName: "circle.fill")
                    .font(.system(size: 5))
                    .foregroundStyle(isSelected ? theme[ThemeKey.accentForeground] : theme[ThemeKey.accent])
                    .help("Already in settings.json")
            }
            if let secondary {
                Text(secondary)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? theme[ThemeKey.accentForeground].opacity(0.85) : theme[ThemeKey.popoverForeground].opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: JSONCompletionPopup.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isSelected ? theme[ThemeKey.accent] : .clear)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Keys show the key; values their friendly name when there is one.
    private var primary: String {
        switch item.kind {
        case .setting, .key: item.label
        case .value: item.title ?? item.label
        }
    }

    private var secondary: String? {
        switch item.kind {
        case .setting: item.title
        case .key: item.detail
        case .value:
            if item.title != nil { item.isDefault ? "Default" : item.detail }
            else { item.isDefault ? "Default" : item.detail }
        }
    }

    private var symbol: String {
        switch item.kind {
        case .setting: return "gearshape"
        case .key: return "key"
        case .value:
            let label = item.label
            if label.hasPrefix("\"") { return "textformat" }
            if label == "true" || label == "false" { return "switch.2" }
            if label.hasPrefix("{") { return "curlybraces" }
            if label.hasPrefix("[") { return "list.bullet" }
            if label == "null" { return "circle.slash" }
            return "number"
        }
    }
}

// MARK: - Hover card

/// Docs for a key (title, summary, default, type or values, Modified) and
/// the problems under the pointer, with a "Change to …" fix for unknown keys.
struct JSONHoverCard: View {
    @Environment(\.theme) private var theme
    let session: SettingsJSONSession
    let hover: JSONHoverState
    let paneSize: CGSize

    @State private var size: CGSize = .zero

    var body: some View {
        let width = min(400, max(200, paneSize.width - 16))
        let x = min(max(8, hover.anchor.minX - 6), max(8, paneSize.width - width - 8))
        let below = hover.anchor.maxY + 4
        let above = hover.anchor.minY - 4 - size.height
        let y = below + size.height <= paneSize.height - 4 || above < 4 ? below : above
        content
            .frame(maxWidth: width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { newSize in
                size = newSize
                session.hoverCardFrame = CGRect(x: x, y: y, width: newSize.width, height: newSize.height)
            }
            .onChange(of: hover.anchor) {
                session.hoverCardFrame = CGRect(x: x, y: y, width: size.width, height: size.height)
            }
            .offset(x: x, y: y)
            .transition(.opacity)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(hover.problems.enumerated()), id: \.offset) { _, problem in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    JSONSeverityIcon(severity: problem.severity)
                    Text(problem.message)
                        .font(.system(size: 12))
                        .foregroundStyle(theme[ThemeKey.popoverForeground])
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let fix = hover.quickFix {
                SettingsLinkButton("Change to “\(fix.key)”", systemImage: "wand.and.stars") {
                    session.applyQuickFix(fix)
                }
            }
            if !hover.problems.isEmpty, hover.docs != nil {
                Rectangle().fill(theme[ThemeKey.popoverBorder]).frame(height: 1)
            }
            if let docs = hover.docs {
                docsView(docs)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme[ThemeKey.popoverBackground])
                .shadow(color: .black.opacity(0.2), radius: 10, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme[ThemeKey.popoverBorder])
        )
        .accessibilityElement(children: .combine)
    }

    private func docsView(_ docs: JSONHoverDocs) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(docs.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme[ThemeKey.popoverForeground])
                if docs.isModified {
                    SettingsPill(text: "Modified", tinted: true)
                }
                Spacer(minLength: 0)
            }
            if docs.title != docs.key {
                Text(docs.key)
                    .font(.system(size: 11).monospaced())
                    .foregroundStyle(theme[ThemeKey.popoverForeground].opacity(0.6))
            }
            if let summary = docs.summary {
                Text(summary)
                    .font(.system(size: 12))
                    .foregroundStyle(theme[ThemeKey.popoverForeground].opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(docs.facts, id: \.label) { fact in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(fact.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme[ThemeKey.popoverForeground].opacity(0.6))
                        .frame(width: 50, alignment: .leading)
                    Text(fact.value)
                        .font(.system(size: 11).monospaced())
                        .foregroundStyle(theme[ThemeKey.popoverForeground])
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
    }
}
