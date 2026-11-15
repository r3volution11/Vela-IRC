// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Foundation
import SwiftUI

/// An sRGB color with straight (non-premultiplied) alpha. Components are 0…1.
///
/// Theme files store colors as hex strings (`#RGB`, `#RGBA`, `#RRGGBB` or
/// `#RRGGBBAA`, the same forms VS Code accepts); `ThemeColor` encodes and
/// decodes as that string.
public struct ThemeColor: Sendable, Hashable, Codable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
        self.alpha = Self.clamp(alpha)
    }

    /// Parses `#RGB`, `#RGBA`, `#RRGGBB` or `#RRGGBBAA` (the `#` is optional,
    /// surrounding whitespace is ignored). Returns `nil` for anything else.
    public init?(hex: String) {
        var text = Substring(hex.trimmingCharacters(in: .whitespacesAndNewlines))
        if text.hasPrefix("#") { text = text.dropFirst() }
        guard [3, 4, 6, 8].contains(text.count), text.allSatisfy(\.isHexDigit) else { return nil }

        var digits = Array(text)
        if digits.count <= 4 {
            digits = digits.flatMap { [$0, $0] }
        }
        func byte(_ index: Int) -> Double {
            Double(Int(String(digits[index * 2...index * 2 + 1]), radix: 16) ?? 0) / 255
        }
        self.init(
            red: byte(0),
            green: byte(1),
            blue: byte(2),
            alpha: digits.count == 8 ? byte(3) : 1
        )
    }

    /// `#RRGGBB`, or `#RRGGBBAA` when the color is not fully opaque. Uppercase.
    public var hex: String {
        let r = Self.byte(red), g = Self.byte(green), b = Self.byte(blue), a = Self.byte(alpha)
        if a == 255 {
            return String(format: "#%02X%02X%02X", r, g, b)
        }
        return String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }

    /// WCAG 2 relative luminance (0 = black, 1 = white). Alpha is ignored.
    public var luminance: Double {
        func linear(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// The same color with its alpha replaced by `a`.
    public func withAlpha(_ a: Double) -> ThemeColor {
        ThemeColor(red: red, green: green, blue: blue, alpha: a)
    }

    /// Linear interpolation in sRGB: `amount` 0 returns `self`, 1 returns `other`.
    public func mixed(with other: ThemeColor, amount: Double) -> ThemeColor {
        let t = Self.clamp(amount)
        return ThemeColor(
            red: red + (other.red - red) * t,
            green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t,
            alpha: alpha + (other.alpha - alpha) * t
        )
    }

    /// The opaque color seen when this color is drawn over `background`.
    public func composited(over background: ThemeColor) -> ThemeColor {
        let base = background.alpha < 1 ? background.composited(over: .black) : background
        guard alpha < 1 else { return self }
        return ThemeColor(
            red: red * alpha + base.red * (1 - alpha),
            green: green * alpha + base.green * (1 - alpha),
            blue: blue * alpha + base.blue * (1 - alpha),
            alpha: 1
        )
    }

    /// WCAG 2 contrast ratio (1…21) of this color drawn over `background`.
    /// Translucent colors are composited first.
    public func contrastRatio(against background: ThemeColor) -> Double {
        let back = background.alpha < 1 ? background.composited(over: .black) : background
        let front = composited(over: back)
        let l1 = front.luminance, l2 = back.luminance
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    /// Whether this color reads as dark (luminance below the midpoint between
    /// black and white in contrast terms).
    public var isDark: Bool { luminance < 0.179 }

    public var color: SwiftUI.Color {
        SwiftUI.Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    public var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    public static let black = ThemeColor(red: 0, green: 0, blue: 0)
    public static let white = ThemeColor(red: 1, green: 1, blue: 1)
    public static let clear = ThemeColor(red: 0, green: 0, blue: 0, alpha: 0)

    // MARK: Codable (as a hex string)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let color = ThemeColor(hex: text) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "“\(text)” is not a hex color (#RGB, #RGBA, #RRGGBB or #RRGGBBAA)."
            )
        }
        self = color
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }

    // MARK: Helpers

    private static func clamp(_ value: Double) -> Double {
        value.isNaN ? 0 : min(max(value, 0), 1)
    }

    private static func byte(_ value: Double) -> Int {
        Int((clamp(value) * 255).rounded())
    }
}

extension ThemeColor: CustomStringConvertible {
    public var description: String { hex }
}

// MARK: - Perceptual helpers (OKLab), used by the importer and palette tools

extension ThemeColor {
    /// OKLab coordinates (L 0…1, a/b roughly −0.4…0.4).
    var oklab: (l: Double, a: Double, b: Double) {
        func linear(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let r = linear(red), g = linear(green), b = linear(blue)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return (
            0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        )
    }

    /// OKLCh chroma: ~0 for greys, ~0.1+ for clearly colored values.
    var chroma: Double {
        let lab = oklab
        return (lab.a * lab.a + lab.b * lab.b).squareRoot()
    }

    /// OKLCh hue in degrees (0…360).
    var hue: Double {
        let lab = oklab
        let degrees = atan2(lab.b, lab.a) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// Perceptual distance between two colors (OKLab ΔE).
    func distance(to other: ThemeColor) -> Double {
        let p = oklab, q = other.oklab
        let dl = p.l - q.l, da = p.a - q.a, db = p.b - q.b
        return (dl * dl + da * da + db * db).squareRoot()
    }

    /// Moves this color toward black or white (whichever increases contrast)
    /// until it reaches `minimum` contrast against `background`, keeping as
    /// much of its hue as possible. Returns `self` when it already passes.
    func ensuringContrast(_ minimum: Double, against background: ThemeColor) -> ThemeColor {
        let opaque = composited(over: background)
        if opaque.contrastRatio(against: background) >= minimum { return self }
        let target: ThemeColor = background.isDark ? .white : .black
        var step = 0.05
        while step <= 1 {
            let candidate = opaque.mixed(with: target, amount: step)
            if candidate.contrastRatio(against: background) >= minimum { return candidate }
            step += 0.05
        }
        return target
    }
}
