// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaIRC

// Chat logs (`logging.*` settings) are plain UTF-8 text with LF line
// endings, one line per message or event:
//
//     --- Log opened 2026-11-17 21:04:01 ---
//     [2026-11-17 21:04:01] -!- doug (doug@example.org) joined #vela
//     [2026-11-17 21:04:01] -!- Topic: Vela, a native IRC client
//     [2026-11-17 21:04:05] <alice> hi doug, see https://velairc.app
//     [2026-11-17 21:04:09] * doug waves
//     [2026-11-17 21:04:12] -ChanServ- Welcome to #vela
//     [2026-11-17 21:05:30] -!- bob deleted a message from alice sent at 2026-11-17 21:04:05 (oops)
//     [2026-11-17 21:06:00] -!- alice quit (Ping timeout)
//     --- Log closed 2026-11-17 23:10:00 ---
//
// Times are local to the Mac. Only what was written is kept: mIRC
// formatting codes are removed, links stay as they were typed, and link
// previews, images, videos, translations and Catch me up summaries are
// never logged.

/// What one log line says, in a form that can leave the main actor.
nonisolated public enum ChatLogContent: Sendable, Hashable {
    /// A chat line: a message, action, notice or event.
    case line(kind: ChatLineKind, nick: String?, text: String, isSelf: Bool)
    /// An IRCv3 message deletion (`REDACT`). The deleted line stays in the
    /// log as it was written; this notes that it was deleted.
    case redaction(by: String?, originalNick: String?, originalTime: Date, reason: String?)
}

/// Formats chat log lines and reads timestamps back out of logs.
nonisolated public enum ChatLogFormat {
    /// The marker written before the first line Vela writes to a file since
    /// it started logging (launch, turning logging on, a new file).
    public static func openedMarker(at date: Date, clock: ChatLogClock) -> String {
        "--- Log opened \(clock.string(from: date)) ---"
    }

    /// The marker written when Vela stops writing to a file: it quits,
    /// logging is turned off, the folder changes or the file is full.
    public static func closedMarker(at date: Date, clock: ChatLogClock) -> String {
        "--- Log closed \(clock.string(from: date)) ---"
    }

    /// The log line for `content` at `time`, without a line ending.
    public static func line(_ content: ChatLogContent, at time: Date, clock: ChatLogClock) -> String {
        "[\(clock.string(from: time))] \(body(content, clock: clock))"
    }

    /// The part after the timestamp.
    static func body(_ content: ChatLogContent, clock: ChatLogClock) -> String {
        switch content {
        case .line(let kind, let nick, let rawText, let isSelf):
            let text = plainText(rawText)
            switch kind {
            case .message:
                return "<\(nick ?? "?")> \(text)"
            case .action:
                return "* \(nick ?? "?") \(text)"
            case .notice:
                guard let nick else { return "-!- \(text)" }
                return "-\(nick)- \(text)"
            case .nick:
                // "You are now known as x" reads oddly in a log.
                if isSelf, let nick, text.hasPrefix(selfNickPrefix) {
                    return "-!- \(nick) is now known as \(text.dropFirst(selfNickPrefix.count))"
                }
                return "-!- \(text)"
            case .error:
                return "-!- Error: \(text)"
            case .join, .part, .quit, .kick, .topic, .mode, .invite, .info, .motd, .ctcp, .dayChange:
                return "-!- \(text)"
            }
        case .redaction(let by, let originalNick, let originalTime, let reason):
            let sent = clock.string(from: originalTime)
            let who = by ?? "Someone"
            let whose: String = if let originalNick, let by, originalNick == by {
                "their message"
            } else {
                "a message from \(originalNick ?? "someone")"
            }
            let why = reason.map { plainText($0) }.flatMap { $0.isEmpty ? nil : " (\($0))" } ?? ""
            return "-!- \(who) deleted \(whose) sent at \(sent)\(why)"
        }
    }

    private static let selfNickPrefix = "You are now known as "

    /// `text` as one plain line: formatting codes removed, line breaks
    /// turned into spaces, other control characters dropped. Everything
    /// else, links and emoji included, stays as written.
    public static func plainText(_ text: String) -> String {
        let stripped = IRCFormatting.strip(text)
        guard stripped.unicodeScalars.contains(where: isControl) else { return stripped }
        var scalars = String.UnicodeScalarView()
        var previousWasBreak = false
        for scalar in stripped.unicodeScalars {
            if scalar == "\n" || scalar == "\r" {
                // "\r\n" becomes one space.
                if !previousWasBreak { scalars.append(" ") }
                previousWasBreak = true
                continue
            }
            previousWasBreak = false
            if isControl(scalar) { continue }
            scalars.append(scalar)
        }
        return String(scalars)
    }

    private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        (scalar.value < 0x20 && scalar != "\t") || scalar.value == 0x7F
    }

    // MARK: Reading logs back

    /// The time of the last message or event line in `text` (the end of a
    /// log), ignoring the open and close markers. Nil when there's none.
    public static func lastLineTime(in text: Substring, clock: ChatLogClock) -> Date? {
        for line in text.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            if let time = lineTime(line, clock: clock) { return time }
        }
        return nil
    }

    /// The time of the first message or event line in `text` (the start of
    /// a log), or of the first "Log opened" marker when there's none.
    public static func firstTime(in text: Substring, clock: ChatLogClock) -> Date? {
        var opened: Date?
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if let time = lineTime(line, clock: clock) { return time }
            if opened == nil, line.hasPrefix("--- Log opened ") {
                opened = clock.date(from: line.dropFirst(15).prefix(ChatLogClock.length))
            }
        }
        return opened
    }

    /// `[2026-11-17 21:04:05] …` → its time.
    static func lineTime(_ line: Substring, clock: ChatLogClock) -> Date? {
        guard line.first == "[" else { return nil }
        let stamp = line.dropFirst().prefix(ChatLogClock.length)
        guard stamp.count == ChatLogClock.length, line.dropFirst(1 + ChatLogClock.length).first == "]" else { return nil }
        return clock.date(from: stamp)
    }
}

/// Which lines go in a log: what was said, plus events if wanted. The
/// server buffer (when it's logged at all) keeps everything it shows.
nonisolated public enum ChatLogPolicy {
    public static func includes(_ kind: ChatLineKind, in bufferKind: BufferKind, events: Bool) -> Bool {
        switch bufferKind {
        case .server:
            return kind != .dayChange
        case .channel, .query:
            if kind.isConversation { return true }
            switch kind {
            case .join, .part, .quit, .nick, .kick, .topic, .mode: return events
            default: return false
            }
        }
    }
}

/// Local-time timestamps as logs write them: `2026-11-17 21:04:05`.
nonisolated public struct ChatLogClock: Sendable {
    public let calendar: Calendar

    /// Characters in a timestamp.
    static let length = 19

    public init(timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    /// `2026-11-17 21:04:05`.
    public func string(from date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return "\(pad(c.year ?? 0, 4))-\(pad(c.month ?? 0))-\(pad(c.day ?? 0)) \(pad(c.hour ?? 0)):\(pad(c.minute ?? 0)):\(pad(c.second ?? 0))"
    }

    /// `2026-11-17`, for rotated file names.
    public func day(from date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(pad(c.year ?? 0, 4))-\(pad(c.month ?? 0))-\(pad(c.day ?? 0))"
    }

    /// Parses ``string(from:)``.
    public func date<S: StringProtocol>(from text: S) -> Date? {
        let parts = text.split(whereSeparator: { $0 == "-" || $0 == " " || $0 == ":" })
        guard text.count == Self.length, parts.count == 6 else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == 6 else { return nil }
        let components = DateComponents(
            year: numbers[0], month: numbers[1], day: numbers[2],
            hour: numbers[3], minute: numbers[4], second: numbers[5]
        )
        return calendar.date(from: components)
    }

    private func pad(_ value: Int, _ width: Int = 2) -> String {
        let digits = String(value)
        return digits.count >= width ? digits : String(repeating: "0", count: width - digits.count) + digits
    }
}
