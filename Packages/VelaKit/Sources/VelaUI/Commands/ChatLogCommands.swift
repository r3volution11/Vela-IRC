// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaStore

extension VelaCommandCatalog {
    /// Opens the chat logs folder in Finder (File menu and palette).
    var showChatLogs: VelaCommand {
        let app = context.app
        return VelaCommand(
            id: "logs.show", category: .chat, title: "Show Chat Logs",
            keywords: ["logging", "logs", "transcripts", "folder", "finder", "files", "history", "text"]
        ) { ChatLogActions.showFolder(app) }
    }

    /// Chat log commands for the palette: show the folder, turn logging on
    /// or off, and leave the selected channel out.
    var chatLogCommands: [VelaCommand] {
        let app = context.app
        let settings = context.app.settings
        var commands = [
            showChatLogs,
            VelaCommand(
                id: "logs.toggle", category: .chat, title: "Save Chat Logs",
                keywords: ["logging", "logs", "transcripts", "record", "plain text", "toggle"],
                isChecked: settings[.loggingEnabled]
            ) { settings[.loggingEnabled].toggle() },
        ]
        if settings[.loggingEnabled], let buffer = app.selectedBuffer, buffer.kind != .server {
            commands.append(Self.logExclusionCommand(app: app, buffer: buffer))
        }
        return commands
    }

    /// "Don't Log This Channel" (or Conversation), for the palette and
    /// buffer context menus. Disabled, and checked, while its whole network
    /// isn't logged, which this can't undo.
    static func logExclusionCommand(app: AppModel, buffer: BufferModel) -> VelaCommand {
        let bufferID = buffer.id
        let inherited = app.isLogExcluded(network: bufferID.networkID)
        let excluded = app.isLogExcluded(bufferID)
        return VelaCommand(
            id: "buffer.toggleLogging", category: .buffer,
            title: buffer.kind == .query ? "Don't Log This Conversation" : "Don't Log This Channel",
            keywords: ["logging", "logs", "chat logs", "exclude", "private", "record"],
            isEnabled: !inherited, isChecked: excluded
        ) { app.setLogExcluded(!excluded, for: bufferID) }
    }

    /// "Don't Log on This Network", for network context menus.
    static func networkLogExclusionCommand(app: AppModel, networkID: UUID) -> VelaCommand {
        let excluded = app.isLogExcluded(network: networkID)
        return VelaCommand(
            id: "network.toggleLogging.\(networkID.uuidString)", category: .network, title: "Don't Log on This Network",
            keywords: ["logging", "logs", "chat logs", "exclude"],
            isChecked: excluded, showsInPalette: false
        ) { app.setLogExcluded(!excluded, network: networkID) }
    }
}

/// "Don't Log This Channel" in a channel's or conversation's context menu,
/// while chat logs are on.
struct ChatLogBufferMenuItems: View {
    @Environment(AppModel.self) private var app
    let buffer: BufferModel

    var body: some View {
        if app.settings[.loggingEnabled], buffer.kind != .server {
            CommandMenuToggle(VelaCommandCatalog.logExclusionCommand(app: app, buffer: buffer))
        }
    }
}

/// "Don't Log on This Network" in a network's context menu, while chat
/// logs are on.
struct ChatLogNetworkMenuItems: View {
    @Environment(AppModel.self) private var app
    let session: NetworkSession

    var body: some View {
        if app.settings[.loggingEnabled] {
            CommandMenuToggle(VelaCommandCatalog.networkLogExclusionCommand(app: app, networkID: session.id))
        }
    }
}

/// Finder and folder-picking actions for chat logs.
@MainActor
enum ChatLogActions {
    /// Opens the logs folder in Finder, creating it first if nothing has
    /// been logged yet.
    static func showFolder(_ app: AppModel) {
        let folder = app.chatLogs.folderForShowing()
        if !NSWorkspace.shared.open(folder) {
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        }
    }

    /// Selects the logs folder in a Finder window.
    static func revealFolder(_ app: AppModel) {
        NSWorkspace.shared.activateFileViewerSelecting([app.chatLogs.folderForShowing()])
    }

    /// Asks for a folder for chat logs. `completion` gets an error message
    /// when the folder can't be remembered, or nil.
    static func chooseFolder(_ app: AppModel, completion: @escaping @MainActor (String?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose a folder for chat logs. Vela makes a folder for each network inside it."
        panel.directoryURL = app.chatLogs.folderURL.deletingLastPathComponent()
        panel.begin { response in
            MainActor.assumeIsolated {
                guard response == .OK, let url = panel.url else { return }
                do {
                    try app.chatLogs.chooseFolder(url)
                    completion(nil)
                } catch {
                    completion("Vela couldn't remember that folder: \(error.localizedDescription)")
                }
            }
        }
    }
}
