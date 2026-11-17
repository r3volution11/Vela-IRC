// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Observation
import SwiftUI
import VelaTheme

// A text field with a suggestions dropdown, for the settings editor's token
// fields and search. The field is an `NSTextField` so ↑/↓, Return, Tab, Esc
// and ⌫ arrive as field-editor commands, whatever the key bindings (the
// command palette's search field works the same way). The dropdown is a
// small child panel that never takes focus, so typing continues in the
// field while it's open, and it isn't clipped by the scroll view.

/// Where the suggestions dropdown hangs: under the view this is attached to
/// with ``SwiftUI/View/suggestionAnchor(_:)``, as wide as it.
@MainActor
final class SuggestionAnchor {
    fileprivate weak var view: NSView?
}

extension View {
    /// Hangs the dropdown of a ``SuggestionTextField`` using `anchor` under
    /// this view (a token field's whole box rather than its text field).
    func suggestionAnchor(_ anchor: SuggestionAnchor) -> some View {
        background(SuggestionAnchorView(anchor: anchor))
    }
}

private struct SuggestionAnchorView: NSViewRepresentable {
    let anchor: SuggestionAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        anchor.view = view
    }
}

/// A borderless text field (the surrounding SwiftUI view draws the box)
/// that offers `suggestions` in a dropdown.
///
/// - ↓ opens the dropdown and moves through it, ↑ moves back.
/// - Return picks the highlighted suggestion, or calls `onSubmit`.
/// - Tab picks the highlighted suggestion, or moves focus as usual.
/// - Esc closes the dropdown, then calls `onCancel`.
/// - ⌫ in an empty field calls `onDeleteBackwardWhenEmpty`.
struct SuggestionTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var accessibilityLabel: String
    /// What to offer for the current text, already filtered.
    var suggestions: [TokenSuggestion] = []
    /// The suggestion Return picks before any arrowing
    /// (``TokenFieldModel/autoHighlight(query:in:)``).
    var autoHighlight: Int?
    /// Open the dropdown as soon as the field has focus, before typing.
    var showsOnFocus = false
    var anchor: SuggestionAnchor?
    var monospaced = false
    var fontSize: CGFloat = 13
    /// Bump to move keyboard focus here.
    var focusRequest = 0
    var onPick: (TokenSuggestion) -> Void = { _ in }
    var onSubmit: () -> Void = {}
    var onDeleteBackwardWhenEmpty: () -> Void = {}
    /// Esc with the dropdown closed; return true when handled.
    var onCancel: () -> Bool = { false }
    var onFocusChange: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> SuggestionNSTextField {
        let field = SuggestionNSTextField()
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
        field.onFocusChange = { [weak coordinator = context.coordinator] focused in
            coordinator?.focusChanged(focused)
        }
        context.coordinator.field = field
        context.coordinator.lastFocusRequest = focusRequest
        apply(to: field, theme: context.environment.theme)
        return field
    }

    func updateNSView(_ field: SuggestionNSTextField, context: Context) {
        let coordinator = context.coordinator
        let suggestionsChanged = coordinator.parent.suggestions.map(\.id) != suggestions.map(\.id)
        coordinator.parent = self
        coordinator.theme = context.environment.theme
        let isComposing = (field.currentEditor() as? NSTextView)?.hasMarkedText() ?? false
        if field.stringValue != text, !isComposing {
            field.stringValue = text
            if let editor = field.currentEditor() {
                editor.selectedRange = NSRange(location: (text as NSString).length, length: 0)
            }
        }
        apply(to: field, theme: context.environment.theme)
        if suggestionsChanged {
            coordinator.highlighted = autoHighlight
        }
        if focusRequest != coordinator.lastFocusRequest {
            coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async { [weak field] in field?.takeFocus() }
        }
        coordinator.refreshDropdown()
    }

    static func dismantleNSView(_ field: SuggestionNSTextField, coordinator: Coordinator) {
        coordinator.dropdown.hide()
    }

    private func apply(to field: SuggestionNSTextField, theme: ResolvedTheme) {
        let font = monospaced
            ? NSFont.monospacedSystemFont(ofSize: fontSize - 0.5, weight: .regular)
            : NSFont.systemFont(ofSize: fontSize)
        let foreground = theme.color(ThemeKey.settingsForeground).nsColor
        if field.font != font { field.font = font }
        if field.textColor != foreground { field.textColor = foreground }
        field.caretColor = foreground
        field.selectionColor = theme.color(ThemeKey.chatSelectionBackground).nsColor
        let placeholderColor = theme.color(ThemeKey.settingsSecondaryForeground).withAlpha(0.75).nsColor
        if field.placeholderAttributedString?.string != placeholder || field.placeholderColor != placeholderColor {
            field.placeholderColor = placeholderColor
            field.placeholderAttributedString = NSAttributedString(
                string: placeholder,
                attributes: [.font: font, .foregroundColor: placeholderColor]
            )
        }
        field.setAccessibilityLabel(accessibilityLabel)
        field.applyEditorColors()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SuggestionTextField
        weak var field: SuggestionNSTextField?
        var theme: ResolvedTheme = .fallbackDark
        let dropdown = SuggestionDropdown()

        var lastFocusRequest = 0
        var isFocused = false
        /// The highlighted row, if any.
        var highlighted: Int?
        /// Closed with Esc or by a pick, until the text changes or ↓.
        var dismissed = false
        /// Opened with ↓ while empty.
        var opened = false

        init(parent: SuggestionTextField) {
            self.parent = parent
        }

        private var isDropdownVisible: Bool {
            isFocused && !parent.suggestions.isEmpty && !dismissed
                && (parent.showsOnFocus || opened || !parent.text.isEmpty)
        }

        func refreshDropdown() {
            let items = parent.suggestions
            if let highlighted, !items.indices.contains(highlighted) { self.highlighted = nil }
            let anchorView: NSView? = parent.anchor?.view ?? field
            guard isDropdownVisible, let anchor = anchorView else {
                dropdown.hide()
                return
            }
            dropdown.show(items: items, highlighted: highlighted, below: anchor, theme: theme) { [weak self] index in
                self?.pick(index)
            }
        }

        func focusChanged(_ focused: Bool) {
            guard focused != isFocused else { return }
            isFocused = focused
            if !focused {
                dismissed = false
                opened = false
            }
            refreshDropdown()
            let report = parent.onFocusChange
            // Focus can change during a SwiftUI update.
            DispatchQueue.main.async { report(focused) }
        }

        private func pick(_ index: Int) {
            let items = parent.suggestions
            guard items.indices.contains(index) else { return }
            dismissed = true
            opened = false
            highlighted = nil
            refreshDropdown()
            parent.onPick(items[index])
        }

        private func move(by offset: Int) {
            let count = parent.suggestions.count
            guard count > 0 else { return }
            let next: Int
            if let highlighted {
                next = min(count - 1, max(0, highlighted + offset))
            } else {
                next = offset > 0 ? 0 : count - 1
            }
            highlighted = next
            refreshDropdown()
            announce(parent.suggestions[next])
        }

        private func announce(_ suggestion: TokenSuggestion) {
            guard let field else { return }
            let text = [suggestion.label, suggestion.detail].compactMap { $0 }.joined(separator: ", ")
            NSAccessibility.post(
                element: field,
                notification: .announcementRequested,
                userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue]
            )
        }

        // MARK: NSTextFieldDelegate

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let value = field.stringValue
            dismissed = false
            guard parent.text != value else { return }
            parent.text = value
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveDown(_:)):
                guard !parent.suggestions.isEmpty else { return false }
                if !isDropdownVisible {
                    dismissed = false
                    opened = true
                    highlighted = nil
                }
                move(by: 1)
                return true
            case #selector(NSResponder.moveUp(_:)):
                guard isDropdownVisible else { return false }
                move(by: -1)
                return true
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                if isDropdownVisible, let highlighted {
                    pick(highlighted)
                } else {
                    parent.onSubmit()
                }
                return true
            case #selector(NSResponder.insertTab(_:)):
                if isDropdownVisible, let highlighted {
                    pick(highlighted)
                    return true
                }
                return false
            case #selector(NSResponder.cancelOperation(_:)):
                if isDropdownVisible {
                    dismissed = true
                    refreshDropdown()
                    return true
                }
                return parent.onCancel()
            case #selector(NSResponder.deleteBackward(_:)):
                guard textView.string.isEmpty, textView.selectedRange().location == 0 else { return false }
                parent.onDeleteBackwardWhenEmpty()
                return true
            default:
                return false
            }
        }
    }
}

/// Reports focus, takes focus on request, and colors its field editor.
final class SuggestionNSTextField: NSTextField {
    var onFocusChange: ((Bool) -> Void)?
    var caretColor: NSColor = .textColor
    var selectionColor: NSColor = .selectedTextBackgroundColor
    var placeholderColor: NSColor?

    /// Asked for focus before joining a window; taken on arrival.
    private var wantsFocus = false

    func takeFocus() {
        guard let window else {
            wantsFocus = true
            return
        }
        wantsFocus = false
        guard window.firstResponder !== currentEditor() else { return }
        window.makeFirstResponder(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard wantsFocus, window != nil else { return }
        DispatchQueue.main.async { [weak self] in self?.takeFocus() }
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            applyEditorColors()
            onFocusChange?(true)
        }
        return accepted
    }

    /// Sent when focus leaves the field editor, changed text or not.
    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        onFocusChange?(false)
    }

    func applyEditorColors() {
        guard let editor = currentEditor() as? NSTextView else { return }
        editor.insertionPointColor = caretColor
        editor.selectedTextAttributes = [.backgroundColor: selectionColor, .foregroundColor: textColor ?? .textColor]
    }
}

// MARK: - Dropdown

/// The suggestions list in a child panel under the anchor. It never
/// becomes key, so the text field keeps focus; it closes when the list
/// scrolls, the window resizes or loses focus.
@MainActor
final class SuggestionDropdown {
    private var panel: SuggestionPanel?
    private let model = SuggestionListModel()
    private var observers: [NSObjectProtocol] = []

    static let rowHeight: CGFloat = 24
    static let maximumVisibleRows = 8
    static let padding: CGFloat = 4

    func show(items: [TokenSuggestion], highlighted: Int?, below anchor: NSView, theme: ResolvedTheme, onPick: @escaping (Int) -> Void) {
        guard let window = anchor.window else {
            hide()
            return
        }
        model.items = items
        model.highlighted = highlighted
        model.theme = theme
        model.onPick = onPick

        let panel = self.panel ?? makePanel()
        panel.appearance = NSAppearance(named: theme.appearanceName)
        let anchorRect = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let rows = CGFloat(min(items.count, Self.maximumVisibleRows))
        let height = rows * Self.rowHeight + Self.padding * 2
        let width = max(anchorRect.width, 240)
        var origin = NSPoint(x: anchorRect.minX, y: anchorRect.minY - height - 3)
        if let screen = window.screen ?? NSScreen.main, origin.y < screen.visibleFrame.minY {
            origin.y = anchorRect.maxY + 3
        }
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
        if panel.parent !== window {
            panel.parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
            observe(window: window, anchor: anchor)
        }
        panel.orderFront(nil)
    }

    func hide() {
        removeObservers()
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    private func makePanel() -> SuggestionPanel {
        let panel = SuggestionPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.hidesOnDeactivate = true
        panel.becomesKeyOnlyIfNeeded = true
        let hosting = FirstMouseHostingView(rootView: SuggestionListView(model: model))
        hosting.sizingOptions = []
        panel.contentView = hosting
        self.panel = panel
        return panel
    }

    private func observe(window: NSWindow, anchor: NSView) {
        removeObservers()
        let center = NotificationCenter.default
        let close: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
        observers = [
            center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main, using: close),
            center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main, using: close),
            center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main, using: close),
        ]
        // Scrolling the list moves the field away from the dropdown.
        var view: NSView? = anchor.superview
        while let current = view {
            if let scrollView = current as? NSScrollView {
                scrollView.contentView.postsBoundsChangedNotifications = true
                observers.append(center.addObserver(
                    forName: NSView.boundsDidChangeNotification,
                    object: scrollView.contentView,
                    queue: .main,
                    using: close
                ))
            }
            view = current.superview
        }
    }

    private func removeObservers() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }
}

private final class SuggestionPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Clicks land on the first try, though the panel never becomes key.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@Observable
private final class SuggestionListModel {
    var items: [TokenSuggestion] = []
    var highlighted: Int?
    var theme: ResolvedTheme = .fallbackDark
    @ObservationIgnored var onPick: (Int) -> Void = { _ in }
}

private struct SuggestionListView: View {
    let model: SuggestionListModel
    @State private var hovered: Int?

    var body: some View {
        let theme = model.theme
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        row(item, index: index, theme: theme)
                            .id(index)
                    }
                }
                .padding(SuggestionDropdown.padding)
            }
            .scrollIndicators(.automatic)
            .onChange(of: model.highlighted) { _, index in
                if let index { proxy.scrollTo(index) }
            }
        }
        .background(shape.fill(theme[ThemeKey.popoverBackground]))
        .overlay(shape.strokeBorder(theme[ThemeKey.popoverBorder]))
        .clipShape(shape)
        .environment(\.colorScheme, theme.colorScheme)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggestions")
    }

    private func row(_ item: TokenSuggestion, index: Int, theme: ResolvedTheme) -> some View {
        let isHighlighted = model.highlighted == index
        let foreground = isHighlighted ? theme[ThemeKey.accentForeground] : theme[ThemeKey.popoverForeground]
        return Button {
            model.onPick(index)
        } label: {
            HStack(spacing: 8) {
                Text(item.label)
                    .font(item.previewFontFamily.map { .custom($0, size: 13) } ?? .system(size: 13))
                    .foregroundStyle(foreground)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                if let detail = item.detail {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(foreground.opacity(0.7))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: SuggestionDropdown.rowHeight)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isHighlighted ? theme[ThemeKey.accent] : (hovered == index ? theme[ThemeKey.popoverForeground].opacity(0.08) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? index : (hovered == index ? nil : hovered) }
        .accessibilityLabel([item.label, item.detail].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(isHighlighted ? [.isButton, .isSelected] : .isButton)
    }
}
