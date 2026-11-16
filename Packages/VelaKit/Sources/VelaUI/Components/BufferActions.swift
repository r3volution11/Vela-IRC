// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaIRC
import VelaStore
import VelaTheme

/// Context-menu items for a buffer, shared by the sidebar, rail and tabs.
struct BufferContextMenuItems: View {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var uiState
    let buffer: BufferModel
    let session: NetworkSession

    var body: some View {
        switch buffer.kind {
        case .server:
            ServerContextMenuItems(session: session)
        case .channel, .query:
            if buffer.unreadCount > 0 || buffer.highlightCount > 0 {
                Button("Mark as Read") { session.markRead(buffer) }
            }
            Button(buffer.isMuted ? "Unmute" : "Mute") { session.setMuted(!buffer.isMuted, for: buffer) }
            let mediaOn = app.isMediaEnabled(for: buffer.id)
            Button(mediaOn ? "Disable Inline Media" : "Enable Inline Media") {
                app.setMediaEnabled(!mediaOn, for: buffer.id)
            }
            Divider()
            if buffer.kind == .channel {
                if buffer.isJoined {
                    Button("Leave Channel") { session.submit("/part \(buffer.name)", in: buffer) }
                } else {
                    Button("Join Channel") { session.submit("/join \(buffer.name)", in: buffer) }
                        .disabled(!session.isConnected)
                }
            } else {
                Button("Whois \(buffer.name)") { session.submit("/whois \(buffer.name)", in: buffer) }
                    .disabled(!session.isConnected)
            }
            Button(buffer.kind == .channel ? "Close Channel" : "Close Conversation") { app.close(buffer) }
        }
    }
}

/// Context-menu items for a network.
struct ServerContextMenuItems: View {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var uiState
    let session: NetworkSession

    var body: some View {
        if session.connectionState == .disconnected {
            Button("Connect") { session.connect() }
        } else {
            Button("Disconnect") { session.disconnect() }
            Button("Reconnect") { session.reconnect() }
        }
        Button("Join Channel…") { uiState.joinChannelNetwork = session.id }
            .disabled(!session.isConnected || session.isBouncerControl)
        let mediaOn = app.isMediaEnabled(forNetwork: session.id)
        Button(mediaOn ? "Disable Inline Media on This Network" : "Enable Inline Media on This Network") {
            app.setMediaEnabled(!mediaOn, forNetwork: session.id)
        }
        Divider()
        Button("Edit Network…") {
            uiState.networkEditor = .existing(session.config.parentNetworkID ?? session.id)
        }
        Button("Remove Network…", role: .destructive) {
            uiState.networkPendingRemoval = session.config.parentNetworkID ?? session.id
        }
    }
}

/// Small sheet asking for a channel name (and optional key) to join.
struct JoinChannelSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let networkID: UUID

    @State private var channel = "#"
    @State private var key = ""

    var body: some View {
        let session = app.session(for: networkID)
        VStack(alignment: .leading, spacing: 14) {
            Text("Join a channel on \(session?.displayName ?? "network")")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme[ThemeKey.popoverForeground])
            TextField("Channel", text: $channel)
                .textFieldStyle(.roundedBorder)
                .onSubmit(join)
            SecureField("Key (optional)", text: $key)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(ThemedButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Join", action: join)
                    .buttonStyle(ThemedButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(normalized.count < 2)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(theme[ThemeKey.popoverBackground])
    }

    private var normalized: String {
        let trimmed = channel.trimmingCharacters(in: .whitespaces)
        guard let session = app.session(for: networkID) else { return trimmed }
        if let first = trimmed.first, session.isupport.channelTypes.contains(first) { return trimmed }
        return "#" + trimmed
    }

    private func join() {
        guard normalized.count >= 2, let session = app.session(for: networkID) else { return }
        let command = key.isEmpty ? "/join \(normalized)" : "/join \(normalized) \(key)"
        session.submit(command, in: session.serverBuffer)
        dismiss()
    }
}
