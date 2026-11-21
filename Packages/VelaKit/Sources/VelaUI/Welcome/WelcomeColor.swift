// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Savage
import VelaTheme

// The welcome scene's colors are Savage's PaintColor. This is what the
// scene adds: theme colors, and the small color math its lighting uses.

nonisolated extension PaintColor {
    /// A theme color's channels (its alpha is dropped: composite it first).
    init(_ color: ThemeColor) {
        self.init(red: color.red, green: color.green, blue: color.blue)
    }

    /// Brightness, roughly as the eye sees it.
    var luma: Double { red * 0.3 + green * 0.59 + blue * 0.11 }

    /// Each channel times `s`.
    func times(_ s: Double) -> PaintColor { PaintColor(red: red * s, green: green * s, blue: blue * s, opacity: opacity) }

    /// The same hue at a given brightness.
    func atLuma(_ target: Double) -> PaintColor { times(target / max(0.001, luma)) }

    /// The hue, in degrees.
    var hue: Double {
        let mx = max(red, green, blue), mn = min(red, green, blue)
        guard mx > mn else { return 0 }
        let h = mx == red ? (green - blue) / (mx - mn) : mx == green ? 2 + (blue - red) / (mx - mn) : 4 + (red - green) / (mx - mn)
        return (h * 60 + 360).truncatingRemainder(dividingBy: 360)
    }
}
