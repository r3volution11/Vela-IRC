// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Observation
import VelaTheme

/// Lets other views ask the Theme Editor window to start from a specific
/// theme ("Customize in Theme Editor…" on a gallery card). Set
/// `requestedBase`, then open the window; the editor picks it up whether it
/// was already open or not.
@Observable
final class ThemeEditorHandoff {
    static let shared = ThemeEditorHandoff()

    var requestedBase: ThemeInfo?

    private init() {}
}

extension ThemeDefinition {
    /// `My Theme (2)` → `my-theme-2`, for export file names.
    var fileSlug: String {
        var result = ""
        for scalar in name.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar), scalar.isASCII {
                result.unicodeScalars.append(scalar)
            } else if !result.isEmpty, !result.hasSuffix("-") {
                result.append("-")
            }
        }
        while result.hasSuffix("-") { result.removeLast() }
        return result.isEmpty ? "theme" : result
    }
}
