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
        var rest = Substring(raw)
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
public struct IRCMessage: Sendable, Hashable, CustomStringConvertible {
    public var tags: [String: String]
    public var source: IRCSource?
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
        var line = Substring(rawLine)
        while let last = line.last, last == "\r" || last == "\n" { line.removeLast() }
        guard !line.isEmpty else { return nil }

        var tags: [String: String] = [:]
        if line.first == "@" {
            guard let space = line.firstIndex(of: " ") else { return nil }
            let tagPart = line[line.index(after: line.startIndex)..<space]
            for item in tagPart.split(separator: ";", omittingEmptySubsequences: true) {
                if let eq = item.firstIndex(of: "=") {
                    let key = String(item[..<eq])
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
    public var serialized: String {
        var out = ""
        if !tags.isEmpty {
            out += "@"
            out += tags.sorted { $0.key < $1.key }.map { key, value in
                value.isEmpty ? key : "\(key)=\(Self.escapeTagValue(value))"
            }.joined(separator: ";")
            out += " "
        }
        if let source { out += ":\(source.raw) " }
        out += command
        for (index, param) in params.enumerated() {
            let isLast = index == params.count - 1
            if isLast && (param.isEmpty || param.contains(" ") || param.hasPrefix(":")) {
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

    // MARK: Common tags

    public var serverTime: Date? { tags["time"].flatMap(IRCTime.parse) }
    public var msgid: String? { tags["msgid"] }
    public var batchID: String? { tags["batch"] }
    public var label: String? { tags["label"] }
    public var account: String? { tags["account"] }
    public var replyTo: String? { tags["+draft/reply"] ?? tags["+reply"] }

    // MARK: Tag escaping (IRCv3 message-tags)

    static func escapeTagValue(_ value: String) -> String {
        var out = ""
        out.reserveCapacity(value.count)
        for char in value {
            switch char {
            case ";": out += "\\:"
            case " ": out += "\\s"
            case "\\": out += "\\\\"
            case "\r": out += "\\r"
            case "\n": out += "\\n"
            default: out.append(char)
            }
        }
        return out
    }

    static func unescapeTagValue(_ value: Substring) -> String {
        var out = ""
        out.reserveCapacity(value.count)
        var iterator = value.makeIterator()
        while let char = iterator.next() {
            guard char == "\\" else {
                out.append(char)
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
        return out
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
    /// `:nick!user@host ` prefix the server adds when relaying.
    public static func chatLines(
        command: String = "PRIVMSG",
        target: String,
        text: String,
        tags: [String: String] = [:],
        prefixAllowance: Int = 100
    ) -> [IRCMessage] {
        let overhead = command.utf8.count + target.utf8.count + 5 + prefixAllowance
        let budget = max(64, 510 - overhead)
        var result: [IRCMessage] = []
        for rawLine in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = String(rawLine)
            if line.isEmpty { continue }
            for chunk in splitUTF8(line, maxBytes: budget) {
                result.append(IRCMessage(tags: result.isEmpty ? tags : [:], command: command, params: [target, chunk]))
            }
        }
        return result
    }

    /// Splits text into chunks of at most `maxBytes` UTF-8 bytes, preferring
    /// to break at spaces and never splitting a grapheme cluster.
    static func splitUTF8(_ text: String, maxBytes: Int) -> [String] {
        guard text.utf8.count > maxBytes else { return [text] }
        var chunks: [String] = []
        var current = ""
        var currentBytes = 0
        var lastSpace: String.Index?

        for char in text {
            let size = String(char).utf8.count
            if currentBytes + size > maxBytes {
                if let space = lastSpace {
                    let head = String(current[..<space])
                    let tail = String(current[current.index(after: space)...])
                    chunks.append(head)
                    current = tail
                    currentBytes = current.utf8.count
                } else {
                    chunks.append(current)
                    current = ""
                    currentBytes = 0
                }
                lastSpace = nil
            }
            if char == " " { lastSpace = current.endIndex }
            current.append(char)
            currentBytes += size
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}
