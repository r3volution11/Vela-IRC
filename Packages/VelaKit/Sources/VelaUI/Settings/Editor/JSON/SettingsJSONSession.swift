// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Observation
import VelaFoundation
import VelaStore
import VelaTheme

/// The completion list while it's open.
struct JSONCompletionState: Equatable {
    var items: [SettingsCompletionItem]
    var selectedIndex: Int
    /// The text being completed, in the editor pane's coordinates.
    var anchor: CGRect
    /// Where the replaced text starts, to tell when the caret has left it.
    var replaceStart: Int
    var selectedItem: SettingsCompletionItem? { items.indices.contains(selectedIndex) ? items[selectedIndex] : nil }
}

/// A hover card: documentation for a key and the problems under the pointer.
struct JSONHoverState: Equatable {
    enum Pane: Equatable { case editor, defaults }
    var pane: Pane
    /// The hovered text, in that pane's coordinates.
    var anchor: CGRect
    var docs: JSONHoverDocs?
    var problems: [SettingsDiagnostic]
    /// "Change to “chat.fontSize”" for an unknown key with a likely match.
    var quickFix: QuickFix?

    struct QuickFix: Equatable {
        var range: NSRange
        var key: String
    }
}

/// The defaults pane's ✎ button: shown on the line of the key under the pointer.
struct JSONDefaultsKeyHover: Equatable {
    var key: String
    /// The line, in the defaults pane's coordinates.
    var lineRect: CGRect
    /// Where the text starts (after the gutter), in the same coordinates.
    var textStart: CGFloat
}

/// The JSON view's state and logic. One per ``SettingsEditorState`` (so
/// per app), kept for the app's lifetime: the text views, their undo
/// history and any unsaved edits survive switching to the UI view, other
/// Settings panes, and closing the Settings window.
@MainActor
@Observable
final class SettingsJSONSession: NSObject {
    // MARK: Registry

    @ObservationIgnored private static let sessions = NSMapTable<SettingsEditorState, SettingsJSONSession>(
        keyOptions: .weakMemory, valueOptions: .strongMemory
    )

    static func session(for editor: SettingsEditorState) -> SettingsJSONSession {
        if let session = sessions.object(forKey: editor) { return session }
        let session = SettingsJSONSession(editor: editor)
        sessions.setObject(session, forKey: editor)
        return session
    }

    // MARK: Collaborators

    @ObservationIgnored private weak var editorState: SettingsEditorState?
    @ObservationIgnored private(set) weak var store: SettingsStore?
    /// The app's suggestions (themes, fonts, channels…).
    @ObservationIgnored var suggestions: JSONCompletionModel.Suggestions = { _ in [] }
    @ObservationIgnored private var suggestionProvider: SettingSuggestionProvider?
    @ObservationIgnored private var theme: ResolvedTheme?
    @ObservationIgnored private var font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    // MARK: Views

    @ObservationIgnored let editorPane: JSONPaneView
    @ObservationIgnored let defaultsPane: JSONPaneView
    @ObservationIgnored let undoManager = UndoManager()
    @ObservationIgnored private lazy var closeGuard = JSONWindowCloseGuard { [weak self] in self?.closeAttempted() }

    var textView: JSONCodeTextView { editorPane.textView }
    private var defaultsTextView: JSONCodeTextView { defaultsPane.textView }

    // MARK: Buffer

    @ObservationIgnored private var buffer: JSONBufferModel?
    @ObservationIgnored private var lineIndex = JSONLineIndex()
    @ObservationIgnored private var defaultsLineIndex = JSONLineIndex()
    @ObservationIgnored private var runs: [JSONSyntaxRun] = []
    /// Bumped on every edit.
    @ObservationIgnored private var textVersion = 0
    /// The last parsed text and the version it belongs to.
    @ObservationIgnored private var document: JSONCDocument?
    @ObservationIgnored private var documentVersion = -1
    @ObservationIgnored private var validationTask: Task<Void, Never>?
    /// Edits the text storage reported since the last `textDidChange`.
    @ObservationIgnored private var pendingEdits: [(range: NSRange, delta: Int)] = []
    @ObservationIgnored private var defaultsDocument = JSONCDocument("")
    @ObservationIgnored private var defaultsKeysByLine: [Int: JSONCProperty] = [:]
    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var hoverTarget: NSRange?
    /// The hover card's frame, reported by the view, so moving onto it
    /// doesn't close it.
    @ObservationIgnored var hoverCardFrame: CGRect?

    // MARK: Observable state

    /// The buffer differs from settings.json.
    private(set) var isDirty = false
    /// settings.json changed on disk while there were unsaved edits.
    private(set) var hasConflict = false
    /// The latest validation's problems, in text order.
    private(set) var diagnostics: [SettingsDiagnostic] = []
    var problemsExpanded = false
    /// Remembered between launches (not by demo snapshots).
    var showsDefaults = !SnapshotSupport.isActive && UserDefaults.standard.bool(forKey: SettingsJSONSession.showsDefaultsKey) {
        didSet {
            guard !SnapshotSupport.isActive else { return }
            UserDefaults.standard.set(showsDefaults, forKey: Self.showsDefaultsKey)
        }
    }
    private(set) var completion: JSONCompletionState?
    private(set) var hover: JSONHoverState?
    private(set) var defaultsKeyHover: JSONDefaultsKeyHover?
    /// The window's close button or ⌘W was used with unsaved edits.
    var closeRequested = false
    /// Why the last save failed.
    private(set) var saveError: String?
    /// A one-off message, such as a key that couldn't be added.
    var notice: String?
    /// 1-based caret line and column, for the status bar.
    private(set) var caretLine = 1
    private(set) var caretColumn = 1

    private static let showsDefaultsKey = "Vela.settingsJSON.showsDefaults"

    private init(editor: SettingsEditorState) {
        editorState = editor
        editorPane = JSONPaneView(editable: true)
        defaultsPane = JSONPaneView(editable: false)
        super.init()
        textView.owner = self
        textView.delegate = self
        textView.textStorage?.delegate = self
        defaultsTextView.owner = self
        defaultsTextView.delegate = self
        let notifications = NotificationCenter.default
        for pane in [editorPane, defaultsPane] {
            pane.scrollView.contentView.postsBoundsChangedNotifications = true
            notifications.addObserver(self, selector: #selector(paneScrolled(_:)), name: NSView.boundsDidChangeNotification, object: pane.scrollView.contentView)
        }
        let defaults = SettingsCatalog.defaultSettingsDocument()
        defaultsDocument = JSONCDocument(defaults)
        defaultsLineIndex = JSONLineIndex(defaults)
        for property in defaultsDocument.root?.properties ?? [] {
            defaultsKeysByLine[defaultsLineIndex.line(containing: property.keyRange.location)] = property
        }
        defaultsTextView.textStorage?.setAttributedString(NSAttributedString(string: defaults, attributes: baseAttributes))
        defaultsTextView.updateGutter(lineCount: defaultsLineIndex.lineCount)
    }

    // MARK: Attaching

    /// Connects the session to the app's settings and suggestions, and
    /// loads settings.json the first time (or catches up with changes made
    /// while the view was away).
    func attach(store: SettingsStore, makeProvider: () -> SettingSuggestionProvider) {
        self.store = store
        if suggestionProvider == nil {
            let provider = makeProvider()
            suggestionProvider = provider
            suggestions = { [weak provider] source in provider?.suggestions(for: source) ?? [] }
            Task { await provider.loadLanguagesIfNeeded() }
        }
        if buffer == nil {
            load()
        } else {
            syncWithStore()
        }
    }

    /// Colors and font from the theme and chat settings.
    func apply(theme newTheme: ResolvedTheme, font newFont: NSFont) {
        let themeChanged = theme != newTheme
        let fontChanged = font != newFont
        guard themeChanged || fontChanged else { return }
        theme = newTheme
        font = newFont
        let palette = JSONCodeTextView.Palette(
            background: newTheme.color(ThemeKey.settingsBackground).nsColor,
            gutterForeground: newTheme.color(ThemeKey.settingsSecondaryForeground).withAlpha(0.65).nsColor,
            gutterActiveForeground: newTheme.color(ThemeKey.settingsForeground).nsColor,
            gutterBorder: newTheme.color(ThemeKey.settingsBorder).nsColor,
            currentLine: newTheme.color(ThemeKey.settingsForeground).withAlpha(0.045).nsColor,
            error: newTheme.color(ThemeKey.statusError).nsColor,
            warning: newTheme.color(ThemeKey.statusWarning).nsColor,
            info: newTheme.color(ThemeKey.settingsSecondaryForeground).nsColor
        )
        for view in [textView, defaultsTextView] {
            view.palette = palette
            view.font = newFont
            view.insertionPointColor = newTheme.color(ThemeKey.accent).nsColor
            view.selectedTextAttributes = [.backgroundColor: newTheme.color(ThemeKey.accent).withAlpha(0.28).nsColor]
            view.typingAttributes = baseAttributes
            if let storage = view.textStorage, storage.length > 0 {
                storage.addAttributes(baseAttributes, range: NSRange(location: 0, length: storage.length))
            }
            view.enclosingScrollView?.backgroundColor = palette.background
            view.enclosingScrollView?.scrollerKnobStyle = newTheme.kind == .dark ? .light : .dark
            view.appearance = NSAppearance(named: newTheme.kind == .dark ? .darkAqua : .aqua)
        }
        textView.updateGutter(lineCount: lineIndex.lineCount)
        defaultsTextView.updateGutter(lineCount: defaultsLineIndex.lineCount)
        recolorAll(textView, runs: runs)
        recolorAll(defaultsTextView, runs: JSONSyntax.runs(for: defaultsDocument.tokens))
    }

    private var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: theme?.color(ThemeKey.settingsForeground).nsColor ?? NSColor.textColor]
    }

    // MARK: Loading and syncing

    private func load() {
        guard let store else { return }
        let text = store.fileText()
        buffer = JSONBufferModel(diskText: text, revision: store.fileRevision)
        textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: baseAttributes))
        undoManager.removeAllActions()
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        resetAfterWholeTextChange()
    }

    /// Catches up with settings.json on disk: reloads silently when the
    /// buffer is clean, or flags a conflict when it isn't.
    func syncWithStore() {
        guard let store else { return }
        guard var model = buffer else { return load() }
        guard store.fileRevision != model.baselineRevision, store.fileRevision != model.conflict?.revision else { return }
        let diskText = store.fileText()
        let response = model.fileChanged(diskText: diskText, revision: store.fileRevision, buffer: textView.string)
        buffer = model
        switch response {
        case .none:
            break
        case .reload(let text):
            replaceText(with: text, actionName: "Reload settings.json")
        case .conflict:
            break
        }
        hasConflict = model.conflict != nil
        updateDirty()
    }

    // MARK: Saving

    /// ⌘S: writes the buffer to settings.json exactly as it is.
    @discardableResult
    func save() -> Bool {
        guard let store, var model = buffer else { return false }
        let text = textView.string
        do {
            try store.saveFileText(text)
        } catch {
            saveError = "Couldn't save settings.json: \(error.localizedDescription)"
            return false
        }
        model.saved(text, revision: store.fileRevision)
        buffer = model
        saveError = nil
        hasConflict = false
        updateDirty()
        return true
    }

    /// Puts the buffer back to settings.json as it is on disk.
    func revert() {
        syncWithStore()
        guard var model = buffer else { return }
        let text = model.revert()
        buffer = model
        replaceText(with: text, actionName: "Revert")
        hasConflict = false
        updateDirty()
    }

    /// The conflict banner's "Reload".
    func reloadFromDisk() {
        guard var model = buffer, let text = model.reloadFromConflict() else { return }
        buffer = model
        replaceText(with: text, actionName: "Reload settings.json")
        hasConflict = false
        updateDirty()
    }

    /// The conflict banner's "Keep My Changes".
    func keepMyChanges() {
        guard var model = buffer else { return }
        model.keepMine()
        buffer = model
        hasConflict = false
        updateDirty()
    }

    private func updateDirty() {
        let dirty = buffer?.isDirty(textView.string) ?? false
        if isDirty != dirty { isDirty = dirty }
        if editorState?.hasUnsavedJSON != dirty { editorState?.hasUnsavedJSON = dirty }
        updateCloseGuard()
        if !dirty, closeRequested {
            // Saved or reverted another way while the prompt showed.
            closeRequested = false
        }
    }

    // MARK: Leaving with unsaved edits

    enum LeaveChoice { case save, discard, cancel }

    /// Answers the Save / Discard / Cancel prompt shown for a pending mode
    /// switch (``SettingsEditorState/pendingMode``) or a window close.
    func resolveLeave(_ choice: LeaveChoice) {
        guard let editor = editorState else { return }
        switch choice {
        case .cancel:
            editor.pendingMode = nil
            closeRequested = false
            return
        case .save:
            guard save() else { return }
        case .discard:
            revert()
        }
        if let mode = editor.pendingMode {
            editor.pendingMode = nil
            editor.mode = mode
        }
        if closeRequested {
            closeRequested = false
            closeGuard.closeWindow()
        }
    }

    private func closeAttempted() {
        guard isDirty else {
            closeGuard.closeWindow()
            return
        }
        closeRequested = true
    }

    private func updateCloseGuard() {
        closeGuard.guardWindow(isDirty ? textView.window : nil)
    }

    // MARK: Reveal and copy

    /// Selects `key`'s value, adding the setting with its default first
    /// when settings.json doesn't have it ("Edit in settings.json").
    func reveal(key: String) {
        let descriptor = SettingsCatalog.descriptor(forKey: key)
        guard let plan = JSONReveal.plan(key: key, defaultValue: descriptor?.defaultValue, in: textView.string) else {
            notice = descriptor == nil
                ? "“\(key)” isn't in settings.json."
                : "Couldn't add “\(key)”: fix the errors in settings.json first."
            return
        }
        if plan.added {
            applyEdits(plan.edits, selecting: plan.selection, actionName: "Add Setting")
        } else {
            textView.setSelectedRange(plan.selection)
        }
        focusEditor()
        // A freshly shown view lays out after this run loop turn.
        DispatchQueue.main.async { [weak self] in
            self?.scrollToCenter(plan.selection)
        }
    }

    /// The defaults pane's ✎: copies `key` with its default into
    /// settings.json (or goes to it, if it's there) and selects the value.
    func copyDefault(key: String) {
        hover = nil
        reveal(key: key)
    }

    /// Selects `range` and scrolls to it (a problem in the problems list).
    func jump(to range: NSRange) {
        let length = (textView.string as NSString).length
        let clamped = NSRange(location: min(range.location, length), length: max(0, min(range.length, length - min(range.location, length))))
        textView.setSelectedRange(clamped)
        focusEditor()
        scrollToCenter(clamped)
    }

    /// Opens the find bar (⌘F).
    func showFind() {
        focusEditor()
        let item = NSMenuItem()
        item.tag = NSTextFinder.Action.showFindInterface.rawValue
        textView.performTextFinderAction(item)
    }

    func focusEditor() {
        textView.window?.makeFirstResponder(textView)
    }

    private func scrollToCenter(_ range: NSRange) {
        guard let rect = textView.rect(forCharacterRange: range) else {
            textView.scrollRangeToVisible(range)
            return
        }
        let clip = editorPane.scrollView.contentView
        let maxY = max(0, textView.frame.height - clip.bounds.height)
        let y = min(max(0, rect.midY - clip.bounds.height / 2), maxY)
        clip.scroll(to: NSPoint(x: 0, y: y))
        editorPane.scrollView.reflectScrolledClipView(clip)
    }

    // MARK: Editing

    /// Applies `edits` (ranges in the current text) as one undoable change.
    func applyEdits(_ edits: [JSONCEdit], selecting selection: NSRange?, actionName: String) {
        guard !edits.isEmpty, let storage = textView.textStorage else {
            if let selection { textView.setSelectedRange(selection) }
            return
        }
        textView.breakUndoCoalescing()
        undoManager.beginUndoGrouping()
        let ordered = edits.enumerated().sorted {
            ($0.element.range.location, $0.offset) > ($1.element.range.location, $1.offset)
        }
        for (_, edit) in ordered {
            guard textView.shouldChangeText(in: edit.range, replacementString: edit.replacement) else { continue }
            storage.replaceCharacters(in: edit.range, with: edit.replacement)
            textView.didChangeText()
        }
        undoManager.endUndoGrouping()
        undoManager.setActionName(actionName)
        if let selection { textView.setSelectedRange(selection) }
    }

    /// Replaces the buffer's text with `text` as one minimal, undoable
    /// edit, keeping the selection and scroll position.
    private func replaceText(with text: String, actionName: String) {
        guard let edit = JSONCEdit.difference(from: textView.string, to: text) else { return }
        let selection = JSONSelection.adjust(textView.selectedRange(), for: edit)
        let clip = editorPane.scrollView.contentView
        let origin = clip.bounds.origin
        applyEdits([edit], selecting: selection, actionName: actionName)
        clip.scroll(to: origin)
        editorPane.scrollView.reflectScrolledClipView(clip)
    }

    private func resetAfterWholeTextChange() {
        pendingEdits.removeAll()
        let text = textView.string
        lineIndex = JSONLineIndex(text)
        textView.updateGutter(lineCount: lineIndex.lineCount)
        runs = JSONSyntax.runs(in: text)
        recolorAll(textView, runs: runs)
        textView.diagnostics = []
        textVersion &+= 1
        updateDirty()
        updateCaretPosition()
        validate(after: .zero)
    }

    /// Handles one edit of the editor's text.
    private func processEdits() {
        let edits = pendingEdits
        pendingEdits.removeAll()
        guard !edits.isEmpty else { return }
        guard edits.count == 1, let edit = edits.first else {
            resetAfterWholeTextChange()
            return
        }
        let text = textView.string
        let nsText = text as NSString
        lineIndex.update(editedRange: edit.range, delta: edit.delta, in: nsText)
        textView.updateGutter(lineCount: lineIndex.lineCount)

        let newRuns = JSONSyntax.runs(in: text)
        if let changed = JSONSyntax.changedRange(old: runs, new: newRuns, editedRange: edit.range, delta: edit.delta) {
            recolor(textView, runs: newRuns, in: changed)
        }
        runs = newRuns
        textView.diagnostics = JSONColorChecks.shift(textView.diagnostics, editedRange: edit.range, delta: edit.delta)
        textVersion &+= 1
        hideHover()
        updateDirty()
        validate(after: .milliseconds(150))
    }

    // MARK: Highlighting

    private func recolorAll(_ view: JSONCodeTextView, runs: [JSONSyntaxRun]) {
        let length = (view.string as NSString).length
        recolor(view, runs: runs, in: NSRange(location: 0, length: length))
    }

    private func recolor(_ view: JSONCodeTextView, runs: [JSONSyntaxRun], in range: NSRange) {
        guard let theme, let layoutManager = view.layoutManager else { return }
        let length = (view.string as NSString).length
        let range = NSIntersectionRange(range, NSRange(location: 0, length: length))
        guard range.length > 0 else { return }
        var colors: [JSONSyntaxRole: NSColor] = [:]
        for role in JSONSyntaxRole.allCases {
            colors[role] = theme.color(JSONSyntax.colorKey(for: role)).nsColor
        }
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
        var index = JSONSyntax.firstRun(endingAfter: range.location, in: runs)
        let end = range.location + range.length
        while index < runs.count, runs[index].range.location < end {
            let run = runs[index]
            let clipped = NSIntersectionRange(run.range, range)
            if clipped.length > 0, let color = colors[run.role] {
                layoutManager.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: clipped)
            }
            index += 1
        }
    }

    // MARK: Validation

    private func validate(after delay: Duration) {
        validationTask?.cancel()
        let version = textVersion
        let text = textView.string
        validationTask = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
            }
            let (document, diagnostics) = await Task.detached(priority: .userInitiated) {
                Self.validate(text)
            }.value
            guard let self, !Task.isCancelled, self.textVersion == version else { return }
            self.document = document
            self.documentVersion = version
            self.textView.diagnostics = diagnostics
            if self.diagnostics != diagnostics { self.diagnostics = diagnostics }
        }
    }

    nonisolated private static func validate(_ text: String) -> (JSONCDocument, [SettingsDiagnostic]) {
        let document = JSONCDocument(text)
        let diagnostics = SettingsValidator.diagnostics(for: document, extraChecks: JSONColorChecks.extraChecks)
        return (document, JSONColorChecks.refine(diagnostics, in: document))
    }

    /// The parsed current text (reparsing when the last parse is stale).
    private var currentDocument: JSONCDocument {
        if let document, documentVersion == textVersion { return document }
        let parsed = JSONCDocument(textView.string)
        document = parsed
        documentVersion = textVersion
        return parsed
    }

    /// The format of new text: the file's indentation and line breaks.
    private var format: JSONCFormat { JSONCFormat(detectingIn: currentDocument) }

    // MARK: Completion

    /// Opens (or refreshes) the completion list at the caret. With
    /// `explicit` (⌃Space) it also opens where typing wouldn't.
    func updateCompletion(explicit: Bool = false, reopen: Bool = false) {
        let selection = textView.selectedRange()
        guard selection.length == 0 || explicit || reopen else { return closeCompletion() }
        let document = currentDocument
        let context = SettingsCompletion.context(in: document, at: selection.location)
        guard let replaceRange = JSONCompletionModel.replaceRange(of: context) else { return closeCompletion() }
        if let current = completion, !explicit, !reopen {
            // Stay open only while typing in the same spot.
            let between = NSRange(location: min(current.replaceStart, replaceRange.location),
                                  length: abs(current.replaceStart - replaceRange.location))
            let skipped = (textView.string as NSString).substring(with: between)
            guard skipped.allSatisfy(\.isWhitespace) else { return closeCompletion() }
        }
        let all = JSONCompletionModel.items(for: context, suggestions: suggestions) { [theme] token in
            theme?.color(token).hex
        }
        let items = JSONCompletionModel.filtered(all, for: context)
        guard !items.isEmpty else { return closeCompletion() }
        guard let rect = textView.rect(forCharacterRange: NSRange(location: replaceRange.location, length: 0)) else {
            return closeCompletion()
        }
        let anchor = editorPane.convert(rect, from: textView)
        var selected = 0
        if let current = completion, let item = current.selectedItem, let index = items.firstIndex(where: { $0.id == item.id }) {
            selected = index
        } else if let index = items.firstIndex(where: \.isDefault), JSONCompletionModel.prefix(of: context).isEmpty {
            selected = index
        }
        completion = JSONCompletionState(items: items, selectedIndex: selected, anchor: anchor, replaceStart: replaceRange.location)
    }

    func closeCompletion() {
        if completion != nil { completion = nil }
    }

    func selectCompletion(_ index: Int) {
        guard var state = completion, state.items.indices.contains(index) else { return }
        state.selectedIndex = index
        completion = state
    }

    private func moveCompletionSelection(by offset: Int) {
        guard var state = completion, !state.items.isEmpty else { return }
        let count = state.items.count
        let next = state.selectedIndex + offset
        if abs(offset) == 1 {
            state.selectedIndex = (next % count + count) % count
        } else {
            state.selectedIndex = min(max(0, next), count - 1)
        }
        completion = state
    }

    /// Inserts the item at `index` (Return, Tab or a click).
    func acceptCompletion(at index: Int? = nil) {
        guard let state = completion else { return }
        let index = index ?? state.selectedIndex
        guard state.items.indices.contains(index) else { return }
        let item = state.items[index]
        closeCompletion()
        let (edits, selection) = JSONCompletionModel.acceptance(of: item, in: textView.string as NSString)
        applyEdits(edits, selecting: selection, actionName: "Insert Completion")
        focusEditor()
        // A key went in with its value: offer the values next when there's
        // a choice (enum values, true/false, themes, site rules…).
        if JSONCompletionModel.offersValues(after: item) {
            updateCompletion(reopen: true)
        }
    }

    // MARK: Hover

    private func hoverChanged(in view: JSONCodeTextView, point: NSPoint?, characterIndex: Int?) {
        let pane: JSONHoverState.Pane = view === textView ? .editor : .defaults
        let paneView = pane == .editor ? editorPane : defaultsPane
        if let point, let frame = hoverCardFrame, hover?.pane == pane,
           frame.insetBy(dx: -4, dy: -4).contains(paneView.convert(point, from: view))
        {
            return // on the card itself
        }
        if pane == .defaults { updateDefaultsKeyHover(point: point) }
        guard let point, let index = characterIndex, completion == nil else {
            hideHover()
            return
        }
        let target = hoverRange(in: view, at: index)
        guard let target else {
            hideHover()
            return
        }
        if target == hoverTarget, hover != nil || hoverTask != nil { return }
        hideHover()
        hoverTarget = target
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, let self else { return }
            self.hoverTask = nil
            self.showHover(in: view, pane: pane, range: target, at: index, point: point)
        }
    }

    /// The span a hover is about at `index`: the problem under it, or the key.
    private func hoverRange(in view: JSONCodeTextView, at index: Int) -> NSRange? {
        if view === textView, let problem = textView.diagnostics.first(where: { NSLocationInRange(index, $0.range) }) {
            return problem.range
        }
        let document = view === textView ? currentDocument : defaultsDocument
        return SettingsCompletion.hover(in: document, at: index)?.range
    }

    private func showHover(in view: JSONCodeTextView, pane: JSONHoverState.Pane, range: NSRange, at index: Int, point: NSPoint) {
        let document = view === textView ? currentDocument : defaultsDocument
        let problems = view === textView ? textView.diagnostics.filter { NSLocationInRange(index, $0.range) } : []
        var docs: JSONHoverDocs?
        if let info = SettingsCompletion.hover(in: document, at: index) {
            if info.isSetting, let descriptor = info.descriptor {
                docs = JSONHoverDocs(descriptor: descriptor, isModified: store?.value(forKey: descriptor.key) != nil)
            } else if !info.isSetting, info.path.first == JSONColorChecks.settingKey {
                docs = JSONHoverDocs(themeToken: info.key)
            }
        }
        guard docs != nil || !problems.isEmpty else { return }
        let quickFix = problems.first { $0.kind == .unknownKey && $0.suggestedKey != nil }.flatMap { problem in
            problem.suggestedKey.map { JSONHoverState.QuickFix(range: problem.range, key: $0) }
        }
        let paneView = pane == .editor ? editorPane : defaultsPane
        let rect = view.rect(forCharacterRange: range) ?? NSRect(origin: point, size: .zero)
        hover = JSONHoverState(pane: pane, anchor: paneView.convert(rect, from: view), docs: docs, problems: problems, quickFix: quickFix)
    }

    func hideHover() {
        hoverTask?.cancel()
        hoverTask = nil
        hoverTarget = nil
        hoverCardFrame = nil
        if hover != nil { hover = nil }
    }

    /// "Change to “…”" on an unknown key.
    func applyQuickFix(_ fix: JSONHoverState.QuickFix) {
        hideHover()
        let quoted = JSONCEditing.quote(fix.key)
        applyEdits([JSONCEdit(range: fix.range, replacement: quoted)],
                   selecting: NSRange(location: fix.range.location + quoted.utf16.count, length: 0),
                   actionName: "Change Setting Name")
        focusEditor()
    }

    private func updateDefaultsKeyHover(point: NSPoint?) {
        guard let point, let layoutManager = defaultsTextView.layoutManager, let container = defaultsTextView.textContainer else {
            if defaultsKeyHover != nil { defaultsKeyHover = nil }
            return
        }
        let origin = defaultsTextView.textContainerOrigin
        let containerPoint = NSPoint(x: 0, y: point.y - origin.y)
        let glyph = layoutManager.glyphIndex(for: containerPoint, in: container)
        let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let character = layoutManager.characterIndexForGlyph(at: glyph)
        let line = defaultsLineIndex.line(containing: character)
        guard fragment.minY - 2 <= containerPoint.y, containerPoint.y <= fragment.maxY + 2,
              let property = defaultsKeysByLine[line]
        else {
            if defaultsKeyHover != nil { defaultsKeyHover = nil }
            return
        }
        let lineRect = NSRect(x: 0, y: fragment.minY + origin.y, width: defaultsTextView.bounds.width, height: fragment.height)
        let converted = defaultsPane.convert(lineRect, from: defaultsTextView)
        let textStart = defaultsPane.convert(NSPoint(x: origin.x, y: 0), from: defaultsTextView).x
        let next = JSONDefaultsKeyHover(key: property.key, lineRect: converted, textStart: textStart)
        if defaultsKeyHover != next { defaultsKeyHover = next }
    }

    /// Shows the hover card for `offset` right away (demo snapshots).
    func showHoverForSnapshot(at offset: Int) {
        guard let range = hoverRange(in: textView, at: offset) else { return }
        let point = textView.rect(forCharacterRange: range)?.origin ?? .zero
        showHover(in: textView, pane: .editor, range: range, at: offset, point: point)
    }

    /// Shows the defaults pane's ✎ on `key`'s line (demo snapshots).
    func showDefaultsKeyForSnapshot(_ key: String) {
        guard let property = defaultsDocument.root?.lastProperty(named: key),
              let rect = defaultsTextView.rect(forCharacterRange: NSRange(location: property.keyRange.location, length: 0))
        else { return }
        updateDefaultsKeyHover(point: NSPoint(x: rect.midX, y: rect.midY))
        let point = NSPoint(x: rect.maxX + 4, y: rect.midY)
        showHover(in: defaultsTextView, pane: .defaults, range: property.keyRange, at: property.keyRange.location + 1, point: point)
    }

    /// "Ln 12, Col 5" for a problem.
    func lineAndColumn(of offset: Int) -> (line: Int, column: Int) {
        let line = lineIndex.line(containing: offset)
        return (line + 1, offset - lineIndex.start(ofLine: line) + 1)
    }

    // MARK: Caret

    private func updateCaretPosition() {
        let location = textView.selectedRange().location
        let line = lineIndex.line(containing: location)
        let column = location - lineIndex.start(ofLine: line) + 1
        if caretLine != line + 1 { caretLine = line + 1 }
        if caretColumn != column { caretColumn = column }
    }

    @objc private func paneScrolled(_ notification: Notification) {
        hideHover()
        if notification.object as? NSClipView === defaultsPane.scrollView.contentView {
            defaultsKeyHover = nil
        } else if completion != nil {
            updateCompletion(reopen: true)
        }
    }
}

// MARK: - Text view delegate

extension SettingsJSONSession: NSTextViewDelegate, NSTextStorageDelegate {
    func undoManager(for view: NSTextView) -> UndoManager? {
        view === textView ? undoManager : nil
    }

    nonisolated func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        MainActor.assumeIsolated {
            pendingEdits.append((editedRange, delta))
        }
    }

    func textDidChange(_ notification: Notification) {
        guard notification.object as? NSTextView === textView else { return }
        processEdits()
        if completion != nil { updateCompletion() }
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard notification.object as? NSTextView === textView else { return }
        updateCaretPosition()
        // Edits update the list in textDidChange; this is for caret moves.
        if completion != nil, pendingEdits.isEmpty { updateCompletion() }
    }

    func textView(_ view: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard view === textView else { return false }
        if completion != nil {
            switch selector {
            case #selector(NSResponder.moveDown(_:)): moveCompletionSelection(by: 1); return true
            case #selector(NSResponder.moveUp(_:)): moveCompletionSelection(by: -1); return true
            case #selector(NSResponder.pageDown(_:)), #selector(NSResponder.scrollPageDown(_:)): moveCompletionSelection(by: 8); return true
            case #selector(NSResponder.pageUp(_:)), #selector(NSResponder.scrollPageUp(_:)): moveCompletionSelection(by: -8); return true
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)): acceptCompletion(); return true
            case #selector(NSResponder.cancelOperation(_:)): closeCompletion(); return true
            case #selector(NSResponder.moveLeft(_:)), #selector(NSResponder.moveRight(_:)),
                 #selector(NSResponder.moveToBeginningOfLine(_:)), #selector(NSResponder.moveToEndOfLine(_:)):
                closeCompletion()
                return false
            default:
                break
            }
        }
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            let format = format
            let (text, caret) = JSONTyping.newline(
                in: textView.string as NSString, selection: textView.selectedRange(),
                indentUnit: format.indent, lineEnding: format.lineEnding
            )
            let range = textView.selectedRange()
            guard textView.shouldChangeText(in: range, replacementString: text) else { return true }
            textView.textStorage?.replaceCharacters(in: range, with: text)
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: range.location + caret, length: 0))
            textView.scrollRangeToVisible(textView.selectedRange())
            return true
        case #selector(NSResponder.insertTab(_:)):
            textView.insertText(format.indent, replacementRange: textView.selectedRange())
            return true
        case #selector(NSResponder.insertBacktab(_:)):
            let ranges = JSONTyping.outdentRanges(in: textView.string as NSString, selection: textView.selectedRange(), indentUnit: format.indent)
            let selection = textView.selectedRange()
            let removedBefore = ranges.filter { $0.location < selection.location }.reduce(0) { $0 + $1.length }
            applyEdits(ranges.map(JSONCEdit.delete), selecting: NSRange(location: max(0, selection.location - removedBefore), length: selection.length), actionName: "Outdent")
            return true
        default:
            return false
        }
    }
}

// MARK: - Code view owner

extension SettingsJSONSession: JSONCodeTextViewOwner {
    func codeViewRequestsCompletion(_ view: JSONCodeTextView) {
        guard view === textView else { return }
        hideHover()
        updateCompletion(explicit: true)
    }

    func codeViewCancel(_ view: JSONCodeTextView) -> Bool {
        if completion != nil {
            closeCompletion()
            return true
        }
        if hover != nil {
            hideHover()
            return true
        }
        return false
    }

    func codeView(_ view: JSONCodeTextView, pointerAt point: NSPoint?, characterIndex: Int?) {
        hoverChanged(in: view, point: point, characterIndex: characterIndex)
    }

    func codeViewDidResignFocus(_ view: JSONCodeTextView) {
        guard view === textView else { return }
        // A click in the list moves focus only after the item is taken.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.textView.window?.firstResponder !== self.textView else { return }
            self.closeCompletion()
        }
    }

    func codeViewDidMoveToWindow(_ view: JSONCodeTextView) {
        guard view === textView else { return }
        if view.window == nil { closeCompletion(); hideHover() }
        updateCloseGuard()
    }

    func codeView(_ view: JSONCodeTextView, didType text: String) {
        guard view === textView else { return }
        if completion != nil {
            updateCompletion()
            return
        }
        // Most keystrokes can't open the list; skip parsing the file for them.
        let caret = textView.selectedRange().location
        guard JSONTyping.mightOpenCompletion(afterTyping: text, in: textView.string as NSString, at: caret) else { return }
        let context = SettingsCompletion.context(in: currentDocument, at: caret)
        if JSONCompletionModel.shouldOpen(afterTyping: text, context: context) {
            updateCompletion(reopen: true)
        }
    }

    func lineIndex(for view: JSONCodeTextView) -> JSONLineIndex {
        view === textView ? lineIndex : defaultsLineIndex
    }
}

// MARK: - Pane view

/// A flipped container holding a code view's scroll view, so popups and
/// cards can be placed over it in SwiftUI coordinates.
final class JSONPaneView: NSView {
    let scrollView: NSScrollView
    let textView: JSONCodeTextView

    init(editable: Bool) {
        (textView, scrollView) = JSONCodeTextView.make(editable: editable)
        super.init(frame: .zero)
        scrollView.translatesAutoresizingMaskIntoConstraints = true
        scrollView.autoresizingMask = [.width, .height]
        scrollView.frame = bounds
        addSubview(scrollView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
    }
}
