// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// A text color from mIRC formatting codes.
public enum IRCColor: Sendable, Hashable {
    /// A palette index, 0–98 (`\x03NN`). 0–15 are the classic, theme-able
    /// colors; 16–98 are the fixed extended palette.
    case palette(Int)
    /// A 24-bit color `0xRRGGBB` from the `\x04` hex color code.
    case rgb(UInt32)

    /// The conventional RGB value for this color (`0xRRGGBB`). Themes are
    /// expected to override palette entries 0–15.
    public var defaultRGB: UInt32? {
        switch self {
        case .rgb(let value):
            value
        case .palette(let index):
            Self.paletteRGB.indices.contains(index) ? Self.paletteRGB[index] : nil
        }
    }

    /// Reference palette (https://modern.ircdocs.horse/formatting#colors).
    public static let paletteRGB: [UInt32] = [
        // 0–15
        0xFFFFFF, 0x000000, 0x00007F, 0x009300, 0xFF0000, 0x7F0000, 0x9C009C, 0xFC7F00,
        0xFFFF00, 0x00FC00, 0x009393, 0x00FFFF, 0x0000FC, 0xFF00FF, 0x7F7F7F, 0xD2D2D2,
        // 16–27
        0x470000, 0x472100, 0x474700, 0x324700, 0x004700, 0x00472C, 0x004747, 0x002747,
        0x000047, 0x2E0047, 0x470047, 0x47002A,
        // 28–39
        0x740000, 0x743A00, 0x747400, 0x517400, 0x007400, 0x007449, 0x007474, 0x004074,
        0x000074, 0x4B0074, 0x740074, 0x740045,
        // 40–51
        0xB50000, 0xB56300, 0xB5B500, 0x7DB500, 0x00B500, 0x00B571, 0x00B5B5, 0x0063B5,
        0x0000B5, 0x7500B5, 0xB500B5, 0xB5006B,
        // 52–63
        0xFF0000, 0xFF8C00, 0xFFFF00, 0xB2FF00, 0x00FF00, 0x00FFA0, 0x00FFFF, 0x008CFF,
        0x0000FF, 0xA500FF, 0xFF00FF, 0xFF0098,
        // 64–75
        0xFF5959, 0xFFB459, 0xFFFF71, 0xCFFF60, 0x6FFF6F, 0x65FFC9, 0x6DFFFF, 0x59B4FF,
        0x5959FF, 0xC459FF, 0xFF66FF, 0xFF59BC,
        // 76–87
        0xFF9C9C, 0xFFD39C, 0xFFFF9C, 0xE2FF9C, 0x9CFF9C, 0x9CFFDB, 0x9CFFFF, 0x9CD3FF,
        0x9C9CFF, 0xDC9CFF, 0xFF9CFF, 0xFF94D3,
        // 88–98
        0x000000, 0x131313, 0x282828, 0x363636, 0x4D4D4D, 0x656565, 0x818181, 0x9F9F9F,
        0xBCBCBC, 0xE2E2E2, 0xFFFFFF,
    ]
}

/// The formatting state applying to a run of text.
public struct IRCTextStyle: Sendable, Hashable {
    public var bold: Bool
    public var italic: Bool
    public var underline: Bool
    public var strikethrough: Bool
    public var monospace: Bool
    /// Swap foreground and background when rendering.
    public var reverse: Bool
    public var foreground: IRCColor?
    public var background: IRCColor?

    public init(
        bold: Bool = false,
        italic: Bool = false,
        underline: Bool = false,
        strikethrough: Bool = false,
        monospace: Bool = false,
        reverse: Bool = false,
        foreground: IRCColor? = nil,
        background: IRCColor? = nil
    ) {
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.strikethrough = strikethrough
        self.monospace = monospace
        self.reverse = reverse
        self.foreground = foreground
        self.background = background
    }

    public static let plain = IRCTextStyle()

    public var isPlain: Bool { self == .plain }
}

/// A run of text sharing one style.
public struct IRCTextSpan: Sendable, Hashable {
    public var text: String
    public var style: IRCTextStyle

    public init(text: String, style: IRCTextStyle = .plain) {
        self.text = text
        self.style = style
    }
}

/// mIRC-style formatting codes (https://modern.ircdocs.horse/formatting).
public enum IRCFormatting {
    public static let bold: Character = "\u{02}"
    public static let color: Character = "\u{03}"
    public static let hexColor: Character = "\u{04}"
    public static let reset: Character = "\u{0F}"
    public static let monospace: Character = "\u{11}"
    public static let reverse: Character = "\u{16}"
    public static let italic: Character = "\u{1D}"
    public static let strikethrough: Character = "\u{1E}"
    public static let underline: Character = "\u{1F}"

    /// Splits `text` into styled spans. Formatting codes are removed;
    /// adjacent spans with identical styles are merged and empty spans are
    /// never produced.
    public static func parse(_ text: String) -> [IRCTextSpan] {
        guard containsFormatting(text) else {
            return text.isEmpty ? [] : [IRCTextSpan(text: text)]
        }
        var spans: [IRCTextSpan] = []
        scan(text) { run, style in
            if let last = spans.last, last.style == style {
                spans[spans.count - 1].text += run
            } else {
                spans.append(IRCTextSpan(text: run, style: style))
            }
        }
        return spans
    }

    /// Removes all formatting codes (including color parameters).
    public static func strip(_ text: String) -> String {
        guard containsFormatting(text) else { return text }
        var out = ""
        scan(text) { run, _ in out += run }
        return out
    }

    /// True when `text` contains any formatting control code.
    public static func containsFormatting(_ text: String) -> Bool {
        text.utf8.contains { byte in
            switch byte {
            case 0x02, 0x03, 0x04, 0x0F, 0x11, 0x16, 0x1D, 0x1E, 0x1F: true
            default: false
            }
        }
    }

    // MARK: Scanner

    private static func scan(_ text: String, emit: (String, IRCTextStyle) -> Void) {
        let scalars = Array(text.unicodeScalars)
        var style = IRCTextStyle()
        var buffer = String.UnicodeScalarView()
        var index = 0

        func flush() {
            guard !buffer.isEmpty else { return }
            emit(String(buffer), style)
            buffer = String.UnicodeScalarView()
        }

        func digit(at position: Int) -> Int? {
            guard position < scalars.count else { return nil }
            let value = scalars[position].value
            return (0x30...0x39).contains(value) ? Int(value - 0x30) : nil
        }

        /// Up to two decimal digits starting at `position`.
        func colorNumber(at position: Int) -> (value: Int, length: Int)? {
            guard let first = digit(at: position) else { return nil }
            if let second = digit(at: position + 1) { return (first * 10 + second, 2) }
            return (first, 1)
        }

        /// Exactly six hex digits starting at `position`.
        func hexColor(at position: Int) -> UInt32? {
            guard position + 6 <= scalars.count else { return nil }
            var value: UInt32 = 0
            for offset in 0..<6 {
                guard let nibble = hexDigit(scalars[position + offset]) else { return nil }
                value = value << 4 | nibble
            }
            return value
        }

        func paletteColor(_ number: Int) -> IRCColor? {
            number == 99 ? nil : .palette(number)
        }

        while index < scalars.count {
            let scalar = scalars[index]
            switch scalar.value {
            case 0x02:
                flush(); style.bold.toggle(); index += 1
            case 0x1D:
                flush(); style.italic.toggle(); index += 1
            case 0x1F:
                flush(); style.underline.toggle(); index += 1
            case 0x1E:
                flush(); style.strikethrough.toggle(); index += 1
            case 0x11:
                flush(); style.monospace.toggle(); index += 1
            case 0x16:
                flush(); style.reverse.toggle(); index += 1
            case 0x0F:
                flush(); style = IRCTextStyle(); index += 1
            case 0x03:
                flush()
                index += 1
                guard let fg = colorNumber(at: index) else {
                    // Bare \x03 resets both colors; a following comma is text.
                    style.foreground = nil
                    style.background = nil
                    continue
                }
                index += fg.length
                style.foreground = paletteColor(fg.value)
                if index < scalars.count, scalars[index] == ",", let bg = colorNumber(at: index + 1) {
                    index += 1 + bg.length
                    style.background = paletteColor(bg.value)
                }
            case 0x04:
                flush()
                index += 1
                guard let fg = hexColor(at: index) else {
                    style.foreground = nil
                    style.background = nil
                    continue
                }
                index += 6
                style.foreground = .rgb(fg)
                if index < scalars.count, scalars[index] == ",", let bg = hexColor(at: index + 1) {
                    index += 7
                    style.background = .rgb(bg)
                }
            default:
                buffer.append(scalar)
                index += 1
            }
        }
        flush()
    }

    private static func hexDigit(_ scalar: Unicode.Scalar) -> UInt32? {
        switch scalar.value {
        case 0x30...0x39: scalar.value - 0x30
        case 0x41...0x46: scalar.value - 0x41 + 10
        case 0x61...0x66: scalar.value - 0x61 + 10
        default: nil
        }
    }
}

/// Client-To-Client Protocol framing (`\x01COMMAND argument\x01`).
public enum CTCP {
    public static let delimiter: Character = "\u{01}"

    /// Parses a CTCP message body. The closing `\x01` is optional (some
    /// clients omit it). Returns nil when `text` is not CTCP. `argument` is
    /// nil when there is no space after the command, and may be empty.
    public static func parse(_ text: String) -> (command: String, argument: String?)? {
        var body = text.unicodeScalars[...]
        guard body.first == "\u{01}" else { return nil }
        body.removeFirst()
        if body.last == "\u{01}" { body.removeLast() }
        let command: String
        let argument: String?
        if let space = body.firstIndex(of: " ") {
            command = String(body[..<space])
            argument = String(body[body.index(after: space)...])
        } else {
            command = String(body)
            argument = nil
        }
        guard !command.isEmpty else { return nil }
        return (command.uppercased(), argument)
    }

    /// Builds `\x01COMMAND argument\x01`.
    public static func encode(_ command: String, _ argument: String? = nil) -> String {
        if let argument {
            return "\u{01}\(command.uppercased()) \(argument)\u{01}"
        }
        return "\u{01}\(command.uppercased())\u{01}"
    }

    /// The text of a `/me` action, or nil when `text` is not an ACTION.
    public static func actionText(_ text: String) -> String? {
        guard let parsed = parse(text), parsed.command == "ACTION" else { return nil }
        return parsed.argument ?? ""
    }
}
