// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Turns the timestamp settings (`chat.clock`, `chat.timestampSeconds`,
/// `chat.timestampFormat`) into the Unicode date pattern chat uses.
public enum TimestampFormat {
    /// The pattern timestamps use: `custom` when it has any non-space
    /// characters, otherwise one for `clock`, with or without seconds.
    ///
    /// `.system` asks `locale` for its hour cycle. Pass
    /// `Locale.autoupdatingCurrent` to follow the Mac's 24-hour time setting,
    /// which shows up as an hour-cycle preference on the current locale.
    public static func pattern(clock: TimestampClock, seconds: Bool, custom: String = "", locale: Locale) -> String {
        if !custom.allSatisfy(\.isWhitespace) { return custom }
        switch clock {
        case .twelveHour:
            return seconds ? "h:mm:ss a" : "h:mm a"
        case .twentyFourHour:
            return seconds ? "HH:mm:ss" : "HH:mm"
        case .system:
            let template = seconds ? "jmmss" : "jmm"
            guard let pattern = DateFormatter.dateFormat(fromTemplate: template, options: 0, locale: locale) else {
                return seconds ? "HH:mm:ss" : "HH:mm"
            }
            // ICU puts a narrow no-break space before AM/PM ("h:mm\u{202F}a").
            // A plain space keeps System and 12-hour identical, and keeps the
            // pattern readable when it seeds a custom format.
            return pattern.replacingOccurrences(of: "\u{202F}", with: " ")
        }
    }

    /// A formatter that writes `pattern` exactly as given, using `locale`'s
    /// language and region (for AM/PM symbols).
    ///
    /// It drops the Mac's 12/24-hour override: `DateFormatter` applies that
    /// override even to fixed patterns, which would turn an explicit 12-hour
    /// choice (or a custom `h:mm a`) into 24-hour times, and vice versa.
    /// ``pattern(clock:seconds:custom:locale:)`` already honors it for the
    /// System clock.
    public static func formatter(pattern: String, locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: locale.identifier)
        formatter.dateFormat = pattern
        return formatter
    }
}
