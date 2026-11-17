// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaFoundation
import VelaTheme

/// What a run of settings.json text is, for its color.
nonisolated enum JSONSyntaxRole: Hashable, Sendable, CaseIterable {
    /// A string followed by a colon.
    case propertyKey
    case string
    case number
    /// `true`, `false` and `null`.
    case literal
    /// `{ } [ ] : ,`
    case punctuation
    case comment
    /// Bare words, malformed numbers and stray characters.
    case invalid
}

/// A colored run of text (UTF-16 range).
nonisolated struct JSONSyntaxRun: Hashable, Sendable {
    var range: NSRange
    var role: JSONSyntaxRole
}

/// Syntax highlighting for the JSON view, from ``JSONCScanner``'s tokens.
///
/// Runs are recomputed for the whole text on every edit (the scanner is
/// fast), but only the part that changed is restyled: see
/// ``changedRange(old:new:editedRange:delta:)``.
nonisolated enum JSONSyntax {
    /// Runs for every token except whitespace and line breaks.
    static func runs(in text: String) -> [JSONSyntaxRun] {
        runs(for: JSONCScanner.tokens(in: text))
    }

    /// Runs for `tokens`. A string is a property key when the next token
    /// that isn't whitespace or a comment is a colon, so keys are told
    /// apart without parsing (and while the text is half-typed).
    static func runs(for tokens: [JSONCToken]) -> [JSONSyntaxRun] {
        var runs: [JSONSyntaxRun] = []
        runs.reserveCapacity(tokens.count / 2 + 1)
        for (index, token) in tokens.enumerated() {
            let role: JSONSyntaxRole
            switch token.kind {
            case .whitespace, .lineBreak:
                continue
            case .string:
                role = isFollowedByColon(tokens, index) ? .propertyKey : .string
            case .number:
                role = token.problem == nil ? .number : .invalid
            case .true, .false, .null:
                role = .literal
            case .lineComment, .blockComment:
                role = .comment
            case .openBrace, .closeBrace, .openBracket, .closeBracket, .colon, .comma:
                role = .punctuation
            case .invalid:
                role = .invalid
            }
            runs.append(JSONSyntaxRun(range: token.range, role: role))
        }
        return runs
    }

    private static func isFollowedByColon(_ tokens: [JSONCToken], _ index: Int) -> Bool {
        var next = index + 1
        while next < tokens.count {
            let token = tokens[next]
            if token.kind == .colon { return true }
            // Keys and colons sit on one line in practice; stop at a break.
            if token.kind == .lineBreak || !token.isTrivia { return false }
            next += 1
        }
        return false
    }

    /// The theme token each role is drawn in. Vela's themes have no
    /// syntax colors, so these borrow tokens whose colors are distinct in
    /// every built-in theme and readable as text:
    ///
    /// - keys: `accentText`
    /// - strings: `status.success` (green in every built-in theme)
    /// - numbers: `chat.notice` (orange in most)
    /// - `true`, `false`, `null`: `chat.action`
    /// - punctuation: `settings.foreground`
    /// - comments: `settings.secondaryForeground`
    /// - invalid text: `status.error`
    static func colorKey(for role: JSONSyntaxRole) -> String {
        switch role {
        case .propertyKey: ThemeKey.accentText
        case .string: ThemeKey.statusSuccess
        case .number: ThemeKey.chatNotice
        case .literal: ThemeKey.chatAction
        case .punctuation: ThemeKey.settingsForeground
        case .comment: ThemeKey.settingsSecondaryForeground
        case .invalid: ThemeKey.statusError
        }
    }

    /// The part of the new text whose colors may differ from what's shown
    /// after an edit, or nil when nothing needs restyling.
    ///
    /// - Parameters:
    ///   - old: The runs before the edit.
    ///   - new: The runs after it.
    ///   - editedRange: The changed characters, in the new text.
    ///   - delta: The change in length.
    ///
    /// Runs that end before the edit and are unchanged keep their colors;
    /// so do runs after it that only moved by `delta` (the layout manager
    /// moves their colors with the text). Every run in between is
    /// restyled, e.g. the rest of the file after typing `/*`, while a
    /// character typed inside a string touches only that string. Stale
    /// colors can only be left on whitespace, where they don't show (and
    /// text typed there later is part of that edit's range).
    static func changedRange(old: [JSONSyntaxRun], new: [JSONSyntaxRun], editedRange: NSRange, delta: Int) -> NSRange? {
        let editEnd = editedRange.location + editedRange.length
        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix],
              old[prefix].range.location + old[prefix].range.length <= editedRange.location
        {
            prefix += 1
        }
        // In old-text coordinates, where the edit ended.
        let oldEditEnd = editEnd - delta
        var suffix = 0
        while suffix < old.count - prefix, suffix < new.count - prefix {
            let oldRun = old[old.count - 1 - suffix]
            let newRun = new[new.count - 1 - suffix]
            guard oldRun.range.location >= oldEditEnd,
                  oldRun.role == newRun.role,
                  oldRun.range.length == newRun.range.length,
                  oldRun.range.location + delta == newRun.range.location
            else { break }
            suffix += 1
        }

        var start = editedRange.location
        var end = editEnd
        if prefix < new.count - suffix {
            let last = new[new.count - 1 - suffix].range
            start = min(start, new[prefix].range.location)
            end = max(end, last.location + last.length)
        }
        guard end > start else { return nil }
        return NSRange(location: start, length: end - start)
    }

    /// The index of the first run that ends after `offset` (binary search).
    static func firstRun(endingAfter offset: Int, in runs: [JSONSyntaxRun]) -> Int {
        var low = 0, high = runs.count
        while low < high {
            let mid = (low + high) / 2
            if runs[mid].range.location + runs[mid].range.length <= offset {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }
}
