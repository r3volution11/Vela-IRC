// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Security
import SwiftUI
import UniformTypeIdentifiers
import VelaCore
import VelaIRC
import VelaStore
import VelaTheme

/// Add or edit a network. Presented as a sheet from the main window and
/// from Settings → Networks. Config goes to networks.json; passwords,
/// channel keys and certificates go to the Keychain.
struct NetworkEditorView: View {
    let target: NetworkEditorTarget

    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var draft = NetworkDraft()
    @State private var original: NetworkConfig?
    @State private var originalSecrets = NetworkSecrets()
    @State private var parentName: String?
    @State private var isLoaded = false
    @State private var showsProblems = false

    @State private var identities: [CertificateIdentity] = []
    @State private var pendingCertificate: URL?
    @State private var certificatePassword = ""
    @State private var certificateError: String?

    init(target: NetworkEditorTarget) {
        self.target = target
    }

    private struct CertificateIdentity: Identifiable, Hashable {
        let label: String
        let ref: Data
        var id: Data { ref }
    }

    var body: some View {
        let problems = showsProblems ? draft.problems : [:]
        VStack(spacing: 0) {
            header
            SettingsHairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if draft.isBouncerChild {
                        SettingsCallout(
                            .info,
                            "Provided by \(parentName ?? "your bouncer")",
                            message: "This network comes from your soju bouncer. It connects with the bouncer's server, identity and login; edit the bouncer to change those."
                        )
                        SettingsSection("General") {
                            field("Name") {
                                ThemedTextField("Network name", text: $draft.name, accessibilityName: "Network name")
                            }
                        }
                        hiddenChannelsSection
                    } else {
                        serverSection(problems)
                        identitySection(problems)
                        authenticationSection(problems)
                        bouncerSection
                        channelsSection
                        hiddenChannelsSection
                    }
                    performSection
                    listsSection
                    SettingsSection("Connection") {
                        SettingsToggle("Connect automatically", detail: "Connect when Vela opens.", isOn: $draft.autoConnect)
                    }
                }
                .padding(20)
            }
            SettingsHairline()
            footer(problems: draft.problems)
        }
        .frame(width: 560)
        .frame(minHeight: 480, idealHeight: 640, maxHeight: 1000)
        .background(theme[ThemeKey.settingsBackground])
        .onAppear(perform: load)
        .task(id: draft.authentication) {
            if draft.authentication == .saslExternal, identities.isEmpty { reloadIdentities() }
        }
    }

    // MARK: Header & footer

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: draft.bouncer == .none ? "network" : "server.rack")
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
                Text("Settings are saved to networks.json; passwords, channel keys and certificates go to your Keychain.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if !draft.isBouncerChild {
                Menu {
                    ForEach(NetworkDraft.presets) { preset in
                        Button("\(preset.name) — \(preset.host)") { draft.apply(preset) }
                    }
                    Divider()
                    Button("Custom") { draft.apply(nil) }
                } label: {
                    Label("Presets", systemImage: "list.bullet")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .tint(theme[ThemeKey.accent])
                .help("Fill in a well-known network")
                .accessibilityLabel("Network presets")
            }
        }
        .padding(20)
    }

    private var title: String {
        switch target {
        case .new: "Add Network"
        case .existing: "Edit “\(original?.name ?? draft.name)”"
        }
    }

    private func footer(problems: [NetworkDraft.Field: String]) -> some View {
        HStack(spacing: 10) {
            if showsProblems && !problems.isEmpty {
                Label("Fix the highlighted fields to save.", systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(theme[ThemeKey.statusError])
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(ThemedButtonStyle())
                .keyboardShortcut(.cancelAction)
            Button(target == .new ? "Add Network" : "Save", action: save)
                .buttonStyle(ThemedButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(theme[ThemeKey.settingsSidebarBackground])
    }

    // MARK: Sections

    private func serverSection(_ problems: [NetworkDraft.Field: String]) -> some View {
        SettingsSection("Server") {
            field("Name", hint: "Shown in the sidebar and tabs. Defaults to the address.") {
                ThemedTextField(draft.host.isEmpty ? "Libera.Chat" : draft.host, text: $draft.name, accessibilityName: "Network name")
            }
            field("Address", error: problems[.host]) {
                HStack(spacing: 8) {
                    ThemedTextField("irc.example.net", text: $draft.host, monospaced: true, accessibilityName: "Server address")
                    Text("Port")
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                        .accessibilityHidden(true)
                    ThemedTextField("6697", text: $draft.port, monospaced: true, accessibilityName: "Port")
                        .frame(width: 70)
                }
            }
            if let error = problems[.port] {
                errorRow(error)
            }
            SettingsToggle(
                "Use TLS",
                detail: draft.useTLS ? "Encrypts the connection. Almost every network supports it on port 6697." : "Messages and passwords are sent unencrypted.",
                isOn: Binding(
                    get: { draft.useTLS },
                    set: { draft.useTLS = $0; draft.tlsChanged() }
                )
            )
            if draft.useTLS {
                SettingsToggle(
                    "Allow invalid certificates",
                    detail: "Accept self-signed or expired certificates.",
                    isOn: $draft.allowInvalidCertificates
                )
                if draft.allowInvalidCertificates {
                    SettingsCallout(
                        .warning,
                        "Only for servers you trust",
                        message: "With certificate checks off, anyone between you and the server could read your messages and passwords without you noticing."
                    )
                    .padding(10)
                }
            }
        }
    }

    private func identitySection(_ problems: [NetworkDraft.Field: String]) -> some View {
        SettingsSection("Identity") {
            field("Nickname", error: problems[.nick]) {
                ThemedTextField("nickname", text: $draft.nick, monospaced: true, accessibilityName: "Nickname")
            }
            field("Alternates", hint: "Tried in order if your nickname is taken. Separate with commas.") {
                ThemedTextField(draft.nick.isEmpty ? "nick_, nick__" : "\(draft.nick)_, \(draft.nick)__", text: $draft.alternateNicks, monospaced: true, accessibilityName: "Alternate nicknames")
            }
            field("Username", hint: "The ident part of your hostmask. Defaults to your nickname.") {
                ThemedTextField(draft.nick.isEmpty ? "username" : draft.nick, text: $draft.username, monospaced: true, accessibilityName: "Username")
            }
            field("Real name", hint: "Shown in WHOIS.") {
                ThemedTextField(draft.nick.isEmpty ? "Your Name" : draft.nick, text: $draft.realname, accessibilityName: "Real name")
            }
        }
    }

    private func authenticationSection(_ problems: [NetworkDraft.Field: String]) -> some View {
        SettingsSection("Authentication") {
            field("Method", hint: draft.authentication.explanation) {
                Picker("Authentication method", selection: $draft.authentication) {
                    ForEach(NetworkDraft.Authentication.allCases) { method in
                        Text(method.title).tag(method)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            switch draft.authentication {
            case .none:
                EmptyView()
            case .saslPlain:
                field("Account", hint: "Your services account name. Defaults to your nickname.") {
                    ThemedTextField(draft.nick.isEmpty ? "account" : draft.nick, text: $draft.saslAccount, monospaced: true, accessibilityName: "Account name")
                }
                field("Password", error: problems[.saslPassword]) {
                    ThemedTextField("Account password", text: $draft.saslPassword, isSecure: true, accessibilityName: "Account password")
                }
            case .saslExternal:
                certificateField(error: problems[.certificate])
                if !draft.useTLS {
                    errorRow("SASL EXTERNAL needs TLS. Turn on Use TLS above.")
                }
            case .serverPassword:
                EmptyView()
            }
            if draft.usesServerPassword {
                field("Server password", error: problems[.serverPassword]) {
                    ThemedTextField(
                        draft.bouncer == .znc ? "username/network:password" : "Server password",
                        text: $draft.serverPassword,
                        isSecure: true,
                        accessibilityName: "Server password"
                    )
                }
            }
        }
    }

    private func certificateField(error: String?) -> some View {
        field("Certificate", hint: "A certificate with its private key, from your Keychain or a .p12 file.", error: error ?? certificateError) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Picker("Client certificate", selection: $draft.certificateRef) {
                        Text("None").tag(Data?.none)
                        if let ref = draft.certificateRef, !identities.contains(where: { $0.ref == ref }) {
                            Text(identities.isEmpty ? "Saved certificate" : "Missing certificate").tag(Data?.some(ref))
                        }
                        ForEach(identities) { identity in
                            Text(identity.label).tag(Data?.some(identity.ref))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 230)
                    Button("Import .p12…", action: chooseCertificate)
                        .buttonStyle(ThemedButtonStyle())
                }
                if let pendingCertificate {
                    HStack(spacing: 8) {
                        ThemedTextField(
                            "Password for \(pendingCertificate.lastPathComponent)",
                            text: $certificatePassword,
                            isSecure: true,
                            accessibilityName: "Certificate file password",
                            onSubmit: importCertificate
                        )
                        Button("Import", action: importCertificate)
                            .buttonStyle(ThemedButtonStyle(prominent: true))
                        Button("Cancel") {
                            self.pendingCertificate = nil
                            certificatePassword = ""
                            certificateError = nil
                        }
                        .buttonStyle(ThemedButtonStyle())
                    }
                }
            }
        }
    }

    private var bouncerSection: some View {
        SettingsSection("Bouncer") {
            field("Type") {
                Picker("Bouncer type", selection: $draft.bouncer) {
                    Text("None").tag(BouncerKind.none)
                    Text("soju").tag(BouncerKind.soju)
                    Text("ZNC").tag(BouncerKind.znc)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }
            switch draft.bouncer {
            case .none:
                EmptyView()
            case .soju:
                hintRow(
                    systemImage: "sparkles",
                    "soju lists your networks automatically: each appears under this connection with its own channels and history. Log in with SASL PLAIN using your soju username."
                )
            case .znc:
                hintRow(
                    systemImage: "info.circle",
                    "ZNC uses one connection per network. Log in as username/network (for example doug/libera) with SASL PLAIN, or with a server password of the form username/network:password."
                )
            }
        }
    }

    private var channelsSection: some View {
        SettingsSection(
            "Channels",
            footer: draft.bouncer == .none
                ? "Joined after connecting. Keys are stored in your Keychain."
                : "Your bouncer rejoins channels itself, so this list is only used when connecting directly."
        ) {
            ForEach($draft.channels) { $channel in
                HStack(spacing: 8) {
                    ThemedTextField("#channel", text: $channel.name, monospaced: true, accessibilityName: "Channel name")
                    ThemedTextField("Key (optional)", text: $channel.key, isSecure: true, accessibilityName: "Channel key for \(channel.name)")
                        .frame(width: 150)
                    Button {
                        draft.channels.removeAll { $0.id == channel.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    }
                    .buttonStyle(.plain)
                    .help("Remove \(channel.name)")
                    .accessibilityLabel("Remove \(channel.name.isEmpty ? "channel" : channel.name)")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
            }
            HStack {
                Button {
                    draft.channels.append(NetworkDraft.Channel())
                } label: {
                    Label("Add Channel", systemImage: "plus")
                }
                .buttonStyle(ThemedButtonStyle())
                if draft.channels.isEmpty {
                    Text("No channels yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                }
                Spacer()
            }
            .padding(10)
        }
    }

    /// Detached bouncer channels taken out of the list (Hide Channel), each
    /// with Show and Join. They act at once, not on Save: the channel's
    /// already on the bouncer.
    @ViewBuilder
    private var hiddenChannelsSection: some View {
        if case .existing(let id) = target, let session = app.session(for: id), !session.hiddenChannels.isEmpty {
            SettingsSection(
                "Hidden channels",
                footer: "Channels you left here and hid. \(session.bouncerName) is still in them and keeps their history. Show puts one back in the list; Join also joins it, to catch up."
            ) {
                ForEach(session.hiddenChannels) { hidden in
                    HStack(spacing: 8) {
                        Text(hidden.name)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(theme[ThemeKey.settingsForeground])
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Button("Show") { app.show(hidden, selecting: false) }
                            .buttonStyle(ThemedButtonStyle())
                            .help("Put \(hidden.name) back in the list, still detached")
                            .accessibilityLabel("Show \(hidden.name)")
                        Button("Join") {
                            if let channel = app.show(hidden, selecting: false) { app.rejoin(channel) }
                        }
                        .buttonStyle(ThemedButtonStyle())
                        .disabled(!session.isConnected)
                        .help("Put \(hidden.name) back in the list and join it")
                        .accessibilityLabel("Join \(hidden.name)")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                }
            }
        }
    }

    private var performSection: some View {
        SettingsSection(
            "Perform on connect",
            footer: "Commands run after connecting, one per line. They're saved in networks.json in plain text, so don't put passwords here."
        ) {
            ThemedTextEditor(
                text: $draft.performCommands,
                placeholder: "/mode \(draft.nick.isEmpty ? "nick" : draft.nick) +x\n/msg ChanServ op #vela",
                accessibilityName: "Perform commands",
                minHeight: 74,
                // IRC commands: no spelling, autocorrect or smart quotes.
                checksText: false
            )
            .padding(10)
        }
    }

    private var listsSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsSection("Highlight words", footer: "On this network only, in addition to your nick and the words in Settings → Notifications.") {
                StringListEditor(
                    items: $draft.highlightWords,
                    placeholder: "Add a word",
                    itemName: "highlight word",
                    emptyMessage: "No network-specific highlight words.",
                    monospaced: false
                )
            }
            SettingsSection("Ignore list", footer: "Hide messages from matching people. Masks use nick!user@host with * wildcards.") {
                StringListEditor(
                    items: $draft.ignoreMasks,
                    placeholder: "nick!*@*",
                    itemName: "ignore mask",
                    emptyMessage: "Nobody is ignored."
                )
            }
        }
    }

    // MARK: Rows

    private func field<Content: View>(
        _ label: String,
        hint: String? = nil,
        error: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(theme[ThemeKey.settingsForeground])
                .frame(width: 112, alignment: .leading)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                content()
                if let error {
                    Text(error)
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme[ThemeKey.statusError])
                        .fixedSize(horizontal: false, vertical: true)
                } else if let hint {
                    Text(hint)
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func errorRow(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle.fill")
            .font(.system(size: 11.5))
            .foregroundStyle(theme[ThemeKey.statusError])
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
    }

    private func hintRow(systemImage: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(theme[ThemeKey.accent])
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: Loading & saving

    private var caseMapping: CaseMapping {
        if case .existing(let id) = target, let session = app.session(for: id) {
            return session.isupport.caseMapping
        }
        return .rfc1459
    }

    private func load() {
        guard !isLoaded else { return }
        isLoaded = true
        switch target {
        case .new:
            draft.nick = NetworkDraft.defaultNick
            let fullName = NSFullUserName()
            draft.realname = fullName == draft.nick ? "" : fullName
        case .existing(let id):
            guard let config = app.networkStore.network(id: id) ?? app.session(for: id)?.config else { return }
            original = config
            let secrets = app.secrets(for: config.parentNetworkID ?? id)
            originalSecrets = secrets
            let mapping = caseMapping
            draft = NetworkDraft(config: config, secrets: secrets) { channel in
                guard channel.hasKey else { return nil }
                return app.keychain.secret(account: Keychain.channelKeyAccount(networkID: id, channel: mapping.fold(channel.name)))
            }
            if let parent = config.parentNetworkID {
                parentName = app.networkStore.network(id: parent)?.name ?? app.session(for: parent)?.displayName
            }
        }
    }

    private func save() {
        showsProblems = true
        guard draft.problems.isEmpty else { return }
        var config = original ?? NetworkConfig(name: "", host: "", nick: "")
        draft.apply(to: &config)
        if draft.isBouncerChild {
            app.updateNetwork(config, secrets: nil)
        } else {
            storeChannelKeys(for: config)
            let secrets = draft.secrets(keeping: originalSecrets.nickServPassword)
            if original == nil {
                app.addNetwork(config, secrets: secrets)
            } else {
                app.updateNetwork(config, secrets: secrets)
            }
        }
        dismiss()
    }

    private func storeChannelKeys(for config: NetworkConfig) {
        let mapping = caseMapping
        let channels = draft.normalizedChannels
        let kept = Set(channels.map { mapping.fold($0.name) })
        for channel in channels {
            let account = Keychain.channelKeyAccount(networkID: config.id, channel: mapping.fold(channel.name))
            if channel.key.isEmpty {
                app.keychain.deleteSecret(account: account)
            } else {
                try? app.keychain.setSecret(channel.key, account: account)
            }
        }
        for old in original?.autoJoin ?? [] where old.hasKey && !kept.contains(mapping.fold(old.name)) {
            app.keychain.deleteSecret(account: Keychain.channelKeyAccount(networkID: config.id, channel: mapping.fold(old.name)))
        }
    }

    // MARK: Certificates

    private func reloadIdentities() {
        identities = app.keychain.identities().map { CertificateIdentity(label: $0.label, ref: $0.persistentRef) }
    }

    private func chooseCertificate() {
        let panel = NSOpenPanel()
        panel.title = "Import Client Certificate"
        panel.message = "Choose a .p12 file containing your certificate and its private key."
        panel.prompt = "Choose"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType.pkcs12]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pendingCertificate = url
        certificatePassword = ""
        certificateError = nil
    }

    private func importCertificate() {
        guard let url = pendingCertificate else { return }
        do {
            let data = try Data(contentsOf: url)
            let ref = try app.keychain.importPKCS12(data, password: certificatePassword)
            reloadIdentities()
            draft.certificateRef = ref
            pendingCertificate = nil
            certificatePassword = ""
            certificateError = nil
        } catch let error as KeychainError {
            certificateError = error.status == errSecAuthFailed
                ? "That password doesn't open this file."
                : error.description
        } catch {
            certificateError = "Couldn't read \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }
}
