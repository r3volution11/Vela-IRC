// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// A link found in message text.
public struct DetectedLink: Sendable, Hashable {
    /// The link, always with an `http` or `https` scheme.
    public let url: URL
    /// Where the link's text sits in the string that was scanned.
    public let range: Range<String.Index>

    public init(url: URL, range: Range<String.Index>) {
        self.url = url
        self.range = range
    }
}

/// Finds web links in chat text.
///
/// Matching is done by `NSDataDetector`, then cleaned up the way people
/// expect in chat:
/// - only `http`/`https` links, written with a scheme or starting with `www.`
///   (bare domains such as `readme.md` are ignored to avoid false positives);
/// - trailing sentence punctuation (`. , ; : ! ?`) and stray quotes are dropped;
/// - closing brackets are kept only when balanced inside the URL, so
///   `(see https://en.wikipedia.org/wiki/Swift_(programming_language))`
///   yields the Wikipedia URL with exactly one closing parenthesis;
/// - wrappers such as `<https://…>`, `"https://…"` or `*https://…*` are excluded.
public enum LinkDetector {
    public static func links(in text: String) -> [DetectedLink] {
        // Cheap pre-check: most chat lines contain no links at all.
        guard text.contains("://") || text.range(of: "www.", options: .caseInsensitive) != nil else {
            return []
        }
        let detector = Self.detector
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var results: [DetectedLink] = []

        for match in detector.matches(in: text, options: [], range: fullRange) {
            guard let matchRange = Range(match.range, in: text) else { continue }
            let matchedText = text[matchRange]
            guard hasAcceptablePrefix(matchedText) else { continue }

            let opener = matchRange.lowerBound > text.startIndex
                ? text[text.index(before: matchRange.lowerBound)]
                : nil
            let trimmedEnd = trimmedEndIndex(of: matchedText, openedBy: opener)
            guard trimmedEnd > matchRange.lowerBound else { continue }
            let range = matchRange.lowerBound..<trimmedEnd

            let url: URL?
            if trimmedEnd == matchRange.upperBound {
                url = match.url
            } else {
                url = resolveURL(for: String(text[range]), detector: detector)
            }
            guard let url, let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https", url.host() != nil
            else { continue }
            results.append(DetectedLink(url: url, range: range))
        }
        return results
    }

    // NSRegularExpression (and so NSDataDetector) is documented as immutable
    // and safe to use from multiple threads.
    private static let detector: NSDataDetector = {
        do {
            return try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        } catch {
            fatalError("NSDataDetector for links is unavailable: \(error)")
        }
    }()

    private static func hasAcceptablePrefix(_ text: Substring) -> Bool {
        let lower = text.prefix(8).lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("www.")
    }

    private static let closerForOpener: [Character: Character] = [
        "<": ">", "(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'",
        "*": "*", "_": "_", "`": "`", "«": "»", "“": "”", "‘": "’",
    ]

    /// Strips characters at the end of a match that belong to the sentence
    /// rather than to the URL.
    private static func trimmedEndIndex(of text: Substring, openedBy opener: Character?) -> String.Index {
        var end = text.endIndex
        let start = text.startIndex
        // A symmetric wrapper (`*url*`, `_url_`, `'url'`) is stripped once.
        var wrapperCloser = opener.flatMap { closerForOpener[$0] }

        while end > start {
            let last = text[text.index(before: end)]
            let body = text[start..<text.index(before: end)]
            var shouldTrim: Bool
            switch last {
            case ".", ",", ";", ":", "!", "?", "…", "\"", ">", "”", "’", "»":
                shouldTrim = true
            // Brackets are kept only when they close one opened inside the URL.
            case ")":
                shouldTrim = count("(", in: body) <= count(")", in: body)
            case "]":
                shouldTrim = count("[", in: body) <= count("]", in: body)
            case "}":
                shouldTrim = count("{", in: body) <= count("}", in: body)
            case "'":
                // Keep an apostrophe that pairs with another one inside the URL.
                shouldTrim = last == wrapperCloser || count("'", in: body).isMultiple(of: 2)
            case "*", "_", "`":
                shouldTrim = last == wrapperCloser
            default:
                shouldTrim = false
            }
            if shouldTrim, last == wrapperCloser { wrapperCloser = nil }
            guard shouldTrim else { break }
            end = text.index(before: end)
        }
        return end
    }

    private static func count(_ character: Character, in text: Substring) -> Int {
        text.reduce(0) { $1 == character ? $0 + 1 : $0 }
    }

    /// Builds the URL for trimmed link text by running the detector again,
    /// which takes care of IDNA hosts and percent-encoding.
    private static func resolveURL(for text: String, detector: NSDataDetector) -> URL? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        if let match = detector.firstMatch(in: text, options: [], range: range),
           match.range == range, let url = match.url {
            return url
        }
        let lower = text.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return URL(string: text)
        }
        return URL(string: "https://" + text)
    }
}
