// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaFoundation
import VelaStore
import VelaTheme

// Building blocks shared by the Settings panes, the network editor and the
// theme editor. Everything is drawn from `settings.*` theme tokens.

// MARK: - Page

/// A scrolling settings page: large title, optional subtitle, then sections.
///
/// With `pane`, the title gets a "Show in settings editor" link that opens
/// Advanced filtered to that pane's settings (when it has any in
/// settings.json).
struct SettingsPage<Content: View>: View {
    @Environment(\.theme) private var theme
    @Environment(UIState.self) private var uiState: UIState?
    let title: String
    var subtitle: String?
    var pane: SettingsPane?
    let content: Content

    init(_ title: String, subtitle: String? = nil, pane: SettingsPane? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.pane = pane
        self.content = content()
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    SettingsPageHeader(title: title, subtitle: subtitle, pane: pane)
                    content
                }
                .padding(.horizontal, 28)
                .padding(.top, 14)
                .padding(.bottom, 32)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.automatic)
            .background(theme[ThemeKey.settingsBackground])
            // A section asked for from elsewhere ("Use Your Own Key in
            // Settings" in the GIF picker): scrolled to once it's laid out.
            .onChange(of: uiState?.settingsSectionReveal, initial: true) { _, reveal in
                guard let reveal, let uiState, reveal.pane == pane else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(80))
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(reveal.section, anchor: .top) }
                    if uiState.settingsSectionReveal == reveal { uiState.settingsSectionReveal = nil }
                }
            }
        }
    }
}

/// A settings page's large title and subtitle, plus the "Show in settings
/// editor" link for panes with settings in settings.json.
struct SettingsPageHeader: View {
    @Environment(\.theme) private var theme
    @Environment(UIState.self) private var uiState: UIState?
    let title: String
    var subtitle: String?
    var pane: SettingsPane?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(theme[ThemeKey.settingsForeground])
                    .accessibilityAddTraits(.isHeader)
                if let pane, let uiState, !SettingsCategory.categories(forPane: pane.rawValue).isEmpty {
                    Spacer(minLength: 8)
                    SettingsLinkButton("Show in settings editor", systemImage: "slider.horizontal.3") {
                        uiState.settingsEditor.showInEditor("\(SettingsQuery.panePrefix)\(pane.rawValue)")
                    }
                    .help("See this pane's settings in Advanced, as they're stored in settings.json")
                    .accessibilityHint("Opens Advanced, filtered to the \(pane.title) settings.")
                }
            }
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Sections and cards

/// A titled group of rows drawn on a `settings.controlBackground` card, with
/// hairlines between rows.
struct SettingsSection<Content: View, Accessory: View>: View {
    @Environment(\.theme) private var theme
    let title: String?
    let footer: String?
    let content: Content
    let accessory: Accessory

    init(
        _ title: String? = nil,
        footer: String? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.footer = footer
        self.content = content()
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if title != nil || Accessory.self != EmptyView.self {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let title {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme[ThemeKey.settingsForeground])
                            .accessibilityAddTraits(.isHeader)
                    }
                    Spacer(minLength: 8)
                    accessory
                }
                .padding(.horizontal, 4)
            }
            SettingsCard { content }
            if let footer {
                Text(footer)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

extension SettingsSection where Accessory == EmptyView {
    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title, footer: footer, content: content, accessory: { EmptyView() })
    }
}

/// A rounded card that separates its direct children with hairlines.
struct SettingsCard<Content: View>: View {
    @Environment(\.theme) private var theme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group(subviews: content) { subviews in
                ForEach(subviews) { subview in
                    if subview.id != subviews.first?.id {
                        SettingsHairline().padding(.leading, 14)
                    }
                    subview
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme[ThemeKey.settingsControlBackground])
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(theme[ThemeKey.settingsBorder])
        )
    }
}

/// A 1-pt `settings.border` line.
struct SettingsHairline: View {
    @Environment(\.theme) private var theme
    var vertical = false

    var body: some View {
        Rectangle()
            .fill(theme[ThemeKey.settingsBorder])
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
            .accessibilityHidden(true)
    }
}

// MARK: - Rows

/// Title and optional explanation on the left, a control on the right.
struct SettingsRow<Control: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    var detail: String?
    /// Hide the row's texts from VoiceOver because the control carries the
    /// same label (and the detail as its hint).
    var labelsControl = false
    let control: Control

    init(_ title: String, detail: String? = nil, labelsControl: Bool = false, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.labelsControl = labelsControl
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(theme[ThemeKey.settingsForeground])
                if let detail {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(labelsControl)
            control
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(minHeight: 40)
    }
}

/// A switch bound to a setting.
struct SettingsToggle: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool

    init(_ title: String, detail: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        _isOn = isOn
    }

    var body: some View {
        SettingsRow(title, detail: detail, labelsControl: true) {
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .accessibilityHint(detail ?? "")
        }
    }
}

/// A slider with a live value readout. Values snap to `step` without the
/// tick marks a stepped `Slider` draws on macOS.
struct SettingsSliderRow: View {
    @Environment(\.theme) private var theme
    let title: String
    var detail: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var minimumLabel: String?
    var maximumLabel: String?
    var width: CGFloat = 170
    var format: (Double) -> String = { "\(Int($0.rounded())) pt" }

    var body: some View {
        SettingsRow(title, detail: detail, labelsControl: true) {
            HStack(spacing: 8) {
                if let minimumLabel { sideLabel(minimumLabel) }
                Slider(value: snapped, in: range) { Text(title) }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: width)
                    .accessibilityValue(format(value))
                    .accessibilityHint(detail ?? "")
                if let maximumLabel { sideLabel(maximumLabel) }
                Text(format(value))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    .frame(minWidth: 50, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        }
    }

    private var snapped: Binding<Double> {
        Binding(
            get: { min(range.upperBound, max(range.lowerBound, value)) },
            set: { newValue in
                let rounded = step > 0 ? (newValue / step).rounded() * step : newValue
                let clamped = min(range.upperBound, max(range.lowerBound, rounded))
                if abs(clamped - value) > 0.0001 { value = clamped }
            }
        )
    }

    private func sideLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
            .fixedSize()
            .accessibilityHidden(true)
    }
}

/// A segmented picker row.
struct SettingsSegmentedRow<Value: Hashable>: View {
    let title: String
    var detail: String?
    @Binding var selection: Value
    let options: [(value: Value, label: String)]

    var body: some View {
        SettingsRow(title, detail: detail, labelsControl: true) {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize()
            .accessibilityHint(detail ?? "")
        }
    }
}

/// A pop-up menu picker row.
struct SettingsMenuRow<Value: Hashable>: View {
    let title: String
    var detail: String?
    @Binding var selection: Value
    let options: [(value: Value, label: String)]

    var body: some View {
        SettingsRow(title, detail: detail, labelsControl: true) {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .accessibilityHint(detail ?? "")
        }
    }
}

// MARK: - Text fields

/// A plain text field drawn with theme tokens, with an accent focus ring.
struct ThemedTextField: View {
    @Environment(\.theme) private var theme
    let placeholder: String
    @Binding var text: String
    var isSecure = false
    var monospaced = false
    var accessibilityName: String?
    var onSubmit: () -> Void = {}

    @FocusState private var isFocused: Bool

    init(
        _ placeholder: String,
        text: Binding<String>,
        isSecure: Bool = false,
        monospaced: Bool = false,
        accessibilityName: String? = nil,
        onSubmit: @escaping () -> Void = {}
    ) {
        self.placeholder = placeholder
        _text = text
        self.isSecure = isSecure
        self.monospaced = monospaced
        self.accessibilityName = accessibilityName
        self.onSubmit = onSubmit
    }

    var body: some View {
        Group {
            if isSecure {
                SecureField(accessibilityName ?? placeholder, text: $text, prompt: prompt)
            } else {
                TextField(accessibilityName ?? placeholder, text: $text, prompt: prompt)
            }
        }
        .textFieldStyle(.plain)
        .font(monospaced ? .system(size: 12.5, design: .monospaced) : .system(size: 13))
        .foregroundStyle(theme[ThemeKey.settingsForeground])
        .focused($isFocused)
        .onSubmit(onSubmit)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(theme[ThemeKey.settingsBackground])
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(
                    isFocused ? theme[ThemeKey.focusBorder] : theme[ThemeKey.settingsBorder],
                    lineWidth: isFocused ? 1.5 : 1
                )
        )
    }

    private var prompt: Text {
        Text(placeholder).foregroundStyle(theme[ThemeKey.settingsSecondaryForeground].opacity(0.75))
    }
}

/// A multi-line plain text editor drawn with theme tokens.
///
/// With `checksText: false`, macOS leaves the text alone: no spelling
/// underlines, autocorrect, text replacements, smart quotes or dashes, or
/// Writing Tools. Use it for text that holds IRC commands or JSON.
struct ThemedTextEditor: View {
    @Environment(\.theme) private var theme
    @Binding var text: String
    var placeholder: String
    var accessibilityName: String
    var minHeight: CGFloat = 70
    var checksText = true

    @FocusState private var isFocused: Bool
    /// Focus of the unchecked editor, which SwiftUI's focus doesn't see.
    @State private var plainEditorFocused = false

    init(
        text: Binding<String>,
        placeholder: String,
        accessibilityName: String,
        minHeight: CGFloat = 70,
        checksText: Bool = true
    ) {
        _text = text
        self.placeholder = placeholder
        self.accessibilityName = accessibilityName
        self.minHeight = minHeight
        self.checksText = checksText
    }

    var body: some View {
        let focused = checksText ? isFocused : plainEditorFocused
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground].opacity(0.75))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            if checksText {
                TextEditor(text: $text)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(theme[ThemeKey.settingsForeground])
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
                    .accessibilityLabel(accessibilityName)
            } else {
                UncheckedTextView(
                    text: $text,
                    isFocused: $plainEditorFocused,
                    font: .monospacedSystemFont(ofSize: 12.5, weight: .regular),
                    textColor: theme.color(ThemeKey.settingsForeground).nsColor,
                    accessibilityName: accessibilityName
                )
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
            }
        }
        .frame(minHeight: minHeight)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(theme[ThemeKey.settingsBackground])
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(
                    focused ? theme[ThemeKey.focusBorder] : theme[ThemeKey.settingsBorder],
                    lineWidth: focused ? 1.5 : 1
                )
        )
    }
}

/// A plain `NSTextView` with every kind of macOS text checking off, for
/// ``ThemedTextEditor``'s `checksText: false`.
private struct UncheckedTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let font: NSFont
    let textColor: NSColor
    let accessibilityName: String

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let textView = FocusReportingTextView(usingTextLayoutManager: false)
        textView.frame = NSRect(origin: .zero, size: scrollView.contentSize)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 0, height: 1)
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = false
        textView.usesFontPanel = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.writingToolsBehavior = .none
        textView.inlinePredictionType = .no
        textView.focusRingType = .none
        textView.delegate = context.coordinator
        textView.onFocusChange = { [weak coordinator = context.coordinator] focused in
            coordinator?.focusChanged(focused)
        }
        scrollView.documentView = textView
        context.coordinator.textView = textView
        apply(to: textView)
        textView.string = text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
        apply(to: textView)
        if textView.string != text, !textView.hasMarkedText() {
            textView.string = text
        }
    }

    private func apply(to textView: NSTextView) {
        if textView.font != font { textView.font = font }
        if textView.textColor != textColor {
            textView.textColor = textColor
            textView.insertionPointColor = textColor
        }
        textView.typingAttributes = [.font: font, .foregroundColor: textColor]
        textView.setAccessibilityLabel(accessibilityName)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: UncheckedTextView
        weak var textView: NSTextView?

        init(parent: UncheckedTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            if parent.text != textView.string { parent.text = textView.string }
        }

        func focusChanged(_ focused: Bool) {
            let binding = parent.$isFocused
            // Focus can move during a SwiftUI update.
            Task { @MainActor in
                if binding.wrappedValue != focused { binding.wrappedValue = focused }
            }
        }
    }

    final class FocusReportingTextView: NSTextView {
        var onFocusChange: ((Bool) -> Void)?

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
    }
}

// MARK: - List editor

/// An editable list of short strings (domains, highlight words, ignore
/// masks): rows with remove buttons, plus an add field and +/− buttons.
struct StringListEditor: View {
    @Environment(\.theme) private var theme
    @Binding var items: [String]
    let placeholder: String
    /// What the list holds, for VoiceOver ("blocked domain").
    let itemName: String
    var emptyMessage = "Nothing here yet."
    var monospaced = true
    /// Cleans up typed text; return nil to reject it.
    var normalize: (String) -> String? = StringListEditor.trimmed

    @State private var newItem = ""
    @State private var selectedIndex: Int?
    @State private var hoveredIndex: Int?

    init(
        items: Binding<[String]>,
        placeholder: String,
        itemName: String,
        emptyMessage: String = "Nothing here yet.",
        monospaced: Bool = true,
        normalize: @escaping (String) -> String? = StringListEditor.trimmed
    ) {
        _items = items
        self.placeholder = placeholder
        self.itemName = itemName
        self.emptyMessage = emptyMessage
        self.monospaced = monospaced
        self.normalize = normalize
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if items.isEmpty {
                Text(emptyMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            } else {
                ForEach(items.indices, id: \.self) { index in
                    row(index)
                }
            }
            SettingsHairline()
            HStack(spacing: 6) {
                ThemedTextField(placeholder, text: $newItem, monospaced: monospaced, accessibilityName: "New \(itemName)", onSubmit: add)
                Button(action: add) {
                    Image(systemName: "plus")
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(ThemedButtonStyle())
                .themedDisabled(normalize(newItem) == nil)
                .help("Add \(itemName)")
                .accessibilityLabel("Add \(itemName)")
                Button(action: removeSelected) {
                    Image(systemName: "minus")
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(ThemedButtonStyle())
                .themedDisabled(selectedIndex == nil)
                .help("Remove selected \(itemName)")
                .accessibilityLabel("Remove selected \(itemName)")
            }
            .padding(10)
        }
    }

    private func row(_ index: Int) -> some View {
        let item = items[index]
        let isSelected = selectedIndex == index
        return HStack(spacing: 8) {
            Text(item)
                .font(monospaced ? .system(size: 12, design: .monospaced) : .system(size: 13))
                .foregroundStyle(theme[ThemeKey.settingsForeground])
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Button {
                remove(at: index)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
            }
            .buttonStyle(.plain)
            .opacity(hoveredIndex == index || isSelected ? 1 : 0)
            .help("Remove \(item)")
            .accessibilityLabel("Remove \(item)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(isSelected ? theme[ThemeKey.accent].opacity(0.16) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { selectedIndex = isSelected ? nil : index }
        .onHover { hoveredIndex = $0 ? index : (hoveredIndex == index ? nil : hoveredIndex) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction(named: "Remove") { remove(at: index) }
    }

    private func add() {
        guard let value = normalize(newItem) else { return }
        if !items.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) {
            items.append(value)
        }
        newItem = ""
    }

    private func remove(at index: Int) {
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
        selectedIndex = nil
    }

    private func removeSelected() {
        guard let index = selectedIndex else { return }
        remove(at: index)
    }

    nonisolated static func trimmed(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// `https://www.Example.com/path` → `www.example.com`; `*.example.com` → `example.com`.
    nonisolated static func domain(_ text: String) -> String? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let range = value.range(of: "://") { value = String(value[range.upperBound...]) }
        if let slash = value.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) { value = String(value[..<slash]) }
        if let at = value.lastIndex(of: "@") { value = String(value[value.index(after: at)...]) }
        if let colon = value.lastIndex(of: ":") { value = String(value[..<colon]) }
        while value.hasPrefix("*.") || value.hasPrefix(".") { value.removeFirst(value.hasPrefix("*.") ? 2 : 1) }
        while value.hasSuffix(".") { value.removeLast() }
        guard !value.isEmpty, value.contains("."), !value.contains(where: \.isWhitespace) else { return nil }
        return value
    }
}

// MARK: - Choice cards

/// A selectable card with an illustration, used for layout choices.
struct SettingsChoiceCard<Preview: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    var subtitle: String?
    let isSelected: Bool
    let action: () -> Void
    let preview: Preview

    @State private var isHovered = false

    init(
        _ title: String,
        subtitle: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder preview: () -> Preview
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.action = action
        self.preview = preview()
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                preview
                    .frame(maxWidth: .infinity)
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme[ThemeKey.settingsForeground])
                    Spacer(minLength: 4)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(isSelected ? theme[ThemeKey.accent] : theme[ThemeKey.settingsBorder])
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(10)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(theme[ThemeKey.settingsControlBackground])
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? theme[ThemeKey.accent] : theme[ThemeKey.settingsBorder].opacity(isHovered ? 1 : 0.9),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle ?? "")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Callouts

/// An inline message: info, success, warning or error.
struct SettingsCallout<Actions: View>: View {
    @Environment(\.theme) private var theme

    enum Kind {
        case info, success, warning, error

        var systemImage: String {
            switch self {
            case .info: "info.circle.fill"
            case .success: "checkmark.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .error: "xmark.octagon.fill"
            }
        }

        var colorKey: String {
            switch self {
            case .info: ThemeKey.accent
            case .success: ThemeKey.statusSuccess
            case .warning: ThemeKey.statusWarning
            case .error: ThemeKey.statusError
            }
        }
    }

    let kind: Kind
    let title: String
    var message: String?
    let actions: Actions

    init(_ kind: Kind, _ title: String, message: String? = nil, @ViewBuilder actions: () -> Actions) {
        self.kind = kind
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        let tint = theme[kind.colorKey]
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: kind.systemImage)
                .font(.system(size: 14))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme[ThemeKey.settingsForeground])
                    .fixedSize(horizontal: false, vertical: true)
                if let message {
                    Text(message)
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                if Actions.self != EmptyView.self {
                    HStack(spacing: 8) { actions }
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(tint.opacity(0.35)))
        .accessibilityElement(children: .contain)
    }
}

extension SettingsCallout where Actions == EmptyView {
    init(_ kind: Kind, _ title: String, message: String? = nil) {
        self.init(kind, title, message: message, actions: { EmptyView() })
    }
}

// MARK: - Small pieces

/// A small capsule label, e.g. "Active" or "Built-in".
struct SettingsPill: View {
    @Environment(\.theme) private var theme
    let text: String
    /// Solid accent fill.
    var prominent = false
    /// A light accent tint with accent text.
    var tinted = false

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(foreground)
            .background(Capsule().fill(background))
            .fixedSize()
    }

    private var foreground: Color {
        if prominent { return theme[ThemeKey.accentForeground] }
        if tinted { return theme[ThemeKey.accentText] }
        return theme[ThemeKey.settingsSecondaryForeground]
    }

    private var background: Color {
        if prominent { return theme[ThemeKey.accent] }
        if tinted { return theme[ThemeKey.accent].opacity(0.16) }
        return theme[ThemeKey.settingsSecondaryForeground].opacity(0.14)
    }
}

extension View {
    /// Disables the view and dims it, for buttons drawn with
    /// `ThemedButtonStyle` (which doesn't show a disabled state itself).
    func themedDisabled(_ disabled: Bool) -> some View {
        self.disabled(disabled).opacity(disabled ? 0.45 : 1)
    }
}

/// Text-styled button that uses the accent color, for inline links.
struct SettingsLinkButton: View {
    @Environment(\.theme) private var theme
    let title: String
    var systemImage: String?
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(theme[ThemeKey.accentText])
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
    }
}

// MARK: - Helpers

enum SettingsFormat {
    /// Compact JSON for a settings value, e.g. `"grouped"`, `13`, `true`.
    static func json(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return "null" }
        return String(decoding: data, as: UTF8.self)
    }

    static func points(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value)) pt" : String(format: "%.1f pt", value)
    }
}

/// Applies theme-driven chrome to the hosting window: transparent title
/// bar over full-size content, the background color and light/dark
/// appearance for system-drawn controls.
struct ThemedWindowConfigurator: NSViewRepresentable {
    let theme: ResolvedTheme
    var backgroundKey = ThemeKey.settingsBackground
    var title: String
    var resizable = true
    /// Adds an empty unified toolbar so the title bar is tall (52 pt) and
    /// the traffic lights line up with a custom header drawn under it.
    var tallTitleBar = false

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configure(nsView.window)
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        WindowChrome.apply(
            to: window,
            title: title,
            backgroundColor: theme.color(backgroundKey).nsColor,
            appearanceName: theme.appearanceName,
            resizable: resizable
        )
        if tallTitleBar, window.toolbar == nil {
            let toolbar = NSToolbar(identifier: "Vela.\(title.filter(\.isLetter))")
            toolbar.displayMode = .iconOnly
            window.toolbar = toolbar
            window.toolbarStyle = .unified
        }
    }
}

extension ThemeColor {
    /// Converts a SwiftUI color (e.g. from a `ColorPicker`) to sRGB.
    init(swiftUIColor color: Color) {
        let ns = NSColor(color)
        let srgb = ns.usingColorSpace(.sRGB) ?? ns.usingColorSpace(.deviceRGB)
        self.init(
            red: Double(srgb?.redComponent ?? 0),
            green: Double(srgb?.greenComponent ?? 0),
            blue: Double(srgb?.blueComponent ?? 0),
            alpha: Double(srgb?.alphaComponent ?? 1)
        )
    }
}
