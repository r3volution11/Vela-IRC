// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Observation
import VelaCore

/// What the palette floats to the top for an empty query: recently run
/// commands and recently visited conversations, most recent first.
///
/// Stored in `UserDefaults` (view state, not a settings.json preference).
/// Conversation visits are tracked by observing the selection, so ones
/// reached from the sidebar, tabs or shortcuts count too.
final class PaletteHistory {
    static let shared = PaletteHistory(defaults: .standard)

    static let limit = 50
    private static let commandsKey = "Vela.palette.recentCommands"
    private static let buffersKey = "Vela.palette.recentBuffers"

    private let defaults: UserDefaults
    private(set) var commandIDs: [String]
    /// `BufferID.description`s.
    private(set) var bufferIDs: [String]
    private weak var trackedApp: AppModel?
    /// Off in demo mode, which shares the real app's defaults.
    private var persists = true

    init(defaults: UserDefaults) {
        self.defaults = defaults
        commandIDs = defaults.stringArray(forKey: Self.commandsKey) ?? []
        bufferIDs = defaults.stringArray(forKey: Self.buffersKey) ?? []
    }

    func recordCommand(_ id: String) {
        Self.bump(id, in: &commandIDs)
        if persists { defaults.set(commandIDs, forKey: Self.commandsKey) }
    }

    func recordBuffer(_ id: BufferID) {
        Self.bump(id.description, in: &bufferIDs)
        if persists { defaults.set(bufferIDs, forKey: Self.buffersKey) }
    }

    /// Records every buffer selection from now on. Safe to call repeatedly.
    func startTracking(_ app: AppModel) {
        guard trackedApp !== app else { return }
        trackedApp = app
        // Demo sessions get fresh ids each launch; keep the real lists clean.
        persists = !app.isDemo
        if app.isDemo { bufferIDs = [] }
        observeSelection(of: app)
    }

    private func observeSelection(of app: AppModel) {
        let id = withObservationTracking {
            app.selectedBufferID
        } onChange: { [weak self, weak app] in
            // Called before the change lands; read the new value afterwards.
            Task { @MainActor in
                guard let self, let app, self.trackedApp === app else { return }
                self.observeSelection(of: app)
            }
        }
        if let id { recordBuffer(id) }
    }

    private static func bump(_ id: String, in list: inout [String]) {
        list.removeAll { $0 == id }
        list.insert(id, at: 0)
        if list.count > limit { list.removeLast(list.count - limit) }
    }
}
