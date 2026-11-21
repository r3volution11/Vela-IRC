// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaTheme

// The emoji grid shared by the reaction picker and the message box's
// emoji and GIF picker: recents, categories and search from `EmojiCatalog`,
// moved through with the arrow keys.

/// An emoji in one of the grid's sections. The same emoji can be in
/// "Frequently Used" and in its category.
struct EmojiGridItem: Hashable, Identifiable {
    let section: String
    let emoji: String
    var id: Self { self }
}

/// A titled run of emoji in the grid.
struct EmojiGridSection: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let items: [EmojiGridItem]
}

/// A direction to move a grid's selection in.
enum GridMove {
    case left, right, up, down

    init?(_ key: PaletteKey) {
        switch key {
        case .left: self = .left
        case .right: self = .right
        case .up: self = .up
        case .down: self = .down
        default: return nil
        }
    }
}

/// What the grid shows for a search (recents and every category when it's
/// empty), and how the arrow keys move through it: ← → in reading order,
/// ↑ ↓ by rows, each section starting a new row.
struct EmojiGridContent {
    let query: String
    let sections: [EmojiGridSection]
    let columns: Int

    init(query: String, frequent: [String], columns: Int) {
        self.query = query
        self.columns = max(1, columns)
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            var sections = [Self.section("frequent", "Frequently Used", "clock", frequent)]
            sections += EmojiCatalog.categories.map { Self.section($0.id, $0.title, $0.systemImage, $0.emoji) }
            self.sections = sections
        } else {
            let results = EmojiCatalog.search(trimmed)
            self.sections = results.isEmpty ? [] : [Self.section("results", "Results", "magnifyingglass", results)]
        }
    }

    private static func section(_ id: String, _ title: String, _ systemImage: String, _ emoji: [String]) -> EmojiGridSection {
        EmojiGridSection(id: id, title: title, systemImage: systemImage, items: emoji.map { EmojiGridItem(section: id, emoji: $0) })
    }

    var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    var isEmpty: Bool { sections.allSatisfy(\.items.isEmpty) }
    var first: EmojiGridItem? { sections.lazy.compactMap(\.items.first).first }

    /// Where `item` is: its section and index in it.
    private func position(of item: EmojiGridItem) -> (section: Int, index: Int)? {
        guard let section = sections.firstIndex(where: { $0.id == item.section }),
              let index = sections[section].items.firstIndex(of: item)
        else { return nil }
        return (section, index)
    }

    /// The item a key moves the selection to. With nothing selected, any
    /// key selects the first emoji.
    func moved(from item: EmojiGridItem?, _ move: GridMove) -> EmojiGridItem? {
        guard let item, let (sectionIndex, index) = position(of: item) else { return first }
        let items = sections[sectionIndex].items
        switch move {
        case .left:
            if index > 0 { return items[index - 1] }
            return sections[..<sectionIndex].last(where: { !$0.items.isEmpty })?.items.last ?? item
        case .right:
            if index + 1 < items.count { return items[index + 1] }
            return sections[(sectionIndex + 1)...].first(where: { !$0.items.isEmpty })?.items.first ?? item
        case .up:
            if index >= columns { return items[index - columns] }
            guard let previous = sections[..<sectionIndex].last(where: { !$0.items.isEmpty }) else { return item }
            // The same column in the previous section's last row.
            let lastRowStart = (previous.items.count - 1) / columns * columns
            return previous.items[min(previous.items.count - 1, lastRowStart + index % columns)]
        case .down:
            if index + columns < items.count { return items[index + columns] }
            // In the last row already, or a shorter last row below.
            let row = index / columns, lastRow = (items.count - 1) / columns
            if row < lastRow { return items[items.count - 1] }
            guard let next = sections[(sectionIndex + 1)...].first(where: { !$0.items.isEmpty }) else { return item }
            return next.items[min(next.items.count - 1, index % columns)]
        }
    }
}

/// The grid: a category bar (when not searching) over scrolling sections.
/// Hovering or selecting an emoji highlights it; clicking picks it.
struct EmojiGridView: View {
    @Environment(\.theme) private var theme
    let content: EmojiGridContent
    @Binding var selection: EmojiGridItem?
    @Binding var hovered: EmojiGridItem?
    var cellSize: CGFloat = 34
    var height: CGFloat = 260
    let onPick: (String) -> Void

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(cellSize), spacing: 2), count: content.columns)
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                if !content.isSearching {
                    categoryBar(proxy)
                }
                Rectangle().fill(theme[ThemeKey.popoverBorder]).frame(height: 1)
                ScrollView {
                    LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
                        if content.isEmpty {
                            Section {
                                EmptyView()
                            } header: {
                                Text("No emoji match “\(content.query)”")
                                    .font(.system(size: 12))
                                    .foregroundStyle(theme[ThemeKey.chatSecondaryForeground])
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 18)
                            }
                        } else {
                            ForEach(content.sections) { section in
                                sectionView(section)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
                .frame(height: height)
            }
            .onChange(of: selection) { _, item in
                guard let item else { return }
                proxy.scrollTo(item, anchor: nil)
            }
        }
    }

    private func categoryBar(_ proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 0) {
            ForEach(content.sections) { section in
                Button {
                    proxy.scrollTo(section.id, anchor: .top)
                } label: {
                    Image(systemName: section.systemImage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme[ThemeKey.chatSecondaryForeground])
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(section.title)
                .accessibilityLabel(section.title)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    private func sectionView(_ section: EmojiGridSection) -> some View {
        Section {
            ForEach(section.items) { item in
                EmojiCell(emoji: item.emoji, size: cellSize, isHighlighted: hovered == item || selection == item, isSelected: selection == item) {
                    onPick(item.emoji)
                }
                .id(item)
                .onHover { inside in
                    if inside { hovered = item } else if hovered == item { hovered = nil }
                }
            }
        } header: {
            Text(section.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme[ThemeKey.chatSecondaryForeground])
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .background(theme[ThemeKey.popoverBackground])
                .id(section.id)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

private struct EmojiCell: View {
    @Environment(\.theme) private var theme
    let emoji: String
    let size: CGFloat
    let isHighlighted: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(emoji)
                .font(.system(size: (size * 0.65).rounded()))
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isHighlighted ? theme[ThemeKey.chatSelectionBackground] : .clear)
                )
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(theme[ThemeKey.focusBorder], lineWidth: 1.5)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(EmojiCatalog.entries[emoji]?.name ?? emoji)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Under the grid: the hovered or selected emoji and its name (or a
/// prompt), and a button for the system's Character Viewer.
struct EmojiFooter: View {
    @Environment(\.theme) private var theme
    let emoji: String?
    let prompt: String
    let onCharacterViewer: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let emoji {
                Text(emoji).font(.system(size: 20))
                Text(EmojiCatalog.entries[emoji]?.name ?? "")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme[ThemeKey.popoverForeground])
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text(prompt)
                    .font(.system(size: 12))
                    .foregroundStyle(theme[ThemeKey.chatSecondaryForeground])
            }
            Spacer(minLength: 8)
            Button(action: onCharacterViewer) {
                Image(systemName: "keyboard")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme[ThemeKey.chatSecondaryForeground])
                    .frame(width: 26, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open the Character Viewer")
            .accessibilityLabel("Open the Character Viewer")
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
    }
}

/// The pickers' search field: a magnifying glass, the field (which takes
/// the focus when it appears and reports navigation keys), and a clear
/// button.
struct PickerSearchBox: View {
    @Environment(\.theme) private var theme
    @Binding var text: String
    let placeholder: String
    var accessibilityLabel: String?
    var onTextChange: (String) -> Void = { _ in }
    let onKey: (PaletteKey) -> Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme[ThemeKey.inputPlaceholder])
                .accessibilityHidden(true)
            PaletteSearchField(
                text: $text,
                placeholder: placeholder,
                accessibilityLabel: accessibilityLabel ?? placeholder,
                font: .systemFont(ofSize: 13),
                textColor: theme.color(ThemeKey.inputForeground).nsColor,
                placeholderColor: theme.color(ThemeKey.inputPlaceholder).nsColor,
                caretColor: theme.color(ThemeKey.inputForeground).nsColor,
                selectionColor: theme.color(ThemeKey.chatSelectionBackground).nsColor,
                onTextChange: onTextChange,
                onKey: onKey
            )
            .frame(height: 18)
            if !text.isEmpty {
                Button {
                    text = ""
                    onTextChange("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(theme[ThemeKey.inputPlaceholder])
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(theme[ThemeKey.inputBackground])
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(theme[ThemeKey.inputFocusBorder], lineWidth: 1)
        )
    }
}

extension EmojiCatalog {
    /// The single emoji the Character Viewer put in a search field, if
    /// that's all the field holds.
    static func characterViewerPick(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count == 1, let character = trimmed.first, EmojiDetection.isEmoji(character) else { return nil }
        return trimmed
    }
}
