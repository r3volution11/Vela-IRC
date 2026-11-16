// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaTheme

/// Reaction picker: search, frequently used, categories, and a shortcut to
/// the system Character Viewer (whose pick lands in the search field and is
/// used directly).
struct EmojiPickerView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let onPick: (String) -> Void

    @State private var query = ""
    @State private var hovered: SectionEmoji?
    @State private var frequent = EmojiRecents.frequent()
    @FocusState private var searchFocused: Bool

    private static let cell: CGFloat = 34
    private static let columns = Array(repeating: GridItem(.fixed(cell), spacing: 2), count: 9)
    private static let width: CGFloat = 9 * cell + 8 * 2 + 24

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .padding([.horizontal, .top], 12)
                .padding(.bottom, 8)
            ScrollViewReader { proxy in
              VStack(spacing: 0) {
                if query.isEmpty {
                    categoryBar(proxy)
                }
                Rectangle().fill(theme[ThemeKey.popoverBorder]).frame(height: 1)
                ScrollView {
                    LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
                        if query.isEmpty {
                            section(id: "frequent", title: "Frequently Used", emoji: frequent)
                            ForEach(EmojiCatalog.categories) { category in
                                section(id: category.id, title: category.title, emoji: category.emoji)
                            }
                        } else {
                            let results = EmojiCatalog.search(query)
                            if results.isEmpty {
                                Section {
                                    EmptyView()
                                } header: {
                                    Text("No emoji match “\(query)”")
                                        .font(.system(size: 12))
                                        .foregroundStyle(theme[ThemeKey.chatSecondaryForeground])
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 18)
                                }
                            } else {
                                section(id: "results", title: "Results", emoji: results)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
                .frame(height: 260)
              }
            }
            Rectangle().fill(theme[ThemeKey.popoverBorder]).frame(height: 1)
            footer
        }
        .frame(width: Self.width)
        .background(theme[ThemeKey.popoverBackground])
        .onAppear { searchFocused = true }
        .onChange(of: query) { _, newValue in
            // The Character Viewer inserts its pick into the focused search field.
            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
            if trimmed.count == 1, let character = trimmed.first, EmojiDetection.isEmoji(character) {
                pick(trimmed)
            }
        }
    }

    // MARK: Pieces

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme[ThemeKey.inputPlaceholder])
            TextField("", text: $query, prompt: Text("Search emoji").foregroundStyle(theme[ThemeKey.inputPlaceholder]))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(theme[ThemeKey.inputForeground])
                .focused($searchFocused)
                .onSubmit {
                    if let first = EmojiCatalog.search(query).first { pick(first) }
                }
            if !query.isEmpty {
                Button {
                    query = ""
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
                .strokeBorder(theme[searchFocused ? ThemeKey.inputFocusBorder : ThemeKey.inputBorder], lineWidth: 1)
        )
    }

    private func categoryBar(_ proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 0) {
            categoryButton(id: "frequent", title: "Frequently Used", systemImage: "clock", proxy: proxy)
            ForEach(EmojiCatalog.categories) { category in
                categoryButton(id: category.id, title: category.title, systemImage: category.systemImage, proxy: proxy)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    private func categoryButton(id: String, title: String, systemImage: String, proxy: ScrollViewProxy) -> some View {
        Button {
            proxy.scrollTo(id, anchor: .top)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme[ThemeKey.chatSecondaryForeground])
                .frame(maxWidth: .infinity, minHeight: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }

    private func section(id: String, title: String, emoji: [String]) -> some View {
        Section {
            // Ids are scoped to the section: an emoji can appear both in
            // "Frequently Used" and its category within the same lazy grid.
            ForEach(emoji.map { SectionEmoji(section: id, emoji: $0) }) { item in
                EmojiCell(emoji: item.emoji, isHovered: hovered == item) { pick(item.emoji) }
                    .onHover { inside in
                        if inside { hovered = item } else if hovered == item { hovered = nil }
                    }
            }
        } header: {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme[ThemeKey.chatSecondaryForeground])
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .background(theme[ThemeKey.popoverBackground])
                .id(id)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let hovered = hovered?.emoji {
                Text(hovered).font(.system(size: 20))
                Text(EmojiCatalog.entries[hovered]?.name ?? "")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme[ThemeKey.popoverForeground])
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text("Pick a reaction")
                    .font(.system(size: 12))
                    .foregroundStyle(theme[ThemeKey.chatSecondaryForeground])
            }
            Spacer(minLength: 8)
            Button {
                searchFocused = true
                NSApp.orderFrontCharacterPalette(nil)
            } label: {
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

    private func pick(_ emoji: String) {
        onPick(emoji)
        dismiss()
    }
}

private struct EmojiCell: View {
    @Environment(\.theme) private var theme
    let emoji: String
    let isHovered: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(emoji)
                .font(.system(size: 22))
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isHovered ? theme[ThemeKey.chatSelectionBackground] : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(EmojiCatalog.entries[emoji]?.name ?? emoji)
    }
}

/// An emoji within one picker section.
private struct SectionEmoji: Hashable, Identifiable {
    let section: String
    let emoji: String
    var id: Self { self }
}
