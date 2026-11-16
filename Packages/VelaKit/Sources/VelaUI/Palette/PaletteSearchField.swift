// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI

/// Keys the palette handles while its search field has focus.
enum PaletteKey {
    case up, down, pageUp, pageDown, submit, cancel
    /// Backspace in an empty field (leaves command mode, like deleting
    /// VS Code's `>`).
    case deleteBackwardWhenEmpty
}

/// The palette's search field: an `NSTextField` that takes focus as soon as
/// it's on screen and reports navigation keys (↑/↓, ⌃P/⌃N, Page Up/Down,
/// Return, Esc) through its field editor's commands, so they work whatever
/// the key bindings and never reach the text.
struct PaletteSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var accessibilityLabel: String
    var font: NSFont
    var textColor: NSColor
    var placeholderColor: NSColor
    var caretColor: NSColor
    var selectionColor: NSColor
    /// Called synchronously for every edit, so results are current before
    /// the next key (e.g. a quick Return) is handled.
    let onTextChange: (String) -> Void
    let onKey: (PaletteKey) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> PaletteTextField {
        let field = PaletteTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.usesSingleLineMode = true
        field.delegate = context.coordinator
        field.stringValue = text
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        apply(to: field)
        return field
    }

    func updateNSView(_ field: PaletteTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
            if let editor = field.currentEditor() {
                editor.selectedRange = NSRange(location: (text as NSString).length, length: 0)
            }
        }
        apply(to: field)
    }

    private func apply(to field: PaletteTextField) {
        field.font = font
        field.textColor = textColor
        field.caretColor = caretColor
        field.selectionColor = selectionColor
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [.font: font, .foregroundColor: placeholderColor]
        )
        field.setAccessibilityLabel(accessibilityLabel)
        field.setAccessibilityPlaceholderValue(placeholder)
        field.applyEditorColors()
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PaletteSearchField

        init(parent: PaletteSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let value = field.stringValue
            guard parent.text != value else { return }
            parent.text = value
            parent.onTextChange(value)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                return parent.onKey(.up)
            case #selector(NSResponder.moveDown(_:)):
                return parent.onKey(.down)
            case #selector(NSResponder.scrollPageUp(_:)), #selector(NSResponder.pageUp(_:)):
                return parent.onKey(.pageUp)
            case #selector(NSResponder.scrollPageDown(_:)), #selector(NSResponder.pageDown(_:)):
                return parent.onKey(.pageDown)
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                return parent.onKey(.submit)
            case #selector(NSResponder.cancelOperation(_:)):
                return parent.onKey(.cancel)
            case #selector(NSResponder.deleteBackward(_:)):
                return textView.string.isEmpty && parent.onKey(.deleteBackwardWhenEmpty)
            case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
                // Keep focus in the palette.
                return true
            default:
                return false
            }
        }
    }
}

/// Takes first responder when it joins a window and colors its field editor.
final class PaletteTextField: NSTextField {
    var caretColor: NSColor = .textColor
    var selectionColor: NSColor = .selectedTextBackgroundColor

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        focus()
        // The window may still be settling (the palette opens during a
        // SwiftUI update); make sure focus sticks.
        DispatchQueue.main.async { [weak self] in self?.focus() }
    }

    private func focus() {
        guard let window, window.firstResponder !== currentEditor() else { return }
        window.makeFirstResponder(self)
        applyEditorColors()
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { applyEditorColors() }
        return accepted
    }

    func applyEditorColors() {
        guard let editor = currentEditor() as? NSTextView else { return }
        editor.insertionPointColor = caretColor
        editor.selectedTextAttributes = [.backgroundColor: selectionColor, .foregroundColor: textColor ?? .textColor]
    }
}
