// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreFoundation
import Foundation

/// Turns the (possibly truncated) bytes of an HTML response into a String.
///
/// Encoding is taken from, in order: a byte order mark, the `charset`
/// parameter of the Content-Type header, a `<meta charset>` or
/// `<meta http-equiv="Content-Type">` in the first few KB, and finally UTF-8.
/// Undeclared bytes that are not valid UTF-8 are read as Windows-1252
/// (what browsers do for "ISO-8859-1").
enum HTMLTextDecoder {
    static func decode(_ data: Data, contentType: String?, isTruncated: Bool = false) -> String {
        if let (encoding, bomLength) = byteOrderMark(data) {
            return string(from: data.dropFirst(bomLength), encoding: encoding, isTruncated: isTruncated)
                ?? String(decoding: data.dropFirst(bomLength), as: UTF8.self)
        }

        let declared = contentType.flatMap(charsetParameter) ?? sniffMetaCharset(data)
        let encoding = declared.flatMap(encoding(forLabel:))

        if let encoding, encoding != .utf8 {
            if let text = string(from: data, encoding: encoding, isTruncated: isTruncated) { return text }
        }
        if let text = strictUTF8(data, isTruncated: isTruncated) { return text }
        if encoding == .utf8 {
            // Declared UTF-8 but malformed: keep what we can.
            return String(decoding: data, as: UTF8.self)
        }
        return String(data: data, encoding: .windowsCP1252)
            ?? String(data: data, encoding: .isoLatin1)
            ?? String(decoding: data, as: UTF8.self)
    }

    /// `text/html; charset="Shift_JIS"` → `Shift_JIS`.
    static func charsetParameter(_ contentType: String) -> String? {
        for parameter in contentType.split(separator: ";").dropFirst() {
            let pair = parameter.split(separator: "=", maxSplits: 1)
            guard pair.count == 2,
                  pair[0].trimmingCharacters(in: .whitespaces).lowercased() == "charset"
            else { continue }
            let value = pair[1].trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"'")))
            return value.isEmpty ? nil : value
        }
        return nil
    }

    /// Looks for an encoding declaration in the first 4 KB, as browsers do.
    static func sniffMetaCharset(_ data: Data) -> String? {
        var scanner = HTMLTagScanner(bytes: Array(data.prefix(4096)))
        while let token = scanner.next() {
            switch token {
            case .endTag(let name) where name == "head":
                return nil
            case .startTag(let name, let attributes, _) where name == "meta":
                if let charset = attributes["charset"]?.trimmingCharacters(in: .whitespaces), !charset.isEmpty {
                    return charset
                }
                if attributes["http-equiv"]?.lowercased() == "content-type",
                   let content = attributes["content"], let charset = charsetParameter(content) {
                    return charset
                }
            default:
                continue
            }
        }
        return nil
    }

    static func encoding(forLabel label: String) -> String.Encoding? {
        let normalized = label.trimmingCharacters(in: .whitespaces).lowercased()
        switch normalized {
        case "utf-8", "utf8", "unicode-1-1-utf-8":
            return .utf8
        // WHATWG Encoding: these labels all mean windows-1252.
        case "iso-8859-1", "iso8859-1", "latin1", "l1", "us-ascii", "ascii", "windows-1252", "cp1252", "x-cp1252":
            return .windowsCP1252
        default:
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(normalized as CFString)
            guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
        }
    }

    // MARK: - Helpers

    private static func byteOrderMark(_ data: Data) -> (String.Encoding, Int)? {
        let prefix = Array(data.prefix(3))
        if prefix.starts(with: [0xEF, 0xBB, 0xBF]) { return (.utf8, 3) }
        if prefix.starts(with: [0xFE, 0xFF]) { return (.utf16BigEndian, 2) }
        if prefix.starts(with: [0xFF, 0xFE]) { return (.utf16LittleEndian, 2) }
        return nil
    }

    /// Decodes with `encoding`; when the data was cut off mid-character,
    /// retries without the last few bytes.
    private static func string(from data: Data, encoding: String.Encoding, isTruncated: Bool) -> String? {
        if encoding == .utf8 { return strictUTF8(data, isTruncated: isTruncated) }
        if let text = String(data: data, encoding: encoding) { return text }
        guard isTruncated else { return nil }
        for drop in 1...3 where data.count > drop {
            if let text = String(data: data.dropLast(drop), encoding: encoding) { return text }
        }
        return nil
    }

    private static func strictUTF8(_ data: Data, isTruncated: Bool) -> String? {
        if let text = String(validating: data, as: UTF8.self) { return text }
        guard isTruncated else { return nil }
        // Drop an incomplete multi-byte sequence at the cut.
        for drop in 1...3 where data.count > drop {
            if let text = String(validating: data.dropLast(drop), as: UTF8.self) { return text }
        }
        return nil
    }
}
