// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaStore
import VelaTheme

/// Settings → Messages → History: whether messages are saved on this Mac
/// (`history.save`), how long saved messages are kept, and deleting them.
struct HistorySection: View {
    @Environment(AppModel.self) private var app
    @State private var dialog: HistoryDialog?

    var body: some View {
        @Bindable var settings = app.settings
        let saves = settings[.historySave]
        let saved = app.savedHistory

        SettingsSection("History", footer: Self.footer(saves: saves)) {
            SettingsToggle(
                "Save message history",
                detail: "Keep messages, reactions and link previews on this Mac, so they're there after Vela restarts. Off, they're kept only while Vela is open. Your channels and where you stopped reading are saved either way.",
                isOn: Binding(
                    get: { saves },
                    set: { HistorySaving.setSaving($0, app: app) { dialog = .stopSaving } }
                )
            )
            SettingsMenuRow(
                title: "Keep messages",
                detail: Self.keepDetail(saves: saves, hasSavedMessages: saved.hasMessages),
                selection: $settings[.historyRetentionDays],
                options: MessagesPane.options(
                    [0, 7, 30, 90, 180, 365, 730],
                    current: settings[.historyRetentionDays],
                    label: AdvancedPane.retentionLabel
                )
            )
            .themedDisabled(!saves && !saved.hasMessages)
            SettingsRow(
                "Saved history",
                detail: HistorySaving.canDelete(app) ? "Messages, reactions and link previews saved on this Mac." : "Nothing is saved on this Mac."
            ) {
                Button("Delete Saved History…") { dialog = .delete }
                    .buttonStyle(ThemedButtonStyle())
                    .themedDisabled(!HistorySaving.canDelete(app))
                    .accessibilityHint("Asks before deleting the messages, reactions and link previews saved on this Mac.")
            }
        }
        .historyDialogs($dialog)
        // Pick up what was saved since launch (it isn't tracked line by line).
        .task { await app.refreshSavedHistory() }
    }

    static func footer(saves: Bool) -> String {
        if saves {
            return "Older messages are removed from this Mac when Vela starts. Chat logs, below, are a separate plain-text copy."
        }
        return "Messages are kept in memory while Vela is open, then fetched again from a bouncer or server that keeps history. Chat logs, below, are separate: plain-text files, saved only if you turn them on."
    }

    static func keepDetail(saves: Bool, hasSavedMessages: Bool) -> String? {
        if saves { return nil }
        return hasSavedMessages
            ? "Applies to the history saved before you turned saving off."
            : "Used while Save message history is on."
    }
}

// MARK: - Dialogs

/// The questions asked about saved history.
enum HistoryDialog: Hashable {
    /// Turning saving off while history is saved: delete it or keep it?
    case stopSaving
    /// "Delete Saved History…": are you sure?
    case delete
}

extension View {
    /// Asks `dialog`'s question as a sheet on this view's window.
    func historyDialogs(_ dialog: Binding<HistoryDialog?>) -> some View {
        modifier(HistoryDialogs(dialog: dialog))
    }
}

private struct HistoryDialogs: ViewModifier {
    @Environment(AppModel.self) private var app
    @Binding var dialog: HistoryDialog?
    @State private var failure: String?

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Stop saving message history?", isPresented: presenting(.stopSaving), titleVisibility: .visible) {
                Button("Delete Saved History", role: .destructive) {
                    HistorySaving.stopSaving(app: app, deleting: true) { failure = $0 }
                }
                Button("Keep What's Saved") {
                    HistorySaving.stopSaving(app: app, deleting: false) { failure = $0 }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("New messages won't be saved either way. Delete the messages, reactions and link previews already saved on this Mac, or keep them: kept history still shows in your channels.")
            }
            .confirmationDialog("Delete saved message history?", isPresented: presenting(.delete), titleVisibility: .visible) {
                Button("Delete Saved History", role: .destructive) {
                    HistorySaving.delete(app: app) { failure = $0 }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The messages, reactions and link previews saved on this Mac are deleted. Your channels, read positions, settings and chat logs stay, and messages on screen stay until you quit Vela. This can't be undone.")
            }
            .alert(
                "Saved history couldn't be deleted",
                isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(failure ?? "")
            }
    }

    private func presenting(_ kind: HistoryDialog) -> Binding<Bool> {
        Binding(
            get: { dialog == kind },
            set: { if !$0, dialog == kind { dialog = nil } }
        )
    }
}

// MARK: - Actions

/// Turning `history.save` on and off, and deleting saved history, for the
/// settings pane and the command palette.
@MainActor
enum HistorySaving {
    /// Turns saving on, or off. Turning it off while history is saved calls
    /// `ask` instead, to ask whether to delete it (``HistoryDialog/stopSaving``).
    static func setSaving(_ isOn: Bool, app: AppModel, ask: @escaping @MainActor () -> Void) {
        guard isOn != app.settings[.historySave] else { return }
        guard !isOn else {
            app.settings[.historySave] = true
            return
        }
        Task {
            if await app.refreshSavedHistory().isEmpty {
                app.settings[.historySave] = false
            } else {
                ask()
            }
        }
    }

    /// The answer to ``HistoryDialog/stopSaving``: saving is off either way.
    static func stopSaving(app: AppModel, deleting: Bool, failed: @escaping @MainActor (String) -> Void) {
        app.settings[.historySave] = false
        if deleting { delete(app: app, failed: failed) }
    }

    static func delete(app: AppModel, failed: @escaping @MainActor (String) -> Void) {
        Task {
            do {
                try await app.deleteSavedHistory()
            } catch {
                failed(error.localizedDescription)
            }
        }
    }

    /// Whether there may be something to delete: saving is on (lines may
    /// have been saved since ``AppModel/savedHistory`` was read), or
    /// something was saved.
    static func canDelete(_ app: AppModel) -> Bool {
        app.database != nil && (app.settings[.historySave] || !app.savedHistory.isEmpty)
    }
}
