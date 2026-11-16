// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaIRC
import VelaStore
import VelaTheme

/// Configured networks with live status; add, edit and remove them.
struct NetworksPane: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    @State private var selection: UUID?
    @State private var editorTarget: NetworkEditorTarget?
    @State private var pendingRemoval: UUID?

    var body: some View {
        let entries = orderedNetworks
        SettingsPage(
            "Networks",
            subtitle: "The IRC networks and bouncers Vela connects to. Passwords, channel keys and certificates are kept in your Keychain."
        ) {
            SettingsSection(footer: "Double-click a network to edit it. Networks provided by a soju bouncer appear under their bouncer and follow its connection settings.") {
                if entries.isEmpty {
                    emptyState
                } else {
                    ForEach(entries, id: \.id) { config in
                        NetworkRow(
                            config: config,
                            session: app.session(for: config.id),
                            isSelected: selection == config.id,
                            select: { selection = config.id },
                            edit: { editorTarget = .existing(config.id) },
                            remove: { pendingRemoval = config.id }
                        )
                    }
                }
                toolbar(entries: entries)
            }
        }
        .sheet(item: $editorTarget) { target in
            NetworkEditorView(target: target)
        }
        .confirmationDialog(
            "Remove “\(removalName)”?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove Network", role: .destructive) {
                if let id = pendingRemoval {
                    app.removeNetwork(id: id)
                    if selection == id { selection = nil }
                }
                pendingRemoval = nil
            }
        } message: {
            Text("Its settings, saved passwords and message history on this Mac will be deleted, along with any networks it provides.")
        }
    }

    /// Saved networks, each followed by its bouncer children. Sessions
    /// without a saved config (demo mode) are included too.
    private var orderedNetworks: [NetworkConfig] {
        var configs = app.networkStore.networks
        let saved = Set(configs.map(\.id))
        configs += app.sessions.map(\.config).filter { !saved.contains($0.id) }
        let parents = configs.filter { $0.parentNetworkID == nil }
        let parentIDs = Set(parents.map(\.id))
        var ordered: [NetworkConfig] = []
        for parent in parents {
            ordered.append(parent)
            ordered += configs
                .filter { $0.parentNetworkID == parent.id }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        ordered += configs.filter { config in
            guard let parent = config.parentNetworkID else { return false }
            return !parentIDs.contains(parent)
        }
        return ordered
    }

    private var removalName: String {
        guard let id = pendingRemoval else { return "network" }
        return orderedNetworks.first { $0.id == id }?.name ?? "network"
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "network")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(theme[ThemeKey.accent])
                .accessibilityHidden(true)
            Text("No networks yet")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme[ThemeKey.settingsForeground])
            Text("Add an IRC network such as Libera.Chat, or a soju or ZNC bouncer.")
                .font(.system(size: 12))
                .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private func toolbar(entries: [NetworkConfig]) -> some View {
        let selected = entries.first { $0.id == selection }
        let session = selected.flatMap { app.session(for: $0.id) }
        return HStack(spacing: 8) {
            Button {
                editorTarget = .new
            } label: {
                Label("Add Network…", systemImage: "plus")
            }
            .buttonStyle(ThemedButtonStyle(prominent: true))
            Button("Edit…") {
                if let selected { editorTarget = .existing(selected.id) }
            }
            .buttonStyle(ThemedButtonStyle())
            .themedDisabled(selected == nil)
            Button("Remove…") {
                pendingRemoval = selected?.id
            }
            .buttonStyle(ThemedButtonStyle())
            .themedDisabled(selected == nil || selected?.isBouncerChild == true)
            .help(selected?.isBouncerChild == true ? "Networks provided by a bouncer are managed by the bouncer." : "Remove the selected network")
            Spacer()
            if let session {
                if session.connectionState == .disconnected {
                    Button("Connect") { session.connect() }
                        .buttonStyle(ThemedButtonStyle())
                } else {
                    Button("Disconnect") { session.disconnect() }
                        .buttonStyle(ThemedButtonStyle())
                }
            }
        }
        .padding(10)
    }
}

/// One network: status, name, server and nick.
private struct NetworkRow: View {
    @Environment(\.theme) private var theme
    let config: NetworkConfig
    let session: NetworkSession?
    let isSelected: Bool
    let select: () -> Void
    let edit: () -> Void
    let remove: () -> Void

    var body: some View {
        let status = Self.status(of: session)
        HStack(spacing: 10) {
            if config.isBouncerChild {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    .padding(.leading, 6)
                    .accessibilityHidden(true)
            }
            Circle()
                .fill(theme[status.colorKey])
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(config.name.isEmpty ? config.host : config.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme[ThemeKey.settingsForeground])
                    if !config.isBouncerChild, config.bouncerKind != .none {
                        SettingsPill(text: config.bouncerKind == .soju ? "soju" : "ZNC")
                    }
                    if !config.autoConnect {
                        SettingsPill(text: "Manual")
                    }
                }
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(status.text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(status.colorKey == ThemeKey.settingsSecondaryForeground ? theme[ThemeKey.settingsSecondaryForeground] : theme[status.colorKey])
                .help(session?.lastError ?? status.text)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(isSelected ? theme[ThemeKey.accent].opacity(0.15) : .clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            select()
            edit()
        }
        .onTapGesture(count: 1, perform: select)
        .contextMenu {
            if let session {
                if session.connectionState == .disconnected {
                    Button("Connect") { session.connect() }
                } else {
                    Button("Disconnect") { session.disconnect() }
                    Button("Reconnect") { session.reconnect() }
                }
                Divider()
            }
            Button("Edit…", action: edit)
            if !config.isBouncerChild {
                Button("Remove…", role: .destructive, action: remove)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(config.name), \(status.text)")
        .accessibilityValue(subtitle)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { select() }
        .accessibilityAction(named: "Edit", edit)
    }

    private var subtitle: String {
        if config.isBouncerChild {
            return "Provided by bouncer · \(config.nick)"
        }
        var parts = ["\(config.host):\(config.port)"]
        parts.append(config.useTLS ? "TLS" : "Unencrypted")
        if !config.nick.isEmpty { parts.append(config.nick) }
        return parts.joined(separator: " · ")
    }

    static func status(of session: NetworkSession?) -> (text: String, colorKey: String) {
        guard let session else { return ("Not connected", ThemeKey.settingsSecondaryForeground) }
        switch session.connectionState {
        case .connected:
            return ("Connected", ThemeKey.statusSuccess)
        case .connecting, .registering:
            return ("Connecting…", ThemeKey.statusWarning)
        case .disconnected:
            return session.lastError == nil
                ? ("Disconnected", ThemeKey.settingsSecondaryForeground)
                : ("Disconnected", ThemeKey.statusError)
        }
    }
}
