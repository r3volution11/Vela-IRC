// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Observation

/// Shared state of the settings editor (Settings → Advanced).
@Observable
public final class SettingsEditorState {
    public enum Mode: String, Sendable {
        /// Every setting with the right control for its type.
        case ui
        /// settings.json itself, with completion and validation.
        case json
    }

    /// Which view the editor shows.
    public var mode: Mode = .ui

    /// The UI view's search text. Besides words, it understands filters:
    /// `@modified`, `@category:<SettingsCategory id>`, `@pane:<SettingsPane id>`
    /// and `@unknown`.
    public var query = ""

    /// Set to move keyboard focus to the search field (bumped, not toggled).
    public var focusSearchRequest = 0

    /// The last ``focusSearchRequest`` the search field acted on, so an
    /// editor that appears after the request (Settings was closed) still
    /// takes focus.
    var handledFocusSearchRequest = 0

    /// A key the JSON view should scroll to and select (e.g. from a row's
    /// "Edit in settings.json"). The JSON view clears it once shown.
    public var revealKeyInJSON: String?

    /// True while the JSON view has edits that aren't saved yet.
    public var hasUnsavedJSON = false

    /// A view to switch to once the JSON view's unsaved edits are dealt
    /// with. ``requestMode(_:)`` sets it instead of ``mode`` while
    /// ``hasUnsavedJSON``; the JSON view asks Save / Discard / Cancel, then
    /// sets ``mode`` (or not) and clears it.
    public var pendingMode: Mode?

    /// A Settings pane to switch to, set from outside the Settings window
    /// (the palette's "Settings: Search…") or from a pane's "Show in
    /// settings editor" link. The Settings window selects it and clears it.
    var requestedPane: SettingsPane?

    public init() {}

    /// Switches to `newMode`, unless that would leave unsaved JSON edits:
    /// then it's left to the JSON view (``pendingMode``).
    public func requestMode(_ newMode: Mode) {
        if mode == .json, newMode != .json, hasUnsavedJSON {
            pendingMode = newMode
        } else {
            pendingMode = nil
            mode = newMode
        }
    }

    /// Shows the UI view searching for `query` and focuses the search field.
    public func search(_ query: String) {
        requestMode(.ui)
        self.query = query
        focusSearchRequest &+= 1
    }

    /// Shows the JSON view at `key`.
    public func editInJSON(_ key: String) {
        mode = .json
        revealKeyInJSON = key
    }

    /// Switches Settings to Advanced and searches for `query` ("Show in
    /// settings editor": `@pane:<id>`).
    func showInEditor(_ query: String) {
        requestedPane = .advanced
        search(query)
    }

    /// "Settings: Search…": Advanced, UI view, search field focused, the
    /// current search kept.
    func openSearch() {
        requestedPane = .advanced
        search(query)
    }

    /// Text typed in the Settings sidebar's search field: Advanced shows
    /// the results while focus stays in the sidebar.
    func searchFromSidebar(_ text: String) {
        requestedPane = .advanced
        requestMode(.ui)
        query = text
    }
}
