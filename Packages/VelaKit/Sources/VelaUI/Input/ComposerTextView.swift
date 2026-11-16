// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI

/// Colors, font and text settings for the composer's text view.
struct ComposerAppearance: Equatable {
    var font: NSFont
    var textColor: NSColor
    var placeholderColor: NSColor
    var caretColor: NSColor
    var selectionColor: NSColor
    var placeholder: String
    var spellCheck: Bool
    var accessibilityLabel: String
}

/// What the composer asks of its owner.
struct ComposerActions {
    /// Return was pressed (without ⇧/⌥).
    var submit: () -> Void
    /// The user changed the text (typing, pasting, completing) — not programmatic updates.
    var userEdited: (String) -> Void
    /// ↑ on the first line. Return true if a history entry was recalled.
    var historyPrevious: () -> Bool
    /// ↓ on the last line. Return true if handled.
    var historyNext: () -> Bool
    /// Escape. Return true if something was dismissed.
    var escape: () -> Bool
    /// A paste is about to happen. Return true to take it over (it's not inserted).
    var interceptPaste: (String) -> Bool
    /// Tab-completion candidates for the word before the caret.
    var completions: (_ word: String, _ atLineStart: Bool) -> [String]
}

/// Text to insert at the caret, delivered once per `id`.
struct ComposerInsertion: Equatable {
    let id = UUID()
    let text: String
}

/// The composer's multi-line editor: an `NSTextView` that grows from one line
/// to `maxLines` and then scrolls, with chat key handling (Return sends,
/// ⇧Return/⌥Return insert a newline, Tab completes, ↑/↓ walk history,
/// Escape dismisses) and `:shortcode:` emoji replacement.
struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    @Binding var isFocused: Bool
    var appearance: ComposerAppearance
    /// Changing this focuses the editor.
    var focusRequest: Int
    var insertion: ComposerInsertion?
    var maxLines = 8
    var actions: ComposerActions

    static let verticalInset: CGFloat = 7

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let coordinator = context.coordinator
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScrollElasticity = .none

        let textView = ComposerNSTextView(usingTextLayoutManager: false)
        let contentSize = scrollView.contentSize
        textView.frame = NSRect(origin: .zero, size: contentSize)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = NSSize(width: 0, height: Self.verticalInset)

        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsImageEditing = false
        textView.allowsUndo = true
        textView.usesFindBar = false
        textView.usesFontPanel = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.focusRingType = .none
        textView.setAccessibilityRole(.textArea)

        textView.delegate = coordinator
        textView.onPaste = { [weak coordinator] text in coordinator?.parent.actions.interceptPaste(text) ?? false }
        textView.onFocusChange = { [weak coordinator] focused in coordinator?.focusChanged(focused) }
        textView.onWidthChange = { [weak coordinator] in coordinator?.updateHeight(deferred: true) }
        textView.onAttachedToWindow = { [weak coordinator] in coordinator?.focus(force: false) }

        scrollView.documentView = textView
        coordinator.textView = textView
        coordinator.scrollView = scrollView
        coordinator.apply(appearance)
        coordinator.lastFocusRequest = focusRequest
        textView.string = text
        coordinator.updateHeight(deferred: true)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let textView = coordinator.textView else { return }

        if coordinator.appliedAppearance != appearance {
            coordinator.apply(appearance)
            coordinator.updateHeight(deferred: true)
        }
        if textView.string != text, !textView.hasMarkedText() {
            coordinator.replaceAll(with: text)
        }
        if let insertion, insertion.id != coordinator.lastInsertionID {
            coordinator.lastInsertionID = insertion.id
            textView.insertText(insertion.text, replacementRange: textView.selectedRange())
        }
        if focusRequest != coordinator.lastFocusRequest {
            coordinator.lastFocusRequest = focusRequest
            coordinator.focus(force: true)
        }
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextView
        weak var textView: ComposerNSTextView?
        weak var scrollView: NSScrollView?
        var appliedAppearance: ComposerAppearance?
        var lastFocusRequest = 0
        var lastInsertionID: UUID?

        private var reportedFocus = false
        private var isProgrammaticChange = false
        private var isApplyingCompletion = false
        private var completion: CompletionState?

        private struct CompletionState {
            var range: NSRange
            var candidates: [String]
            var index: Int
        }

        init(parent: ComposerTextView) {
            self.parent = parent
        }

        func apply(_ appearance: ComposerAppearance) {
            appliedAppearance = appearance
            guard let textView else { return }
            textView.font = appearance.font
            textView.textColor = appearance.textColor
            textView.insertionPointColor = appearance.caretColor
            textView.typingAttributes = [.font: appearance.font, .foregroundColor: appearance.textColor]
            textView.selectedTextAttributes = [.backgroundColor: appearance.selectionColor, .foregroundColor: appearance.textColor]
            textView.isContinuousSpellCheckingEnabled = appearance.spellCheck
            textView.placeholder = NSAttributedString(
                string: appearance.placeholder,
                attributes: [.font: appearance.font, .foregroundColor: appearance.placeholderColor]
            )
            textView.setAccessibilityLabel(appearance.accessibilityLabel)
            textView.setAccessibilityPlaceholderValue(appearance.placeholder)
        }

        // MARK: Focus

        func focus(force: Bool) {
            guard let textView else { return }
            guard let window = textView.window else {
                textView.wantsFocusOnAttach = true
                return
            }
            if !force && !Self.mayTakeFocus(from: window.firstResponder) { return }
            window.makeFirstResponder(textView)
        }

        /// Don't pull focus out of another text field, or out of a list the
        /// user is moving through with the keyboard (e.g. the sidebar).
        private static func mayTakeFocus(from responder: NSResponder?) -> Bool {
            guard let responder else { return true }
            if responder is ComposerNSTextView || responder is NSWindow { return true }
            if responder is NSTextView { return false }
            if responder is NSTableView {
                let type = NSApp.currentEvent?.type
                return !(type == .keyDown || type == .keyUp)
            }
            return true
        }

        func focusChanged(_ focused: Bool) {
            // Deferred: focus can move during a SwiftUI update (makeFirstResponder
            // from updateNSView). Compare against the last report, not the
            // binding, which may not have caught up yet.
            guard reportedFocus != focused else { return }
            reportedFocus = focused
            let binding = parent.$isFocused
            Task { @MainActor in binding.wrappedValue = focused }
        }

        // MARK: Text

        /// Replaces the whole text (send, history recall, draft restore)
        /// without reporting it as a user edit. Undoable.
        func replaceAll(with newText: String) {
            guard let textView else { return }
            let full = NSRange(location: 0, length: (textView.string as NSString).length)
            isProgrammaticChange = true
            if textView.shouldChangeText(in: full, replacementString: newText) {
                textView.replaceCharacters(in: full, with: newText)
                textView.didChangeText()
            }
            isProgrammaticChange = false
            textView.setSelectedRange(NSRange(location: (newText as NSString).length, length: 0))
            completion = nil
            textView.needsDisplay = true
            updateHeight(deferred: true)
            textView.scrollRangeToVisible(textView.selectedRange())
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            textView.needsDisplay = true
            if !isApplyingCompletion { completion = nil }
            updateHeight(deferred: false)
            guard !isProgrammaticChange else { return }
            if !isApplyingCompletion, !textView.hasMarkedText() {
                replaceEmojiShortcodeBeforeCaret()
            }
            let value = textView.string
            if parent.text != value { parent.text = value }
            parent.actions.userEdited(value)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            if !isApplyingCompletion { completion = nil }
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                let flags = NSApp.currentEvent?.modifierFlags ?? []
                if flags.contains(.shift) || flags.contains(.option) {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                } else {
                    parent.actions.submit()
                }
                return true
            case #selector(NSResponder.insertTab(_:)):
                return complete(forward: true)
            case #selector(NSResponder.insertBacktab(_:)):
                return complete(forward: false)
            case #selector(NSResponder.moveUp(_:)):
                return isCaretOnFirstLine() && parent.actions.historyPrevious()
            case #selector(NSResponder.moveDown(_:)):
                return isCaretOnLastLine() && parent.actions.historyNext()
            case #selector(NSResponder.cancelOperation(_:)):
                _ = parent.actions.escape()
                // Never fall through to NSTextView's completion popup.
                return true
            default:
                return false
            }
        }

        // MARK: Height

        func updateHeight(deferred: Bool) {
            guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer else { return }
            layoutManager.ensureLayout(for: container)
            let font = textView.font ?? parent.appearance.font
            let lineHeight = layoutManager.defaultLineHeight(for: font)
            let used = max(layoutManager.usedRect(for: container).height, lineHeight)
            let insets = textView.textContainerInset.height * 2
            let maxHeight = lineHeight * CGFloat(max(1, parent.maxLines)) + insets
            let target = min(used + insets, maxHeight).rounded(.up)
            scrollView?.hasVerticalScroller = used + insets > maxHeight + 0.5
            guard abs(target - parent.height) > 0.5 else { return }
            let binding = parent.$height
            if deferred {
                Task { @MainActor in
                    binding.wrappedValue = target
                    textView.scrollRangeToVisible(textView.selectedRange())
                }
            } else {
                binding.wrappedValue = target
                textView.scrollRangeToVisible(textView.selectedRange())
            }
        }

        // MARK: Lines

        private func lineRect(at location: Int) -> NSRect? {
            guard let textView, let layoutManager = textView.layoutManager else { return nil }
            let length = (textView.string as NSString).length
            if length == 0 { return .zero }
            if location >= length {
                if layoutManager.extraLineFragmentTextContainer != nil {
                    return layoutManager.extraLineFragmentRect
                }
                let glyph = layoutManager.glyphIndexForCharacter(at: length - 1)
                return layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            }
            let glyph = layoutManager.glyphIndexForCharacter(at: location)
            return layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        }

        private func isCaretOnFirstLine() -> Bool {
            guard let textView else { return false }
            let selection = textView.selectedRange()
            guard selection.length == 0, let caret = lineRect(at: selection.location), let first = lineRect(at: 0) else {
                return false
            }
            return caret.minY <= first.minY + 0.5
        }

        private func isCaretOnLastLine() -> Bool {
            guard let textView else { return false }
            let selection = textView.selectedRange()
            let length = (textView.string as NSString).length
            guard selection.length == 0, let caret = lineRect(at: selection.location), let last = lineRect(at: length) else {
                return false
            }
            return caret.minY >= last.minY - 0.5
        }

        // MARK: Completion

        private func complete(forward: Bool) -> Bool {
            guard let textView, !textView.hasMarkedText() else { return true }
            // Nothing typed: Tab moves focus like it does elsewhere.
            if textView.string.isEmpty {
                if forward {
                    textView.window?.selectNextKeyView(nil)
                } else {
                    textView.window?.selectPreviousKeyView(nil)
                }
                return true
            }
            let text = textView.string as NSString
            let selection = textView.selectedRange()

            // Repeated Tab: cycle through the same candidates.
            if var state = completion, selection.length == 0, NSMaxRange(state.range) == selection.location,
               NSMaxRange(state.range) <= text.length,
               text.substring(with: state.range) == state.candidates[state.index] {
                let count = state.candidates.count
                state.index = (state.index + (forward ? 1 : count - 1)) % count
                state.range = replace(state.range, with: state.candidates[state.index])
                completion = state
                return true
            }

            guard selection.length == 0 else { return true }
            let caret = selection.location
            var start = caret
            while start > 0, !Self.isSpace(text.character(at: start - 1)) {
                start -= 1
            }
            guard start < caret else { return true }
            let word = text.substring(with: NSRange(location: start, length: caret - start))
            let atLineStart = start == 0 || text.character(at: start - 1) == 0x0A
            let candidates = parent.actions.completions(word, atLineStart)
            guard !candidates.isEmpty else {
                NSSound.beep()
                return true
            }
            let index = forward ? 0 : candidates.count - 1
            let range = replace(NSRange(location: start, length: caret - start), with: candidates[index])
            completion = CompletionState(range: range, candidates: candidates, index: index)
            return true
        }

        /// Replaces `range` as an undoable user edit and puts the caret after it.
        @discardableResult
        private func replace(_ range: NSRange, with string: String) -> NSRange {
            guard let textView else { return range }
            isApplyingCompletion = true
            defer { isApplyingCompletion = false }
            if textView.shouldChangeText(in: range, replacementString: string) {
                textView.replaceCharacters(in: range, with: string)
                textView.didChangeText()
            }
            let inserted = NSRange(location: range.location, length: (string as NSString).length)
            textView.setSelectedRange(NSRange(location: NSMaxRange(inserted), length: 0))
            return inserted
        }

        /// Turns a just-typed `:shortcode:` into its emoji.
        private func replaceEmojiShortcodeBeforeCaret() {
            guard let textView, textView.selectedRange().length == 0 else { return }
            let text = textView.string as NSString
            let caret = textView.selectedRange().location
            guard caret >= 3, caret <= text.length, text.character(at: caret - 1) == 0x3A else { return }
            var start = caret - 2
            while start >= 0, caret - start <= 40 {
                let character = text.character(at: start)
                if character == 0x3A { break }
                guard Self.isShortcodeCharacter(character) else { return }
                start -= 1
            }
            guard start >= 0, caret - start > 2, text.character(at: start) == 0x3A else { return }
            if start > 0, !Self.isSpace(text.character(at: start - 1)) { return }
            let code = text.substring(with: NSRange(location: start + 1, length: caret - start - 2))
            guard let emoji = EmojiShortcodes.emoji(for: code) else { return }
            replace(NSRange(location: start, length: caret - start), with: emoji)
        }

        private static func isSpace(_ character: unichar) -> Bool {
            guard let scalar = Unicode.Scalar(character) else { return false }
            return CharacterSet.whitespacesAndNewlines.contains(scalar)
        }

        private static func isShortcodeCharacter(_ character: unichar) -> Bool {
            switch character {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x5F, 0x2B, 0x2D: true // 0-9 A-Z a-z _ + -
            default: false
            }
        }
    }
}

/// The text view behind the composer: draws its placeholder, reports focus,
/// width changes and pastes, and can take focus as soon as it's in a window.
final class ComposerNSTextView: NSTextView {
    var placeholder: NSAttributedString? {
        didSet { needsDisplay = true }
    }
    var onPaste: ((String) -> Bool)?
    var onFocusChange: ((Bool) -> Void)?
    var onWidthChange: (() -> Void)?
    var onAttachedToWindow: (() -> Void)?
    var wantsFocusOnAttach = true

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocusChange?(true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { onFocusChange?(false) }
        return accepted
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, wantsFocusOnAttach else { return }
        wantsFocusOnAttach = false
        // Let the window settle (the previous buffer's composer is going away).
        DispatchQueue.main.async { [weak self] in
            self?.onAttachedToWindow?()
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(newSize.width - frame.width) > 0.5
        super.setFrameSize(newSize)
        if widthChanged { onWidthChange?() }
    }

    override func paste(_ sender: Any?) {
        if let text = NSPasteboard.general.string(forType: .string), onPaste?(text) == true { return }
        pasteAsPlainText(sender)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !hasMarkedText(), let placeholder else { return }
        let origin = textContainerOrigin
        let padding = textContainer?.lineFragmentPadding ?? 0
        let rect = NSRect(
            x: origin.x + padding,
            y: origin.y,
            width: max(0, bounds.width - origin.x * 2 - padding * 2),
            height: max(0, bounds.height - origin.y)
        )
        placeholder.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}
