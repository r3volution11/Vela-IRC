// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaIntelligence
import VelaStore
import VelaTheme

/// Opening Settings → Intelligence at its Models section.
@MainActor
enum AIModelActions {
    static func openSettings(uiState: UIState, openSettings: OpenSettingsAction) {
        uiState.settingsSectionReveal = .aiModels
        uiState.settingsEditor.requestedPane = .intelligence
        openSettings()
    }

    /// A menu item's title: "Claude Opus 5.5 (recommended)".
    static func itemTitle(_ item: AIModelMenuItem) -> String {
        item.isRecommended ? "\(item.title) (recommended)" : item.title
    }
}

/// "Change ⌄" under a Catch me up card or a Recap: every model that can be
/// chosen (Apple's first, then your providers'), checked where it's the one
/// that wrote it; choosing one writes it again with that model. Apple's
/// models are dimmed while Apple Intelligence can't run.
struct AIModelChangeMenu: View {
    @Environment(IntelligenceServices.self) private var intelligence
    @Environment(UIState.self) private var uiState: UIState?
    @Environment(\.openSettings) private var openSettings
    /// The model asked for (or the setting's), for the checkmark.
    let current: AIModelChoice
    var title = "Change"
    var font: Font = .system(size: 11, weight: .semibold)
    let choose: (AIModelChoice) -> Void

    var body: some View {
        let models = intelligence.models
        let appleAvailable = models.isAppleAvailable
        Menu {
            ForEach(models.menuSections()) { section in
                Section(section.title) {
                    ForEach(section.items) { item in
                        Button {
                            choose(item.choice)
                        } label: {
                            if item.choice == current {
                                Label(AIModelActions.itemTitle(item), systemImage: "checkmark")
                            } else {
                                Text(AIModelActions.itemTitle(item))
                            }
                        }
                        .disabled(item.isApple && !appleAvailable)
                    }
                }
            }
            if let uiState {
                Divider()
                Button("Manage Models…") { AIModelActions.openSettings(uiState: uiState, openSettings: openSettings) }
            }
        } label: {
            Text(title).font(font)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
        .help("Write this again with another model")
        .accessibilityLabel("Change model")
        .accessibilityValue(models.title(for: current))
        .accessibilityHint("Writes this again with the model you choose")
    }
}

/// A Settings row picking a model setting (`intelligence.model`,
/// `intelligence.catchUpModel`, `intelligence.recapModel`): Apple's
/// models, then each provider that's on with its recommended model first.
/// A feature's row starts with "Same as default". A model saved in
/// settings.json that isn't in the lists is kept, and listed.
struct AIModelSettingRow: View {
    @Environment(AppModel.self) private var app
    @Environment(IntelligenceServices.self) private var intelligence
    let title: String
    var detail: String?
    let key: SettingKey<String>
    /// A feature's row: "" follows `intelligence.model`.
    var followsDefault = false

    var body: some View {
        @Bindable var settings = app.settings
        let models = intelligence.models
        let sections = models.menuSections()
        let listed = Set(sections.flatMap(\.items).map(\.choice.settingValue))
        let current = settings[key]
        let isListed = current.isEmpty ? followsDefault : listed.contains(AIModelChoice(settingValue: current)?.settingValue ?? current)
        SettingsRow(title, detail: detail, labelsControl: true) {
            Picker(title, selection: selection(current)) {
                if followsDefault {
                    let defaultChoice = AIModelChoice(settingValue: settings[.intelligenceModel]) ?? .automatic
                    Text("Same as default (\(models.title(for: defaultChoice)))").tag("")
                }
                ForEach(sections) { section in
                    Section(section.title) {
                        ForEach(section.items) { item in
                            Text(AIModelActions.itemTitle(item)).tag(item.choice.settingValue)
                        }
                    }
                }
                if !isListed {
                    Divider()
                    Text(AIModelChoice(settingValue: current).map(models.title(for:)) ?? current).tag(current)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .accessibilityHint(detail ?? "")
        }
    }

    /// Writes the choice; picking what's the default anyway removes the
    /// key from settings.json.
    private func selection(_ current: String) -> Binding<String> {
        Binding(
            get: { current },
            set: { value in
                if value == key.defaultValue {
                    app.settings.reset(key)
                } else {
                    app.settings[key] = value
                }
            }
        )
    }
}
