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

    /// A key the JSON view should scroll to and select (e.g. from a row's
    /// "Edit in settings.json"). The JSON view clears it once shown.
    public var revealKeyInJSON: String?

    /// True while the JSON view has edits that aren't saved yet.
    public var hasUnsavedJSON = false

    public init() {}

    /// Shows the UI view searching for `query` and focuses the search field.
    public func search(_ query: String) {
        mode = .ui
        self.query = query
        focusSearchRequest &+= 1
    }

    /// Shows the JSON view at `key`.
    public func editInJSON(_ key: String) {
        mode = .json
        revealKeyInJSON = key
    }
}
