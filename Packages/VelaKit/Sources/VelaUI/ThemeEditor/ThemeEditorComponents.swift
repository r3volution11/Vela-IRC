// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaTheme

// MARK: - Token list

/// The right-hand list of tokens for the selected group, search or filter.
struct TokenListView: View {
    @Environment(\.theme) private var theme
    let filter: ThemeEditorView.TokenFilter
    let query: String
    let draft: ThemeDefinition
    let findings: [ThemeAudit.Finding]
    let setColor: (_ key: String, _ hex: String) -> Void
    let reset: (_ key: String) -> Void

    var body: some View {
        let tokens = visibleTokens
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header(tokens: tokens)
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                    .padding(.bottom, 10)
                SettingsHairline()
                if tokens.isEmpty {
                    Text(emptyMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                        .padding(18)
                }
                ForEach(tokens) { token in
                    ThemeTokenRow(
                        token: token,
                        kind: draft.type,
                        explicitHex: draft.colors[token.key],
                        resolved: theme.color(token.key),
                        issues: findings.filter { $0.foreground == token.key || $0.background == token.key },
                        setColor: { setColor(token.key, $0) },
                        reset: { reset(token.key) }
                    )
                    SettingsHairline()
                        .padding(.leading, 18)
                }
            }
        }
        .background(theme[ThemeKey.settingsBackground])
        .id(filter)
    }

    private var visibleTokens: [ThemeToken] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace)
        if !terms.isEmpty {
            return ThemeRegistry.tokens.filter { token in
                let haystack = "\(token.key) \(token.description)".lowercased()
                return terms.allSatisfy { haystack.contains($0) }
            }
        }
        switch filter {
        case .all:
            return ThemeRegistry.tokens
        case .group(let id):
            return ThemeRegistry.tokens(in: id)
        case .modified:
            return ThemeRegistry.tokens.filter { draft.colors[$0.key] != nil }
        case .issues:
            let keys = Set(findings.flatMap { [$0.foreground, $0.background] })
            return ThemeRegistry.tokens.filter { keys.contains($0.key) }
        }
    }

    private var title: String {
        if !query.trimmingCharacters(in: .whitespaces).isEmpty { return "Results for “\(query)”" }
        switch filter {
        case .all: return "All tokens"
        case .group(let id): return ThemeRegistry.groups.first { $0.id == id }?.title ?? id
        case .modified: return "Set in this theme"
        case .issues: return "Contrast issues"
        }
    }

    private var subtitle: String {
        if !query.trimmingCharacters(in: .whitespaces).isEmpty { return "Matching token names and descriptions." }
        switch filter {
        case .all: return "Every color Vela draws with. Anything you don't set is derived from other tokens."
        case .group(let id): return ThemeRegistry.groups.first { $0.id == id }?.description ?? ""
        case .modified: return "Colors this theme sets explicitly. Everything else follows from these."
        case .issues: return "Text that may be hard to read. Adjust the text color or the background it sits on."
        }
    }

    private var emptyMessage: String {
        switch filter {
        case .issues where query.isEmpty: "No contrast problems. Everything meets its target."
        case .modified where query.isEmpty: "This theme doesn't set any colors yet; every token uses its default."
        default: "No tokens match."
        }
    }

    private func header(tokens: [ThemeToken]) -> some View {
        let setCount = tokens.filter { draft.colors[$0.key] != nil }.count
        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(theme[ThemeKey.settingsForeground])
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                .fixedSize(horizontal: false, vertical: true)
            Text("\(tokens.count) \(tokens.count == 1 ? "token" : "tokens") · \(setCount) set in this theme")
                .font(.system(size: 11))
                .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
        }
    }
}

/// One token: color well, key, description, default, contrast warnings,
/// hex field and reset.
private struct ThemeTokenRow: View {
    @Environment(\.theme) private var theme
    let token: ThemeToken
    let kind: ThemeKind
    let explicitHex: String?
    let resolved: ThemeColor
    let issues: [ThemeAudit.Finding]
    let setColor: (String) -> Void
    let reset: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ColorPicker(
                token.key,
                selection: Binding(
                    get: { resolved.color },
                    set: { setColor(ThemeColor(swiftUIColor: $0).hex) }
                ),
                supportsOpacity: true
            )
            .labelsHidden()
            .frame(width: 46)
            .help(resolved.hex)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(token.key)
                        .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme[ThemeKey.settingsForeground])
                        .textSelection(.enabled)
                    if explicitHex != nil {
                        SettingsPill(text: "Set", tinted: true)
                    } else {
                        SettingsPill(text: "Inherited")
                    }
                }
                Text(token.description)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    .fixedSize(horizontal: false, vertical: true)
                if explicitHex == nil {
                    Text("Default: \(token.defaultValue(for: kind).expression)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                        .textSelection(.enabled)
                }
                ForEach(issues, id: \.self) { finding in
                    Label(issueText(finding), systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(theme[ThemeKey.statusWarning])
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HexField(hex: explicitHex ?? resolved.hex, tokenKey: token.key, onCommit: setColor)
            Button(action: reset) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .foregroundStyle(explicitHex == nil ? theme[ThemeKey.settingsSecondaryForeground].opacity(0.4) : theme[ThemeKey.accent])
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(explicitHex == nil)
            .help(explicitHex == nil ? "Already using the default" : "Reset to default: \(token.defaultValue(for: kind).expression)")
            .accessibilityLabel("Reset \(token.key) to its default")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    private func issueText(_ finding: ThemeAudit.Finding) -> String {
        let ratio = String(format: "%.1f:1", finding.ratio)
        let minimum = String(format: "%g:1", finding.minimum)
        if finding.foreground == token.key {
            return "\(ratio) on \(finding.background), needs \(minimum)"
        }
        return "\(finding.foreground) on this is \(ratio), needs \(minimum)"
    }
}

/// An editable hex value that commits on Return or when focus leaves.
private struct HexField: View {
    @Environment(\.theme) private var theme
    let hex: String
    let tokenKey: String
    let onCommit: (String) -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    init(hex: String, tokenKey: String, onCommit: @escaping (String) -> Void) {
        self.hex = hex
        self.tokenKey = tokenKey
        self.onCommit = onCommit
    }

    var body: some View {
        TextField("Hex value for \(tokenKey)", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(theme[ThemeKey.settingsForeground])
            .focused($isFocused)
            .onSubmit(commit)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .frame(width: 96)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(theme[ThemeKey.settingsControlBackground]))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(isFocused ? theme[ThemeKey.focusBorder] : theme[ThemeKey.settingsBorder], lineWidth: isFocused ? 1.5 : 1)
            )
            .onAppear { text = hex }
            .onChange(of: hex) { _, newValue in
                if !isFocused { text = newValue }
            }
            .onChange(of: isFocused) { _, focused in
                if !focused { commit() }
            }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let color = ThemeColor(hex: trimmed) else {
            text = hex
            return
        }
        if color.hex != ThemeColor(hex: hex)?.hex { onCommit(color.hex) }
        text = color.hex
    }
}

// MARK: - Nick palette

/// A row of color wells for `nickColors`, with add, remove and reset.
struct NickPaletteEditor: View {
    @Environment(\.theme) private var theme
    let draft: ThemeDefinition
    let findings: [ThemeAudit.Finding]
    let update: ((inout ThemeDefinition) -> Void) -> Void

    var body: some View {
        let palette = theme.nickColors.map(\.hex)
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Nick colors")
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                Text(draft.nickColors == nil ? "Default palette" : "\(palette.count) colors")
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground].opacity(0.8))
            }
            .frame(width: 84, alignment: .leading)

            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(palette.indices, id: \.self) { index in
                        let finding = findings.first { $0.foreground == "nickColors[\(index)]" }
                        VStack(spacing: 3) {
                            ColorPicker(
                                "Nick color \(index + 1)",
                                selection: Binding(
                                    get: { theme.nickColors.indices.contains(index) ? theme.nickColors[index].color : .clear },
                                    set: { color in set(index, ThemeColor(swiftUIColor: color).hex, palette: palette) }
                                ),
                                supportsOpacity: false
                            )
                            .labelsHidden()
                            .controlSize(.small)
                            Circle()
                                .fill(finding == nil ? .clear : theme[ThemeKey.statusWarning])
                                .frame(width: 5, height: 5)
                        }
                        .help(finding.map { String(format: "%@ — %.1f:1 on chat.background, needs %g:1", palette[index], $0.ratio, $0.minimum) } ?? palette[index])
                        .contextMenu {
                            Button("Remove Color") { remove(index, palette: palette) }
                                .disabled(palette.count <= 1)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.never)

            Button {
                let seed = palette.last.flatMap(ThemeColor.init(hex:)) ?? theme.color(ThemeKey.accent)
                let next = seed.mixed(with: theme.color(ThemeKey.chatForeground), amount: 0.35)
                update { $0.nickColors = palette + [next.hex] }
            } label: {
                Image(systemName: "plus").frame(width: 12, height: 12)
            }
            .buttonStyle(ThemedButtonStyle())
            .help("Add a nick color")
            .accessibilityLabel("Add nick color")
            Button {
                remove(palette.count - 1, palette: palette)
            } label: {
                Image(systemName: "minus").frame(width: 12, height: 12)
            }
            .buttonStyle(ThemedButtonStyle())
            .themedDisabled(palette.count <= 1)
            .help("Remove the last nick color")
            .accessibilityLabel("Remove last nick color")
            Button("Reset") { update { $0.nickColors = nil } }
                .buttonStyle(ThemedButtonStyle())
                .themedDisabled(draft.nickColors == nil)
                .help("Use the default palette for \(draft.type == .dark ? "dark" : "light") themes")
        }
    }

    private func set(_ index: Int, _ hex: String, palette: [String]) {
        var colors = palette
        guard colors.indices.contains(index) else { return }
        colors[index] = hex
        update { $0.nickColors = colors }
    }

    private func remove(_ index: Int, palette: [String]) {
        guard palette.count > 1, palette.indices.contains(index) else { return }
        var colors = palette
        colors.remove(at: index)
        update { $0.nickColors = colors }
    }
}

// MARK: - mIRC colors

/// Color wells for mIRC colors 0–15.
struct IRCColorEditor: View {
    @Environment(\.theme) private var theme
    let draft: ThemeDefinition
    let update: ((inout ThemeDefinition) -> Void) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 70), spacing: 8, alignment: .leading), count: 8), alignment: .leading, spacing: 10) {
                ForEach(0..<16, id: \.self) { index in
                    let isSet = draft.ircColors?["\(index)"] != nil
                    HStack(spacing: 5) {
                        ColorPicker(
                            "mIRC color \(index), \(IRCPalette.name(of: index))",
                            selection: Binding(
                                get: { theme.ircColor(index)?.color ?? .clear },
                                set: { color in
                                    let hex = ThemeColor(swiftUIColor: color).hex
                                    update { definition in
                                        var colors = definition.ircColors ?? [:]
                                        colors["\(index)"] = hex
                                        definition.ircColors = colors
                                    }
                                }
                            ),
                            supportsOpacity: false
                        )
                        .labelsHidden()
                        .controlSize(.small)
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 3) {
                                Text("\(index)")
                                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(theme[ThemeKey.settingsForeground])
                                if isSet {
                                    Circle().fill(theme[ThemeKey.accent]).frame(width: 4, height: 4)
                                }
                            }
                            Text(IRCPalette.name(of: index))
                                .font(.system(size: 9.5))
                                .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    .contextMenu {
                        Button("Reset to Default") { reset(index) }
                            .disabled(!isSet)
                    }
                }
            }
            HStack {
                Text("Colors 16–98 keep the standard extended palette unless the theme file sets them. Right-click a color to reset it.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Reset All") { update { $0.ircColors = nil } }
                    .buttonStyle(ThemedButtonStyle())
                    .themedDisabled((draft.ircColors ?? [:]).isEmpty)
            }
        }
    }

    private func reset(_ index: Int) {
        update { definition in
            var colors = definition.ircColors ?? [:]
            colors.removeValue(forKey: "\(index)")
            definition.ircColors = colors.isEmpty ? nil : colors
        }
    }
}
