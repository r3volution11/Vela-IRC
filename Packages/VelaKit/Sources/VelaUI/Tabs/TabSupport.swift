// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Observation
import SwiftUI
import VelaCore
import VelaIRC

/// Identifies a tab in either row.
enum TabKey: Hashable {
    case buffer(BufferID)
    case network(UUID)
}

/// Remembers the buffer last selected on each network, so a server tab
/// returns to where you were (like a Vivaldi stack remembering its active tab).
enum TabMemory {
    private static var lastSelected: [UUID: BufferID] = [:]

    static func record(_ id: BufferID?) {
        guard let id else { return }
        lastSelected[id.networkID] = id
    }

    /// The remembered buffer of `session`, or its server buffer.
    static func destination(in session: NetworkSession) -> BufferModel {
        if let id = lastSelected[session.id], let buffer = session.buffer(id: id) { return buffer }
        return session.serverBuffer
    }
}

/// Hover state shared by both rows (for separators and close buttons) and
/// middle-click-to-close, which SwiftUI has no gesture for.
@Observable
final class TabInteraction {
    var hovered: TabKey?

    @ObservationIgnored private var monitor: Any?

    func setHovering(_ hovering: Bool, _ key: TabKey) {
        if hovering {
            hovered = key
        } else if hovered == key {
            hovered = nil
        }
    }

    /// Calls `handler` with the hovered tab when the middle button is released
    /// over it. The click is swallowed only when `handler` returns true.
    func installMiddleClickMonitor(_ handler: @escaping (TabKey) -> Bool) {
        removeMiddleClickMonitor()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseUp) { [weak self] event in
            guard event.buttonNumber == 2, let key = self?.hovered else { return event }
            return handler(key) ? nil : event
        }
    }

    func removeMiddleClickMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// Actions shared by tabs, menus and shortcuts.
enum TabActions {
    /// Selects the network's remembered buffer.
    static func select(_ session: NetworkSession, app: AppModel) {
        app.select(TabMemory.destination(in: session))
    }

    /// Closes a channel or query tab. When it's the selected tab, its right
    /// neighbor (or left, at the end) is selected first, like a browser.
    static func close(_ buffer: BufferModel, in session: NetworkSession, app: AppModel) {
        guard buffer.kind != .server else { return }
        if app.selectedBufferID == buffer.id {
            let tabs = session.allBuffers
            if let index = tabs.firstIndex(where: { $0.id == buffer.id }) {
                let neighbor = tabs.indices.contains(index + 1) ? tabs[index + 1] : tabs[max(0, index - 1)]
                app.select(neighbor)
            }
        }
        session.close(buffer)
    }

    /// Tabs reachable with ⌘1…⌘9: the network's channels, then queries.
    static func shortcutTargets(in session: NetworkSession?) -> [BufferModel] {
        guard let session, !session.isBouncerControl else { return [] }
        return session.buffers
    }
}

/// VoiceOver and tooltip text.
enum TabDescriptions {
    static func activity(unread: Int, highlights: Int) -> [String] {
        var parts: [String] = []
        if highlights > 0 { parts.append(highlights == 1 ? "1 mention" : "\(highlights) mentions") }
        if unread > 0 { parts.append("\(unread) unread") }
        return parts
    }

    static func connection(_ state: IRCConnectionState) -> String {
        switch state {
        case .connected: "Connected"
        case .connecting, .registering: "Connecting"
        case .disconnected: "Disconnected"
        }
    }

    static func bufferValue(_ buffer: BufferModel, in session: NetworkSession) -> String {
        var parts = activity(unread: buffer.isMuted ? 0 : buffer.unreadCount, highlights: buffer.highlightCount)
        if buffer.isMuted { parts.append("muted") }
        if buffer.kind == .channel && !buffer.isJoined { parts.append("not joined") }
        if !session.isConnected { parts.append(connection(session.connectionState).lowercased()) }
        return parts.joined(separator: ", ")
    }

    static func bufferKind(_ buffer: BufferModel) -> String {
        switch buffer.kind {
        case .server: "Server console"
        case .channel: "Channel"
        case .query: "Conversation"
        }
    }
}

/// Hidden ⌘1…⌘9 buttons; present only while the tab stack is on screen.
struct TabShortcutButtons: View {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var uiState
    let session: NetworkSession?

    var body: some View {
        let targets = TabActions.shortcutTargets(in: session)
        ZStack {
            ForEach(1...9, id: \.self) { number in
                let index = number - 1
                Button("Select Tab \(number)") {
                    guard targets.indices.contains(index) else { return }
                    app.select(targets[index])
                    uiState.focusInput()
                }
                .keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: .command)
                .disabled(!targets.indices.contains(index))
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}
