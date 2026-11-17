// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaFoundation
import VelaStore
import VelaTheme

// The settings editor's controls for each kind of value (see
// ``SettingControlKind``). They show the value they're given and report
// changes; none keeps its own copy of a setting.

// MARK: - Follows macOS

/// What macOS says for a `SystemFollowingBool` setting.
enum SystemFollowingSettings {
    static func systemValue(forKey key: String, in values: SystemTextDefaults) -> Bool {
        switch key {
        case SettingKey<SystemFollowingBool>.inputAutocorrect.key: values.autocorrect
        case SettingKey<SystemFollowingBool>.inputTextReplacements.key: values.textReplacements
        case SettingKey<SystemFollowingBool>.inputSmartPunctuation.key: values.smartPunctuation
        default: false
        }
    }

    static func current(_ entry: SettingsEditorEntry) -> SystemFollowingBool {
        SystemFollowingBool(settingJSON: entry.effectiveValue) ?? .system
    }
}

/// The switch of a setting that follows macOS: it shows the value in
/// effect; flipping it sets the setting.
struct FollowsSystemToggle: View {
    let entry: SettingsEditorEntry
    let title: String
    let write: (JSONValue?) -> Void

    var body: some View {
        let system = SystemFollowingSettings.systemValue(forKey: entry.key, in: SystemTextSettings.shared.values)
        let current = SystemFollowingSettings.current(entry)
        Toggle(title, isOn: Binding(
            get: { current.resolved(system: system) },
            set: { write(SystemFollowingBool($0).settingJSON) }
        ))
        .toggleStyle(.switch)
        .labelsHidden()
        .controlSize(.small)
        .accessibilityLabel(title)
        .accessibilityHint(current == .system ? "Same as macOS." : "Changed from the macOS setting.")
    }
}

/// "Same as macOS" while the setting follows macOS, else a "Use macOS
/// Setting" link that removes it.
struct FollowsSystemStatus: View {
    @Environment(\.theme) private var theme
    let entry: SettingsEditorEntry
    let write: (JSONValue?) -> Void

    var body: some View {
        let system = SystemFollowingSettings.systemValue(forKey: entry.key, in: SystemTextSettings.shared.values)
        if SystemFollowingSettings.current(entry) == .system {
            Text("Same as macOS")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                .accessibilityHidden(true)
        } else {
            SettingsLinkButton("Use macOS Setting") { write(nil) }
                .help("Follow System Settings → Keyboard → Text Input (\(system ? "on" : "off") there)")
                .accessibilityHint("macOS has it \(system ? "on" : "off").")
        }
    }
}

// MARK: - Pop-up

/// A pop-up of a setting's allowed values. A value in settings.json that
/// isn't one of them is listed too, marked invalid.
struct EnumSettingControl: View {
    let title: String
    let current: String
    let options: [String]
    let select: (String) -> Void

    var body: some View {
        Picker(title, selection: Binding(get: { current }, set: { select($0) })) {
            if !options.contains(current) {
                Text("\(current) (invalid)").tag(current)
                Divider()
            }
            ForEach(options, id: \.self) { option in
                Text(SettingsMetadata.enumLabel(option)).tag(option)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
        .help("settings.json value: \"\(current)\"")
        .accessibilityLabel(title)
    }
}

// MARK: - Number

/// A number field and stepper. The stepper stays in range; a typed number
/// out of range (or not a number) shows why and isn't written.
struct NumberSettingControl: View {
    @Environment(\.theme) private var theme
    let title: String
    let value: Double
    let range: ClosedRange<Double>?
    let integer: Bool
    let write: (Double) -> Void

    @State private var text = ""
    @State private var problem: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        let step = NumberSettingInput.step(for: range, integer: integer)
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 4) {
                TextField(title, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5).monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(theme[ThemeKey.settingsForeground])
                    .focused($isFocused)
                    .onSubmit(commit)
                    .onExitCommand(perform: revert)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .frame(width: 72)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(theme[ThemeKey.settingsBackground])
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(
                                problem != nil ? theme[ThemeKey.statusError] : (isFocused ? theme[ThemeKey.focusBorder] : theme[ThemeKey.settingsBorder]),
                                lineWidth: isFocused ? 1.5 : 1
                            )
                    )
                    .help(range.map { "From \(format($0.lowerBound)) to \(format($0.upperBound))" } ?? "")
                    .accessibilityLabel(title)
                    .accessibilityHint(range.map { "From \(format($0.lowerBound)) to \(format($0.upperBound))." } ?? "")
                Stepper(
                    title,
                    value: Binding(
                        get: { value },
                        set: { newValue in
                            let snapped = integer ? newValue.rounded() : (newValue / step).rounded() * step
                            write(NumberSettingInput.clamp(snapped, to: range))
                            problem = nil
                        }
                    ),
                    in: range ?? -1_000_000_000...1_000_000_000,
                    step: step
                )
                .labelsHidden()
                .controlSize(.small)
                .accessibilityLabel(title)
                .accessibilityValue(format(value))
            }
            if let problem {
                Text(problem)
                    .font(.system(size: 11))
                    .foregroundStyle(theme[ThemeKey.statusError])
                    .fixedSize()
                    .accessibilityLabel("Problem: \(problem)")
            }
        }
        .onAppear { text = format(value) }
        .onChange(of: value) { _, newValue in
            if !isFocused { text = format(newValue) }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { commit() }
        }
        .onChange(of: text) { problem = nil }
    }

    private func format(_ number: Double) -> String {
        NumberSettingInput.format(number, integer: integer)
    }

    private func commit() {
        switch NumberSettingInput.parse(text, range: range, integer: integer) {
        case .success(let parsed):
            problem = nil
            if parsed != value { write(parsed) }
            text = format(parsed)
        case .failure(let failure):
            problem = failure.message(integer: integer)
        }
    }

    private func revert() {
        text = format(value)
        problem = nil
    }
}

// MARK: - Text

/// What a ``CommitTextField`` does with its text.
enum TextValidation {
    /// Write this.
    case accept(String)
    /// Don't write; show why.
    case reject(String)
}

/// A text field that writes on Return or when it loses focus, after
/// `validate` accepts the text. Esc puts the value back.
struct CommitTextField: View {
    @Environment(\.theme) private var theme
    var placeholder: String
    let value: String
    var accessibilityName: String
    var monospaced = false
    /// The value to write, or why the text can't be written.
    var validate: (String) -> TextValidation
    let write: (String) -> Void

    @State private var text = ""
    @State private var problem: String?
    @FocusState private var isFocused: Bool

    init(
        placeholder: String,
        value: String,
        accessibilityName: String,
        monospaced: Bool = false,
        validate: @escaping (String) -> TextValidation,
        write: @escaping (String) -> Void
    ) {
        self.placeholder = placeholder
        self.value = value
        self.accessibilityName = accessibilityName
        self.monospaced = monospaced
        self.validate = validate
        self.write = write
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(accessibilityName, text: $text, prompt: Text(placeholder).foregroundStyle(theme[ThemeKey.settingsSecondaryForeground].opacity(0.75)))
                .textFieldStyle(.plain)
                .font(monospaced ? .system(size: 12, design: .monospaced) : .system(size: 12.5))
                .foregroundStyle(theme[ThemeKey.settingsForeground])
                .focused($isFocused)
                .onSubmit(commit)
                .onExitCommand(perform: revert)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(theme[ThemeKey.settingsBackground])
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            problem != nil ? theme[ThemeKey.statusError] : (isFocused ? theme[ThemeKey.focusBorder] : theme[ThemeKey.settingsBorder]),
                            lineWidth: isFocused ? 1.5 : 1
                        )
                )
            if let problem {
                Text(problem)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme[ThemeKey.statusError])
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Problem: \(problem)")
            }
        }
        .onAppear { text = value }
        .onChange(of: value) { _, newValue in
            if !isFocused { text = newValue }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { commit() }
        }
        .onChange(of: text) { problem = nil }
    }

    private func commit() {
        guard text != value else {
            problem = nil
            return
        }
        switch validate(text) {
        case .accept(let accepted):
            problem = nil
            write(accepted)
        case .reject(let message):
            problem = message
        }
    }

    private func revert() {
        text = value
        problem = nil
    }
}

// MARK: - Objects and unknown keys

/// An object without its own editor: its JSON, and a button to edit it in
/// settings.json.
struct JSONValueSummary: View {
    @Environment(\.theme) private var theme
    let value: JSONValue
    let edit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(SettingsJSONText.compact(value))
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            Button("Edit in settings.json", action: edit)
                .buttonStyle(ThemedButtonStyle())
        }
    }
}

/// A key Vela doesn't know: its raw JSON value, editable, and Remove.
struct UnknownSettingControl: View {
    let entry: SettingsEditorEntry
    let write: (JSONValue?) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            CommitTextField(
                placeholder: "JSON value",
                value: entry.value.map(SettingsJSONText.compact) ?? "",
                accessibilityName: "Value of \(entry.key), as JSON",
                monospaced: true,
                validate: { text in
                    switch SettingsJSONText.parse(text) {
                    case .value: .accept(text)
                    case .problem(let message): .reject(message)
                    }
                },
                write: { text in
                    if case .value(let value) = SettingsJSONText.parse(text) { write(value) }
                }
            )
            Button("Remove") { write(nil) }
                .buttonStyle(ThemedButtonStyle())
                .help("Remove \(entry.key) from settings.json")
                .accessibilityLabel("Remove \(entry.key)")
        }
    }
}
