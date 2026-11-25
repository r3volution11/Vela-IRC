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
    /// Spelling, autocorrect, substitutions and Writing Tools.
    var textChecking: TextCheckingOptions
    var accessibilityLabel: String
}

/// What text checking needs to know about the conversation: words it must
/// leave alone.
struct ComposerTextContext {
    /// Members (or the other person in a query), plus your own nick.
    var nicks: [String]
    /// Characters that start a channel name on this network.
    var channelTypes: Set<Character>
}

/// What the composer asks of its owner.
struct ComposerActions {
    /// Return was pressed (without ⇧/⌥).
    var submit: () -> Void
    /// The user changed the text (typing, pasting, completing) — not
    /// programmatic updates, and not edits made while Writing Tools works.
    var userEdited: (String) -> Void
    /// ↑ on the first line. Return true if a history entry was recalled.
    var historyPrevious: () -> Bool
    /// ↓ on the last line. Return true if handled.
    var historyNext: () -> Bool
    /// Escape. Return true if something was dismissed.
    var escape: () -> Bool
    /// Page Up, Page Down, Home and End (and Esc with nothing to cancel,
    /// `.present`) scroll the message list instead of the text. Return
    /// false when there's no list to scroll.
    var scrollMessages: (MessageListScroll) -> Bool = { _ in false }
    /// A paste is about to happen. Return true to take it over (it's not inserted).
    var interceptPaste: (String) -> Bool
    /// Tab-completion candidates for the word before the caret.
    var completions: (_ word: String, _ atLineStart: Bool) -> [String]
    /// A spelling or substitution switch was flipped in the Edit menu or
    /// the right-click menu; save it so it sticks.
    var textCheckingToggled: (TextCheckingToggle, Bool) -> Void = { _, _ in }
    /// Nicks and channel types, read when text is checked.
    var textContext: () -> ComposerTextContext = { ComposerTextContext(nicks: [], channelTypes: ["#", "&"]) }
    /// Delete with the caret at the very start and nothing selected.
    /// Return true if something before the text (a GIF) was removed.
    var deleteBackwardAtStart: () -> Bool = { false }
}

/// Text to insert at the caret, delivered once per `id`.
struct ComposerInsertion: Equatable {
    let id = UUID()
    let text: String
    /// `text` is a nick to mention: it's spaced (or followed by a colon)
    /// for where the caret is (`mentionText(for:before:)`).
    var isMention = false

    /// A nick mentioned from a menu: `nick: ` to start a message,
    /// ` nick ` after a word, `nick ` after a space.
    static func mentionText(for nick: String, before preceding: String) -> String {
        guard let last = preceding.last else { return "\(nick): " }
        return last.isWhitespace ? "\(nick) " : " \(nick) "
    }
}

/// The composer's multi-line editor: an `NSTextView` that grows from one line
/// to `maxLines` and then scrolls, with chat key handling (Return sends,
/// ⇧Return/⌥Return insert a newline, Tab completes, ↑/↓ walk history,
/// Escape dismisses, or with nothing to dismiss jumps to the newest
/// message; Page Up/Down, Home and End scroll the messages) and
/// `:shortcode:` emoji replacement.
///
/// macOS text checking (spelling, grammar, autocorrect, text replacements,
/// smart quotes and dashes) follows ``ComposerAppearance/textChecking`` and
/// never changes IRC syntax (``ProtectedTextRanges``) or text Vela put
/// there itself. Writing Tools gets the panel experience (the view stays
/// on TextKit 1); while it works, Return doesn't send and typing
/// indicators and emoji replacement pause.
struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    @Binding var isFocused: Bool
    var appearance: ComposerAppearance
    /// Changing this focuses the editor.
    var focusRequest: Int
    /// Whether another area of the window has the keyboard focus (the
    /// sidebar, the messages, the member list): a new editor, after
    /// switching channels, then leaves it there instead of taking it.
    var yieldsFocus: () -> Bool = { false }
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
        // Spelling, grammar, autocorrect, text replacements, smart quotes and
        // dashes and Writing Tools come from the appearance (see apply).
        // These stay off: they'd change what's sent.
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.allowedWritingToolsResultOptions = .plainText
        textView.focusRingType = .none
        textView.setAccessibilityRole(.textArea)

        textView.delegate = coordinator
        textView.textStorage?.delegate = coordinator
        textView.onPaste = { [weak coordinator] text in coordinator?.parent.actions.interceptPaste(text) ?? false }
        textView.onFocusChange = { [weak coordinator] focused in coordinator?.focusChanged(focused) }
        textView.onWidthChange = { [weak coordinator] in coordinator?.updateHeight(deferred: true) }
        textView.onAttachedToWindow = { [weak coordinator] in
            guard let coordinator, !coordinator.parent.yieldsFocus() else { return }
            coordinator.focus(force: false)
        }
        textView.onTextCheckingToggle = { [weak coordinator] toggle, isOn in coordinator?.textCheckingToggled(toggle, isOn: isOn) }
        textView.onWillCheckText = { [weak coordinator] in coordinator?.refreshIgnoredWords() }
        textView.textCheckingFilter = { [weak coordinator] results in coordinator?.filter(results) ?? results }
        textView.onWillChangeText = { [weak coordinator] in coordinator?.willChangeText() }

        scrollView.documentView = textView
        coordinator.textView = textView
        coordinator.scrollView = scrollView
        coordinator.apply(appearance)
        coordinator.lastFocusRequest = focusRequest
        coordinator.setInitialText(text)
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
        // Writing Tools owns the text until it's done.
        if textView.string != text, !textView.hasMarkedText(), !coordinator.isWritingToolsActive {
            coordinator.replaceAll(with: text)
        }
        if let insertion, insertion.id != coordinator.lastInsertionID {
            coordinator.lastInsertionID = insertion.id
            // On the next turn: the edit reports the new text through the
            // binding, which a write during this update loses. The next
            // update then put the old text back (a Mention chosen while
            // the message box didn't have the focus came to nothing).
            DispatchQueue.main.async { [weak coordinator] in coordinator?.insert(insertion) }
        }
        if focusRequest != coordinator.lastFocusRequest {
            coordinator.lastFocusRequest = focusRequest
            coordinator.focus(force: true)
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.endWritingToolsUndoGroup()
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate, @preconcurrency NSTextStorageDelegate {
        var parent: ComposerTextView
        weak var textView: ComposerNSTextView?
        weak var scrollView: NSScrollView?
        var appliedAppearance: ComposerAppearance?
        var lastFocusRequest = 0
        var lastInsertionID: UUID?

        private var reportedFocus = false
        private var isProgrammaticChange = false
        private var isApplyingCompletion = false
        /// Inserting text for the user (an edited paste): a user edit, but
        /// never autocorrected.
        private var isInserting = false
        private var completion: CompletionState?

        /// Text Vela put in itself, which autocorrect leaves alone.
        private(set) var insertedRanges = InsertedTextRanges()
        /// Nicks last given to the spell checker to ignore.
        private var ignoredNicks: Set<String> = []
        private var lastNicks: [String]?
        private var nickSet = NickSet([String]())

        // Writing Tools
        private var writingToolsUndo = WritingToolsUndoGroup()
        private var textBeforeWritingTools: String?

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
            applyTextChecking(appearance.textChecking)
            textView.placeholder = NSAttributedString(
                string: appearance.placeholder,
                attributes: [.font: appearance.font, .foregroundColor: appearance.placeholderColor]
            )
            textView.setAccessibilityLabel(appearance.accessibilityLabel)
            textView.setAccessibilityPlaceholderValue(appearance.placeholder)
        }

        /// Sets only what changed, so a pending check isn't restarted for nothing.
        private func applyTextChecking(_ options: TextCheckingOptions) {
            guard let textView else { return }
            if textView.isContinuousSpellCheckingEnabled != options.spelling {
                textView.isContinuousSpellCheckingEnabled = options.spelling
            }
            if textView.isGrammarCheckingEnabled != options.grammar {
                textView.isGrammarCheckingEnabled = options.grammar
            }
            if textView.isAutomaticSpellingCorrectionEnabled != options.autocorrect {
                textView.isAutomaticSpellingCorrectionEnabled = options.autocorrect
            }
            if textView.isAutomaticTextReplacementEnabled != options.textReplacements {
                textView.isAutomaticTextReplacementEnabled = options.textReplacements
            }
            if textView.isAutomaticQuoteSubstitutionEnabled != options.smartQuotes {
                textView.isAutomaticQuoteSubstitutionEnabled = options.smartQuotes
            }
            if textView.isAutomaticDashSubstitutionEnabled != options.smartDashes {
                textView.isAutomaticDashSubstitutionEnabled = options.smartDashes
            }
            let behavior: NSWritingToolsBehavior = options.writingTools ? .default : .none
            if textView.writingToolsBehavior != behavior {
                textView.writingToolsBehavior = behavior
            }
        }

        // MARK: Text checking

        /// The Edit menu or right-click menu flipped a switch on the text
        /// view; save it as a setting (which re-applies it here).
        func textCheckingToggled(_ toggle: TextCheckingToggle, isOn: Bool) {
            parent.actions.textCheckingToggled(toggle, isOn)
        }

        /// Keeps the conversation's nicks out of the spell checker's
        /// complaints. Called before each check; cheap when nothing changed.
        func refreshIgnoredWords() {
            guard let textView, textView.isContinuousSpellCheckingEnabled else { return }
            let wanted = Set(currentContext().nicks)
            guard wanted != ignoredNicks else { return }
            let checker = NSSpellChecker.shared
            let tag = textView.spellCheckerDocumentTag
            // Keep words the user chose to ignore with "Ignore Spelling".
            var words = Set(checker.ignoredWords(inSpellDocumentWithTag: tag) ?? [])
            words.subtract(ignoredNicks)
            words.formUnion(wanted)
            ignoredNicks = wanted
            checker.setIgnoredWords(Array(words), inSpellDocumentWithTag: tag)
        }

        /// The conversation's nicks and channel types, with ``nickSet`` kept
        /// in step.
        private func currentContext() -> ComposerTextContext {
            let context = parent.actions.textContext()
            if context.nicks != lastNicks {
                lastNicks = context.nicks
                nickSet = NickSet(context.nicks)
            }
            return context
        }

        func protectedRanges(for text: String) -> ProtectedTextRanges {
            let context = currentContext()
            return ProtectedTextRanges.compute(text: text, nicks: nickSet, channelTypes: context.channelTypes)
        }

        /// Drops corrections that would touch IRC syntax or text Vela put
        /// there, and spelling underlines on nicks, channels, links and code.
        func filter(_ results: [NSTextCheckingResult]) -> [NSTextCheckingResult] {
            guard let textView, !results.isEmpty else { return results }
            let text = textView.string
            return TextCheckingFilter.filter(
                results,
                textLength: (text as NSString).length,
                protected: protectedRanges(for: text),
                inserted: insertedRanges.ranges,
                allowsSubstitutions: !isWritingToolsActive
            )
        }

        func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            guard editedMask.contains(.editedCharacters) else { return }
            insertedRanges.record(
                editedRange: editedRange,
                changeInLength: delta,
                inserted: isProgrammaticChange || isApplyingCompletion || isInserting || isWritingToolsActive
            )
        }

        // MARK: Writing Tools

        var isWritingToolsActive: Bool {
            writingToolsUndo.isSessionActive || (textView?.isWritingToolsActive ?? false)
        }

        func textViewWritingToolsWillBegin(_ textView: NSTextView) {
            writingToolsUndo.sessionWillBegin()
            textBeforeWritingTools = textView.string
            // The result is its own undo step, apart from what was typed.
            textView.breakUndoCoalescing()
            completion = nil
        }

        func textViewWritingToolsDidEnd(_ textView: NSTextView) {
            writingToolsUndo.sessionDidEnd()
            textView.breakUndoCoalescing()
            let value = textView.string
            if parent.text != value { parent.text = value }
            if let before = textBeforeWritingTools, before != value {
                parent.actions.userEdited(value)
            }
            textBeforeWritingTools = nil
            updateHeight(deferred: true)
        }

        func textView(_ textView: NSTextView, writingToolsIgnoredRangesInEnclosingRange enclosingRange: NSRange) -> [NSValue] {
            protectedRanges(for: textView.string)
                .ranges(in: enclosingRange)
                .map { NSValue(range: $0) }
        }

        /// Called before every text change. Writing Tools' edits are grouped
        /// into one undo step (see ``WritingToolsUndoGroup``).
        func willChangeText() {
            writingToolsUndo.textWillChange(textView?.undoManager)
        }

        func endWritingToolsUndoGroup() {
            writingToolsUndo.close()
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
            // Also before each check; this covers a draft checked on focus.
            if focused { refreshIgnoredWords() }
            let binding = parent.$isFocused
            Task { @MainActor in binding.wrappedValue = focused }
        }

        // MARK: Text

        /// Replaces the whole text (send, history recall, draft restore)
        /// without reporting it as a user edit. Undoable.
        func replaceAll(with newText: String) {
            guard let textView else { return }
            let full = NSRange(location: 0, length: (textView.string as NSString).length)
            // A correction offered for the old text has nothing left to correct.
            NSSpellChecker.shared.dismissCorrectionIndicator(for: textView)
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

        /// The text the view starts with (a restored draft): not undoable,
        /// and never autocorrected.
        func setInitialText(_ initial: String) {
            guard let textView else { return }
            isProgrammaticChange = true
            textView.string = initial
            isProgrammaticChange = false
        }

        /// Inserts text from outside (a mention, an edited paste) at the
        /// selection.
        func insert(_ insertion: ComposerInsertion) {
            guard let textView else { return }
            guard insertion.isMention else {
                insert(insertion.text)
                return
            }
            let text = textView.string as NSString
            let caret = min(textView.selectedRange().location, text.length)
            insert(ComposerInsertion.mentionText(for: insertion.text, before: text.substring(to: caret)))
        }

        /// Inserts `string` at the selection as a user edit (it's reported
        /// and undoable) that autocorrect leaves alone.
        func insert(_ string: String) {
            guard let textView else { return }
            let range = textView.selectedRange()
            isInserting = true
            if textView.shouldChangeText(in: range, replacementString: string) {
                textView.replaceCharacters(in: range, with: string)
                // Caret after the text before reporting, as typing would
                // (emoji replacement looks just before it).
                textView.setSelectedRange(NSRange(location: range.location + (string as NSString).length, length: 0))
                textView.didChangeText()
            }
            isInserting = false
            textView.scrollRangeToVisible(textView.selectedRange())
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            textView.needsDisplay = true
            if !isApplyingCompletion { completion = nil }
            updateHeight(deferred: false)
            guard !isProgrammaticChange else { return }
            let value = textView.string
            if isWritingToolsActive {
                // Keep the binding (and the draft) current, but it's not
                // typing: no indicator, no emoji replacement. Reported once
                // when Writing Tools is done.
                if parent.text != value { parent.text = value }
                return
            }
            if !isApplyingCompletion, !textView.hasMarkedText() {
                replaceEmojiShortcodeBeforeCaret()
            }
            let current = textView.string
            if parent.text != current { parent.text = current }
            parent.actions.userEdited(current)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            if !isApplyingCompletion { completion = nil }
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if isWritingToolsActive {
                switch selector {
                // Return doesn't send, Tab doesn't complete and ↑/↓ only
                // move the caret: nothing replaces text Writing Tools is
                // working on.
                case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)),
                     #selector(NSResponder.insertBacktab(_:)), #selector(NSResponder.cancelOperation(_:)):
                    return true
                default:
                    return false
                }
            }
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
            case #selector(NSResponder.deleteBackward(_:)):
                let selection = textView.selectedRange()
                return selection.location == 0 && selection.length == 0 && parent.actions.deleteBackwardAtStart()
            case #selector(NSResponder.cancelOperation(_:)):
                // A pending paste or a reply first, as before; then a Tab
                // completion being cycled through, which ends, leaving the
                // word. With nothing to cancel: back to the newest message,
                // like Jump to present.
                if parent.actions.escape() {
                    // Cancelled.
                } else if completion != nil {
                    completion = nil
                } else {
                    _ = parent.actions.scrollMessages(.present)
                }
                // Never fall through to NSTextView's completion popup.
                return true
            // The message list, not the text, which is a few lines at most
            // (⌘↑ and ⌘↓ still move the caret to its start and end).
            // fn-↑ and fn-↓ are Page Up and Page Down.
            case #selector(NSResponder.scrollPageUp(_:)):
                return parent.actions.scrollMessages(.pageUp)
            case #selector(NSResponder.scrollPageDown(_:)):
                return parent.actions.scrollMessages(.pageDown)
            case #selector(NSResponder.scrollToBeginningOfDocument(_:)):
                return parent.actions.scrollMessages(.top)
            case #selector(NSResponder.scrollToEndOfDocument(_:)):
                return parent.actions.scrollMessages(.present)
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
                Beep.play()
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

/// Groups a Writing Tools session's edits into one undo step. The group
/// opens lazily, at the session's first change, so a session that changes
/// nothing leaves no empty step behind, and closes when the session ends.
///
/// The session is tracked from will-begin to did-end here, not read from
/// `NSTextView.isWritingToolsActive`, which can still be true after did-end:
/// a change arriving then must not open a group nothing would close.
struct WritingToolsUndoGroup {
    /// Between Writing Tools' will-begin and did-end.
    private(set) var isSessionActive = false
    /// The undo manager holding the open group, if any (kept, since the
    /// view may have left its window by the time it closes).
    private weak var undoManager: UndoManager?

    /// Whether a group is open.
    var isOpen: Bool { undoManager != nil }

    mutating func sessionWillBegin() {
        // A session that never reported its end doesn't leave its group open.
        close()
        isSessionActive = true
    }

    /// Text is about to change.
    mutating func textWillChange(_ undoManager: UndoManager?) {
        guard isSessionActive, self.undoManager == nil, let undoManager else { return }
        undoManager.beginUndoGrouping()
        self.undoManager = undoManager
    }

    mutating func sessionDidEnd() {
        isSessionActive = false
        close()
    }

    /// Closes the open group, if any (also when the composer goes away).
    mutating func close() {
        guard let undoManager else { return }
        self.undoManager = nil
        if undoManager.groupingLevel > 0 {
            undoManager.endUndoGrouping()
        }
    }
}

/// The text view behind the composer: draws its placeholder, reports focus,
/// width changes and pastes, and can take focus as soon as it's in a window.
/// Reports the Edit menu's spelling and substitution switches so they're
/// saved, and filters text checking so IRC syntax isn't corrected.
final class ComposerNSTextView: NSTextView {
    var placeholder: NSAttributedString? {
        didSet { needsDisplay = true }
    }
    var onPaste: ((String) -> Bool)?
    var onFocusChange: ((Bool) -> Void)?
    var onWidthChange: (() -> Void)?
    var onAttachedToWindow: (() -> Void)?
    /// A spelling or substitution switch was flipped; reports its new state.
    var onTextCheckingToggle: ((TextCheckingToggle, Bool) -> Void)?
    /// Text is about to be checked.
    var onWillCheckText: (() -> Void)?
    /// Removes results that must not be applied.
    var textCheckingFilter: (([NSTextCheckingResult]) -> [NSTextCheckingResult])?
    /// Text is about to change.
    var onWillChangeText: (() -> Void)?
    var wantsFocusOnAttach = true

    // MARK: Text checking

    override func toggleContinuousSpellChecking(_ sender: Any?) {
        super.toggleContinuousSpellChecking(sender)
        onTextCheckingToggle?(.spelling, isContinuousSpellCheckingEnabled)
    }

    override func toggleGrammarChecking(_ sender: Any?) {
        super.toggleGrammarChecking(sender)
        onTextCheckingToggle?(.grammar, isGrammarCheckingEnabled)
    }

    override func toggleAutomaticSpellingCorrection(_ sender: Any?) {
        super.toggleAutomaticSpellingCorrection(sender)
        onTextCheckingToggle?(.autocorrect, isAutomaticSpellingCorrectionEnabled)
    }

    override func toggleAutomaticTextReplacement(_ sender: Any?) {
        super.toggleAutomaticTextReplacement(sender)
        onTextCheckingToggle?(.textReplacements, isAutomaticTextReplacementEnabled)
    }

    override func toggleAutomaticQuoteSubstitution(_ sender: Any?) {
        super.toggleAutomaticQuoteSubstitution(sender)
        onTextCheckingToggle?(.smartQuotes, isAutomaticQuoteSubstitutionEnabled)
    }

    override func toggleAutomaticDashSubstitution(_ sender: Any?) {
        super.toggleAutomaticDashSubstitution(sender)
        onTextCheckingToggle?(.smartDashes, isAutomaticDashSubstitutionEnabled)
    }

    override func checkText(in range: NSRange, types checkingTypes: NSTextCheckingTypes, options: [NSSpellChecker.OptionKey: Any] = [:]) {
        onWillCheckText?()
        super.checkText(in: range, types: checkingTypes, options: options)
    }

    override func handleTextCheckingResults(
        _ results: [NSTextCheckingResult],
        forRange range: NSRange,
        types checkingTypes: NSTextCheckingTypes,
        options: [NSSpellChecker.OptionKey: Any] = [:],
        orthography: NSOrthography,
        wordCount: Int
    ) {
        let kept = textCheckingFilter?(results) ?? results
        super.handleTextCheckingResults(
            kept, forRange: range, types: checkingTypes, options: options, orthography: orthography, wordCount: wordCount
        )
    }

    // Both, in case one doesn't go through the other. Reporting twice is harmless.
    override func shouldChangeText(inRanges affectedRanges: [NSValue], replacementStrings: [String]?) -> Bool {
        onWillChangeText?()
        return super.shouldChangeText(inRanges: affectedRanges, replacementStrings: replacementStrings)
    }

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        onWillChangeText?()
        return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
    }

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
