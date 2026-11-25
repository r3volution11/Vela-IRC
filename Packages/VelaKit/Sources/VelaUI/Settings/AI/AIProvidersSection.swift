// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaIntelligence
import VelaStore
import VelaTheme

/// Settings → AI Providers → Providers: your own providers (OpenAI,
/// Anthropic, Google Gemini, or a server such as Ollama or LM Studio), each
/// with its key (in the Keychain, never shown back), a Test that fetches its
/// model list, and on or off. Adding OpenAI, Anthropic or Gemini opens the
/// setup sheet; a server is added here, and filled in on its row. Whether
/// each may be sent messages is in AI Privacy.
struct AIProvidersSection: View {
    @Environment(IntelligenceServices.self) private var intelligence
    @Environment(\.theme) private var theme
    let navigate: (SettingsPane) -> Void
    /// Opens the setup sheet.
    let startSetup: (AIProviderSetupRequest.Start) -> Void

    /// Providers whose details are open.
    @State private var expanded: Set<String> = []

    var body: some View {
        let models = intelligence.models
        let providers = models.providers
        SettingsSection("Providers", footer: Self.footer) {
            if providers.isEmpty {
                emptyRow(canAdd: models.canAddProviders)
            }
            ForEach(providers) { entry in
                AIProviderRow(entry: entry, isExpanded: expandedBinding(entry.id), navigate: navigate)
            }
        } accessory: {
            if models.canAddProviders {
                addMenu(existing: providers)
            } else {
                // Demo mode never goes online.
                Text("Not in demo mode")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
            }
        }
        .id("models")
        .onAppear { models.refreshStaleModels() }
    }

    static let footer = "Keys are kept in your Keychain and sent only to their own provider. What each provider is sent, and whether it may be, is in AI Privacy."

    private func emptyRow(canAdd: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 13))
                .foregroundStyle(theme[ThemeKey.accentText])
                .accessibilityHidden(true)
            Text("Use OpenAI, Anthropic or Google Gemini with your own key, or a server such as Ollama or LM Studio. Apple Intelligence stays the default until you choose another.")
                .font(.system(size: 11.5))
                .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if canAdd {
                Button("Add a Provider…") { startSetup(.choose) }
                    .buttonStyle(ThemedButtonStyle(prominent: true))
                    .fixedSize()
                    .accessibilityHint("Walks you through getting a key and connecting OpenAI, Anthropic or Google Gemini")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func addMenu(existing: [AIProviderEntry]) -> some View {
        Menu {
            ForEach(AIProviderSetupRequest.hostedKinds, id: \.self) { kind in
                Button("\(kind.addTitle)…") { startSetup(.key(kind)) }
                    .disabled(existing.contains { $0.kind == kind })
            }
            Divider()
            ForEach(LocalModelServer.allCases) { server in
                Button("\(server.name) on This Mac") { connect(server) }
                    .disabled(intelligence.models.provider(for: server) != nil)
            }
            Button("Other OpenAI-Compatible Server") { add(.openAICompatible, name: "Custom server", baseURL: "") }
        } label: {
            Label("Add Provider", systemImage: "plus")
                .font(.system(size: 12, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .foregroundStyle(theme[ThemeKey.accentText])
        .accessibilityLabel("Add Provider")
        .accessibilityHint("OpenAI, Anthropic, Google Gemini, or an OpenAI-compatible server such as Ollama")
    }

    private func add(_ kind: AIProviderKind, name: String? = nil, baseURL: String? = nil) {
        guard let entry = intelligence.models.addProvider(kind, name: name, baseURL: baseURL) else { return }
        expanded.insert(entry.id)
    }

    /// Ollama or LM Studio at its usual address, opened to Test it.
    private func connect(_ server: LocalModelServer) {
        guard let entry = intelligence.models.connect(server, models: []) else { return }
        expanded.insert(entry.id)
    }

    private func expandedBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { isOpen in
                if isOpen { expanded.insert(id) } else { expanded.remove(id) }
            }
        )
    }
}

/// One provider: its name and state, on or off, and (opened) its key, a
/// custom server's address and context, the model list with Test, whether
/// it may be sent messages (changed in AI Privacy), and Remove.
private struct AIProviderRow: View {
    @Environment(IntelligenceServices.self) private var intelligence
    @Environment(\.theme) private var theme
    let entry: AIProviderEntry
    @Binding var isExpanded: Bool
    let navigate: (SettingsPane) -> Void

    @State private var keyDraft = ""
    @State private var hasKey = false
    @State private var keyError: String?
    @State private var nameDraft = ""
    @State private var addressDraft = ""
    @State private var testResult: TestResult?
    @State private var isTesting = false
    @State private var confirmsRemoval = false

    private enum TestResult: Equatable {
        case success(Int)
        case failure(String)
    }

    /// Context windows offered for a custom server.
    static let contextChoices = [4_096, 8_192, 16_384, 32_768, 65_536, 131_072]

    private var models: AIModels { intelligence.models }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                details
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
        }
        .onAppear(perform: readState)
        .onChange(of: entry.id) { _, _ in readState() }
        .confirmationDialog("Remove \(entry.name)?", isPresented: $confirmsRemoval, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { models.removeProvider(entry.id) }
        } message: {
            Text(entry.kind.requiresKey
                ? "Its key is deleted from your Keychain, and Catch me up and Recap go back to Apple Intelligence or the default model if they used it."
                : "Catch me up and Recap go back to Apple Intelligence or the default model if they used it.")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    Image(systemName: entry.kind == .openAICompatible ? "server.rack" : "sparkles")
                        .font(.system(size: 13))
                        .foregroundStyle(theme[ThemeKey.accentText])
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.name)
                            .font(.system(size: 13))
                            .foregroundStyle(theme[ThemeKey.settingsForeground])
                        Text(subtitle)
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(entry.name), \(subtitle)")
            .accessibilityHint(isExpanded ? "Hides its settings" : "Shows its key, models and permission")
            .accessibilityAddTraits(.isButton)
            Spacer(minLength: 8)
            if let pill = pill {
                SettingsPill(text: pill.text, tinted: pill.tinted)
            }
            Toggle("Use \(entry.name)", isOn: Binding(
                get: { entry.enabled },
                set: { isOn in
                    var changed = entry
                    changed.enabled = isOn
                    models.updateProvider(changed)
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
            .accessibilityHint("Off keeps it and its key, but offers none of its models")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(minHeight: 44)
    }

    private var subtitle: String {
        if entry.kind == .openAICompatible {
            return entry.apiBaseURL.map { AIConsentText.hostAndPort($0) } ?? "No address yet"
        }
        return entry.kind.displayName
    }

    private var pill: (text: String, tinted: Bool)? {
        if !entry.enabled { return ("Off", false) }
        if entry.kind.requiresKey, !hasKey { return ("No key", false) }
        if entry.kind == .openAICompatible, entry.apiBaseURL == nil { return ("No address", false) }
        return entry.consented ? ("Allowed", true) : ("Asks first", false)
    }

    // MARK: Details

    @ViewBuilder
    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            if entry.kind == .openAICompatible {
                serverFields
            }
            keyField
            modelsRow
            consentRow
            HStack {
                Spacer()
                Button("Remove \(entry.name)…") { confirmsRemoval = true }
                    .buttonStyle(ThemedButtonStyle())
            }
        }
        .padding(.leading, 26)
    }

    private var serverFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            labeled("Name") {
                ThemedTextField("Ollama", text: $nameDraft, accessibilityName: "Server name") { saveServer() }
                    .frame(maxWidth: 220)
            }
            labeled("Address") {
                ThemedTextField("http://localhost:11434/v1", text: $addressDraft, monospaced: true, accessibilityName: "Server address") { saveServer() }
                    .frame(maxWidth: 280)
            }
            if serverDraftChanged {
                HStack {
                    Spacer()
                    Button("Save") { saveServer() }
                        .buttonStyle(ThemedButtonStyle(prominent: true))
                        .themedDisabled(AIProviderEntry.normalizedServerURL(addressDraft) == nil)
                }
            } else if !addressDraft.isEmpty, AIProviderEntry.normalizedServerURL(addressDraft) == nil {
                caption("Enter an http or https address, such as http://localhost:11434/v1.")
            }
            labeled("Context") {
                Picker("Context window", selection: Binding(
                    get: { entry.contextTokens ?? AIProviderEntry.defaultCustomContextTokens },
                    set: { tokens in
                        var changed = entry
                        changed.contextTokens = tokens == AIProviderEntry.defaultCustomContextTokens ? nil : tokens
                        models.updateProvider(changed)
                    }
                )) {
                    ForEach(contextOptions, id: \.self) { tokens in
                        Text("\(tokens.formatted()) tokens").tag(tokens)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .accessibilityHint("Set it to the context length the server loads its models with")
            }
            caption("Set Context to what the server loads models with: it can quietly drop what doesn't fit. Over http, use localhost, a .local name or an IP address.")
        }
    }

    private var contextOptions: [Int] {
        var options = Self.contextChoices
        if let current = entry.contextTokens, !options.contains(current) { options.append(current) }
        return options.sorted()
    }

    private var serverDraftChanged: Bool {
        nameDraft.trimmingCharacters(in: .whitespaces) != entry.name
            || addressDraft.trimmingCharacters(in: .whitespaces) != (entry.baseURL ?? "")
    }

    private var keyField: some View {
        VStack(alignment: .leading, spacing: 6) {
            labeled(entry.kind.requiresKey ? "API key" : "API key (optional)") {
                if hasKey {
                    HStack(spacing: 8) {
                        Text("Saved in your Keychain")
                            .font(.system(size: 12))
                            .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                        Button("Remove Key") { saveKey(nil) }
                            .buttonStyle(ThemedButtonStyle())
                            .accessibilityLabel("Remove the \(entry.name) key")
                    }
                } else {
                    HStack(spacing: 6) {
                        ThemedTextField(entry.kind.keyPlaceholder, text: $keyDraft, isSecure: true, monospaced: true, accessibilityName: "\(entry.name) API key") {
                            saveKey(keyDraft)
                        }
                        .frame(maxWidth: 240)
                        Button("Save") { saveKey(keyDraft) }
                            .buttonStyle(ThemedButtonStyle(prominent: true))
                            .themedDisabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            if let keyError {
                SettingsCallout(.error, "Couldn't save the key", message: keyError)
            }
            if !hasKey, let url = entry.kind.keyURL {
                HStack(spacing: 6) {
                    caption("Usage is billed to the account the key belongs to.")
                    SettingsLinkButton("Get a key", systemImage: "arrow.up.right.square") { NSWorkspace.shared.open(url) }
                        .fixedSize()
                        .accessibilityHint("Opens \(entry.kind.displayName)'s keys page in your browser")
                }
            }
        }
    }

    private var modelsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            labeled("Models") {
                HStack(spacing: 8) {
                    Text(modelsSummary)
                        .font(.system(size: 12))
                        .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    if isTesting {
                        ProgressView().controlSize(.small).accessibilityLabel("Testing")
                    }
                    Button("Test") { test() }
                        .buttonStyle(ThemedButtonStyle())
                        .themedDisabled(isTesting || !canTest)
                        .help("Connect with the key and fetch the provider's models")
                        .accessibilityHint("Connects to \(entry.name) and fetches its model list")
                }
            }
            switch testResult {
            case .success(let count):
                SettingsCallout(.success, "Connected", message: count == 1 ? "1 model is available." : "\(count) models are available.")
            case .failure(let message):
                SettingsCallout(.error, "Couldn't connect", message: message)
            case nil:
                EmptyView()
            }
        }
    }

    private var canTest: Bool {
        if entry.kind.requiresKey { return hasKey }
        return entry.apiBaseURL != nil
    }

    /// "12 models · recommended: Claude Opus 5.5", or Vela's picks before a fetch.
    private var modelsSummary: String {
        let list = models.catalog.models(for: entry)
        let fetched = models.catalog.lists[entry.id] != nil || models.catalog.state(for: entry.id) == .loaded
        let recommended = list.first(where: \.isRecommended)?.name
        if list.isEmpty {
            return entry.kind == .openAICompatible ? "Test to list the server's models." : "None yet."
        }
        let count = list.count == 1 ? "1 model" : "\(list.count) models"
        let pick = recommended.map { " · recommended: \($0)" } ?? ""
        return fetched ? "\(count)\(pick)" : "Vela's picks\(pick). Test to list all."
    }

    /// Whether it may be sent messages; allowed and taken back in AI Privacy.
    private var consentRow: some View {
        labeled("Permission") {
            HStack(spacing: 8) {
                Text(entry.consented ? "Allowed to receive the messages you ask about" : "Vela asks before sending it anything")
                    .font(.system(size: 12))
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                SettingsLinkButton("AI Privacy", systemImage: SettingsPane.aiPrivacy.systemImage) { navigate(.aiPrivacy) }
                    .fixedSize()
                    .accessibilityHint("Opens Settings → AI Privacy, where you allow it or take it back")
            }
        }
    }

    // MARK: Pieces

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme[ThemeKey.settingsForeground])
                .frame(width: 96, alignment: .leading)
                .accessibilityHidden(true)
            content()
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Actions

    private func readState() {
        hasKey = models.keys.hasKey(for: entry.id)
        nameDraft = entry.name
        addressDraft = entry.baseURL ?? ""
    }

    private func saveKey(_ key: String?) {
        do {
            try models.setKey(key, for: entry.id)
            keyError = nil
            keyDraft = ""
            hasKey = models.keys.hasKey(for: entry.id)
            testResult = nil
            // A new key: fetch the model list with it.
            if hasKey { test() }
        } catch {
            keyError = String(describing: error)
        }
    }

    private func saveServer() {
        guard AIProviderEntry.normalizedServerURL(addressDraft) != nil else { return }
        var changed = entry
        let name = nameDraft.trimmingCharacters(in: .whitespaces)
        changed.name = name.isEmpty ? entry.name : name
        changed.baseURL = addressDraft.trimmingCharacters(in: .whitespaces)
        models.updateProvider(changed)
        testResult = nil
    }

    private func test() {
        isTesting = true
        testResult = nil
        let id = entry.id
        Task {
            let result = await models.refreshModels(id)
            isTesting = false
            switch result {
            case .success(let list): testResult = .success(list.count)
            case .failure(let failure): testResult = .failure(failure.message)
            }
        }
    }
}
