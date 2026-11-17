// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaStore
import VelaTheme

/// Settings → Advanced: every setting in settings.json, VS Code style.
///
/// The UI view lists each setting with the control its type calls for,
/// grouped by category, with search (words and `@filters`), a Modified
/// filter and category chips. The JSON view edits settings.json itself.
struct SettingsEditorView: View {
    @Environment(AppModel.self) private var app
    @Environment(ThemeStore.self) private var themeStore
    @Environment(UIState.self) private var uiState
    @Environment(TranslationStore.self) private var translations
    @Environment(\.theme) private var theme

    @State private var providers = ProviderHolder()
    /// Bumped to focus the search field (from the shared focus request).
    @State private var searchFocus = 0
    @State private var confirmsReset = false
    /// The list's width, for sizing controls beside the titles.
    @State private var listWidth: CGFloat = 600

    /// Settings Vela knows, computed once.
    static let catalog = SettingsCatalog.all
    static let catalogKeys = Set(catalog.map(\.key))

    var body: some View {
        let editor = uiState.settingsEditor
        VStack(spacing: 0) {
            header(editor)
            SettingsHairline()
            if editor.mode == .json {
                SettingsJSONEditorView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list(editor)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme[ThemeKey.settingsBackground])
        .onAppear {
            SettingsEditorSnapshotArguments.applyOnce(to: editor)
            focusSearchIfRequested(editor)
        }
        .onChange(of: editor.focusSearchRequest) { focusSearchIfRequested(editor) }
    }

    private var provider: SettingSuggestionProvider {
        providers.provider(app: app, themeStore: themeStore, translations: translations)
    }

    private func focusSearchIfRequested(_ editor: SettingsEditorState) {
        guard editor.focusSearchRequest != editor.handledFocusSearchRequest else { return }
        editor.handledFocusSearchRequest = editor.focusSearchRequest
        guard editor.mode == .ui else { return }
        searchFocus &+= 1
    }

    // MARK: Header

    private func header(_ editor: SettingsEditorState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Advanced")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(theme[ThemeKey.settingsForeground])
                        .accessibilityAddTraits(.isHeader)
                    Text(editor.mode == .ui
                        ? "Every setting in settings.json, with the right control for each."
                        : "Edit settings.json directly. Changes apply when you save.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                EditorModeSwitch(
                    mode: Binding(get: { editor.mode }, set: { editor.requestMode($0) }),
                    hasUnsavedJSON: editor.hasUnsavedJSON
                )
                moreMenu
            }
            if editor.mode == .ui {
                HStack(spacing: 8) {
                    searchField(editor)
                        // ⌘F focuses the search, like VS Code's settings
                        // (the JSON view keeps ⌘F for its find bar).
                        .background {
                            Button("Search Settings") { searchFocus &+= 1 }
                                .keyboardShortcut("f", modifiers: .command)
                                .opacity(0)
                                .frame(width: 0, height: 0)
                                .accessibilityHidden(true)
                        }
                    ModifiedFilterButton(
                        isOn: SettingsQuery(editor.query).modified,
                        count: app.settings.values.count
                    ) {
                        editor.query = SettingsQuery.toggling(SettingsQuery.modifiedToken, in: editor.query)
                    }
                }
                categoryChips(editor)
            }
            if confirmsReset { resetConfirmation }
        }
        .padding(.horizontal, 28)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .frame(maxWidth: 720, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    private var moreMenu: some View {
        Menu {
            Button("Open settings.json in External Editor") { SettingsFiles.openSettingsJSON(app.settings) }
            Button("Reveal Data Folder") {
                NSWorkspace.shared.activateFileViewerSelecting([app.settings.fileURL.deletingLastPathComponent()])
            }
            Divider()
            Button("Reset All Settings…") {
                withAnimation(.snappy(duration: 0.2)) { confirmsReset = true }
            }
            .disabled(!app.settings.values.keys.contains(where: Self.catalogKeys.contains))
        } label: {
            MoreMenuLabel()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
        .accessibilityLabel("More")
    }

    private var resetConfirmation: some View {
        let known = app.settings.values.keys.filter(Self.catalogKeys.contains)
        let unknown = app.settings.values.count - known.count
        return SettingsCallout(
            .warning,
            "Reset all settings to their defaults?",
            message: "This removes \(known.count) \(known.count == 1 ? "setting" : "settings") from settings.json."
                + (unknown > 0 ? " Unknown settings are kept." : "")
                + " Networks, themes and message history aren't affected."
        ) {
            Button("Reset All Settings") {
                for key in known { app.settings.setValue(nil, forKey: key) }
                withAnimation(.snappy(duration: 0.2)) { confirmsReset = false }
            }
            .buttonStyle(ThemedButtonStyle(prominent: true))
            Button("Cancel") {
                withAnimation(.snappy(duration: 0.2)) { confirmsReset = false }
            }
            .buttonStyle(ThemedButtonStyle())
            .keyboardShortcut(.cancelAction)
        }
    }

    // MARK: Search

    private func searchField(_ editor: SettingsEditorState) -> some View {
        let query = editor.query
        let lastWord = query.last?.isWhitespace == false ? String(query.split(whereSeparator: \.isWhitespace).last ?? "") : ""
        let completions = SettingsQuery.filterCompletions(
            for: lastWord,
            categories: SettingsCategory.allCases,
            panes: SettingsPane.allCases
                .filter { !SettingsCategory.categories(forPane: $0.rawValue).isEmpty }
                .map { ($0.rawValue, $0.title) }
        )
        let count = filteredEntries(query: query).count
        return ThemedSuggestionField(
            text: Binding(get: { editor.query }, set: { editor.query = $0 }),
            placeholder: "Search settings, or type @ for filters",
            accessibilityLabel: "Search settings",
            leadingSystemImage: "magnifyingglass",
            suggestions: completions.map { TokenSuggestion(value: $0.value, detail: $0.detail) },
            autoHighlight: completions.isEmpty ? nil : 0,
            focusRequest: searchFocus,
            onPick: { suggestion in
                var words = query.split(whereSeparator: \.isWhitespace).map(String.init)
                if !words.isEmpty { words.removeLast() }
                words.append(suggestion.value)
                editor.query = words.joined(separator: " ") + " "
            },
            onCancel: {
                guard !editor.query.isEmpty else { return false }
                editor.query = ""
                return true
            }
        ) {
            HStack(spacing: 6) {
                Text(count == 1 ? "1 setting" : "\(count) settings")
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    .accessibilityHidden(true)
                if !query.isEmpty {
                    Button {
                        editor.query = ""
                        searchFocus &+= 1
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                    .accessibilityLabel("Clear search")
                }
            }
        }
    }

    // MARK: Category chips

    private func categoryChips(_ editor: SettingsEditorState) -> some View {
        let query = SettingsQuery(editor.query)
        let entries = allEntries
        let categories = SettingsCategory.allCases.filter { category in entries.contains { $0.category == category } }
        let hasUnknown = entries.contains(where: \.isUnknown)
        return FlowLayout(spacing: 5, lineSpacing: 6) {
            CategoryChip(title: "All", isOn: !query.hasScope) {
                editor.query = SettingsQuery.settingScope(nil, in: editor.query)
            }
            ForEach(categories) { category in
                CategoryChip(title: category.title, isOn: query.includes(category)) {
                    let isOn = query.includes(category) && query.categories.count == 1
                    editor.query = SettingsQuery.settingScope(isOn ? nil : "\(SettingsQuery.categoryPrefix)\(category.rawValue)", in: editor.query)
                }
            }
            if hasUnknown {
                CategoryChip(title: "Unknown", systemImage: "exclamationmark.triangle.fill", isOn: query.unknown) {
                    editor.query = SettingsQuery.settingScope(query.unknown ? nil : SettingsQuery.unknownToken, in: editor.query)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Categories")
    }

    // MARK: List

    private var allEntries: [SettingsEditorEntry] {
        SettingsEditorEntry.all(catalog: Self.catalog, values: app.settings.values)
    }

    private func filteredEntries(query text: String) -> [SettingsEditorEntry] {
        let query = SettingsQuery(text)
        return allEntries.filter(query.matches)
    }

    private func list(_ editor: SettingsEditorState) -> some View {
        let groups = SettingsEditorGroup.grouping(filteredEntries(query: editor.query))
        let provider = provider
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    problems
                    if groups.isEmpty {
                        emptyState(editor)
                    }
                    ForEach(groups) { group in
                        Section {
                            SettingsCard {
                                ForEach(group.entries) { entry in
                                    SettingsEditorRow(entry: entry, provider: provider)
                                }
                            }
                            .padding(.bottom, 20)
                        } header: {
                            groupHeader(group)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 2)
                .padding(.bottom, 32)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
                .id(Self.topID)
            }
            .scrollIndicators(.automatic)
            .onChange(of: editor.query) {
                proxy.scrollTo(Self.topID, anchor: .top)
            }
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { listWidth = $0 }
        .environment(\.settingsControlWidth, Self.controlWidth(forListWidth: listWidth))
        .task { await provider.loadLanguagesIfNeeded() }
    }

    private static let topID = "settings-editor-top"

    /// Controls beside a title (pop-ups aside) get about two fifths of a
    /// row, 180–250 pt.
    static func controlWidth(forListWidth width: CGFloat) -> CGFloat {
        let column = min(width, 720) - 56
        return min(250, max(180, (column * 0.42).rounded()))
    }

    private func groupHeader(_ group: SettingsEditorGroup) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if group.isUnknown {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(theme[ThemeKey.statusWarning])
                    .accessibilityHidden(true)
            }
            Text(group.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme[ThemeKey.settingsForeground])
                .accessibilityAddTraits(.isHeader)
            Text("\(group.entries.count)")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                .accessibilityHidden(true)
            Spacer(minLength: 8)
            if let category = group.category, let pane = SettingsPane(rawValue: category.paneID) {
                SettingsLinkButton("\(pane.title) pane", systemImage: "arrow.up.forward.square") {
                    uiState.settingsEditor.requestedPane = pane
                }
                .help("Open the \(pane.title) pane")
                .accessibilityLabel("Open the \(pane.title) pane")
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme[ThemeKey.settingsBackground])
    }

    private var problems: some View {
        VStack(alignment: .leading, spacing: 10) {
            problemCallouts
        }
        .padding(.bottom, hasProblems ? 16 : 0)
    }

    private var hasProblems: Bool {
        app.settings.lastError != nil || app.networkStore.lastError != nil || app.lastError != nil
    }

    @ViewBuilder
    private var problemCallouts: some View {
        if let error = app.settings.lastError {
            SettingsCallout(.error, "settings.json has a problem", message: error) {
                Button("Open JSON View") { uiState.settingsEditor.requestMode(.json) }
                    .buttonStyle(ThemedButtonStyle(prominent: true))
                Button("Open in External Editor") { SettingsFiles.openSettingsJSON(app.settings) }
                    .buttonStyle(ThemedButtonStyle())
            }
        }
        if let error = app.networkStore.lastError {
            SettingsCallout(.error, "networks.json has a problem", message: error)
        }
        if let error = app.lastError {
            SettingsCallout(.warning, "Startup problem", message: error)
        }
    }

    private func emptyState(_ editor: SettingsEditorState) -> some View {
        let query = SettingsQuery(editor.query)
        let (title, message): (String, String) = {
            if query.words.isEmpty, query.modified {
                return ("No modified settings", "Every setting uses its default. Settings you change show up here.")
            }
            if query.words.isEmpty, query.unknown {
                return ("No unknown settings", "Every key in settings.json is one Vela knows.")
            }
            let words = query.words.joined(separator: " ")
            return (
                words.isEmpty ? "No settings match" : "No settings match “\(words)”",
                query.hasFilters ? "Try fewer words, or remove a filter." : "Try fewer or different words."
            )
        }()
        return VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(theme[ThemeKey.accent])
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme[ThemeKey.settingsForeground])
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                .multilineTextAlignment(.center)
            Button("Clear Search") { editor.query = "" }
                .buttonStyle(ThemedButtonStyle())
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .accessibilityElement(children: .contain)
    }
}

extension EnvironmentValues {
    /// The width of a settings editor control beside its title.
    @Entry var settingsControlWidth: CGFloat = 250
}

/// Demo snapshots of the editor (`scripts/demo-screenshot.sh … --settings-pane
/// advanced`) can start it searching or in the JSON view:
/// `--settings-search "@modified"`, `--settings-mode json`.
@MainActor
enum SettingsEditorSnapshotArguments {
    private static var applied = false

    static func applyOnce(to editor: SettingsEditorState) {
        guard SnapshotSupport.isActive, !applied else { return }
        applied = true
        let arguments = SnapshotSupport.arguments
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        if let query = value(after: "--settings-search") { editor.query = query }
        if let mode = value(after: "--settings-mode").flatMap(SettingsEditorState.Mode.init(rawValue:)) { editor.mode = mode }
    }
}

/// Keeps one suggestion provider for the editor's lifetime.
@MainActor
private final class ProviderHolder {
    private var provider: SettingSuggestionProvider?

    func provider(app: AppModel, themeStore: ThemeStore, translations: TranslationStore) -> SettingSuggestionProvider {
        if let provider { return provider }
        let made = SettingSuggestionProvider(app: app, themeStore: themeStore, translations: translations)
        provider = made
        return made
    }
}

// MARK: - Toolbar pieces

/// UI | JSON, like a segmented control, with a dot on JSON while it has
/// unsaved edits.
private struct EditorModeSwitch: View {
    @Environment(\.theme) private var theme
    @Binding var mode: SettingsEditorState.Mode
    let hasUnsavedJSON: Bool

    var body: some View {
        HStack(spacing: 2) {
            segment(.ui, title: "UI", systemImage: "slider.horizontal.3")
            segment(.json, title: "JSON", systemImage: "curlybraces")
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme[ThemeKey.settingsControlBackground])
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme[ThemeKey.settingsBorder])
        )
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Editor view")
    }

    private func segment(_ value: SettingsEditorState.Mode, title: String, systemImage: String) -> some View {
        let isSelected = mode == value
        let showsDot = value == .json && hasUnsavedJSON
        return Button {
            withAnimation(.snappy(duration: 0.15)) { mode = value }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                if showsDot {
                    Circle()
                        .fill(isSelected ? theme[ThemeKey.accentForeground] : theme[ThemeKey.accent])
                        .frame(width: 6, height: 6)
                }
            }
            .foregroundStyle(isSelected ? theme[ThemeKey.accentForeground] : theme[ThemeKey.settingsForeground])
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? theme[ThemeKey.accent] : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(value == .ui ? "Edit settings with controls" : (showsDot ? "Edit settings.json (unsaved changes)" : "Edit settings.json"))
        .accessibilityLabel(value == .ui ? "UI" : (showsDot ? "JSON, unsaved changes" : "JSON"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The ⋯ button's look.
private struct MoreMenuLabel: View {
    @Environment(\.theme) private var theme
    @State private var isHovered = false

    var body: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(theme[ThemeKey.settingsForeground])
            .frame(width: 30, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovered ? theme[ThemeKey.settingsForeground].opacity(0.08) : theme[ThemeKey.settingsControlBackground])
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(theme[ThemeKey.settingsBorder])
            )
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
    }
}

/// The Modified filter: on while the search has `@modified`.
private struct ModifiedFilterButton: View {
    @Environment(\.theme) private var theme
    let isOn: Bool
    let count: Int
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: isOn ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 12, weight: .medium))
                Text("Modified")
                    .font(.system(size: 12, weight: .medium))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(isOn ? theme[ThemeKey.accentForeground].opacity(0.25) : theme[ThemeKey.accent].opacity(0.16)))
                }
            }
            .foregroundStyle(isOn ? theme[ThemeKey.accentForeground] : theme[ThemeKey.settingsForeground])
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isOn ? theme[ThemeKey.accent] : (isHovered ? theme[ThemeKey.settingsForeground].opacity(0.08) : theme[ThemeKey.settingsControlBackground]))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(isOn ? .clear : theme[ThemeKey.settingsBorder])
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .fixedSize()
        .help("Show only settings set in settings.json (@modified)")
        .accessibilityLabel("Modified settings only")
        .accessibilityValue("\(count) modified")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

/// A category filter chip.
private struct CategoryChip: View {
    @Environment(\.theme) private var theme
    let title: String
    var systemImage: String?
    let isOn: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 10))
                        .foregroundStyle(isOn ? theme[ThemeKey.accentForeground] : theme[ThemeKey.statusWarning])
                }
                Text(title)
                    .font(.system(size: 11.5, weight: isOn ? .semibold : .regular))
            }
            .foregroundStyle(isOn ? theme[ThemeKey.accentForeground] : theme[ThemeKey.settingsForeground])
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(
                Capsule().fill(isOn ? theme[ThemeKey.accent] : (isHovered ? theme[ThemeKey.settingsForeground].opacity(0.08) : theme[ThemeKey.settingsControlBackground]))
            )
            .overlay(Capsule().strokeBorder(isOn ? .clear : theme[ThemeKey.settingsBorder]))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Themed suggestion field

/// A ``SuggestionTextField`` in the settings' text field box: theme
/// colors, an accent focus ring, an optional leading icon and trailing
/// accessory.
struct ThemedSuggestionField<Trailing: View>: View {
    @Environment(\.theme) private var theme
    @Binding var text: String
    var placeholder: String
    var accessibilityLabel: String
    var leadingSystemImage: String?
    var suggestions: [TokenSuggestion] = []
    var autoHighlight: Int?
    var showsOnFocus = false
    var monospaced = false
    var focusRequest = 0
    var onPick: (TokenSuggestion) -> Void = { _ in }
    var onSubmit: () -> Void = {}
    var onCancel: () -> Bool = { false }
    var onFocusChange: (Bool) -> Void = { _ in }
    @ViewBuilder var trailing: () -> Trailing

    @State private var isFocused = false
    @State private var anchor = SuggestionAnchor()
    @State private var localFocus = 0

    var body: some View {
        HStack(spacing: 6) {
            if let leadingSystemImage {
                Image(systemName: leadingSystemImage)
                    .font(.system(size: 12))
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    .accessibilityHidden(true)
            }
            SuggestionTextField(
                text: $text,
                placeholder: placeholder,
                accessibilityLabel: accessibilityLabel,
                suggestions: suggestions,
                autoHighlight: autoHighlight,
                showsOnFocus: showsOnFocus,
                anchor: anchor,
                monospaced: monospaced,
                focusRequest: focusRequest &+ localFocus,
                onPick: onPick,
                onSubmit: onSubmit,
                onCancel: onCancel,
                onFocusChange: { focused in
                    isFocused = focused
                    onFocusChange(focused)
                }
            )
            .frame(height: 18)
            trailing()
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(theme[ThemeKey.settingsControlBackground])
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    isFocused ? theme[ThemeKey.focusBorder] : theme[ThemeKey.settingsBorder],
                    lineWidth: isFocused ? 1.5 : 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { localFocus &+= 1 }
        .suggestionAnchor(anchor)
    }
}

extension ThemedSuggestionField where Trailing == EmptyView {
    init(
        text: Binding<String>,
        placeholder: String,
        accessibilityLabel: String,
        leadingSystemImage: String? = nil,
        suggestions: [TokenSuggestion] = [],
        autoHighlight: Int? = nil,
        showsOnFocus: Bool = false,
        monospaced: Bool = false,
        focusRequest: Int = 0,
        onPick: @escaping (TokenSuggestion) -> Void = { _ in },
        onSubmit: @escaping () -> Void = {},
        onCancel: @escaping () -> Bool = { false },
        onFocusChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.init(
            text: text,
            placeholder: placeholder,
            accessibilityLabel: accessibilityLabel,
            leadingSystemImage: leadingSystemImage,
            suggestions: suggestions,
            autoHighlight: autoHighlight,
            showsOnFocus: showsOnFocus,
            monospaced: monospaced,
            focusRequest: focusRequest,
            onPick: onPick,
            onSubmit: onSubmit,
            onCancel: onCancel,
            onFocusChange: onFocusChange,
            trailing: { EmptyView() }
        )
    }
}
