// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// The mIRC color palette used by IRC formatting codes (`^C`).
///
/// 0–15 are mIRC's classic defaults; 16–98 are the standard extended
/// palette from https://modern.ircdocs.horse/formatting.html. Themes
/// typically retune 0–15 for their background and leave 16–98 alone.
public enum IRCPalette {
    public static let count = 99

    /// Human-readable names for 0–15.
    public static let names = [
        "White", "Black", "Blue", "Green", "Red", "Brown", "Magenta", "Orange",
        "Yellow", "Light Green", "Cyan", "Light Cyan", "Light Blue", "Pink", "Grey", "Light Grey",
    ]

    public static func name(of index: Int) -> String {
        index < names.count ? names[index] : "Extended color \(index)"
    }

    public static let standardHex: [String] = [
        // 0–15: mIRC defaults
        "#FFFFFF", "#000000", "#00007F", "#009300", "#FF0000", "#7F0000", "#9C009C", "#FC7F00",
        "#FFFF00", "#00FC00", "#009393", "#00FFFF", "#0000FC", "#FF00FF", "#7F7F7F", "#D2D2D2",
        // 16–27
        "#470000", "#472100", "#474700", "#324700", "#004700", "#00472C",
        "#004747", "#002747", "#000047", "#2E0047", "#470047", "#47002A",
        // 28–39
        "#740000", "#743A00", "#747400", "#517400", "#007400", "#007449",
        "#007474", "#004074", "#000074", "#4B0074", "#740074", "#740045",
        // 40–51
        "#B50000", "#B56300", "#B5B500", "#7DB500", "#00B500", "#00B571",
        "#00B5B5", "#0063B5", "#0000B5", "#7500B5", "#B500B5", "#B5006B",
        // 52–63
        "#FF0000", "#FF8C00", "#FFFF00", "#B2FF00", "#00FF00", "#00FFA0",
        "#00FFFF", "#008CFF", "#0000FF", "#A500FF", "#FF00FF", "#FF0098",
        // 64–75
        "#FF5959", "#FFB459", "#FFFF71", "#CFFF60", "#6FFF6F", "#65FFC9",
        "#6DFFFF", "#59B4FF", "#5959FF", "#C459FF", "#FF66FF", "#FF59BC",
        // 76–87
        "#FF9C9C", "#FFD39C", "#FFFF9C", "#E2FF9C", "#9CFF9C", "#9CFFDB",
        "#9CFFFF", "#9CD3FF", "#9C9CFF", "#DC9CFF", "#FF9CFF", "#FF94D3",
        // 88–98: greyscale
        "#000000", "#131313", "#282828", "#363636", "#4D4D4D", "#656565",
        "#818181", "#9F9F9F", "#BCBCBC", "#E2E2E2", "#FFFFFF",
    ]

    public static let standard: [ThemeColor] = standardHex.map { ThemeColor(hex: $0)! }
}

/// Default nickname palettes, used when a theme doesn't set `nickColors`.
/// Tuned for at least 4.5:1 contrast on the default backgrounds.
public enum NickPalette {
    public static let darkHex = [
        "#F07178", "#F78C6C", "#FFCB6B", "#C3E88D", "#7FDBCA", "#89DDFF",
        "#82AAFF", "#B4A5FF", "#C792EA", "#FF9CAC", "#E6B07E", "#A8D8A0",
    ]

    public static let lightHex = [
        "#C62828", "#BF4A12", "#8C6200", "#4E7A12", "#1B7D4F", "#00727C",
        "#1565C0", "#3949AB", "#6A3FB5", "#9C27B0", "#AD1457", "#7D5A3C",
    ]

    public static func defaultPalette(for kind: ThemeKind) -> [ThemeColor] {
        (kind == .dark ? darkHex : lightHex).map { ThemeColor(hex: $0)! }
    }
}
