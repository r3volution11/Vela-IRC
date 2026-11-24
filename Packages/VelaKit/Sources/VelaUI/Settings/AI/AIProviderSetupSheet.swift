// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaIntelligence
import VelaStore
import VelaTheme

/// What the setup sheet opens on.
struct AIProviderSetupRequest: Identifiable {
    enum Start: Equatable {
        /// Choose OpenAI, Anthropic or Google Gemini.
        case choose
        /// Straight to the key for one of them (the Add Provider menu).
        case key(AIProviderKind)
        /// A provider just connected (Connect for a server on this Mac): its
        /// OK to be sent messages, and whether it becomes the default.
        case connected(providerID: String)
    }

    let id = UUID()
    let start: Start

    /// The providers the sheet walks you through, in its order.
    static let hostedKinds: [AIProviderKind] = [.openAI, .anthropic, .gemini]
}

/// What the setup sheet says, where it depends on what happened. Pure, so
/// it's tested.
enum AIProviderSetupText {
    /// A Test Connection that worked.
    static func connected(_ count: Int) -> String {
        switch count {
        case 0: "Connected. The key works."
        case 1: "Connected. 1 model is available."
        default: "Connected. \(count) models are available."
        }
    }

    /// A Test Connection that didn't, plainly, for someone who just made
    /// their first key.
    static func problem(_ failure: AIProviderFailure, kind: AIProviderKind) -> String {
        let name = kind.displayName
        switch failure.reason {
        case .badKey:
            return "\(name) didn't accept this key. Check that you copied all of it, or make a new one."
        case .quota:
            return "The key works, but the account is out of credit or over its limit. Check billing with \(name), then test again."
        case .offline:
            return "Couldn't reach \(name). Check your internet connection, then test again."
        case .timedOut:
            return "\(name) took too long to answer. Test again in a moment."
        case .missingKey:
            return "Paste a key first."
        case .other(let detail):
            return "\(name) said: \(detail)"
        default:
            return failure.message
        }
    }

    /// A failure that says nothing about the key: you can add it anyway,
    /// and Vela tries again when it's used.
    static func isTransient(_ failure: AIProviderFailure) -> Bool {
        switch failure.reason {
        case .offline, .timedOut, .rateLimited, .overloaded: true
        default: false
        }
    }
}

/// Adding OpenAI, Anthropic or Google Gemini for someone who's never made
/// an API key: choose the provider, then Get a Key (its keys page, with
/// one line on what to do there), paste it (its shape is checked as you
/// paste), Test Connection (lists its models with the key), then what it
/// will be sent, Allow, and whether it becomes the default model. Nothing
/// is saved until Allow and Add; the key goes only to its provider, and
/// then into the Keychain.
///
/// Connect for a server on this Mac opens it at the last step, for the
/// provider just added.
struct AIProviderSetupSheet: View {
    @Environment(IntelligenceServices.self) private var intelligence
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let request: AIProviderSetupRequest

    enum Step: Equatable {
        case choose
        case key
        case allow
    }

    enum KeyCheck: Equatable {
        case idle
        case checking
        case passed([AIModelInfo])
        case failed(AIProviderFailure)
    }

    @State private var step: Step
    @State private var kind: AIProviderKind
    @State private var keyDraft = ""
    @State private var check: KeyCheck = .idle
    @State private var checkTask: Task<Void, Never>?
    /// Continue was clicked before the key was tested: go on once it passes.
    @State private var continuesAfterCheck = false
    @State private var makeDefault: Bool
    @State private var defaultModelID = ""
    @State private var saveError: String?

    init(request: AIProviderSetupRequest, defaultIsApple: Bool) {
        self.request = request
        switch request.start {
        case .choose:
            _step = State(initialValue: .choose)
            _kind = State(initialValue: .openAI)
        case .key(let kind):
            _step = State(initialValue: .key)
            _kind = State(initialValue: kind)
        case .connected:
            _step = State(initialValue: .allow)
            _kind = State(initialValue: .openAICompatible)
        }
        // Becomes the default unless you've already chosen another provider's.
        _makeDefault = State(initialValue: defaultIsApple)
    }

    private var models: AIModels { intelligence.models }

    /// The provider Connect added, for a server on this Mac.
    private var connectedEntry: AIProviderEntry? {
        guard case .connected(let id) = request.start else { return nil }
        return models.providers.first { $0.id == id }
    }

    /// The provider as it will be: what the consent text describes.
    private var entry: AIProviderEntry {
        connectedEntry ?? AIProviderEntry(id: kind.rawValue, kind: kind, name: kind.defaultName)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            SettingsHairline()
            ScrollView {
                Group {
                    switch step {
                    case .choose: chooseStep
                    case .key: keyStep
                    case .allow: allowStep
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            SettingsHairline()
            footer
        }
        .frame(width: 520)
        .frame(minHeight: 380, idealHeight: 520, maxHeight: 760)
        .background(theme[ThemeKey.settingsBackground])
        .onChange(of: keyDraft) { _, _ in resetCheck() }
        .onChange(of: kind) { _, _ in resetCheck() }
        .onDisappear { checkTask?.cancel() }
    }

    // MARK: Header and footer

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.kind == .openAICompatible ? "server.rack" : "sparkles")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(theme[ThemeKey.accentForeground])
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme[ThemeKey.accent]))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(theme[ThemeKey.settingsForeground])
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private var title: String {
        switch step {
        case .choose: "Add a Provider"
        case .key: "Connect \(kind.displayName)"
        case .allow: AIConsentText.title(entry)
        }
    }

    private var subtitle: String {
        switch step {
        case .choose:
            "Have Catch me up and Recap written by a model from your own account. You'll need an API key: making one takes a minute."
        case .key:
            kind.modelsBlurb ?? ""
        case .allow:
            if let connectedEntry {
                "\(connectedEntry.name) is connected. Allow it, and choose whether Catch me up and Recap use it."
            } else {
                "Last step: what \(kind.displayName) is sent, and whether Catch me up and Recap use it."
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if step == .key, request.start == .choose {
                Button("Back") { step = .choose }
                    .buttonStyle(ThemedButtonStyle())
            } else if step == .allow, connectedEntry == nil {
                Button("Back") { step = .key }
                    .buttonStyle(ThemedButtonStyle())
            }
            Spacer()
            switch step {
            case .choose:
                Button("Cancel") { dismiss() }
                    .buttonStyle(ThemedButtonStyle())
                    .keyboardShortcut(.cancelAction)
            case .key:
                Button("Cancel") { dismiss() }
                    .buttonStyle(ThemedButtonStyle())
                    .keyboardShortcut(.cancelAction)
                if case .failed(let failure) = check, AIProviderSetupText.isTransient(failure) {
                    Button("Continue Anyway") { step = .allow }
                        .buttonStyle(ThemedButtonStyle())
                        .accessibilityHint("Adds the key without a working test. Vela tries it when it's first used.")
                }
                Button("Continue") { continueFromKey() }
                    .buttonStyle(ThemedButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .themedDisabled(!canTest)
            case .allow:
                if let connectedEntry {
                    Button("Not Now") { dismiss() }
                        .buttonStyle(ThemedButtonStyle())
                        .keyboardShortcut(.cancelAction)
                        .accessibilityHint("Keeps \(connectedEntry.name). Vela asks before sending it anything.")
                    Button("Allow") { allow(connectedEntry) }
                        .buttonStyle(ThemedButtonStyle(prominent: true))
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(ThemedButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Button("Allow and Add") { addHosted() }
                        .buttonStyle(ThemedButtonStyle(prominent: true))
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(theme[ThemeKey.settingsSidebarBackground])
    }

    // MARK: Choose

    private var chooseStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(AIProviderSetupRequest.hostedKinds, id: \.self) { option in
                let added = models.providers.contains { $0.kind == option }
                ProviderOptionButton(kind: option, isAdded: added) {
                    kind = option
                    step = .key
                }
                .disabled(added)
            }
            Text("To use a model on this Mac with no key or account, close this and connect Ollama or LM Studio under On this Mac.")
                .font(.system(size: 11.5))
                .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }

    // MARK: Key

    private var keyStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            numbered(1, "Get a key") {
                VStack(alignment: .leading, spacing: 8) {
                    if let steps = kind.keySteps { caption(steps) }
                    if let url = kind.keyURL {
                        Button("Get a Key") { NSWorkspace.shared.open(url) }
                            .buttonStyle(ThemedButtonStyle())
                            .help(url.absoluteString)
                            .accessibilityHint("Opens \(kind.displayName)'s API keys page in your browser")
                    }
                    if let cost = kind.costNote { caption(cost) }
                }
            }
            numbered(2, "Paste it here") {
                VStack(alignment: .leading, spacing: 6) {
                    ThemedTextField(kind.keyPlaceholder, text: $keyDraft, isSecure: true, monospaced: true, accessibilityName: "\(kind.displayName) API key") {
                        continueFromKey()
                    }
                    .frame(maxWidth: 360)
                    shapeNote
                }
            }
            numbered(3, "Test it") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Button("Test Connection") { runCheck() }
                            .buttonStyle(ThemedButtonStyle())
                            .themedDisabled(!canTest || check == .checking)
                            .accessibilityHint("Asks \(kind.displayName) for its models with this key. Nothing else is sent.")
                        if check == .checking {
                            ProgressView().controlSize(.small).accessibilityLabel("Testing")
                        }
                    }
                    switch check {
                    case .passed(let list):
                        SettingsCallout(.success, AIProviderSetupText.connected(list.count))
                    case .failed(let failure):
                        SettingsCallout(.error, "Couldn't connect", message: AIProviderSetupText.problem(failure, kind: kind))
                    case .idle, .checking:
                        EmptyView()
                    }
                }
            }
            caption("Your key is kept in your Keychain, and sent only to \(kind.displayName).")
        }
    }

    private var shape: AIKeyShape { AIKeyShape(key: keyDraft, for: kind) }

    /// A key to test: pasted, and not another provider's.
    private var canTest: Bool {
        switch shape {
        case .empty, .otherProvider: false
        case .expected, .unexpected: true
        }
    }

    @ViewBuilder private var shapeNote: some View {
        let shape = shape
        if let message = shape.message(for: kind) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: shape == .expected ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(theme[shape == .expected ? ThemeKey.statusSuccess : ThemeKey.statusWarning])
                    .accessibilityHidden(true)
                Text(message)
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    .fixedSize(horizontal: false, vertical: true)
                if case .otherProvider(let owner) = shape, !models.providers.contains(where: { $0.kind == owner }) {
                    SettingsLinkButton("Use \(owner.displayName) Instead") { kind = owner }
                        .fixedSize()
                }
            }
            .font(.system(size: 11.5))
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Allow

    private var allowStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            AIConsentDetails(entry: entry, foregroundKey: ThemeKey.settingsForeground)
            SettingsCard {
                SettingsToggle(
                    "Use it for Catch me up and Recap",
                    detail: "Makes it the default model. You can choose another, or one for each feature, at any time.",
                    isOn: $makeDefault
                )
                if makeDefault, !offeredModels.isEmpty {
                    SettingsRow("Model", labelsControl: true) {
                        Picker("Default model", selection: $defaultModelID) {
                            ForEach(offeredModels) { model in
                                Text(model.isRecommended ? "\(model.name) (recommended)" : model.name).tag(model.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
                }
            }
            if makeDefault, offeredModels.isEmpty {
                caption("\(entry.name) hasn't listed any models yet. Download one in it, then choose it in AI Providers.")
            }
            if let saveError {
                SettingsCallout(.error, "Couldn't save the key", message: saveError)
            }
        }
        .onAppear(perform: chooseDefaultModel)
    }

    /// The models the default can be: the list the check fetched (or the
    /// server listed), else Vela's picks for the provider.
    private var offeredModels: [AIModelInfo] {
        if case .passed(let list) = check, !list.isEmpty { return list }
        if let connectedEntry { return models.catalog.models(for: connectedEntry) }
        return kind.recommendedModels
    }

    private func chooseDefaultModel() {
        let offered = offeredModels
        guard !offered.contains(where: { $0.id == defaultModelID }) else { return }
        defaultModelID = (offered.first(where: \.isRecommended) ?? offered.first)?.id ?? ""
    }

    // MARK: Actions

    private func resetCheck() {
        checkTask?.cancel()
        checkTask = nil
        continuesAfterCheck = false
        if check != .idle { check = .idle }
    }

    private func runCheck() {
        guard canTest else { return }
        checkTask?.cancel()
        check = .checking
        let key = keyDraft
        let kind = kind
        checkTask = Task {
            let result = await models.checkKey(key, for: kind)
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let list):
                check = .passed(list)
                if continuesAfterCheck { step = .allow }
            case .failure(let failure):
                check = .failed(failure)
            }
            continuesAfterCheck = false
        }
    }

    /// Continue: on once the key has passed, testing it first if it hasn't
    /// been.
    private func continueFromKey() {
        switch check {
        case .passed:
            step = .allow
        case .checking:
            continuesAfterCheck = true
        case .idle, .failed:
            guard canTest else { return }
            continuesAfterCheck = true
            runCheck()
        }
    }

    private func addHosted() {
        var fetched: [AIModelInfo] = []
        if case .passed(let list) = check { fetched = list }
        do {
            try models.addProvider(
                kind,
                key: keyDraft,
                models: fetched,
                consented: true,
                defaultModel: makeDefault && !defaultModelID.isEmpty ? defaultModelID : nil
            )
            dismiss()
        } catch {
            saveError = String(describing: error)
        }
    }

    private func allow(_ entry: AIProviderEntry) {
        models.finishSetup(entry, consented: true, defaultModel: makeDefault && !defaultModelID.isEmpty ? defaultModelID : nil)
        dismiss()
    }

    // MARK: Pieces

    private func numbered<Content: View>(_ number: Int, _ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(theme[ThemeKey.accentForeground])
                .frame(width: 22, height: 22)
                .background(Circle().fill(theme[ThemeKey.accent]))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme[ThemeKey.settingsForeground])
                    .accessibilityLabel("Step \(number): \(title)")
                    .accessibilityAddTraits(.isHeader)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// One provider on the sheet's first step: its name, its models and who
/// pays, as a button that goes on to its key.
private struct ProviderOptionButton: View {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    let kind: AIProviderKind
    let isAdded: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.addTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme[ThemeKey.settingsForeground])
                    if let blurb = kind.modelsBlurb {
                        Text(blurb)
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    }
                    if let cost = kind.costNote {
                        Text(cost)
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isAdded {
                    SettingsPill(text: "Added")
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                        .accessibilityHidden(true)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(theme[ThemeKey.settingsControlBackground])
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isHovered && isEnabled ? theme[ThemeKey.accent] : theme[ThemeKey.settingsBorder])
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(isEnabled ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isAdded ? "\(kind.addTitle), already added" : kind.addTitle)
        .accessibilityHint([kind.modelsBlurb, kind.costNote].compactMap { $0 }.joined(separator: " "))
        .accessibilityAddTraits(.isButton)
    }
}
