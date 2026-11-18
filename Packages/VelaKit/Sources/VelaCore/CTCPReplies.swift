// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// The lines Vela shows for CTCP replies to requests you sent (`/ping`,
/// `/version`, the CTCP menu), in the buffer you asked from.
nonisolated public enum CTCPReplyText {
    /// A readable line for `nick`'s reply to `command`. `roundTrip` is how
    /// long a PING took to come back.
    public static func describe(command: String, argument: String?, from nick: String, roundTrip: Duration? = nil) -> String {
        let value = (argument ?? "").trimmingCharacters(in: .whitespaces)
        switch command.uppercased() {
        case "PING":
            guard let roundTrip else { return "Ping reply from \(nick)" }
            return "Ping reply from \(nick): \(format(roundTrip))"
        case "VERSION":
            return value.isEmpty ? "\(nick) didn't say which client they use" : "\(nick) is using \(value)"
        case "TIME":
            return value.isEmpty ? "\(nick) didn't say what time it is" : "\(nick)'s time is \(value)"
        case "CLIENTINFO":
            let commands = value.split(separator: " ").joined(separator: ", ")
            return commands.isEmpty ? "\(nick) didn't list the CTCP requests they answer" : "\(nick) answers CTCP \(commands)"
        default:
            return "CTCP \(command.uppercased()) reply from \(nick)" + (value.isEmpty ? "" : ": \(value)")
        }
    }

    /// The line shown when you send a CTCP request.
    public static func sent(command: String, to target: String) -> String {
        command.uppercased() == "PING" ? "Pinging \(target)…" : "Sent CTCP \(command.uppercased()) to \(target)"
    }

    /// "231 ms", or "1.42 seconds" from a second up.
    public static func format(_ duration: Duration) -> String {
        let (seconds, attoseconds) = duration.components
        let total = Double(seconds) + Double(attoseconds) / 1e18
        if total < 1 { return "\(max(0, Int((total * 1000).rounded()))) ms" }
        return String(format: "%.2f seconds", total)
    }
}
