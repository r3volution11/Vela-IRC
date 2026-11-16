// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaIRC
import VelaStore
import VelaTheme

/// Configured networks with live status; add, edit, remove and reorder them.
struct NetworksPane: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selection: UUID?
    @State private var editorTarget: NetworkEditorTarget?
    @State private var pendingRemoval: UUID?
    @State private var reorder = ReorderController<UUID>(axis: .vertical, coordinateSpace: "settings.networks")

    var body: some View {
        let groups = networkGroups
        let entries = groups.flatMap { [$0.network] + $0.children }
        SettingsPage(
            "Networks",
            subtitle: "The IRC networks and bouncers Vela connects to. Passwords, channel keys and certificates are kept in your Keychain."
        ) {
            SettingsSection(footer: "Double-click a network to edit it, or drag it to change the order. Networks provided by a soju bouncer appear under their bouncer, follow its connection settings and move with it.") {
                if groups.isEmpty {
                    emptyState
                } else {
                    networkList(groups)
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

    /// Top-level networks in the order the sidebar and tabs show them, each
    /// with its bouncer networks. Saved networks without a session (before
    /// Vela has started them) follow in their saved order; sessions without
    /// a saved config (demo mode) are included too. Bouncer networks whose
    /// bouncer is gone come last, on their own.
    private var networkGroups: [NetworkGroup] {
        var configs = app.networkStore.networks
        let saved = Set(configs.map(\.id))
        configs += app.sessions.map(\.config).filter { !saved.contains($0.id) }
        let running = app.sessions.count
        let position = Dictionary(app.sessions.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = configs.enumerated()
            .sorted { (position[$0.element.id] ?? running + $0.offset) < (position[$1.element.id] ?? running + $1.offset) }
            .map(\.element)
        let parents = ordered.filter { $0.parentNetworkID == nil }
        let parentIDs = Set(parents.map(\.id))
        let orphans = ordered.filter { config in
            guard let parent = config.parentNetworkID else { return false }
            return !parentIDs.contains(parent)
        }
        return parents.map { parent in
            NetworkGroup(network: parent, children: ordered.filter { $0.parentNetworkID == parent.id })
        } + orphans.map { NetworkGroup(network: $0) }
    }

    private var removalName: String {
        guard let id = pendingRemoval else { return "network" }
        let config = networkGroups.lazy.flatMap { [$0.network] + $0.children }.first { $0.id == id }
        return config?.name ?? "network"
    }

    // MARK: List

    /// One block per top-level network, so a bouncer drags with its
    /// networks. The card's hairlines would stay put while rows slide, so
    /// each row draws the line above it instead.
    private func networkList(_ groups: [NetworkGroup]) -> some View {
        VStack(spacing: 0) {
            ForEach(groups) { group in
                groupView(group, isFirst: group.id == groups.first?.id)
            }
        }
        .coordinateSpace(.named(reorder.coordinateSpace))
    }

    private func groupView(_ group: NetworkGroup, isFirst: Bool) -> some View {
        // Orphaned bouncer networks have no place among the top level.
        let siblings = group.isOrphan ? [] : app.networkSiblings(of: group.id).map(\.id)
        let lifted = reorder.isDragging(group.id)
        return VStack(spacing: 0) {
            row(for: group.network)
                .accessibilityMoveActions(axis: .vertical, index: siblings.firstIndex(of: group.id) ?? 0, count: siblings.count) {
                    move(group.id, by: $0)
                }
                // Dragged by its own row; its bouncer networks' rows are
                // their own handles (handles can't nest).
                .reorderHandle(group.id, siblings: siblings, in: reorder, isEnabled: !group.isOrphan) { id, index in
                    app.moveNetwork(id, toIndex: index)
                }
            ForEach(group.children) { child in
                childRow(child)
            }
        }
        .overlay(alignment: .top) { RowHairline(isHidden: isFirst || lifted) }
        .modifier(DragLift(isActive: lifted))
        // The whole block moves, so the bouncer's networks come along.
        .reorderPart(of: group.id, in: reorder, part: "block")
    }

    private func childRow(_ config: NetworkConfig) -> some View {
        let siblings = app.networkSiblings(of: config.id).map(\.id)
        let lifted = reorder.isDragging(config.id)
        return row(for: config)
            .accessibilityMoveActions(axis: .vertical, index: siblings.firstIndex(of: config.id) ?? 0, count: siblings.count) {
                move(config.id, by: $0)
            }
            .overlay(alignment: .top) { RowHairline(isHidden: lifted) }
            .modifier(DragLift(isActive: lifted))
            .reorderable(config.id, siblings: siblings, in: reorder) { id, index in
                app.moveNetwork(id, toIndex: index)
            }
    }

    private func row(for config: NetworkConfig) -> some View {
        NetworkRow(
            config: config,
            session: app.session(for: config.id),
            isSelected: selection == config.id,
            select: { selection = config.id },
            edit: { editorTarget = .existing(config.id) },
            remove: { pendingRemoval = config.id }
        )
    }

    /// Move Up/Down for VoiceOver and Full Keyboard Access.
    private func move(_ id: UUID, by offset: Int) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
            app.moveNetwork(id, by: offset)
        }
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

/// A top-level network and the bouncer networks listed under it.
private struct NetworkGroup: Identifiable {
    let network: NetworkConfig
    var children: [NetworkConfig] = []

    var id: UUID { network.id }
    /// A bouncer network whose bouncer is gone, listed on its own.
    var isOrphan: Bool { network.parentNetworkID != nil }
}

/// The hairline above a row. Hidden rather than removed, so rows keep
/// their identity (and a drag in progress) when it comes and goes.
private struct RowHairline: View {
    let isHidden: Bool

    var body: some View {
        SettingsHairline()
            .padding(.leading, 14)
            .opacity(isHidden ? 0 : 1)
            .allowsHitTesting(false)
    }
}

/// Lifts a dragged row (or a bouncer with its networks) off the card, so
/// it reads clearly above the rows sliding beneath it.
private struct DragLift: ViewModifier {
    @Environment(\.theme) private var theme
    let isActive: Bool

    func body(content: Content) -> some View {
        content.background {
            if isActive {
                let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
                shape
                    .fill(theme[ThemeKey.settingsControlBackground])
                    .overlay(shape.strokeBorder(theme[ThemeKey.settingsBorder]))
                    .shadow(color: shadowColor, radius: 8, y: 3)
            }
        }
    }

    private var shadowColor: Color {
        theme.kind == .dark
            ? theme[ThemeKey.settingsBackground].opacity(0.6)
            : theme[ThemeKey.settingsBorder]
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
