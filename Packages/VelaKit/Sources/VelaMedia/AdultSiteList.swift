// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// A set of adult-only domains, matched against a host and its parent domains.
///
/// The bundled list (`Resources/adult-domains.txt`, one domain per line,
/// `#` comments) ships with each release; Vela never downloads it. The
/// adult-only top-level domains `.xxx`, `.porn`, `.adult` and `.sex` match
/// without being listed.
public struct AdultSiteList: Sendable {
    /// Top-level domains reserved for adult content.
    public static let adultTopLevelDomains: Set<String> = ["xxx", "porn", "adult", "sex"]

    private let domains: Set<String>

    /// Builds a list from domain names. Entries are lowercased; a leading
    /// `*.` or `.` and a trailing `.` are dropped; empty entries are skipped.
    public init(domains: some Sequence<String>) {
        var set = Set<String>()
        for domain in domains {
            if let normalized = Self.normalizedEntry(Substring(domain)) { set.insert(normalized) }
        }
        self.domains = set
    }

    /// Parses a list file: one domain per line, blank lines and `#` comments
    /// skipped, CRLF tolerated. Hosts-file lines (`0.0.0.0 example.com`) use
    /// their last field.
    public init(contentsOf url: URL) throws {
        self.domains = Self.parse(try Data(contentsOf: url))
    }

    /// Parses the text of a list file; see `init(contentsOf:)`.
    public init(text: String) {
        self.domains = Self.parse(Data(text.utf8))
    }

    /// Number of listed domains (the built-in top-level domains not included).
    public var count: Int { domains.count }

    /// Whether `host` (or a parent domain of it) is listed, or it is under an
    /// adult-only top-level domain. `example.com.evil.net` does not match
    /// `example.com`.
    public func contains(host: String) -> Bool {
        matchingDomain(forHost: host) != nil
    }

    /// The listed domain covering `host`; for a match on an adult-only
    /// top-level domain, the host's last two labels (`videos.site.xxx` → `site.xxx`).
    public func matchingDomain(forHost host: String) -> String? {
        guard let host = SiteRules.normalizedDomain(host), !SiteRules.isIPLiteral(host) else { return nil }
        let suffixes = SiteRules.domainSuffixes(of: host)
        if !domains.isEmpty {
            for suffix in suffixes where domains.contains(suffix) { return suffix }
        }
        if let tld = suffixes.last, Self.adultTopLevelDomains.contains(tld) {
            return suffixes.count >= 2 ? suffixes[suffixes.count - 2] : host
        }
        return nil
    }

    // MARK: - Bundled list

    /// The list shipped in the app bundle, loaded on first use. Empty if the
    /// resource is missing or unreadable.
    public static let bundled: AdultSiteList = {
        guard let url = Bundle.module.url(forResource: "adult-domains", withExtension: "txt"),
              let list = try? AdultSiteList(contentsOf: url)
        else { return AdultSiteList(domains: []) }
        return list
    }()

    /// Loads `bundled` now. Call it off the main actor at launch so the
    /// first preview doesn't pay for parsing the file.
    public static func warmUp() {
        _ = bundled.count
    }

    // MARK: - Parsing

    /// A byte-level parser: the bundled file has tens of thousands of lines.
    private static func parse(_ data: Data) -> Set<String> {
        var set = Set<String>()
        set.reserveCapacity(data.count / 16)
        data.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            var lineStart = 0
            while lineStart < bytes.count {
                var lineEnd = lineStart
                while lineEnd < bytes.count, bytes[lineEnd] != 0x0A, bytes[lineEnd] != 0x0D { lineEnd += 1 }
                if let domain = entry(in: bytes, from: lineStart, to: lineEnd) { set.insert(domain) }
                lineStart = lineEnd + 1
            }
        }
        return set
    }

    /// The last whitespace-separated field of one line, before any `#`.
    private static func entry(in bytes: UnsafeBufferPointer<UInt8>, from start: Int, to end: Int) -> String? {
        var stop = start
        while stop < end, bytes[stop] != UInt8(ascii: "#") { stop += 1 }
        // Trim trailing whitespace, then find where the last field begins.
        var fieldEnd = stop
        while fieldEnd > start, isSpace(bytes[fieldEnd - 1]) { fieldEnd -= 1 }
        var fieldStart = fieldEnd
        while fieldStart > start, !isSpace(bytes[fieldStart - 1]) { fieldStart -= 1 }
        guard fieldStart < fieldEnd else { return nil }
        let field = String(decoding: UnsafeBufferPointer(rebasing: bytes[fieldStart..<fieldEnd]), as: UTF8.self)
        return normalizedEntry(Substring(field))
    }

    private static func isSpace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0B || byte == 0x0C
    }

    private static func normalizedEntry(_ raw: Substring) -> String? {
        var entry = raw.trimmingCharacters(in: .whitespaces).lowercased()[...]
        while entry.hasPrefix("*") || entry.hasPrefix(".") { entry = entry.dropFirst() }
        while entry.hasSuffix(".") { entry = entry.dropLast() }
        guard !entry.isEmpty else { return nil }
        let domain = String(entry)
        // Hosts files also carry IP addresses and `localhost`.
        if SiteRules.isIPLiteral(domain) || domain == "localhost" { return nil }
        return domain
    }
}
