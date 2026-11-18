// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaFoundation
import VelaStore
import VelaTheme

/// Which control a setting gets, from its schema and metadata.
enum SettingControlKind: Equatable {
    case toggle
    /// `SystemFollowingBool`: a switch that follows macOS until set.
    case followsSystem
    case menu([String])
    case number(range: ClosedRange<Double>?, integer: Bool)
    /// A string with suggestions: a single-value token field.
    case suggestedString(SettingSuggestionSource)
    case text
    /// `[String]`: a token field with chips.
    case stringList(SettingSuggestionSource?)
    /// A list whose elements are a fixed set of strings (`dock.badgeCounts`):
    /// a token field offering just those.
    case enumList([String])
    case siteRules
    case colorCustomizations
    /// Any other object: edited in settings.json.
    case object
    /// A key Vela doesn't know.
    case unknown

    init(_ entry: SettingsEditorEntry) {
        guard let descriptor = entry.descriptor else {
            self = .unknown
            return
        }
        if descriptor.followsSystem {
            self = .followsSystem
            return
        }
        if let values = descriptor.enumValues {
            self = .menu(values)
            return
        }
        switch SettingsJSONText.schemaType(descriptor.schema) {
        case "boolean":
            self = .toggle
        case "number", "integer":
            self = .number(range: descriptor.numberRange, integer: SettingsJSONText.schemaType(descriptor.schema) == "integer")
        case "string":
            self = descriptor.suggestionSource.map { .suggestedString($0) } ?? .text
        case "array":
            if let values = descriptor.itemEnumValues {
                self = .enumList(values)
            } else {
                self = .stringList(descriptor.suggestionSource)
            }
        case "object":
            switch descriptor.key {
            case SettingKey<[String: JSONValue]>.mediaSiteRules.key: self = .siteRules
            case SettingKey<[String: JSONValue]>.appearanceColorCustomizations.key: self = .colorCustomizations
            default: self = .object
            }
        default:
            self = .object
        }
    }

    /// Wide controls go under the description instead of beside it.
    var isWide: Bool {
        switch self {
        case .stringList, .enumList, .siteRules, .colorCustomizations, .object, .unknown: true
        default: false
        }
    }
}

/// One setting: "Group: **Name**", the description, the control, a
/// Modified bar on the left and a ⚙ menu.
struct SettingsEditorRow: View {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var uiState
    @Environment(\.theme) private var theme
    @Environment(\.settingsControlWidth) private var controlWidth
    let entry: SettingsEditorEntry
    let provider: SettingSuggestionProvider

    @State private var isHovered = false

    var body: some View {
        let kind = SettingControlKind(entry)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: kind.isWide ? .top : .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .center, spacing: 4) {
                        title
                        gearMenu
                    }
                    if let summary = entry.descriptor?.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if kind == .followsSystem {
                        FollowsSystemStatus(entry: entry, write: write)
                            .padding(.top, 2)
                    }
                    if entry.isUnknown {
                        Label("Unknown setting. Vela keeps it but doesn't use it.", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme[ThemeKey.statusWarning])
                            .labelStyle(WarningLabelStyle())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                // On the texts only, so text fields keep their own menus.
                .contextMenu { menuItems }
                if !kind.isWide {
                    control(kind)
                }
            }
            if kind.isWide {
                control(kind)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovered ? theme[ThemeKey.settingsForeground].opacity(0.025) : .clear)
        .overlay(alignment: .leading) {
            if entry.isModified {
                Capsule()
                    .fill(theme[entry.isUnknown ? ThemeKey.statusWarning : ThemeKey.accent])
                    .frame(width: 3)
                    .padding(.vertical, 8)
                    .padding(.leading, 5)
                    .help(entry.isUnknown ? "In settings.json, unknown" : "Modified in settings.json")
                    .accessibilityHidden(true)
            }
        }
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(valueDescription)
    }

    // MARK: Title

    @ViewBuilder
    private var title: some View {
        if let descriptor = entry.descriptor {
            Text("\(descriptor.groupTitle): \(Text(descriptor.name).fontWeight(.semibold))")
                .font(.system(size: 13))
                .foregroundStyle(theme[ThemeKey.settingsForeground])
                .help(entry.key)
                .accessibilityHidden(true)
        } else {
            Text(entry.key)
                .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme[ThemeKey.settingsForeground])
                .textSelection(.enabled)
                .accessibilityHidden(true)
        }
    }

    private var accessibilityTitle: String {
        let name = entry.descriptor?.title ?? "\(entry.key), unknown setting"
        return entry.isModified ? "\(name), modified" : name
    }

    /// The value for VoiceOver.
    private var valueDescription: String {
        let value = entry.effectiveValue
        switch value {
        case .bool(let on): return on ? "On" : "Off"
        case .string(let text): return text.isEmpty ? "Empty" : provider.label(for: text, source: entry.descriptor?.suggestionSource)
        case .number(let number): return NumberSettingInput.format(number, integer: false)
        case .array(let items):
            let isEnumList = entry.descriptor?.itemEnumValues != nil
            return items.isEmpty ? "Empty list" : items.map { item in
                item.stringValue.map {
                    isEnumList ? SettingsMetadata.enumLabel($0) : provider.label(for: $0, source: entry.descriptor?.suggestionSource)
                } ?? SettingsJSONText.compact(item)
            }.joined(separator: ", ")
        case .object(let object): return object.isEmpty ? "Empty" : "\(object.count) \(object.count == 1 ? "entry" : "entries")"
        case .null: return "null"
        }
    }

    // MARK: Menu

    private var gearMenu: some View {
        Menu {
            menuItems
        } label: {
            GearLabel(isVisible: isHovered)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More Actions for \(entry.key)")
        .accessibilityLabel("More actions for \(entry.descriptor?.title ?? entry.key)")
    }

    @ViewBuilder
    private var menuItems: some View {
        if entry.isModified {
            Button(entry.isUnknown ? "Remove Setting" : "Reset Setting") { reset() }
            Divider()
        }
        Button("Copy Setting ID") { copy(entry.key) }
        Button("Copy Setting as JSON") { copy(SettingsJSONText.entry(key: entry.key, value: entry.effectiveValue)) }
        Divider()
        Button("Edit in settings.json") { uiState.settingsEditor.editInJSON(entry.key) }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: Writing

    /// Writes `value`; a known setting set back to its default is removed
    /// from settings.json instead, like VS Code.
    private func write(_ value: JSONValue?) {
        if let value, let descriptor = entry.descriptor, value == descriptor.defaultValue {
            app.settings.setValue(nil, forKey: entry.key)
        } else {
            app.settings.setValue(value, forKey: entry.key)
        }
    }

    private func reset() {
        app.settings.setValue(nil, forKey: entry.key)
    }

    // MARK: Controls

    @ViewBuilder
    private func control(_ kind: SettingControlKind) -> some View {
        let title = entry.descriptor?.title ?? entry.key
        let value = entry.effectiveValue
        switch kind {
        case .toggle:
            Toggle(title, isOn: Binding(
                get: { value.boolValue ?? false },
                set: { write(.bool($0)) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
            .accessibilityLabel(title)
        case .followsSystem:
            FollowsSystemToggle(entry: entry, title: title, write: write)
        case .menu(let options):
            EnumSettingControl(title: title, current: value.stringValue ?? SettingsJSONText.compact(value), options: options) {
                write(.string($0))
            }
        case .number(let range, let integer):
            NumberSettingControl(
                title: title,
                value: value.doubleValue ?? 0,
                range: range,
                integer: integer,
                write: { write(.number($0)) }
            )
        case .suggestedString(let source):
            let current = value.stringValue ?? ""
            TokenField(
                values: current.isEmpty ? [] : [current],
                allowsMultiple: false,
                suggestions: provider.suggestions(for: source),
                placeholder: SettingSuggestionProvider.emptyPlaceholder(for: entry.key, source: source),
                accessibilityLabel: title,
                label: { provider.label(for: $0, source: source) },
                detail: { provider.detail(for: $0, source: source) },
                resolve: { provider.resolve($0, source: source) },
                rejectionMessage: Self.rejectionMessage(for: source),
                monospaced: source == .timestampPatterns,
                // Removing the chip goes back to the default.
                onChange: { values in
                    if let value = values.first { write(.string(value)) } else { reset() }
                }
            )
            .frame(width: controlWidth)
        case .text:
            CommitTextField(
                placeholder: "",
                value: value.stringValue ?? "",
                accessibilityName: title,
                validate: { .accept($0) },
                write: { write(.string($0)) }
            )
            .frame(width: controlWidth)
        case .stringList(let source):
            let items = (value.arrayValue ?? []).compactMap(\.stringValue)
            TokenField(
                values: items,
                allowsMultiple: true,
                suggestions: source.map(provider.suggestions(for:)) ?? [],
                placeholder: Self.listPlaceholder(for: source),
                accessibilityLabel: title,
                label: { provider.label(for: $0, source: source) },
                resolve: { provider.resolve($0, source: source) },
                rejectionMessage: Self.rejectionMessage(for: source),
                showsSuggestionsOnFocus: source != nil,
                onChange: { write(.array($0.map { .string($0) })) }
            )
        case .enumList(let allowed):
            TokenField(
                values: (value.arrayValue ?? []).compactMap(\.stringValue),
                allowsMultiple: true,
                suggestions: allowed.map { TokenSuggestion(value: $0, label: SettingsMetadata.enumLabel($0)) },
                placeholder: "Add…",
                accessibilityLabel: title,
                label: { SettingsMetadata.enumLabel($0) },
                resolve: { Self.resolveEnumValue($0, allowed: allowed) },
                rejectionMessage: "Choose from the list: " + allowed.map(SettingsMetadata.enumLabel).joined(separator: ", ") + ".",
                showsSuggestionsOnFocus: true,
                onChange: { write(.array($0.map { .string($0) })) }
            )
        case .siteRules:
            SettingsInsetBox {
                SiteRulesEditor(
                    rules: app.siteRules.entries,
                    emptyMessage: "No site rules. Add a site to always show, limit or block its previews.",
                    setRule: { access, domain in app.setSiteRule(access, forDomain: domain) },
                    domainSuggestions: provider.suggestions(for: .domains)
                )
            }
        case .colorCustomizations:
            ColorCustomizationsEditor(provider: provider)
        case .object:
            JSONValueSummary(value: value) {
                uiState.settingsEditor.editInJSON(entry.key)
            }
        case .unknown:
            UnknownSettingControl(entry: entry, write: { app.settings.setValue($0, forKey: entry.key) })
        }
    }

    static func rejectionMessage(for source: SettingSuggestionSource?) -> String {
        switch source {
        case .buffers: "Pick a channel or network from the list, or type a channel's name."
        case .domains: "Enter a site's domain, such as example.com."
        case .languages: "Pick a language from the list, or type a language code such as “pt-BR”."
        default: "That isn't a value this setting accepts."
        }
    }

    /// Typed text for an enum list: one of `allowed`, by its settings.json
    /// value or its label, ignoring case; anything else is refused.
    static func resolveEnumValue(_ text: String, allowed: [String]) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return allowed.first {
            $0.caseInsensitiveCompare(trimmed) == .orderedSame
                || SettingsMetadata.enumLabel($0).caseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    static func listPlaceholder(for source: SettingSuggestionSource?) -> String {
        switch source {
        case .buffers: "Add a channel or network…"
        case .domains: "Add a site…"
        default: "Add a word, then press Return…"
        }
    }
}

/// The ⚙ button: faint until the row is hovered.
private struct GearLabel: View {
    @Environment(\.theme) private var theme
    let isVisible: Bool
    @State private var isHovered = false

    var body: some View {
        Image(systemName: "gearshape")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(theme[isHovered ? ThemeKey.settingsForeground : ThemeKey.settingsSecondaryForeground])
            .frame(width: 20, height: 18)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isHovered ? theme[ThemeKey.settingsForeground].opacity(0.08) : .clear)
            )
            .contentShape(Rectangle())
            .opacity(isVisible || isHovered ? 1 : 0.0)
            .onHover { isHovered = $0 }
    }
}

/// A warning line: a small icon and text, top-aligned.
private struct WarningLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            configuration.icon.font(.system(size: 10))
            configuration.title.fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A recessed box for wide editors inside a row (site rules, color
/// customizations).
struct SettingsInsetBox<Content: View>: View {
    @Environment(\.theme) private var theme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme[ThemeKey.settingsBackground])
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(theme[ThemeKey.settingsBorder])
            )
    }
}
