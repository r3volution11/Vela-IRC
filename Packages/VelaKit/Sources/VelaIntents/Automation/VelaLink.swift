// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaCore

/// A `vela://` link, parsed. Every link goes through ``parse(_:)``: links
/// opened from outside Vela (a web page, Alfred, Raycast, a shortcut) and
/// the `vela://join/<channel>` links Vela puts on channel names in messages.
///
/// Any web page can open a `vela://` link, so a link only ever shows
/// things: it never sends a message, never joins a channel without asking
/// (``join(channel:network:)`` opens the Join Channel sheet, filled in),
/// never runs a command, and never hands anything back. What does those
/// things is the AppleScript dictionary, which macOS lets an app use only
/// once you've allowed it.
///
/// The routes (`vela-dev://` works the same, for Vela Dev):
///
/// | Link | Does |
/// | --- | --- |
/// | `vela://` or `vela://show` | Brings Vela to the front. |
/// | `vela://open?network=Libera.Chat&channel=%23vela` | Shows a channel (`nick=` for a private conversation, `id=` for a conversation id). |
/// | `vela://join?network=Libera.Chat&channel=%23vela` | Shows the channel if you're in it; otherwise opens Join Channel, filled in. |
/// | `vela://join/%23vela` | The same, on the network you're looking at (the form Vela uses in messages). |
/// | `vela://catchup?network=…&channel=…` | Opens the conversation with its Catch me up card. |
/// | `vela://recap?network=…&channel=…&person=…&span=today` | Opens a Recap, filled in. Every parameter is optional. |
/// | `vela://draft?network=…&channel=…&text=…` | Puts the text in the conversation's message box. You press Return. |
/// | `vela://search?q=…` | Opens message search with the query (`network=`, `channel=` or `nick=` narrow it). |
///
/// `network=` takes a network's name as Vela shows it ("Libera.Chat",
/// case doesn't matter) or its id (a UUID). Without it, Vela looks on the
/// network you're looking at first, then on the others. A parameter given
/// twice makes the link mean nothing (it might mean either), and so does
/// a value that's too long or has control characters in it.
nonisolated public enum VelaLink: Equatable, Sendable {
    /// Bring Vela to the front.
    case show
    /// Show a channel or private conversation.
    case open(ConversationReference)
    /// Show a channel you're in, or offer to join it.
    case join(channel: String, network: String?)
    /// Open Catch me up for a conversation (the busiest unread one if nil).
    case catchUp(ConversationReference?)
    /// Open a Recap.
    case recap(RecapLink)
    /// Fill in a conversation's message box.
    case draft(ConversationReference, text: String)
    /// Open message search.
    case search(query: String, in: SearchLinkScope?)

    /// The schemes Vela answers to: `vela` (Vela) and `vela-dev` (Vela Dev,
    /// so a link meant for one never opens the other).
    public static let schemes: Set<String> = ["vela", "vela-dev"]

    /// The longest channel name, nick or network a link may give.
    public static let maximumNameLength = 200
    /// The longest text ``draft(_:text:)`` puts in the message box.
    public static let maximumDraftLength = 4_000
    /// The longest search query.
    public static let maximumQueryLength = 500

    /// Parses `url`, or nil if it isn't a Vela link that means something.
    public static func parse(_ url: URL) -> VelaLink? {
        guard let scheme = url.scheme?.lowercased(), schemes.contains(scheme),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        // A "#" left unencoded, as in vela://join/#vela or channel=#vela,
        // starts the URL's fragment: put it back where it was written.
        if let fragment = components.percentEncodedFragment {
            components.percentEncodedFragment = nil
            if let query = components.percentEncodedQuery {
                components.percentEncodedQuery = query + "%23" + fragment
            } else {
                let path = components.percentEncodedPath
                components.percentEncodedPath = (path.hasPrefix("/") ? path : "/" + path) + "%23" + fragment
            }
        }
        guard let query = LinkQuery(components.queryItems ?? []) else { return nil }
        let action = (components.host ?? "").lowercased()
        // What follows the action: "#vela" in vela://join/%23vela.
        let path = String(components.path.drop { $0 == "/" })

        switch action {
        case "", "show":
            return path.isEmpty && query.isEmpty ? .show : nil
        case "open":
            return query.conversation().map { .open($0) }
        case "join":
            let named = path.isEmpty ? nil : path
            guard named == nil || query["channel"] == nil,
                  let channel = (named ?? query["channel"]).flatMap(cleanName),
                  query.only(["channel", "network"]) else { return nil }
            if let network = query["network"] {
                guard let name = cleanNetwork(network) else { return nil }
                return .join(channel: channel, network: name)
            }
            return .join(channel: channel, network: nil)
        case "catchup", "catch-up":
            guard query.only(ConversationReference.keys) else { return nil }
            if query.isEmpty { return .catchUp(nil) }
            return query.conversation().map { .catchUp($0) }
        case "recap":
            return RecapLink(query).map { .recap($0) }
        case "draft":
            guard let raw = query["text"], let text = cleanDraft(raw),
                  let target = query.conversation(also: ["text"]) else { return nil }
            return .draft(target, text: text)
        case "search":
            guard let raw = query["q"] ?? query["query"], query["q"] == nil || query["query"] == nil,
                  let text = cleanQuery(raw), query.only(["q", "query"] + ConversationReference.keys) else { return nil }
            if query.hasAny(of: ["id", "channel", "nick"]) {
                guard let target = query.conversation(also: ["q", "query"]) else { return nil }
                return .search(query: text, in: .conversation(target))
            }
            if let network = query["network"] {
                guard let name = cleanNetwork(network) else { return nil }
                return .search(query: text, in: .network(name))
            }
            return .search(query: text, in: nil)
        default:
            return nil
        }
    }

    // MARK: Values

    /// A name as a link may give it: trimmed, at most ``maximumNameLength``
    /// characters, with no spaces, commas or control characters (IRC names
    /// never have them).
    static func cleanName(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name.count <= maximumNameLength,
              !name.unicodeScalars.contains(where: { $0.properties.generalCategory == .control || $0 == " " || $0 == "," || isInvisibleFormatting($0) })
        else { return nil }
        return name
    }

    /// A network's name as a link may give it: like ``cleanName(_:)``, but
    /// spaces are fine ("Ergo Testnet").
    static func cleanNetwork(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name.count <= maximumNameLength,
              !name.unicodeScalars.contains(where: { $0.properties.generalCategory == .control || isInvisibleFormatting($0) })
        else { return nil }
        return name
    }

    /// Text for the message box: line endings made `\n`, control
    /// characters other than newlines and tabs taken out (IRC formatting
    /// codes and direction overrides could hide what you'd be sending), and
    /// at most `maximumLength` characters. Nil if nothing's left, or it's
    /// longer than that.
    static func cleanDraft(_ raw: String, maximumLength: Int = maximumDraftLength) -> String? {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var scalars = String.UnicodeScalarView()
        for scalar in normalized.unicodeScalars {
            if scalar == "\n" || scalar == "\t" {
                scalars.append(scalar)
            } else if scalar.properties.generalCategory == .control || isInvisibleFormatting(scalar) {
                continue
            } else {
                scalars.append(scalar)
            }
        }
        let text = String(scalars)
        guard text.count <= maximumLength, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    /// A search query: one line, trimmed, at most `maximumLength`
    /// characters. Nil if nothing's left, or it's longer than that.
    static func cleanQuery(_ raw: String, maximumLength: Int = maximumQueryLength) -> String? {
        guard let text = cleanDraft(raw, maximumLength: .max)?.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: " ") else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= maximumLength else { return nil }
        return trimmed
    }

    /// Characters that change how text around them shows without showing
    /// themselves: direction overrides, embeddings and isolates.
    private static func isInvisibleFormatting(_ scalar: Unicode.Scalar) -> Bool {
        (0x202A...0x202E).contains(scalar.value) || (0x2066...0x2069).contains(scalar.value)
    }
}

/// A channel or private conversation a link names: by id, by channel name
/// or by nick, on a network or not.
nonisolated public struct ConversationReference: Equatable, Hashable, Sendable {
    public enum Target: Equatable, Hashable, Sendable {
        /// `id=`: a conversation id, `<network-uuid>/<folded-name>`.
        case id(BufferID)
        /// `channel=`: "#vela" (a name without a channel prefix gets "#").
        case channel(String)
        /// `nick=`: a private conversation.
        case nick(String)
    }

    public var target: Target
    /// `network=`: a network's name as Vela shows it, or its id.
    public var network: String?

    public init(_ target: Target, network: String? = nil) {
        self.target = target
        self.network = network
    }

    /// The query parameters that name a conversation.
    static let keys = ["id", "channel", "nick", "network"]

    /// "#vela on Libera.Chat", for notices.
    public var description: String {
        let name: String = switch target {
        case .id(let id): id.foldedName
        case .channel(let channel): channel
        case .nick(let nick): nick
        }
        return network.map { "\(name) on \($0)" } ?? name
    }
}

/// What `vela://search` looks in.
nonisolated public enum SearchLinkScope: Equatable, Sendable {
    case network(String)
    case conversation(ConversationReference)
}

/// A Recap a link asks for. Everything's optional: `vela://recap` is every
/// network since your first unread message.
nonisolated public struct RecapLink: Equatable, Sendable {
    /// One channel or conversation (`id=`, `channel=` or `nick=`).
    public var conversation: ConversationReference?
    /// One network (`network=` without a conversation).
    public var network: String?
    /// `person=`: one person's messages.
    public var person: String?
    public var span: RecapSpanOption

    public init(conversation: ConversationReference? = nil, network: String? = nil, person: String? = nil, span: RecapSpanOption = .sinceUnread) {
        self.conversation = conversation
        self.network = network
        self.person = person
        self.span = span
    }

    init?(_ query: LinkQuery) {
        guard query.only(ConversationReference.keys + ["person", "span"]) else { return nil }
        if query.hasAny(of: ["id", "channel", "nick"]) {
            guard let conversation = query.conversation(also: ["person", "span"]) else { return nil }
            self.conversation = conversation
        } else if let network = query["network"] {
            guard let name = VelaLink.cleanNetwork(network) else { return nil }
            self.network = name
        }
        if let person = query["person"] {
            guard let nick = VelaLink.cleanName(person.trimmingCharacters(in: CharacterSet(charactersIn: "@ "))) else { return nil }
            self.person = nick
        }
        if let raw = query["span"] {
            guard let span = RecapSpanOption(linkValue: raw) else { return nil }
            self.span = span
        } else {
            self.span = .sinceUnread
        }
    }
}

nonisolated extension RecapSpanOption {
    /// A link's `span=`: the action's own names ("lastHour") or short ones
    /// ("1h", "today", "week").
    init?(linkValue raw: String) {
        let value = raw.trimmingCharacters(in: .whitespaces)
        if let exact = RecapSpanOption.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(value) == .orderedSame }) {
            self = exact
            return
        }
        switch value.lowercased() {
        case "unread", "new": self = .sinceUnread
        case "30m", "30min", "halfhour": self = .lastHalfHour
        case "1h", "hour": self = .lastHour
        case "4h": self = .lastFourHours
        case "1d", "day", "24h": self = .lastDay
        case "3d": self = .lastThreeDays
        case "1w", "7d", "week": self = .lastWeek
        default: return nil
        }
    }

    /// The short name a link uses.
    public var linkValue: String {
        switch self {
        case .sinceUnread: "unread"
        case .lastHalfHour: "30m"
        case .lastHour: "1h"
        case .lastFourHours: "4h"
        case .today: "today"
        case .lastDay: "1d"
        case .lastThreeDays: "3d"
        case .lastWeek: "1w"
        }
    }
}

// MARK: - Query

/// A link's query parameters, by lowercased name. A parameter given twice
/// makes the whole query invalid: the link could mean either.
nonisolated struct LinkQuery {
    private let values: [String: String]

    init?(_ items: [URLQueryItem]) {
        var values: [String: String] = [:]
        for item in items {
            let name = item.name.lowercased()
            guard values[name] == nil else { return nil }
            values[name] = item.value ?? ""
        }
        self.values = values
    }

    var isEmpty: Bool { values.isEmpty }

    subscript(name: String) -> String? { values[name] }

    func hasAny(of names: [String]) -> Bool { names.contains { values[$0] != nil } }

    /// Whether every parameter is one of `names`.
    func only(_ names: [String]) -> Bool { values.keys.allSatisfy(names.contains) }

    /// The conversation the query names: exactly one of `id=`, `channel=`
    /// and `nick=`, and maybe `network=`, with nothing else but `extra`.
    func conversation(also extra: [String] = []) -> ConversationReference? {
        guard only(ConversationReference.keys + extra) else { return nil }
        let given = ["id", "channel", "nick"].filter { values[$0] != nil }
        guard given.count == 1 else { return nil }
        var network: String?
        if let raw = values["network"] {
            guard let name = VelaLink.cleanNetwork(raw) else { return nil }
            network = name
        }
        switch given[0] {
        case "id":
            guard let raw = values["id"], let id = BufferID(string: raw.trimmingCharacters(in: .whitespaces)),
                  VelaLink.cleanName(id.foldedName) != nil else { return nil }
            return ConversationReference(.id(id), network: network)
        case "channel":
            return values["channel"].flatMap(VelaLink.cleanName).map { ConversationReference(.channel($0), network: network) }
        default:
            return values["nick"].flatMap(VelaLink.cleanName).map { ConversationReference(.nick($0), network: network) }
        }
    }
}

// MARK: - Making links

nonisolated extension VelaLink {
    /// The link for this route, in its canonical form (`scheme` is `vela`,
    /// or `vela-dev` for Vela Dev). ``parse(_:)`` reads it back as `self`.
    public func url(scheme: String = "vela") -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        var items: [URLQueryItem] = []
        func add(_ reference: ConversationReference) {
            switch reference.target {
            case .id(let id): items.append(URLQueryItem(name: "id", value: id.description))
            case .channel(let channel): items.append(URLQueryItem(name: "channel", value: channel))
            case .nick(let nick): items.append(URLQueryItem(name: "nick", value: nick))
            }
            if let network = reference.network { items.append(URLQueryItem(name: "network", value: network)) }
        }
        switch self {
        case .show:
            components.host = "show"
        case .open(let reference):
            components.host = "open"
            add(reference)
        case .join(let channel, let network):
            components.host = "join"
            items.append(URLQueryItem(name: "channel", value: channel))
            if let network { items.append(URLQueryItem(name: "network", value: network)) }
        case .catchUp(let reference):
            components.host = "catchup"
            if let reference { add(reference) }
        case .recap(let recap):
            components.host = "recap"
            if let conversation = recap.conversation { add(conversation) }
            if let network = recap.network { items.append(URLQueryItem(name: "network", value: network)) }
            if let person = recap.person { items.append(URLQueryItem(name: "person", value: person)) }
            if recap.span != .sinceUnread { items.append(URLQueryItem(name: "span", value: recap.span.linkValue)) }
        case .draft(let reference, let text):
            components.host = "draft"
            add(reference)
            items.append(URLQueryItem(name: "text", value: text))
        case .search(let query, let scope):
            components.host = "search"
            items.append(URLQueryItem(name: "q", value: query))
            switch scope {
            case .network(let network): items.append(URLQueryItem(name: "network", value: network))
            case .conversation(let reference): add(reference)
            case nil: break
            }
        }
        if !items.isEmpty { components.queryItems = items }
        // "#", "&" and "+" mean something in a URL's query: encode them.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
            .replacingOccurrences(of: "#", with: "%23")
        return components.url
    }
}
