// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Decodes HTML character references: numeric (`&#39;`, `&#x27;`) and the
/// named entities that show up in real-world titles and descriptions.
enum HTMLEntities {
    static func decode(_ text: String) -> String {
        guard text.contains("&") else { return text }

        let scalars = Array(text.unicodeScalars)
        var output = String.UnicodeScalarView()
        output.reserveCapacity(scalars.count)
        var i = 0

        while i < scalars.count {
            let scalar = scalars[i]
            guard scalar == "&", let (decoded, length) = reference(in: scalars, at: i) else {
                output.append(scalar)
                i += 1
                continue
            }
            output.append(contentsOf: decoded.unicodeScalars)
            i += length
        }
        return String(output)
    }

    /// Parses a reference starting at `scalars[start] == "&"`.
    /// Returns the replacement and how many scalars it consumed.
    private static func reference(in scalars: [Unicode.Scalar], at start: Int) -> (String, Int)? {
        var i = start + 1
        guard i < scalars.count else { return nil }

        if scalars[i] == "#" {
            i += 1
            var radix = 10
            if i < scalars.count, scalars[i] == "x" || scalars[i] == "X" {
                radix = 16
                i += 1
            }
            let digitsStart = i
            var value: UInt32 = 0
            while i < scalars.count, let digit = Int(String(scalars[i]), radix: radix), i - digitsStart < 8 {
                value = value &* UInt32(radix) &+ UInt32(digit)
                i += 1
            }
            guard i > digitsStart else { return nil }
            if i < scalars.count, scalars[i] == ";" { i += 1 }
            return (String(numericScalar(value)), i - start)
        }

        // Named reference: letters and digits, then ';'.
        var name = ""
        while i < scalars.count, name.unicodeScalars.count < 32,
              scalars[i].isASCII, scalars[i].properties.isAlphabetic || ("0"..."9").contains(scalars[i]) {
            name.unicodeScalars.append(scalars[i])
            i += 1
        }
        guard !name.isEmpty else { return nil }
        if i < scalars.count, scalars[i] == ";" {
            guard let value = named[name] else { return nil }
            return (value, i + 1 - start)
        }
        // Browsers accept a handful of legacy entities without the semicolon.
        if let value = legacyWithoutSemicolon[name] {
            return (value, i - start)
        }
        return nil
    }

    private static func numericScalar(_ value: UInt32) -> Character {
        if (0x80...0x9F).contains(value), let mapped = windows1252[value] {
            return Character(Unicode.Scalar(mapped)!)
        }
        guard value != 0, let scalar = Unicode.Scalar(value) else { return "\u{FFFD}" }
        return Character(scalar)
    }

    private static let legacyWithoutSemicolon: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "nbsp": "\u{A0}", "copy": "©", "reg": "®",
    ]

    /// HTML5 maps C1 control references to their Windows-1252 characters.
    private static let windows1252: [UInt32: UInt32] = [
        0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E, 0x85: 0x2026, 0x86: 0x2020,
        0x87: 0x2021, 0x88: 0x02C6, 0x89: 0x2030, 0x8A: 0x0160, 0x8B: 0x2039, 0x8C: 0x0152,
        0x8E: 0x017D, 0x91: 0x2018, 0x92: 0x2019, 0x93: 0x201C, 0x94: 0x201D, 0x95: 0x2022,
        0x96: 0x2013, 0x97: 0x2014, 0x98: 0x02DC, 0x99: 0x2122, 0x9A: 0x0161, 0x9B: 0x203A,
        0x9C: 0x0153, 0x9E: 0x017E, 0x9F: 0x0178,
    ]

    /// The Latin-1 entities, in code point order from U+00A0 to U+00FF.
    private static let latin1Names = [
        "nbsp", "iexcl", "cent", "pound", "curren", "yen", "brvbar", "sect", "uml", "copy", "ordf",
        "laquo", "not", "shy", "reg", "macr", "deg", "plusmn", "sup2", "sup3", "acute", "micro", "para",
        "middot", "cedil", "sup1", "ordm", "raquo", "frac14", "frac12", "frac34", "iquest", "Agrave",
        "Aacute", "Acirc", "Atilde", "Auml", "Aring", "AElig", "Ccedil", "Egrave", "Eacute", "Ecirc",
        "Euml", "Igrave", "Iacute", "Icirc", "Iuml", "ETH", "Ntilde", "Ograve", "Oacute", "Ocirc",
        "Otilde", "Ouml", "times", "Oslash", "Ugrave", "Uacute", "Ucirc", "Uuml", "Yacute", "THORN",
        "szlig", "agrave", "aacute", "acirc", "atilde", "auml", "aring", "aelig", "ccedil", "egrave",
        "eacute", "ecirc", "euml", "igrave", "iacute", "icirc", "iuml", "eth", "ntilde", "ograve",
        "oacute", "ocirc", "otilde", "ouml", "divide", "oslash", "ugrave", "uacute", "ucirc", "uuml",
        "yacute", "thorn", "yuml",
    ]

    private static let named: [String: String] = {
        var table: [String: String] = [
            "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
            "OElig": "Œ", "oelig": "œ", "Scaron": "Š", "scaron": "š", "Yuml": "Ÿ", "fnof": "ƒ",
            "circ": "ˆ", "tilde": "˜", "ensp": "\u{2002}", "emsp": "\u{2003}", "thinsp": "\u{2009}",
            "zwnj": "\u{200C}", "zwj": "\u{200D}", "lrm": "\u{200E}", "rlm": "\u{200F}",
            "ndash": "–", "mdash": "—", "horbar": "―", "lsquo": "‘", "rsquo": "’", "sbquo": "‚",
            "ldquo": "“", "rdquo": "”", "bdquo": "„", "dagger": "†", "Dagger": "‡", "bull": "•",
            "hellip": "…", "mldr": "…", "permil": "‰", "prime": "′", "Prime": "″", "lsaquo": "‹",
            "rsaquo": "›", "oline": "‾", "frasl": "⁄", "euro": "€", "trade": "™", "TRADE": "™",
            "larr": "←", "uarr": "↑", "rarr": "→", "darr": "↓", "harr": "↔", "rArr": "⇒", "lArr": "⇐",
            "minus": "−", "lowast": "∗", "infin": "∞", "ne": "≠", "le": "≤", "ge": "≥", "asymp": "≈",
            "hearts": "♥", "spades": "♠", "clubs": "♣", "diams": "♦", "loz": "◊", "check": "✓",
            "star": "☆", "starf": "★", "deg": "°", "half": "½", "nbsp": "\u{A0}", "NewLine": "\n",
            "Tab": "\t", "colon": ":", "comma": ",", "period": ".", "excl": "!", "quest": "?",
            "num": "#", "dollar": "$", "percnt": "%", "lpar": "(", "rpar": ")", "ast": "*",
            "plus": "+", "sol": "/", "bsol": "\\", "semi": ";", "equals": "=", "lsqb": "[",
            "rsqb": "]", "lbrack": "[", "rbrack": "]", "lcub": "{", "rcub": "}", "lbrace": "{",
            "rbrace": "}", "verbar": "|", "vert": "|", "grave": "`", "Hat": "^", "lowbar": "_",
            "commat": "@", "hyphen": "‐", "dash": "‐",
            "Alpha": "Α", "Beta": "Β", "Gamma": "Γ", "Delta": "Δ", "Omega": "Ω", "Pi": "Π",
            "Sigma": "Σ", "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε",
            "lambda": "λ", "mu": "μ", "pi": "π", "sigma": "σ", "tau": "τ", "phi": "φ", "omega": "ω",
        ]
        for (offset, name) in latin1Names.enumerated() {
            table[name] = String(Character(Unicode.Scalar(UInt32(0xA0 + offset))!))
        }
        return table
    }()
}
