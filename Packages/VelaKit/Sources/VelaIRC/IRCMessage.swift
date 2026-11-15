// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// The origin of an IRC message: `nick!user@host` or a server name.
public struct IRCSource: Sendable, Hashable, CustomStringConvertible {
    public var raw: String
    public var nick: String
    public var user: String?
    public var host: String?

    public init(raw: String) {
        self.raw = raw
        // Work on scalars so a combining mark after `!`/`@` can't hide the
        // delimiter inside a grapheme cluster.
        var rest = raw.unicodeScalars[...]
        if let at = rest.firstIndex(of: "@") {
            host = String(rest[rest.index(after: at)...])
            rest = rest[..<at]
        }
        if let bang = rest.firstIndex(of: "!") {
            user = String(rest[rest.index(after: bang)...])
            rest = rest[..<bang]
        }
        nick = String(rest)
    }

    public init(nick: String, user: String? = nil, host: String? = nil) {
        var raw = nick
        if let user { raw += "!\(user)" }
        if let host { raw += "@\(host)" }
        self.init(raw: raw)
    }

    /// True for server-originated messages (no user/host and a dotted name).
    public var isServer: Bool { user == nil && host == nil && nick.contains(".") }

    /// `user@host`, when known.
    public var userHost: String? {
        guard let user, let host else { return host }
        return "\(user)@\(host)"
    }

    public var description: String { raw }
}

/// A single IRC protocol line, including IRCv3 message tags.
///
/// Parsing and serialization operate on Unicode scalars rather than
/// `Character`s: Swift treats `"\r\n"` as a single grapheme and glues
/// combining marks onto a preceding space or colon, both of which would
/// otherwise hide protocol delimiters.
public struct IRCMessage: Sendable, Hashable, CustomStringConvertible {
    public var tags: [String: String]
    public var source: IRCSource?
    /// The verb, always uppercased (IRC commands are case-insensitive).
    public var command: String
    public var params: [String]

    public init(tags: [String: String] = [:], source: IRCSource? = nil, command: String, params: [String] = []) {
        self.tags = tags
        self.source = source
        self.command = command.uppercased()
        self.params = params
    }

    public init(_ command: String, _ params: String..., tags: [String: String] = [:]) {
        self.init(tags: tags, command: command, params: params)
    }

    /// Parses a raw line (with or without the trailing CRLF). Returns nil for
    /// empty or malformed lines.
    public init?(line rawLine: String) {
        var line = rawLine.unicodeScalars[...]
        while let last = line.last, last == "\r" || last == "\n" { line.removeLast() }
        line = line.drop(while: { $0 == " " })
        guard !line.isEmpty else { return nil }

        var tags: [String: String] = [:]
        if line.first == "@" {
            guard let space = line.firstIndex(of: " ") else { return nil }
            let tagPart = line[line.index(after: line.startIndex)..<space]
            for item in tagPart.split(separator: ";", omittingEmptySubsequences: true) {
                if let eq = item.firstIndex(of: "=") {
                    let key = String(item[..<eq])
                    guard !key.isEmpty else { continue }
                    tags[key] = Self.unescapeTagValue(item[item.index(after: eq)...])
                } else {
                    tags[String(item)] = ""
                }
            }
            line = line[space...].drop(while: { $0 == " " })
        }

        var source: IRCSource?
        if line.first == ":" {
            guard let space = line.firstIndex(of: " ") else { return nil }
            source = IRCSource(raw: String(line[line.index(after: line.startIndex)..<space]))
            line = line[space...].drop(while: { $0 == " " })
        }

        let commandEnd = line.firstIndex(of: " ") ?? line.endIndex
        let command = String(line[..<commandEnd])
        guard !command.isEmpty else { return nil }
        line = line[commandEnd...]

        var params: [String] = []
        while true {
            line = line.drop(while: { $0 == " " })
            if line.isEmpty { break }
            if line.first == ":" {
                params.append(String(line.dropFirst()))
                break
            }
            let end = line.firstIndex(of: " ") ?? line.endIndex
            params.append(String(line[..<end]))
            line = line[end...]
        }

        self.init(tags: tags, source: source, command: command, params: params)
    }

    /// Wire form without CRLF.
    ///
    /// CR, LF and NUL inside params are replaced with spaces so a message can
    /// never smuggle a second protocol line. Only the last param may contain
    /// spaces, be empty or start with `:`.
    public var serialized: String {
        var out = ""
        if !tags.isEmpty {
            out += "@"
            out += tags.sorted { $0.key < $1.key }.map { key, value in
                value.isEmpty ? key : "\(key)=\(Self.escapeTagValue(value))"
            }.joined(separator: ";")
            out += " "
        }
        if let source { out += ":\(Self.sanitize(source.raw)) " }
        out += command
        for (index, rawParam) in params.enumerated() {
            let param = Self.sanitize(rawParam)
            let isLast = index == params.count - 1
            if isLast && (param.isEmpty || param.utf8.contains(0x20) || param.utf8.first == UInt8(ascii: ":")) {
                out += " :\(param)"
            } else {
                out += " \(param)"
            }
        }
        return out
    }

    public var description: String { serialized }

    public func param(_ index: Int) -> String? {
        params.indices.contains(index) ? params[index] : nil
    }

    /// The last parameter, typically the human-readable text.
    public var trailing: String? { params.last }

    /// True when the command is a three-digit numeric reply.
    public var isNumeric: Bool {
        command.utf8.count == 3 && command.utf8.allSatisfy { $0 >= 0x30 && $0 <= 0x39 }
    }

    // MARK: Common tags

    public var serverTime: Date? { tags["time"].flatMap(IRCTime.parse) }
    public var msgid: String? { tags["msgid"] }
    public var batchID: String? { tags["batch"] }
    public var label: String? { tags["label"] }
    public var account: String? { tags["account"] }
    public var replyTo: String? { tags["+draft/reply"] ?? tags["+reply"] }

    // MARK: Tag escaping (IRCv3 message-tags)

    static func escapeTagValue(_ value: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in value.unicodeScalars {
            switch scalar {
            case ";": out.append(contentsOf: "\\:".unicodeScalars)
            case " ": out.append(contentsOf: "\\s".unicodeScalars)
            case "\\": out.append(contentsOf: "\\\\".unicodeScalars)
            case "\r": out.append(contentsOf: "\\r".unicodeScalars)
            case "\n": out.append(contentsOf: "\\n".unicodeScalars)
            default: out.append(scalar)
            }
        }
        return String(out)
    }

    static func unescapeTagValue(_ value: Substring.UnicodeScalarView) -> String {
        var out = String.UnicodeScalarView()
        var iterator = value.makeIterator()
        while let scalar = iterator.next() {
            guard scalar == "\\" else {
                out.append(scalar)
                continue
            }
            // A trailing lone backslash is dropped, per spec.
            guard let next = iterator.next() else { break }
            switch next {
            case ":": out.append(";")
            case "s": out.append(" ")
            case "\\": out.append("\\")
            case "r": out.append("\r")
            case "n": out.append("\n")
            default: out.append(next)
            }
        }
        return String(out)
    }

    static func unescapeTagValue(_ value: Substring) -> String {
        unescapeTagValue(value.unicodeScalars)
    }

    private static func sanitize(_ value: String) -> String {
        guard value.utf8.contains(where: { $0 == 0x0D || $0 == 0x0A || $0 == 0x00 }) else { return value }
        var scalars = String.UnicodeScalarView()
        for scalar in value.unicodeScalars {
            scalars.append(scalar == "\r" || scalar == "\n" || scalar == "\0" ? " " : scalar)
        }
        return String(scalars)
    }
}

/// IRCv3 `server-time` timestamps (`2019-01-04T14:33:26.123Z`).
public enum IRCTime {
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let whole = Date.ISO8601FormatStyle()

    public static func parse(_ string: String) -> Date? {
        (try? fractional.parse(string)) ?? (try? whole.parse(string))
    }

    public static func format(_ date: Date) -> String {
        fractional.format(date)
    }
}

extension IRCMessage {
    /// Builds PRIVMSG/NOTICE lines for `text`, splitting on newlines and on
    /// the 512-byte line limit. `prefixAllowance` reserves room for the
    /// `:nick!user@host ` prefix the server adds when relaying. `tags` are
    /// attached to the first line only.
    public static func chatLines(
        command: String = "PRIVMSG",
        target: String,
        text: String,
        tags: [String: String] = [:],
        prefixAllowance: Int = 100
    ) -> [IRCMessage] {
        let budget = textBudget(command: command, target: target, prefixAllowance: prefixAllowance)
        var result: [IRCMessage] = []
        for line in splitLines(text) {
            for chunk in splitUTF8(line, maxBytes: budget) {
                result.append(IRCMessage(tags: result.isEmpty ? tags : [:], command: command, params: [target, chunk]))
            }
        }
        return result
    }

    /// Like `chatLines`, but wraps every chunk in a CTCP ACTION (`/me`).
    public static func actionLines(
        target: String,
        text: String,
        tags: [String: String] = [:],
        prefixAllowance: Int = 100
    ) -> [IRCMessage] {
        // "\u{1}ACTION " + "\u{1}" = 9 bytes of framing per line.
        let budget = max(32, textBudget(command: "PRIVMSG", target: target, prefixAllowance: prefixAllowance) - 9)
        var result: [IRCMessage] = []
        for line in splitLines(text) {
            for chunk in splitUTF8(line, maxBytes: budget) {
                result.append(IRCMessage(
                    tags: result.isEmpty ? tags : [:],
                    command: "PRIVMSG",
                    params: [target, CTCP.encode("ACTION", chunk)]
                ))
            }
        }
        return result
    }

    private static func textBudget(command: String, target: String, prefixAllowance: Int) -> Int {
        // ":prefix " (allowance) + "CMD target :" + text <= 510
        let overhead = command.utf8.count + target.utf8.count + 5 + prefixAllowance
        return max(64, 510 - overhead)
    }

    private static func splitLines(_ text: String) -> [String] {
        text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline).map(String.init)
    }

    /// Splits text into chunks of at most `maxBytes` UTF-8 bytes, preferring
    /// to break at spaces (the breaking space is dropped) and never splitting
    /// a grapheme cluster unless that single cluster is itself over budget.
    static func splitUTF8(_ text: String, maxBytes: Int) -> [String] {
        guard maxBytes > 0, text.utf8.count > maxBytes else { return [text] }
        var chunks: [String] = []
        var current = ""
        var currentBytes = 0
        var lastSpace: String.Index?

        for char in text {
            let size = char.utf8.count
            if char == " " && currentBytes > 0 && currentBytes + size > maxBytes {
                // The overflowing character is itself the break: drop it.
                chunks.append(current)
                current = ""
                currentBytes = 0
                lastSpace = nil
                continue
            }
            while currentBytes > 0 && currentBytes + size > maxBytes {
                if let space = lastSpace, space > current.startIndex {
                    chunks.append(String(current[..<space]))
                    current = String(current[current.index(after: space)...])
                    currentBytes = current.utf8.count
                } else {
                    chunks.append(current)
                    current = ""
                    currentBytes = 0
                }
                lastSpace = nil
            }
            if size > maxBytes {
                // A single absurd grapheme (e.g. stacked combining marks):
                // fall back to scalar boundaries.
                var piece = String.UnicodeScalarView()
                var pieceBytes = 0
                for scalar in char.unicodeScalars {
                    let scalarSize = UTF8.width(scalar)
                    if pieceBytes + scalarSize > maxBytes, !piece.isEmpty {
                        chunks.append(String(piece))
                        piece = String.UnicodeScalarView()
                        pieceBytes = 0
                    }
                    piece.append(scalar)
                    pieceBytes += scalarSize
                }
                current = String(piece)
                currentBytes = pieceBytes
                continue
            }
            if char == " " { lastSpace = current.endIndex }
            current.append(char)
            currentBytes += size
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}
