// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VelaCore
import VelaIntelligence
import VelaStore

/// What a Recap window is opened for: its scope, and whether it starts by
/// asking whose conversations to recap ("Recap Conversations with…").
struct RecapWindowValue: Codable, Hashable {
    var scope: RecapScope
    var choosesPerson = false
    /// The model to write it with ("Recap With…"); nil follows Recap's
    /// setting.
    var model: AIModelChoice?
}

/// Opening Recaps, naming them, jumping from them to a message, and Copy
/// and Save as Markdown…. Shared by the menus, the palette, the Catch me
/// up card and the window.
@MainActor
enum RecapActions {
    /// Whether Recap is offered (`intelligence.recap`). A log needs no
    /// Apple Intelligence, so it doesn't depend on its status.
    static func isOffered(_ settings: SettingsStore) -> Bool {
        settings[.intelligenceRecap]
    }

    /// The Recap for `buffer`: that conversation, or the whole network
    /// for its console, since your first unread message.
    static func scope(for buffer: BufferModel, intelligence: IntelligenceServices? = nil) -> RecapScope {
        let place: RecapScope.Place = buffer.kind == .server ? .network(buffer.id.networkID) : .buffer(buffer.id)
        return RecapScope(place: place, output: preferredOutput(intelligence))
    }

    /// Summary, or Log when Recap's model can't run (Apple Intelligence
    /// off, with no provider's model chosen instead).
    static func preferredOutput(_ intelligence: IntelligenceServices?) -> RecapScope.Output {
        guard let intelligence else { return .summary }
        return intelligence.status(for: .recap).isAvailable ? .summary : .log
    }

    static func open(_ value: RecapWindowValue, openWindow: OpenWindowAction) {
        openWindow(value: value)
    }

    static func open(_ scope: RecapScope, openWindow: OpenWindowAction) {
        openWindow(value: RecapWindowValue(scope: scope))
    }

    // MARK: Names

    /// "Recap of #vela", "Recap of Libera.Chat", "Recap of all networks",
    /// "Recap of alice".
    static func title(for scope: RecapScope, app: AppModel) -> String {
        if let person = scope.person { return "Recap of \(person)" }
        return "Recap of \(placeName(scope.place, app: app))"
    }

    /// "#vela", "Libera.Chat", "all networks".
    static func placeName(_ place: RecapScope.Place, app: AppModel) -> String {
        switch place {
        case .buffer(let id): app.lookup(id)?.buffer.name ?? id.foldedName
        case .network(let id): app.session(for: id)?.displayName ?? "a network"
        case .everywhere: "all networks"
        }
    }

    /// Where a Recap's messages are, for its subtitle: the network of a
    /// channel, "#vela on Libera.Chat" for a person's Recap there, or
    /// "Libera.Chat" / "All networks" for a person's.
    static func placeDetail(_ scope: RecapScope, app: AppModel) -> String? {
        switch scope.place {
        case .buffer(let id):
            guard let (session, buffer) = app.lookup(id) else { return nil }
            return scope.person == nil ? session.displayName : "\(buffer.name) on \(session.displayName)"
        case .network(let id):
            return scope.person == nil ? nil : app.session(for: id)?.displayName
        case .everywhere:
            return scope.person == nil ? nil : "All networks"
        }
    }

    /// The line under the title: where, when, the time range, how many
    /// messages and people.
    static func subtitle(_ scope: RecapScope, input: RecapInput?, speakers: Int, app: AppModel, format: RecapFormat) -> String {
        var parts: [String] = []
        if let place = placeDetail(scope, app: app) { parts.append(place) }
        parts.append(scope.span.title)
        if let input, !input.isEmpty {
            if let range = input.timeRange { parts.append(format.range(range)) }
            parts.append(RecapFormat.messages(input.lineCount))
            if speakers > 0 { parts.append(RecapFormat.people(speakers)) }
        }
        return parts.joined(separator: " · ")
    }

    /// Notes on what the Recap is missing: messages Vela doesn't have,
    /// and messages left out to keep it to a size this Mac reads well.
    static func notes(for input: RecapInput, output: RecapScope.Output, format: RecapFormat) -> [String] {
        var notes: [String] = []
        let short = input.conversations.filter(\.startsBeforeHistory)
        if let latest = short.compactMap(\.availableSince).max() {
            let when = format.time(latest)
            notes.append(short.count == 1 && input.conversations.count == 1
                ? "Vela has \(short[0].name) back to \(when)."
                : short.count == 1 ? "Vela has \(short[0].name) only back to \(when)."
                : "Vela has some of these conversations only back to \(when).")
            if !input.readsSavedHistory {
                notes[notes.count - 1] += " Save message history is off, so it has what arrived while it was open and what your bouncer sent."
            }
        }
        if input.droppedLines > 0 {
            notes.append("Shows the newest \(RecapLimits.gatheredLines.formatted()) of \(input.matchingLines.formatted()) matching messages.")
        }
        if output == .summary, input.lineCount > RecapLimits.summaryLines {
            notes.append("Apple Intelligence reads the latest \(RecapLimits.summaryLines.formatted()) of these \(input.lineCount.formatted()) messages. Narrow the Recap to a channel, a person or a shorter span to cover the rest.")
        }
        return notes
    }

    /// How to name each conversation after an item, when there are several.
    static func conversationNames(_ input: RecapInput) -> [BufferID: String] {
        let networks = Set(input.conversations.map(\.networkName))
        return Dictionary(uniqueKeysWithValues: input.conversations.map { conversation in
            (conversation.id, networks.count > 1 ? "\(conversation.name) on \(conversation.networkName)" : conversation.name)
        })
    }

    // MARK: Jumping

    /// Shows `reference`'s message in the main window: selects its channel,
    /// scrolls to the message and highlights it. A message older than
    /// what's loaded is loaded from saved history first.
    static func jump(to reference: RecapReference, app: AppModel, uiState: UIState, openWindow: OpenWindowAction) {
        guard let (session, buffer) = app.lookup(reference.conversation) else { return }
        app.select(buffer)
        openWindow(id: WindowID.main)
        MessageJump.jump(to: LineReference(id: reference.lineID, time: reference.time), in: buffer, session: session, uiState: uiState)
    }

    // MARK: Copy and Save

    static func copy(_ markdown: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(markdown, forType: .string)
    }

    /// Saves `markdown` with a save panel attached to `window`.
    static func save(_ markdown: String, suggestedName: String, in window: NSWindow?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = fileName(suggestedName)
        panel.message = "Save this Recap as a Markdown file."
        let write: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                let alert = NSAlert(error: error)
                if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
            }
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: write)
        } else {
            panel.begin(completionHandler: write)
        }
    }

    /// "Recap of #vela" → "Recap of vela.md", safe for a file name.
    static func fileName(_ title: String) -> String {
        let cleaned = title
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)
        return (cleaned.isEmpty ? "Recap" : cleaned) + ".md"
    }
}

/// Opens Recap windows asked for where there's no window to ask from: a
/// user menu built by AppKit, and Siri and Shortcuts
/// (``RecapRequests``). Lives as long as the app.
@MainActor
final class RecapWindowRouter {
    private let intelligence: IntelligenceServices
    private var openWindow: OpenWindowAction?
    private var handled: UUID?

    /// The router of the running app.
    static weak var shared: RecapWindowRouter?

    init(intelligence: IntelligenceServices) {
        self.intelligence = intelligence
        observe()
    }

    /// Captured from the menu bar, which outlives every window.
    func install(_ action: OpenWindowAction) {
        let first = openWindow == nil
        openWindow = action
        // A request that came before the menu bar did (Siri launching
        // Vela): open it once the scene update is over.
        if first { Task { @MainActor in self.handle() } }
    }

    func open(_ value: RecapWindowValue) {
        openWindow?(value: value)
    }

    private func observe() {
        withObservationTracking {
            _ = intelligence.recaps.latest
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.handle()
                self?.observe()
            }
        }
    }

    private func handle() {
        guard let request = intelligence.recaps.latest, request.id != handled, let openWindow else { return }
        handled = request.id
        AppActivation.activate()
        openWindow(value: RecapWindowValue(scope: request.scope))
    }
}
