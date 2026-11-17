// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaFoundation
import VelaStore
import VelaTheme

/// `appearance.colorCustomizations` in the settings editor: overrides for
/// every theme, then a collapsible group per `"[Theme]"` scope, each row a
/// token with a color well and its hex value. Tokens the accent picker
/// wrote are labeled. Nick and IRC color lists, and anything deeper, link
/// to settings.json.
struct ColorCustomizationsEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(ThemeStore.self) private var themeStore
    @Environment(UIState.self) private var uiState
    @Environment(\.theme) private var theme
    let provider: SettingSuggestionProvider

    @State private var collapsed: Set<String> = []
    /// Scopes added with "Add Theme…" that have no overrides yet. They're
    /// written to settings.json with their first override.
    @State private var draftScopes: [String] = []
    /// The group showing its add row ("" for every theme).
    @State private var addingIn: String?
    @State private var addsTheme = false

    private static let everyTheme = ""
    private static let key = SettingKey<[String: JSONValue]>.appearanceColorCustomizations.key

    var body: some View {
        let customizations = app.settings[.appearanceColorCustomizations]
        let model = ColorCustomizationsModel(customizations)
        let drafts = draftScopes.filter { model.scope($0) == nil }
        VStack(alignment: .leading, spacing: 10) {
            groupBox(
                scope: nil,
                title: "All themes",
                subtitle: "Applied on top of every theme.",
                entries: model.topLevel,
                customizations: customizations
            )
            ForEach(model.scopes) { scope in
                groupBox(scope: scope, title: scope.title, subtitle: subtitle(for: scope.patterns), entries: scope.entries, customizations: customizations)
            }
            ForEach(drafts, id: \.self) { key in
                let patterns = ColorCustomizationsModel.scopePatterns(in: key) ?? [key]
                groupBox(scope: ColorCustomizationsModel.Scope(key: key, patterns: patterns, entries: [], accentPickerTokens: []),
                         title: patterns.joined(separator: ", "), subtitle: subtitle(for: patterns), entries: [], customizations: customizations)
            }
            addThemeRow(customizations: customizations, existing: Set(model.scopes.map(\.key) + drafts))
            if !themeStore.customizationProblems.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(themeStore.customizationProblems, id: \.self) { problem in
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme[ThemeKey.statusWarning])
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Groups

    private func groupBox(
        scope: ColorCustomizationsModel.Scope?,
        title: String,
        subtitle: String,
        entries: [ColorCustomizationsModel.Entry],
        customizations: [String: JSONValue]
    ) -> some View {
        let id = scope?.key ?? Self.everyTheme
        let isCollapsed = collapsed.contains(id)
        return SettingsInsetBox {
            groupHeader(scope: scope, title: title, subtitle: subtitle, count: entries.count, isCollapsed: isCollapsed)
            if !isCollapsed {
                ForEach(entries) { entry in
                    SettingsHairline().padding(.leading, 12)
                    ColorOverrideRow(
                        entry: entry,
                        scope: scope?.key,
                        edit: { token, value in update(token, to: value, scope: scope?.key) },
                        editInJSON: { uiState.settingsEditor.editInJSON(Self.key) }
                    )
                }
                SettingsHairline().padding(.leading, 12)
                if addingIn == id {
                    addOverrideRow(scope: scope, existing: Set(entries.map(\.token)))
                } else {
                    HStack {
                        SettingsLinkButton("Add Override", systemImage: "plus") {
                            addingIn = id
                        }
                        .accessibilityLabel("Add an override for \(title)")
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func groupHeader(scope: ColorCustomizationsModel.Scope?, title: String, subtitle: String, count: Int, isCollapsed: Bool) -> some View {
        let id = scope?.key ?? Self.everyTheme
        return HStack(spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.18)) {
                    if isCollapsed { collapsed.remove(id) } else { collapsed.insert(id) }
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                        .frame(width: 12)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(scope.map { _ in "[\(title)]" } ?? title)
                                .font(scope == nil ? .system(size: 12.5, weight: .semibold) : .system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(theme[ThemeKey.settingsForeground])
                            if scope?.patterns.contains(where: { ColorCustomizationsModel.pattern($0, matches: theme.name) }) == true {
                                SettingsPill(text: "In use", tinted: true)
                            }
                        }
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    }
                    Spacer(minLength: 8)
                    Text(count == 1 ? "1 override" : "\(count) overrides")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(scope == nil ? title : "Theme \(title)"), \(count) overrides")
            .accessibilityValue(isCollapsed ? "Collapsed" : "Expanded")
            .accessibilityHint(isCollapsed ? "Shows the overrides." : "Hides the overrides.")
            if let scope {
                RemoveIconButton(help: "Remove all overrides for \(title)") {
                    draftScopes.removeAll { $0 == scope.key }
                    write(ColorCustomizationsModel.removingScope(scope.key, from: app.settings[.appearanceColorCustomizations]))
                }
            } else {
                // Keeps the counts lined up with the scopes' below.
                Color.clear.frame(width: 13, height: 13).accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// "Palenight" → "Only for Palenight"; a pattern that matches no
    /// installed theme says so.
    private func subtitle(for patterns: [String]) -> String {
        let matching = themeStore.themes.filter { info in
            patterns.contains { ColorCustomizationsModel.pattern($0, matches: info.name) || ColorCustomizationsModel.pattern($0, matches: info.id) }
        }
        if matching.isEmpty { return "No installed theme matches." }
        if matching.count == 1 { return "Only for \(matching[0].name)." }
        return "For \(matching.count) themes: \(matching.prefix(3).map(\.name).joined(separator: ", "))\(matching.count > 3 ? "…" : "")."
    }

    // MARK: Adding

    private func addOverrideRow(scope: ColorCustomizationsModel.Scope?, existing: Set<String>) -> some View {
        let suggestions = SettingSuggestionProvider.themeTokenSuggestions(themeNames: [], includeScopes: false)
            .filter { !existing.contains($0.value) }
        return HStack(alignment: .top, spacing: 8) {
            TokenField(
                values: [],
                allowsMultiple: false,
                suggestions: suggestions,
                placeholder: "Theme token, e.g. accent",
                accessibilityLabel: "Theme token to override",
                resolve: { text in
                    ThemeRegistry.token(text) != nil || text == "vibrancy" ? text : nil
                },
                rejectionMessage: "Not a theme color token. Pick one from the list.",
                monospaced: true,
                onChange: { tokens in
                    guard let token = tokens.first else { return }
                    add(token, scope: scope)
                }
            )
            Button("Cancel") { addingIn = nil }
                .buttonStyle(ThemedButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Adds `token` with the color the theme gives it now, ready to change.
    private func add(_ token: String, scope: ColorCustomizationsModel.Scope?) {
        let base = scope.flatMap(resolvedTheme(for:)) ?? theme
        let value: JSONValue = token == "vibrancy" ? .string(base.vibrancy.rawValue) : .string(base.color(token).hex)
        update(token, to: value, scope: scope?.key)
        addingIn = nil
    }

    /// The first installed theme a scope names, as it looks now.
    private func resolvedTheme(for scope: ColorCustomizationsModel.Scope) -> ResolvedTheme? {
        if scope.patterns.contains(where: { ColorCustomizationsModel.pattern($0, matches: theme.name) }) { return theme }
        let info = themeStore.themes.first { info in
            scope.patterns.contains { ColorCustomizationsModel.pattern($0, matches: info.name) }
        }
        return info.flatMap(themeStore.resolvedTheme(for:))
    }

    private func addThemeRow(customizations: [String: JSONValue], existing: Set<String>) -> some View {
        let suggestions = themeStore.themes
            .filter { !existing.contains(ColorCustomizationsModel.scopeKey(forTheme: $0.name, in: customizations)) }
            .map { TokenSuggestion(value: $0.name, detail: $0.kind == .dark ? "Dark" : "Light") }
        return HStack(alignment: .top, spacing: 8) {
            if addsTheme {
                TokenField(
                    values: [],
                    allowsMultiple: false,
                    suggestions: suggestions,
                    placeholder: "Theme name, or a pattern like Catppuccin *",
                    accessibilityLabel: "Theme to add overrides for",
                    resolve: { text in text.contains(where: { "[]".contains($0) }) ? nil : text },
                    rejectionMessage: "Theme names can't contain [ or ].",
                    onChange: { names in
                        guard let name = names.first else { return }
                        let key = ColorCustomizationsModel.scopeKey(forTheme: name, in: customizations)
                        if !draftScopes.contains(key) { draftScopes.append(key) }
                        collapsed.remove(key)
                        addingIn = key
                        addsTheme = false
                    }
                )
                Button("Cancel") { addsTheme = false }
                    .buttonStyle(ThemedButtonStyle())
            } else {
                SettingsLinkButton("Add Overrides for a Theme…", systemImage: "plus.rectangle.on.rectangle") {
                    addsTheme = true
                }
                Spacer()
                SettingsLinkButton("Edit in settings.json", systemImage: "curlybraces") {
                    uiState.settingsEditor.editInJSON(Self.key)
                }
            }
        }
        .padding(.horizontal, 2)
    }

    // MARK: Writing

    private func update(_ token: String, to value: JSONValue?, scope: String?) {
        let current = app.settings[.appearanceColorCustomizations]
        write(ColorCustomizationsModel.setting(token, to: value, inScope: scope, of: current))
        if let scope, value != nil { draftScopes.removeAll { $0 == scope } }
    }

    private func write(_ customizations: [String: JSONValue]) {
        if customizations.isEmpty {
            app.settings.reset(.appearanceColorCustomizations)
        } else {
            app.settings[.appearanceColorCustomizations] = customizations
        }
    }
}

/// One override: the token, then a color well and hex value (or a pop-up
/// for vibrancy, swatches for color lists), and remove.
private struct ColorOverrideRow: View {
    @Environment(\.theme) private var theme
    let entry: ColorCustomizationsModel.Entry
    let scope: String?
    /// Sets the token's value, or removes it with nil.
    let edit: (String, JSONValue?) -> Void
    let editInJSON: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.token)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(theme[ThemeKey.settingsForeground])
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    if entry.isAccentPicker {
                        SettingsPill(text: "Accent picker", tinted: true)
                            .help("Set by the accent color picker in Settings → Appearance. Changing it here makes it yours: picking Default there keeps it.")
                    }
                }
                if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(theme[ThemeKey.statusWarning])
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(ThemeRegistry.token(entry.token)?.description ?? entry.token)
            valueControl
            RemoveIconButton(help: "Remove \(entry.token)") { edit(entry.token, nil) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(entry.isAccentPicker ? "\(entry.token), set by the accent picker" : entry.token)
    }

    private var problem: String? {
        switch entry.kind {
        case .unknownToken: "Not a theme color token."
        case .invalidColor: "Not a hex color."
        default: nil
        }
    }

    @ViewBuilder
    private var valueControl: some View {
        switch entry.kind {
        case .color, .invalidColor, .unknownToken:
            let hex = entry.value.stringValue ?? ""
            HStack(spacing: 6) {
                ColorPicker(
                    "Color for \(entry.token)",
                    selection: Binding(
                        get: { ThemeColor(hex: hex)?.color ?? theme[ThemeKey.settingsBackground] },
                        set: { color in edit(entry.token, .string(ThemeColor(swiftUIColor: color).hex)) }
                    ),
                    supportsOpacity: true
                )
                .labelsHidden()
                .frame(width: 38)
                CommitTextField(
                    placeholder: "#RRGGBB",
                    value: hex,
                    accessibilityName: "Hex color for \(entry.token)",
                    monospaced: true,
                    validate: { text in
                        let trimmed = text.trimmingCharacters(in: .whitespaces)
                        let withHash = trimmed.hasPrefix("#") ? trimmed : "#\(trimmed)"
                        guard let color = ThemeColor(hex: withHash) else { return .reject("Use #RGB, #RRGGBB or #RRGGBBAA.") }
                        return .accept(color.hex)
                    },
                    write: { edit(entry.token, .string($0)) }
                )
                .frame(width: 104)
            }
        case .vibrancy(let current):
            Picker("Vibrancy", selection: Binding(get: { current }, set: { edit(entry.token, .string($0)) })) {
                if !ColorCustomizationsModel.vibrancyValues.contains(current) {
                    Text("\(current) (invalid)").tag(current)
                }
                ForEach(ColorCustomizationsModel.vibrancyValues, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        case .nickColors(let colors):
            swatches(colors.map { (nil, $0) })
        case .ircColors(let colors):
            swatches(colors.map { ($0.index, $0.color) })
        case .other:
            SettingsLinkButton("Edit in settings.json", systemImage: "curlybraces", action: editInJSON)
        }
    }

    /// Read-only color dots (nick or IRC colors), then a link to edit them.
    private func swatches(_ colors: [(index: String?, color: ThemeColor?)]) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(Array(colors.prefix(16).enumerated()), id: \.offset) { _, item in
                    Circle()
                        .fill(item.color?.color ?? .clear)
                        .overlay(Circle().strokeBorder(theme[ThemeKey.settingsBorder]))
                        .frame(width: 12, height: 12)
                        .help(item.index.map { "\($0): \(item.color?.hex ?? "invalid")" } ?? (item.color?.hex ?? "invalid"))
                }
                if colors.count > 16 {
                    Text("+\(colors.count - 16)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(colors.count) colors")
            SettingsLinkButton("Edit", systemImage: "curlybraces", action: editInJSON)
                .help("Edit in settings.json")
                .accessibilityLabel("Edit \(entry.token) in settings.json")
        }
    }
}

/// A minus button that turns the error color on hover.
private struct RemoveIconButton: View {
    @Environment(\.theme) private var theme
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(theme[isHovered ? ThemeKey.statusError : ThemeKey.settingsSecondaryForeground])
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}
