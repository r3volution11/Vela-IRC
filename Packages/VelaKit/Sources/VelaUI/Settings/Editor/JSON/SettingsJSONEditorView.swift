// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaFoundation
import VelaStore
import VelaTheme

/// The settings editor's JSON view: settings.json with highlighting,
/// completion, validation, hover docs and ⌘S to save, plus the read-only
/// defaults beside it on request.
///
/// The state lives in a ``SettingsJSONSession`` that outlasts this view,
/// so unsaved edits survive switching views, panes and closing Settings.
struct SettingsJSONEditorView: View {
    @Environment(AppModel.self) private var app
    @Environment(ThemeStore.self) private var themeStore
    @Environment(UIState.self) private var uiState
    @Environment(TranslationStore.self) private var translations
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var chatStyle

    var body: some View {
        let editor = uiState.settingsEditor
        let session = SettingsJSONSession.session(for: editor)
        VStack(spacing: 0) {
            JSONEditorToolbar(session: session, store: app.settings)
            SettingsHairline()
            banners(session: session, editor: editor)
            panes(session: session)
            SettingsHairline()
            JSONProblemsBar(session: session)
        }
        .background(theme[ThemeKey.settingsBackground])
        .onAppear {
            session.attach(store: app.settings) {
                SettingSuggestionProvider(app: app, themeStore: themeStore, translations: translations)
            }
            SettingsJSONSnapshotArguments.applyOnce(to: session, editor: editor, store: app.settings)
            revealIfRequested(editor, session: session)
            switchIfClean(editor, session: session)
        }
        .onChange(of: app.settings.fileRevision) { session.syncWithStore() }
        .onChange(of: editor.revealKeyInJSON) { revealIfRequested(editor, session: session) }
        .onChange(of: editor.pendingMode) { switchIfClean(editor, session: session) }
        .onChange(of: session.isDirty) { switchIfClean(editor, session: session) }
    }

    private func revealIfRequested(_ editor: SettingsEditorState, session: SettingsJSONSession) {
        guard let key = editor.revealKeyInJSON else { return }
        editor.revealKeyInJSON = nil
        session.reveal(key: key)
    }

    /// A switch asked for while there were unsaved edits goes ahead once
    /// there aren't any (saved with ⌘S, say).
    private func switchIfClean(_ editor: SettingsEditorState, session: SettingsJSONSession) {
        guard let mode = editor.pendingMode, !session.isDirty else { return }
        editor.pendingMode = nil
        editor.mode = mode
    }

    // MARK: Banners

    @ViewBuilder
    private func banners(session: SettingsJSONSession, editor: SettingsEditorState) -> some View {
        let leaving = (editor.pendingMode != nil || session.closeRequested) && session.isDirty
        let storeError = app.settings.lastError
        let showsStoreError = storeError != nil && !session.isDirty && session.saveError == nil
        if leaving || session.hasConflict || showsStoreError || session.saveError != nil || session.notice != nil {
            VStack(spacing: 0) {
                if leaving {
                    JSONBanner(
                        .warning,
                        "Save changes to settings.json?",
                        message: editor.pendingMode != nil ? "Before switching to the UI view." : "Before closing Settings."
                    ) {
                        JSONBannerButton("Save", prominent: true) { session.resolveLeave(.save) }
                        JSONBannerButton("Discard") { session.resolveLeave(.discard) }
                        JSONBannerButton("Cancel") { session.resolveLeave(.cancel) }
                            .keyboardShortcut(.cancelAction)
                    }
                }
                if session.hasConflict {
                    JSONBanner(.warning, "settings.json changed on disk.", message: "Your edits aren't saved.") {
                        JSONBannerButton("Reload", prominent: true) { session.reloadFromDisk() }
                        JSONBannerButton("Keep My Changes") { session.keepMyChanges() }
                    }
                }
                if let error = session.saveError {
                    JSONBanner(.error, "settings.json wasn't saved.", message: error) { EmptyView() }
                } else if showsStoreError, let storeError {
                    JSONBanner(
                        .error,
                        "settings.json has errors.",
                        message: "Vela keeps using the last valid settings until they're fixed. " + storeError
                    ) { EmptyView() }
                }
                if let notice = session.notice {
                    JSONBanner(.info, notice, message: nil) {
                        JSONBannerButton("OK") { session.notice = nil }
                    }
                }
            }
            .transition(.opacity)
        }
    }

    // MARK: Panes

    private func panes(session: SettingsJSONSession) -> some View {
        let font = Self.editorFont(chatStyle)
        return HStack(spacing: 0) {
            if session.showsDefaults {
                VStack(spacing: 0) {
                    paneCaption("Default Settings", detail: "Read-only · hover a setting and click ✎ to copy it")
                    JSONPaneRepresentable(pane: session.defaultsPane, session: session, theme: theme, font: font)
                        .overlay(alignment: .topLeading) { JSONDefaultsOverlay(session: session) }
                }
                .frame(maxWidth: .infinity)
                SettingsHairline(vertical: true)
            }
            VStack(spacing: 0) {
                if session.showsDefaults {
                    paneCaption("settings.json", detail: "Your settings")
                }
                JSONPaneRepresentable(pane: session.editorPane, session: session, theme: theme, font: font)
                    .overlay(alignment: .topLeading) { JSONEditorOverlay(session: session) }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func paneCaption(_ title: String, detail: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme[ThemeKey.settingsForeground])
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(theme[ThemeKey.settingsForeground].opacity(0.03))
        .overlay(alignment: .bottom) { SettingsHairline() }
    }

    /// The chat's monospaced font (`chat.monospaceFontFamily`), a little
    /// smaller than chat text.
    static func editorFont(_ style: ChatStyle) -> NSFont {
        let size = min(max(style.fontSize - 1, 11), 16)
        let family = style.monospaceFontFamily
        if !family.isEmpty, family != "SF Mono",
           let font = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size) ?? NSFont(name: family, size: size)
        {
            return font
        }
        return .monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

// MARK: - Banners

/// A slim, full-width message row above the text: an icon, the message
/// and its buttons on one line.
private struct JSONBanner<Actions: View>: View {
    @Environment(\.theme) private var theme
    let kind: SettingsCallout<EmptyView>.Kind
    let title: String
    let message: String?
    let actions: Actions

    init(_ kind: SettingsCallout<EmptyView>.Kind, _ title: String, message: String?, @ViewBuilder actions: () -> Actions) {
        self.kind = kind
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        let tint = theme[kind.colorKey]
        HStack(spacing: 8) {
            Image(systemName: kind.systemImage)
                .font(.system(size: 12))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            let detail = Text(message.map { "  " + $0 } ?? "").foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
            Text("\(Text(title).fontWeight(.semibold).foregroundStyle(theme[ThemeKey.settingsForeground]))\(detail)")
                .font(.system(size: 12))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            HStack(spacing: 6) { actions }
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12))
        .overlay(alignment: .bottom) { SettingsHairline() }
        .accessibilityElement(children: .contain)
    }
}

private struct JSONBannerButton: View {
    @Environment(\.theme) private var theme
    let title: String
    var prominent = false
    let action: () -> Void

    init(_ title: String, prominent: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.prominent = prominent
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10)
                .frame(height: 22)
                .foregroundStyle(theme[prominent ? ThemeKey.buttonForeground : ThemeKey.buttonSecondaryForeground])
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(theme[prominent ? ThemeKey.buttonBackground : ThemeKey.buttonSecondaryBackground])
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - AppKit bridge

/// Hosts one of the session's long-lived panes.
private struct JSONPaneRepresentable: NSViewRepresentable {
    let pane: JSONPaneView
    let session: SettingsJSONSession
    let theme: ResolvedTheme
    let font: NSFont

    func makeNSView(context: Context) -> JSONPaneView {
        pane.removeFromSuperview()
        session.apply(theme: theme, font: font)
        return pane
    }

    func updateNSView(_ nsView: JSONPaneView, context: Context) {
        session.apply(theme: theme, font: font)
    }

    static func dismantleNSView(_ nsView: JSONPaneView, coordinator: ()) {
        // The session keeps the pane (and its undo history) for next time.
    }
}

// MARK: - Toolbar

/// The strip above the text: the file, then Show Defaults, Find, Revert,
/// Open in External Editor and Save.
private struct JSONEditorToolbar: View {
    @Environment(\.theme) private var theme
    let session: SettingsJSONSession
    let store: SettingsStore

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "curlybraces.square")
                .font(.system(size: 12))
                .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                .accessibilityHidden(true)
            Text(Self.displayPath(store.fileURL))
                .font(.system(size: 11.5).monospaced())
                .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                .lineLimit(1)
                .truncationMode(.head)
                .help(store.fileURL.path)
                .textSelection(.enabled)
            if session.isDirty {
                HStack(spacing: 4) {
                    Circle().fill(theme[ThemeKey.accent]).frame(width: 6, height: 6)
                    Text("Edited")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                }
                .fixedSize()
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Unsaved changes")
            }
            Spacer(minLength: 8)
            JSONToolbarButton(
                systemImage: "rectangle.split.2x1",
                title: "Defaults",
                help: session.showsDefaults ? "Hide the default settings" : "Show the default settings beside settings.json",
                isOn: session.showsDefaults
            ) {
                withAnimation(.snappy(duration: 0.2)) { session.showsDefaults.toggle() }
            }
            JSONToolbarButton(systemImage: "magnifyingglass", help: "Find (⌘F)") { session.showFind() }
                .keyboardShortcut("f", modifiers: .command)
            JSONToolbarButton(systemImage: "arrow.uturn.backward", help: "Revert to the saved settings.json") { session.revert() }
                .themedDisabled(!session.isDirty && !session.hasConflict)
            JSONToolbarButton(systemImage: "arrow.up.forward.app", help: "Open settings.json in External Editor") {
                SettingsFiles.openSettingsJSON(store)
            }
            JSONToolbarButton(systemImage: "square.and.arrow.down", title: "Save", help: "Save settings.json (⌘S)", isProminent: session.isDirty) {
                session.save()
            }
            .keyboardShortcut("s", modifiers: .command)
            .themedDisabled(!session.isDirty)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
    }

    /// `~/Library/…/settings.json` (inside the sandbox, `~` is the container).
    static func displayPath(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }
}

private struct JSONToolbarButton: View {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    let systemImage: String
    var title: String?
    let help: String
    var isOn = false
    var isProminent = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 11.5, weight: .medium))
                if let title {
                    Text(title).font(.system(size: 11.5, weight: .medium))
                }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, title == nil ? 0 : 8)
            .frame(minWidth: 26)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(background))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isOn || isProminent ? .clear : theme[ThemeKey.settingsBorder])
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
        .accessibilityLabel(title ?? help)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    private var foreground: Color {
        isOn || isProminent ? theme[ThemeKey.accentForeground] : theme[ThemeKey.settingsForeground]
    }

    private var background: Color {
        if isOn || isProminent { return theme[ThemeKey.accent] }
        return isHovered && isEnabled ? theme[ThemeKey.settingsForeground].opacity(0.08) : theme[ThemeKey.settingsControlBackground]
    }
}

// MARK: - Problems bar

/// The slim bar under the text: problem counts and the caret position;
/// click to list the problems, click one to go to it.
private struct JSONProblemsBar: View {
    @Environment(\.theme) private var theme
    let session: SettingsJSONSession

    var body: some View {
        let diagnostics = session.diagnostics
        let counts = JSONColorChecks.counts(diagnostics)
        VStack(spacing: 0) {
            if session.problemsExpanded, !diagnostics.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                            JSONProblemRow(diagnostic: diagnostic, location: location(of: diagnostic)) {
                                session.jump(to: diagnostic.range)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: min(CGFloat(diagnostics.count) * 24 + 8, 150))
                SettingsHairline()
            }
            HStack(spacing: 10) {
                Button {
                    withAnimation(.snappy(duration: 0.18)) { session.problemsExpanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        if diagnostics.isEmpty {
                            Image(systemName: "checkmark.circle")
                                .foregroundStyle(theme[ThemeKey.statusSuccess])
                            Text("No problems")
                        } else {
                            Image(systemName: session.problemsExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                            Text(Self.summary(counts))
                            countLabel(counts.errors, "xmark.octagon.fill", ThemeKey.statusError)
                            countLabel(counts.warnings, "exclamationmark.triangle.fill", ThemeKey.statusWarning)
                            countLabel(counts.infos, "info.circle.fill", ThemeKey.settingsSecondaryForeground)
                        }
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(diagnostics.isEmpty)
                .help(diagnostics.isEmpty ? "settings.json has no problems" : "Show or hide the problems")
                Spacer(minLength: 8)
                Text("Ln \(session.caretLine), Col \(session.caretColumn)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                Text("JSON with Comments")
                    .font(.system(size: 11))
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    .help("Comments (// and /* */) and trailing commas are allowed")
            }
            .padding(.horizontal, 12)
            .frame(height: 26)
        }
        .background(theme[ThemeKey.settingsForeground].opacity(0.03))
    }

    /// "3 problems", "1 problem".
    static func summary(_ counts: (errors: Int, warnings: Int, infos: Int)) -> String {
        let total = counts.errors + counts.warnings + counts.infos
        return total == 1 ? "1 problem" : "\(total) problems"
    }

    @ViewBuilder
    private func countLabel(_ count: Int, _ symbol: String, _ colorKey: String) -> some View {
        if count > 0 {
            HStack(spacing: 3) {
                Image(systemName: symbol).foregroundStyle(theme[colorKey])
                Text("\(count)").monospacedDigit()
            }
        }
    }

    private func location(of diagnostic: SettingsDiagnostic) -> String {
        let position = session.lineAndColumn(of: diagnostic.range.location)
        return "Ln \(position.line), Col \(position.column)"
    }
}

private struct JSONProblemRow: View {
    @Environment(\.theme) private var theme
    let diagnostic: SettingsDiagnostic
    let location: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                JSONSeverityIcon(severity: diagnostic.severity)
                Text(diagnostic.message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme[ThemeKey.settingsForeground])
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let key = diagnostic.key {
                    Text(key)
                        .font(.system(size: 11).monospaced())
                        .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(location)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
            }
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background(isHovered ? theme[ThemeKey.settingsForeground].opacity(0.06) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(diagnostic.message)
        .accessibilityLabel("\(Self.severityName(diagnostic.severity)): \(diagnostic.message), \(location)")
    }

    static func severityName(_ severity: SettingsDiagnostic.Severity) -> String {
        switch severity {
        case .error: "Error"
        case .warning: "Warning"
        case .info: "Note"
        }
    }
}

struct JSONSeverityIcon: View {
    @Environment(\.theme) private var theme
    let severity: SettingsDiagnostic.Severity

    var body: some View {
        let (symbol, key): (String, String) = switch severity {
        case .error: ("xmark.octagon.fill", ThemeKey.statusError)
        case .warning: ("exclamationmark.triangle.fill", ThemeKey.statusWarning)
        case .info: ("info.circle.fill", ThemeKey.settingsSecondaryForeground)
        }
        Image(systemName: symbol)
            .font(.system(size: 11))
            .foregroundStyle(theme[key])
            .accessibilityHidden(true)
    }
}

// MARK: - Snapshots

/// Demo snapshots of the JSON view (with `--settings-pane advanced
/// --settings-mode json`):
///
/// - `--settings-json-text <text>` saves this text as settings.json first
///   (comments, unknown keys, bad values…);
/// - `--settings-json-unsaved <text>` puts this text in the editor unsaved;
/// - `--settings-json-defaults` shows the defaults pane;
/// - `--settings-json-reveal <key>` reveals a key (adding it if missing);
/// - `--settings-json-complete <offset>` opens the completion list there;
/// - `--settings-json-hover <offset>` shows the hover card for that spot;
/// - `--settings-json-problems` expands the problems list;
/// - `--settings-json-conflict <text>` writes this to disk behind the
///   editor's back (with unsaved edits, shows the conflict banner);
/// - `--settings-json-leave` asks for the UI view (with unsaved edits,
///   shows Save / Discard / Cancel);
/// - `--settings-json-defaults-hover <key>` shows the defaults pane's ✎
///   and hover card on that key;
/// - `--settings-json-find` opens the find bar.
@MainActor
enum SettingsJSONSnapshotArguments {
    private static var applied = false

    static func applyOnce(to session: SettingsJSONSession, editor: SettingsEditorState, store: SettingsStore) {
        guard SnapshotSupport.isActive, !applied else { return }
        applied = true
        let arguments = SnapshotSupport.arguments
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        if let text = value(after: "--settings-json-text") {
            try? store.saveFileText(text)
            session.syncWithStore()
        }
        if let text = value(after: "--settings-json-unsaved"), let edit = JSONCEdit.difference(from: session.textView.string, to: text) {
            session.applyEdits([edit], selecting: nil, actionName: "Snapshot")
        }
        if arguments.contains("--settings-json-defaults") { session.showsDefaults = true }
        if arguments.contains("--settings-json-problems") { session.problemsExpanded = true }
        let reveal = value(after: "--settings-json-reveal")
        let complete = value(after: "--settings-json-complete").flatMap(Int.init)
        let hover = value(after: "--settings-json-hover").flatMap(Int.init)
        let conflict = value(after: "--settings-json-conflict")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if let reveal { session.reveal(key: reveal) }
            if let complete {
                session.textView.setSelectedRange(NSRange(location: complete, length: 0))
                session.focusEditor()
                session.updateCompletion(explicit: true)
            }
            if let hover { session.showHoverForSnapshot(at: hover) }
            if let conflict {
                try? store.saveFileText(conflict)
                session.syncWithStore()
            }
            if arguments.contains("--settings-json-leave") { editor.requestMode(.ui) }
            if let key = value(after: "--settings-json-defaults-hover") { session.showDefaultsKeyForSnapshot(key) }
            if arguments.contains("--settings-json-find") { session.showFind() }
        }
    }
}
