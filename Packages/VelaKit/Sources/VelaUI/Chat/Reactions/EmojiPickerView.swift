// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaTheme

/// Reaction picker: search, frequently used, categories, and a shortcut to
/// the system Character Viewer (whose pick lands in the search field and is
/// used directly). The arrow keys move through the emoji and Return picks
/// the selected one (or the first result). The grid is shared with the
/// message box's emoji and GIF picker (`EmojiGridView`).
struct EmojiPickerView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let onPick: (String) -> Void

    @State private var query = ""
    @State private var hovered: EmojiGridItem?
    @State private var selection: EmojiGridItem?
    @State private var frequent = EmojiRecents.frequent()

    static let columns = 9
    private static let cell: CGFloat = 34
    private static let width: CGFloat = CGFloat(columns) * cell + CGFloat(columns - 1) * 2 + 24

    var body: some View {
        let content = EmojiGridContent(query: query, frequent: frequent, columns: Self.columns)
        VStack(spacing: 0) {
            PickerSearchBox(text: $query, placeholder: "Search emoji") { key in
                handle(key, content: content)
            }
            .padding([.horizontal, .top], 12)
            .padding(.bottom, 8)
            EmojiGridView(content: content, selection: $selection, hovered: $hovered, cellSize: Self.cell) { pick($0) }
            Rectangle().fill(theme[ThemeKey.popoverBorder]).frame(height: 1)
            EmojiFooter(emoji: (hovered ?? selection)?.emoji, prompt: "Pick a reaction") {
                NSApp.orderFrontCharacterPalette(nil)
            }
        }
        .frame(width: Self.width)
        .background(theme[ThemeKey.popoverBackground])
        .onChange(of: query) { _, newValue in
            selection = nil
            // The Character Viewer inserts its pick into the focused search field.
            if let emoji = EmojiCatalog.characterViewerPick(in: newValue) { pick(emoji) }
        }
    }

    private func handle(_ key: PaletteKey, content: EmojiGridContent) -> Bool {
        if let move = GridMove(key) {
            selection = content.moved(from: selection, move)
            return true
        }
        switch key {
        case .submit:
            if let emoji = selection?.emoji ?? (content.isSearching ? content.first?.emoji : nil) { pick(emoji) }
            return true
        case .cancel:
            dismiss()
            return true
        default:
            return false
        }
    }

    private func pick(_ emoji: String) {
        onPick(emoji)
        dismiss()
    }
}
