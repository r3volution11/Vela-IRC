// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Lenient JSON reading in the style of VS Code's `jsonc` files:
/// line comments, block comments and trailing commas are accepted.
public enum JSONC {
    /// Returns strict JSON bytes with comments and trailing commas removed.
    /// String contents (including escaped quotes) are preserved untouched.
    public static func normalize(_ data: Data) -> Data {
        let bytes = [UInt8](data)
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count)

        let slash = UInt8(ascii: "/"), star = UInt8(ascii: "*"), quote = UInt8(ascii: "\"")
        let backslash = UInt8(ascii: "\\"), newline = UInt8(ascii: "\n"), comma = UInt8(ascii: ",")
        let closeBrace = UInt8(ascii: "}"), closeBracket = UInt8(ascii: "]")

        var i = 0
        var inString = false
        // Index in `out` of a comma that may turn out to be trailing.
        var pendingComma: Int?

        // Skip a UTF-8 BOM.
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { i = 3 }

        while i < bytes.count {
            let c = bytes[i]
            if inString {
                out.append(c)
                if c == backslash, i + 1 < bytes.count {
                    out.append(bytes[i + 1])
                    i += 2
                    continue
                }
                if c == quote { inString = false }
                i += 1
                continue
            }

            if c == slash, i + 1 < bytes.count, bytes[i + 1] == slash {
                i += 2
                while i < bytes.count, bytes[i] != newline { i += 1 }
                continue
            }
            if c == slash, i + 1 < bytes.count, bytes[i + 1] == star {
                i += 2
                while i + 1 < bytes.count, !(bytes[i] == star && bytes[i + 1] == slash) { i += 1 }
                i += 2
                continue
            }

            let isWhitespace = c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D
            if c == closeBrace || c == closeBracket, let comma = pendingComma {
                out.remove(at: comma)
                pendingComma = nil
            } else if !isWhitespace {
                pendingComma = nil
            }

            if c == quote { inString = true }
            if c == comma { pendingComma = out.count }
            out.append(c)
            i += 1
        }
        return Data(out)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: normalize(data))
    }

    public static func value(from data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: normalize(data))
    }
}
