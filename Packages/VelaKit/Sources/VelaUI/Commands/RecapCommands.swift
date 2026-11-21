// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaIntelligence
import VelaStore

extension VelaCommandCatalog {
    /// Go → Recap… (⇧⌘R) and "Buffer: Recap…": a Recap of the selected
    /// channel or conversation (its network, from a network's console),
    /// since your first unread message. Offered while `intelligence.recap`
    /// is on, whether or not Apple Intelligence can run: a log doesn't
    /// need it.
    var recap: VelaCommand {
        let openWindow = context.openWindow
        return Self.recap(app: context.app, intelligence: context.intelligence) { openWindow(value: $0) }
    }

    /// Static, opening windows through `open`, so tests can build it.
    static func recap(app: AppModel, intelligence: IntelligenceServices?, open: @escaping (RecapWindowValue) -> Void) -> VelaCommand {
        VelaCommand(
            id: "buffer.recap", category: .buffer, title: "Recap…",
            shortcut: Shortcuts.recap,
            keywords: [
                "summary", "summarize", "report", "log", "transcript", "history", "what did i miss", "missed",
                "apple intelligence", "catch up", "since", "hours", "days", "tldr",
            ],
            isEnabled: RecapActions.isOffered(app.settings) && app.selectedBuffer != nil
        ) {
            guard let buffer = app.selectedBuffer else { return }
            open(RecapWindowValue(scope: RecapActions.scope(for: buffer, intelligence: intelligence)))
        }
    }

    /// The palette's other Recaps: conversations with someone (it asks
    /// who), the selected network, and every network.
    var recapCommands: [VelaCommand] {
        let openWindow = context.openWindow
        return Self.recapCommands(app: context.app, intelligence: context.intelligence) { openWindow(value: $0) }
    }

    static func recapCommands(app: AppModel, intelligence: IntelligenceServices?, open: @escaping (RecapWindowValue) -> Void) -> [VelaCommand] {
        guard RecapActions.isOffered(app.settings), let session = app.selectedSession else { return [] }
        let output = RecapActions.preferredOutput(intelligence)
        var commands = [
            VelaCommand(
                id: "buffer.recapPerson", category: .buffer, title: "Recap Conversations with…",
                keywords: ["recap", "person", "nick", "user", "someone", "summary", "log", "history"]
            ) {
                open(RecapWindowValue(scope: RecapScope(place: .network(session.id), output: output), choosesPerson: true))
            },
            VelaCommand(
                id: "network.recap", category: .network, title: "Recap \(session.displayName)…",
                keywords: ["recap", "summary", "log", "network", "server", "everything", "history"]
            ) {
                open(RecapWindowValue(scope: RecapScope(place: .network(session.id), output: output)))
            },
        ]
        if app.sessions.count > 1 {
            commands.append(VelaCommand(
                id: "network.recapAll", category: .network, title: "Recap All Networks…",
                keywords: ["recap", "summary", "log", "everything", "everywhere", "history"]
            ) {
                open(RecapWindowValue(scope: RecapScope(place: .everywhere, output: output)))
            })
        }
        return commands
    }
}

/// "Recap…" in a channel's or conversation's context menu, next to Catch
/// Me Up.
struct RecapBufferMenuItems: View {
    @Environment(AppModel.self) private var app
    @Environment(IntelligenceServices.self) private var intelligence
    @Environment(\.openWindow) private var openWindow
    let buffer: BufferModel

    var body: some View {
        if RecapActions.isOffered(app.settings) {
            Button("Recap…") {
                RecapActions.open(RecapActions.scope(for: buffer, intelligence: intelligence), openWindow: openWindow)
            }
        }
    }
}

/// "Recap Network…" in a network's context menu.
struct RecapNetworkMenuItems: View {
    @Environment(AppModel.self) private var app
    @Environment(IntelligenceServices.self) private var intelligence
    @Environment(\.openWindow) private var openWindow
    let session: NetworkSession

    var body: some View {
        if RecapActions.isOffered(app.settings) {
            Button("Recap Network…") {
                RecapActions.open(
                    RecapScope(place: .network(session.id), output: RecapActions.preferredOutput(intelligence)),
                    openWindow: openWindow
                )
            }
        }
    }
}
