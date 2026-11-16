// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VelaCore
import VelaStore
import VelaTheme

/// Edits a theme's color tokens, nick palette and mIRC colors. The working
/// copy lives in `themeStore.draft`, so the whole app — this window
/// included — previews every change live. Closing the window drops the
/// draft; saving writes a user theme and selects it.
struct ThemeEditorView: View {
    @Environment(AppModel.self) private var app
    @Environment(ThemeStore.self) private var themeStore
    @Environment(\.theme) private var theme
    @Environment(\.dismissWindow) private var dismissWindow

    /// The definition as last loaded or saved, for Revert and the dirty state.
    @State private var baseline: ThemeDefinition?
    @State private var baseName = ""
    @State private var filter: TokenFilter = .group("window")
    @State private var query = ""
    @State private var status: Status?
    @State private var showsIRCColors = false
    @State private var pendingAction: PendingAction?

    enum TokenFilter: Hashable {
        case all
        case group(String)
        case modified
        case issues
    }

    enum Status: Equatable {
        case success(String)
        case failure(String)
    }

    enum PendingAction: Equatable {
        case close
        case switchBase(ThemeInfo)
    }

    private static let untitled = ThemeDefinition(name: "My Theme", type: .dark)

    var body: some View {
        let draft = themeStore.draft ?? Self.untitled
        let findings = ThemeAudit.audit(theme).filter { !$0.passes }

        VStack(spacing: 0) {
            topBar
            SettingsHairline()
            detailsBar(draft, findings: findings)
            SettingsHairline()
            HStack(spacing: 0) {
                sidebar(draft, findings: findings)
                    .frame(width: 220)
                SettingsHairline(vertical: true)
                TokenListView(
                    filter: filter,
                    query: query,
                    draft: draft,
                    findings: findings,
                    setColor: { key, hex in update { $0.colors[key] = hex } },
                    reset: { key in update { $0.colors.removeValue(forKey: key) } }
                )
            }
            SettingsHairline()
            statusBar(draft)
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(theme[ThemeKey.settingsBackground])
        .background(ThemedWindowConfigurator(theme: theme, title: "Theme Editor", tallTitleBar: true))
        .frame(minWidth: 720, minHeight: 560)
        .onAppear(perform: begin)
        .onDisappear { themeStore.draft = nil }
        .onChange(of: ThemeEditorHandoff.shared.requestedBase) { _, base in
            guard let base else { return }
            ThemeEditorHandoff.shared.requestedBase = nil
            requestSwitch(to: base)
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if pendingAction == .close {
                Button("Save") {
                    if save() { close() }
                }
                Button("Discard Changes", role: .destructive) { close() }
            } else if case .switchBase(let info) = pendingAction {
                Button("Discard and Start from “\(info.name)”", role: .destructive) { start(from: info) }
            }
            Button("Cancel", role: .cancel) { pendingAction = nil }
        } message: {
            Text("Your unsaved changes to “\(draft.name)” will be lost.")
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 8) {
            Text("Theme Editor")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme[ThemeKey.settingsForeground])
            if isDirty {
                SettingsPill(text: "Edited")
            }
            Spacer(minLength: 12)
            Button("Revert") { revert() }
                .buttonStyle(ThemedButtonStyle())
                .themedDisabled(!isDirty)
                .help("Undo every change since the theme was loaded or saved")
            Button("Export…", action: export)
                .buttonStyle(ThemedButtonStyle())
                .help("Save a copy of this theme as a .json file")
            Button("Save") { _ = save() }
                .buttonStyle(ThemedButtonStyle(prominent: true))
                .keyboardShortcut("s", modifiers: .command)
                .help("Save to your Themes folder and use it")
            Button("Close", action: requestClose)
                .buttonStyle(ThemedButtonStyle())
                .keyboardShortcut("w", modifiers: .command)
        }
        .padding(.leading, 86)
        .padding(.trailing, 14)
        .frame(height: 52)
        .background(theme[ThemeKey.settingsSidebarBackground])
        .gesture(WindowDragGesture())
        .allowsWindowActivationEvents(true)
    }

    // MARK: Details

    private func detailsBar(_ draft: ThemeDefinition, findings: [ThemeAudit.Finding]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                detailLabel("Name")
                ThemedTextField(
                    "Theme name",
                    text: Binding(get: { draft.name }, set: { name in update { $0.name = name } }),
                    accessibilityName: "Theme name"
                )
                .frame(maxWidth: 240)
                Picker("Type", selection: Binding(get: { draft.type }, set: { kind in update { $0.type = kind } })) {
                    Text("Dark").tag(ThemeKind.dark)
                    Text("Light").tag(ThemeKind.light)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Dark or light: picks the defaults for colors you don't set and the look of system controls")
                .accessibilityLabel("Theme type")
                Spacer(minLength: 12)
                detailLabel("Start from")
                baseMenu
            }

            NickPaletteEditor(draft: draft, findings: findings) { change in update(change) }

            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { showsIRCColors.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .rotationEffect(.degrees(showsIRCColors ? 90 : 0))
                        Text("mIRC colors 0–15")
                            .font(.system(size: 12.5, weight: .medium))
                        if let count = draft.ircColors?.count, count > 0 {
                            SettingsPill(text: "\(count) set")
                        }
                    }
                    .foregroundStyle(theme[ThemeKey.settingsForeground])
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("mIRC colors 0 to 15")
                .accessibilityValue(showsIRCColors ? "Expanded" : "Collapsed")

                if showsIRCColors {
                    IRCColorEditor(draft: draft) { change in update(change) }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(theme[ThemeKey.settingsBackground])
    }

    private func detailLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
            .accessibilityHidden(true)
    }

    private var baseMenu: some View {
        Menu {
            Section("Dark") {
                ForEach(themeStore.themes.filter { $0.kind == .dark }) { info in
                    Button(info.name) { requestSwitch(to: info) }
                }
            }
            Section("Light") {
                ForEach(themeStore.themes.filter { $0.kind == .light }) { info in
                    Button(info.name) { requestSwitch(to: info) }
                }
            }
        } label: {
            Text(baseName.isEmpty ? "Choose a theme" : baseName)
        }
        .menuStyle(.button)
        .fixedSize()
        .help("Load another theme's colors as the starting point")
        .accessibilityLabel("Start from theme")
        .accessibilityValue(baseName)
    }

    // MARK: Sidebar

    private func sidebar(_ draft: ThemeDefinition, findings: [ThemeAudit.Finding]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    .accessibilityHidden(true)
                ThemedTextField("Search tokens", text: $query, accessibilityName: "Search tokens")
            }
            .padding(10)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    filterItem(.all, title: "All tokens", count: ThemeRegistry.tokens.count)
                    Spacer().frame(height: 6)
                    ForEach(ThemeRegistry.groups) { group in
                        let tokens = ThemeRegistry.tokens(in: group.id)
                        filterItem(
                            .group(group.id),
                            title: group.title,
                            count: tokens.count,
                            modified: tokens.filter { draft.colors[$0.key] != nil }.count
                        )
                    }
                    Spacer().frame(height: 6)
                    filterItem(.modified, title: "Set in this theme", systemImage: "paintbrush", count: draft.colors.keys.filter { ThemeRegistry.token($0) != nil }.count)
                    filterItem(.issues, title: "Contrast issues", systemImage: "exclamationmark.triangle", count: Set(findings.map(\.foreground)).count, warns: !findings.isEmpty)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }

            SettingsHairline()
            VStack(alignment: .leading, spacing: 6) {
                Text("Live preview")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                LayoutSchematic(config: LayoutSchematicConfig(settings: app.settings), theme: theme)
                    .frame(width: 196, height: 122.5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(theme[ThemeKey.settingsBorder])
                    )
                Text("Every Vela window shows your changes as you make them.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .layoutPriority(1)
        }
        .background(theme[ThemeKey.settingsSidebarBackground])
    }

    private func filterItem(
        _ item: TokenFilter,
        title: String,
        systemImage: String? = nil,
        count: Int,
        modified: Int = 0,
        warns: Bool = false
    ) -> some View {
        let isSelected = filter == item && query.isEmpty
        return Button {
            filter = item
            query = ""
        } label: {
            HStack(spacing: 7) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isSelected ? theme[ThemeKey.accentForeground] : (warns ? theme[ThemeKey.statusWarning] : theme[ThemeKey.accent]))
                        .frame(width: 14)
                }
                Text(title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? theme[ThemeKey.accentForeground] : theme[ThemeKey.settingsForeground])
                    .lineLimit(1)
                Spacer(minLength: 4)
                if modified > 0 {
                    Circle()
                        .fill(isSelected ? theme[ThemeKey.accentForeground] : theme[ThemeKey.accent])
                        .frame(width: 5, height: 5)
                        .help("\(modified) set in this theme")
                }
                Text("\(count)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(isSelected ? theme[ThemeKey.accentForeground].opacity(0.85) : theme[ThemeKey.settingsSecondaryForeground])
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? theme[ThemeKey.accent] : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(count)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Status

    private func statusBar(_ draft: ThemeDefinition) -> some View {
        HStack(spacing: 8) {
            if let error = themeStore.draftError {
                statusLabel(error, systemImage: "xmark.octagon.fill", colorKey: ThemeKey.statusError)
            } else if let status {
                switch status {
                case .success(let message):
                    statusLabel(message, systemImage: "checkmark.circle.fill", colorKey: ThemeKey.statusSuccess)
                case .failure(let message):
                    statusLabel(message, systemImage: "xmark.octagon.fill", colorKey: ThemeKey.statusError)
                }
            } else if let notice = nameNotice(draft) {
                statusLabel(notice, systemImage: "info.circle.fill", colorKey: ThemeKey.statusWarning)
            } else {
                Text(isDirty ? "Unsaved changes are previewed everywhere until you save or close." : "Changes preview live across Vela.")
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
            }
            Spacer()
        }
        .font(.system(size: 11.5))
        .lineLimit(1)
        .padding(.horizontal, 14)
        .frame(height: 28)
        .background(theme[ThemeKey.settingsSidebarBackground])
    }

    private func statusLabel(_ text: String, systemImage: String, colorKey: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(theme[colorKey])
            Text(text)
                .foregroundStyle(theme[ThemeKey.settingsForeground])
                .truncationMode(.tail)
        }
        .help(text)
    }

    private func nameNotice(_ draft: ThemeDefinition) -> String? {
        let name = draft.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return "Give the theme a name to save it." }
        guard let existing = themeStore.themes.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            return nil
        }
        if existing.source == .builtIn {
            return "Saving creates your own “\(existing.name)”, which takes the built-in's place in the theme list."
        }
        if baseline?.name.caseInsensitiveCompare(name) == .orderedSame { return nil }
        return "Saving replaces your theme “\(existing.name)”."
    }

    // MARK: Draft lifecycle

    private var isDirty: Bool {
        guard let draft = themeStore.draft, let baseline else { return false }
        return draft != baseline
    }

    private var confirmationTitle: String {
        switch pendingAction {
        case .close: "Save changes before closing?"
        case .switchBase(let info): "Start over from “\(info.name)”?"
        case nil: ""
        }
    }

    private func update(_ change: (inout ThemeDefinition) -> Void) {
        var draft = themeStore.draft ?? baseline ?? Self.untitled
        change(&draft)
        themeStore.draft = draft
        if status != nil { status = nil }
    }

    private func begin() {
        if let base = ThemeEditorHandoff.shared.requestedBase {
            ThemeEditorHandoff.shared.requestedBase = nil
            start(from: base)
        } else if let draft = themeStore.draft {
            if baseline == nil { baseline = draft }
        } else if let info = themeStore.currentInfo ?? themeStore.info(for: ThemeSettings.defaultDarkTheme) {
            start(from: info)
        } else {
            themeStore.draft = Self.untitled
            baseline = Self.untitled
        }
    }

    private func requestSwitch(to info: ThemeInfo) {
        if isDirty {
            pendingAction = .switchBase(info)
        } else {
            start(from: info)
        }
    }

    /// Loads `info` (with its includes merged) as the new working copy.
    /// Built-in themes get a new name so saving never shadows them.
    private func start(from info: ThemeInfo) {
        do {
            var definition = try themeStore.flattenedDefinition(for: info)
            definition.schema = ThemeDefinition.schemaURL
            if info.source == .builtIn {
                definition.name = "\(info.name) Custom"
                definition.author = nil
                definition.description = "Based on \(info.name)."
            }
            themeStore.draft = definition
            baseline = definition
            baseName = info.name
            status = nil
            pendingAction = nil
        } catch {
            status = .failure("Couldn't open “\(info.name)”: \(error.localizedDescription)")
        }
    }

    private func revert() {
        guard let baseline else { return }
        themeStore.draft = baseline
        status = nil
    }

    @discardableResult
    private func save() -> Bool {
        guard var definition = themeStore.draft else { return false }
        definition.name = definition.name.trimmingCharacters(in: .whitespaces)
        do {
            let info = try themeStore.saveUserTheme(definition)
            themeStore.draft = definition
            baseline = definition
            baseName = info.name
            let settings = app.settings
            let role: String
            if settings[.appearanceFollowSystem] {
                if info.kind == .dark {
                    settings[.appearancePreferredDarkTheme] = info.name
                    role = "your Dark Mode theme"
                } else {
                    settings[.appearancePreferredLightTheme] = info.name
                    role = "your Light Mode theme"
                }
            } else {
                settings[.appearanceTheme] = info.name
                role = "your theme"
            }
            status = .success("Saved “\(info.name)” to your Themes folder and made it \(role).")
            return true
        } catch {
            status = .failure("Couldn't save: \(error.localizedDescription)")
            return false
        }
    }

    private func export() {
        guard let definition = themeStore.draft else { return }
        let panel = NSSavePanel()
        panel.title = "Export Theme"
        panel.message = "Save “\(definition.name)” as a theme file you can share."
        panel.nameFieldStringValue = "\(definition.fileSlug).json"
        panel.allowedContentTypes = [UTType.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try definition.jsonData().write(to: url, options: .atomic)
            status = .success("Exported “\(definition.name)” to \(url.lastPathComponent).")
        } catch {
            status = .failure("Couldn't export: \(error.localizedDescription)")
        }
    }

    private func requestClose() {
        if isDirty {
            pendingAction = .close
        } else {
            close()
        }
    }

    private func close() {
        pendingAction = nil
        themeStore.draft = nil
        dismissWindow(id: WindowID.themeEditor)
    }
}
