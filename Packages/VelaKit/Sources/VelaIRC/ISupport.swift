// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Server casemapping rules used to compare nicks and channel names.
public enum CaseMapping: String, Sendable, Hashable {
    case ascii
    case rfc1459
    case strictRFC1459 = "strict-rfc1459"
    case rfc7613

    public func fold(_ string: String) -> String {
        switch self {
        case .rfc7613:
            return string.lowercased()
        case .ascii, .rfc1459, .strictRFC1459:
            var scalars = String.UnicodeScalarView()
            for scalar in string.unicodeScalars {
                switch scalar {
                case "A"..."Z":
                    scalars.append(Unicode.Scalar(scalar.value + 32)!)
                case "[" where self != .ascii: scalars.append("{")
                case "]" where self != .ascii: scalars.append("}")
                case "\\" where self != .ascii: scalars.append("|")
                case "~" where self == .rfc1459: scalars.append("^")
                default: scalars.append(scalar)
                }
            }
            return String(scalars)
        }
    }

    public func equal(_ lhs: String, _ rhs: String) -> Bool {
        fold(lhs) == fold(rhs)
    }
}

/// RPL_ISUPPORT (005) state.
public struct ISupport: Sendable, Hashable {
    public private(set) var tokens: [String: String] = [:]

    public var network: String? { tokens["NETWORK"] }

    public var caseMapping: CaseMapping {
        tokens["CASEMAPPING"].flatMap(CaseMapping.init(rawValue:)) ?? .rfc1459
    }

    /// Membership modes in rank order, e.g. `[("o", "@"), ("v", "+")]`.
    public var prefixes: [(mode: Character, symbol: Character)] {
        guard let value = tokens["PREFIX"] else { return [("o", "@"), ("v", "+")] }
        guard value.hasPrefix("("), let close = value.firstIndex(of: ")") else { return [] }
        let modes = Array(value[value.index(after: value.startIndex)..<close])
        let symbols = Array(value[value.index(after: close)...])
        return Array(zip(modes, symbols))
    }

    public var prefixSymbols: [Character] { prefixes.map(\.symbol) }
    public var prefixModes: [Character] { prefixes.map(\.mode) }

    public var channelTypes: Set<Character> {
        Set(tokens["CHANTYPES"] ?? "#&")
    }

    /// CHANMODES=A,B,C,D: list modes, always-param, param-when-set, no-param.
    public var channelModes: (list: Set<Character>, always: Set<Character>, whenSet: Set<Character>, flag: Set<Character>) {
        let parts = (tokens["CHANMODES"] ?? "beI,k,l,imnpst").split(separator: ",", omittingEmptySubsequences: false)
        func set(_ i: Int) -> Set<Character> { parts.indices.contains(i) ? Set(parts[i]) : [] }
        return (set(0), set(1), set(2), set(3))
    }

    public var chatHistoryLimit: Int? { tokens["CHATHISTORY"].flatMap(Int.init) }
    public var botMode: Character? { tokens["BOT"]?.first }
    public var nickLength: Int? { tokens["NICKLEN"].flatMap(Int.init) }
    public var utf8Only: Bool { tokens["UTF8ONLY"] != nil }
    public var monitorLimit: Int? { tokens["MONITOR"].flatMap(Int.init) }
    /// True when the server supports MONITOR (with or without a limit).
    public var supportsMonitor: Bool { tokens["MONITOR"] != nil }
    /// True when the server supports WHOX (`WHO <mask> %fields`).
    public var supportsWHOX: Bool { tokens["WHOX"] != nil }
    public var channelLength: Int? { tokens["CHANNELLEN"].flatMap(Int.init) }
    public var topicLength: Int? { tokens["TOPICLEN"].flatMap(Int.init) }
    public var awayLength: Int? { tokens["AWAYLEN"].flatMap(Int.init) }
    public var kickLength: Int? { tokens["KICKLEN"].flatMap(Int.init) }
    /// Maximum mode changes with a parameter per MODE line (MODES=).
    public var modesPerLine: Int? { tokens["MODES"].flatMap(Int.init) }
    /// Prefix symbols usable for STATUSMSG (e.g. `@#chan`).
    public var statusMessagePrefixes: Set<Character> { Set(tokens["STATUSMSG"] ?? "") }
    /// The soju bouncer network ID of this connection (BOUNCER_NETID).
    public var bouncerNetworkID: String? { tokens["BOUNCER_NETID"] }

    /// Whether the server allows sending client-only tag `name` (e.g.
    /// `+typing`) per CLIENTTAGDENY. Pass the name with or without `+`.
    public func allowsClientTag(_ name: String) -> Bool {
        guard let value = tokens["CLIENTTAGDENY"], !value.isEmpty else { return true }
        let bare = name.hasPrefix("+") ? String(name.dropFirst()) : name
        var allowedByDefault = true
        var exceptions: Set<String> = []
        for entry in value.split(separator: ",") {
            if entry == "*" {
                allowedByDefault = false
            } else if entry.hasPrefix("-") {
                exceptions.insert(String(entry.dropFirst()))
            } else {
                exceptions.insert(String(entry))
            }
        }
        // With "*", listed "-tag" entries are the allowed exceptions; without
        // it, listed entries are the denied ones.
        return allowedByDefault ? !exceptions.contains(bare) : exceptions.contains(bare)
    }

    public init() {}

    public init(tokens params: some Sequence<String>) {
        apply(params)
    }

    /// Applies the token params of a 005 line (excluding the leading nick and
    /// the trailing human-readable text).
    public mutating func apply(_ params: some Sequence<String>) {
        for token in params {
            if token.hasPrefix("-") {
                tokens.removeValue(forKey: String(token.dropFirst()).uppercased())
            } else if let eq = token.firstIndex(of: "=") {
                let key = String(token[..<eq]).uppercased()
                tokens[key] = Self.unescape(String(token[token.index(after: eq)...]))
            } else {
                tokens[token.uppercased()] = ""
            }
        }
    }

    public func isChannel(_ name: String) -> Bool {
        guard let first = name.first else { return false }
        return channelTypes.contains(first)
    }

    /// Splits a NAMES entry like `@+nick` into prefix symbols and nick.
    public func splitPrefixes(_ entry: String) -> (prefixes: String, nick: String) {
        let symbols = Set(prefixSymbols)
        let prefix = entry.prefix(while: { symbols.contains($0) })
        return (String(prefix), String(entry.dropFirst(prefix.count)))
    }

    /// The symbol for a membership mode letter (e.g. `o` → `@`).
    public func symbol(forMode mode: Character) -> Character? {
        prefixes.first(where: { $0.mode == mode })?.symbol
    }

    /// Lower values mean higher rank; non-members rank last.
    public func rank(ofSymbol symbol: Character?) -> Int {
        guard let symbol, let index = prefixSymbols.firstIndex(of: symbol) else { return prefixSymbols.count }
        return index
    }

    /// ISUPPORT values escape special characters as `\xHH` (one byte each;
    /// multi-byte UTF-8 sequences may be escaped byte by byte).
    static func unescape(_ value: String) -> String {
        guard value.contains("\\x") else { return value }
        let bytes = Array(value.utf8)
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count {
            if bytes[index] == UInt8(ascii: "\\"),
               index + 3 < bytes.count,
               bytes[index + 1] == UInt8(ascii: "x"),
               let high = hexValue(bytes[index + 2]),
               let low = hexValue(bytes[index + 3])
            {
                out.append(high << 4 | low)
                index += 4
                continue
            }
            out.append(bytes[index])
            index += 1
        }
        return String(decoding: out, as: UTF8.self)
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): byte - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): byte - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): byte - UInt8(ascii: "A") + 10
        default: nil
        }
    }
}
