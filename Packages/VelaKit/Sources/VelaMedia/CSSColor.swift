// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Normalizes the CSS color values found in `<meta name="theme-color">`
/// to `#RRGGBB`. Alpha is dropped; unknown syntax yields `nil`.
enum CSSColor {
    static func normalizedHex(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return nil }

        if value.hasPrefix("#") {
            return hex(String(value.dropFirst()))
        }
        if value.hasPrefix("rgb") {
            return rgbFunction(value)
        }
        if let named = namedColors[value] {
            return named
        }
        // Some sites omit the '#'.
        if value.count == 6 || value.count == 3 {
            return hex(value)
        }
        return nil
    }

    private static func hex(_ digits: String) -> String? {
        guard digits.allSatisfy(\.isHexDigit) else { return nil }
        let expanded: String
        switch digits.count {
        case 3, 4: expanded = digits.prefix(3).map { "\($0)\($0)" }.joined()
        case 6, 8: expanded = String(digits.prefix(6))
        default: return nil
        }
        return "#" + expanded.uppercased()
    }

    /// `rgb(255, 0, 0)`, `rgba(255,0,0,.5)`, `rgb(255 0 0 / 50%)`, `rgb(100% 0% 0%)`.
    private static func rgbFunction(_ value: String) -> String? {
        guard let open = value.firstIndex(of: "("), let close = value.lastIndex(of: ")"), open < close else {
            return nil
        }
        let inner = value[value.index(after: open)..<close]
        let channels = inner
            .split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
        let parts = channels
            .split(whereSeparator: { $0 == "," || $0 == " " })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard parts.count >= 3 else { return nil }

        var components: [Int] = []
        for part in parts.prefix(3) {
            let number: Double?
            if part.hasSuffix("%") {
                number = Double(part.dropLast()).map { $0 * 2.55 }
            } else {
                number = Double(part)
            }
            guard let number, number.isFinite else { return nil }
            components.append(Int(min(255, max(0, number.rounded()))))
        }
        return String(format: "#%02X%02X%02X", components[0], components[1], components[2])
    }

    private static let namedColors: [String: String] = [
        "black": "#000000", "white": "#FFFFFF", "red": "#FF0000", "green": "#008000", "blue": "#0000FF",
        "yellow": "#FFFF00", "orange": "#FFA500", "purple": "#800080", "gray": "#808080", "grey": "#808080",
        "silver": "#C0C0C0", "maroon": "#800000", "olive": "#808000", "lime": "#00FF00", "aqua": "#00FFFF",
        "cyan": "#00FFFF", "teal": "#008080", "navy": "#000080", "fuchsia": "#FF00FF", "magenta": "#FF00FF",
        "pink": "#FFC0CB", "brown": "#A52A2A", "gold": "#FFD700", "indigo": "#4B0082", "crimson": "#DC143C",
        "darkgray": "#A9A9A9", "darkgrey": "#A9A9A9", "lightgray": "#D3D3D3", "lightgrey": "#D3D3D3",
        "whitesmoke": "#F5F5F5", "rebeccapurple": "#663399",
    ]
}
