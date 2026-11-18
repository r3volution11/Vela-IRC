// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI

extension View {
    /// A context menu for a view with selectable text in it, such as a
    /// message: right-clicking or Control-clicking the text opens it too,
    /// as anywhere else on the view, the way Messages and Slack behave.
    ///
    /// Selectable SwiftUI text answers a right-click with only its own text
    /// menu (Cut, Copy, Paste, Font…), never a `.contextMenu` around it. So
    /// the text inside (`LinkPointerText`, or a `Text` marked
    /// `.contextClicksOpenMenu()`) takes right-clicks and Control-clicks in
    /// a transparent AppKit view over it and lets them through to this menu.
    /// On selected text, the menu starts with the selection's own items
    /// (Look Up, Translate, Search With Google, Copy, Share…), taken from the
    /// text's menu, then this menu's.
    func selectableTextContextMenu<MenuItems: View>(@ViewBuilder menuItems: () -> MenuItems) -> some View {
        contextMenu(menuItems: menuItems)
            .environment(\.textOpensContextMenu, true)
    }

    /// For a selectable `Text` inside a `selectableTextContextMenu`:
    /// right-clicks and Control-clicks on it open that menu. Outside one it
    /// changes nothing. (`LinkPointerText` does this itself.)
    func contextClicksOpenMenu() -> some View {
        modifier(ContextClickRegionModifier())
    }
}

extension EnvironmentValues {
    /// Inside a `selectableTextContextMenu`.
    @Entry var textOpensContextMenu = false
}

private struct ContextClickRegionModifier: ViewModifier {
    @Environment(\.textOpensContextMenu) private var opensMenu

    func body(content: Content) -> some View {
        if opensMenu {
            content.overlay {
                ContextClickRegion()
                    .accessibilityHidden(true)
            }
        } else {
            content
        }
    }
}

/// The transparent AppKit view over selectable text without links: it only
/// ever takes right-clicks and Control-clicks.
private struct ContextClickRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> LinkPointerRegionView {
        let view = LinkPointerRegionView(regions: LinkRegions())
        view.takesContextClicks = true
        return view
    }

    func updateNSView(_ view: LinkPointerRegionView, context: Context) {}
}

// MARK: Selection items

/// The items selectable text offers for its selection, taken from its own
/// menu for the menu around it: Look Up, Translate, Search With Google,
/// Copy, Share…, Speech and whatever else macOS adds there, but not the
/// editing items (Cut, Paste, Font, Spelling and Grammar, Substitutions,
/// Transformations, Writing Direction, Layout Orientation), which do
/// nothing on text you can't edit. Told apart by their actions, not their
/// titles, so it works in every language.
enum SelectionMenuItems {
    /// Moves the selection's items from `textMenu`, the menu of
    /// `textView`, to the top of `menu`, above a separator.
    static func move(from textMenu: NSMenu, of textView: NSView, to menu: NSMenu) {
        let items = selectionItems(in: textMenu)
        guard !items.isEmpty else { return }
        for item in items {
            textMenu.removeItem(item)
            target(item, at: textView)
        }
        let leading = menu.items.isEmpty ? items : items + [.separator()]
        for (index, item) in leading.enumerated() {
            menu.insertItem(item, at: index)
        }
    }

    /// The items of `menu` that act on a selection, with no separator at
    /// either end or two in a row.
    static func selectionItems(in menu: NSMenu) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        for item in menu.items where !isEditing(item) {
            if item.isSeparatorItem, items.last?.isSeparatorItem ?? true { continue }
            items.append(item)
        }
        if items.last?.isSeparatorItem == true { items.removeLast() }
        return items
    }

    /// An editing command, or a submenu of them.
    static func isEditing(_ item: NSMenuItem) -> Bool {
        if let action = item.action, editingActions.contains(NSStringFromSelector(action)) { return true }
        return item.submenu?.items.contains(where: isEditing) ?? false
    }

    /// Items sent up the responder chain (Copy) now open from another
    /// view's menu, so send them to the text.
    private static func target(_ item: NSMenuItem, at textView: NSView) {
        if item.target == nil, let action = item.action, textView.responds(to: action) {
            item.target = textView
        }
        for subitem in item.submenu?.items ?? [] {
            target(subitem, at: textView)
        }
    }

    private static let editingActions: Set<String> = [
        // Cut, Paste, Paste and Match Style
        "cut:", "paste:", "pasteAsPlainText:", "pasteAsRichText:", "pasteAndMatchStyle:", "delete:",
        // Font
        "orderFrontFontPanel:", "addFontTrait:", "modifyFont:", "underline:", "orderFrontColorPanel:",
        // Spelling and Grammar
        "showGuessPanel:", "checkSpelling:", "toggleContinuousSpellChecking:", "toggleGrammarChecking:",
        "toggleAutomaticSpellingCorrection:",
        // Substitutions
        "orderFrontSubstitutionsPanel:", "toggleSmartInsertDelete:", "toggleAutomaticQuoteSubstitution:",
        "toggleAutomaticDashSubstitution:", "toggleAutomaticLinkDetection:", "toggleAutomaticDataDetection:",
        "toggleAutomaticTextReplacement:", "toggleAutomaticTextCompletion:",
        // Transformations
        "uppercaseWord:", "lowercaseWord:", "capitalizeWord:",
        // Writing Direction
        "makeBaseWritingDirectionNatural:", "makeBaseWritingDirectionLeftToRight:", "makeBaseWritingDirectionRightToLeft:",
        "makeTextWritingDirectionNatural:", "makeTextWritingDirectionLeftToRight:", "makeTextWritingDirectionRightToLeft:",
        // Layout Orientation
        "changeLayoutOrientation:",
    ]
}
