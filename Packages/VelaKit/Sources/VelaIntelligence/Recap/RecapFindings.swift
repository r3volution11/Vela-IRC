// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaCore
import VelaMedia

// The parts of a Recap found on this Mac without Apple Intelligence: what
// was for you (and whether you answered), the links shared and who talked.
// Pure and quick, so they show the moment the messages are read, in a log
// as well as a summary.

/// A message that named you, or one sent to you privately.
nonisolated public struct RecapForYou: Sendable, Hashable, Identifiable {
    public var id: UUID { reference.lineID }
    public var nick: String
    /// What they wrote, without the "doug: " in front.
    public var quote: String
    public var reference: RecapReference
    /// `#vela`, or the person's nick for a private conversation.
    public var conversationName: String
    public var isPrivate: Bool
    /// It asks something of you: a question, or "can you…", "please…".
    public var isRequest: Bool
    /// You answered: replied to it, named them after it, wrote back in the
    /// private conversation, or spoke in the channel soon after.
    public var isAnswered: Bool
    /// More messages from them right after, in a private conversation.
    public var followingMessages: Int

    public init(
        nick: String,
        quote: String,
        reference: RecapReference,
        conversationName: String,
        isPrivate: Bool,
        isRequest: Bool,
        isAnswered: Bool,
        followingMessages: Int = 0
    ) {
        self.nick = nick
        self.quote = quote
        self.reference = reference
        self.conversationName = conversationName
        self.isPrivate = isPrivate
        self.isRequest = isRequest
        self.isAnswered = isAnswered
        self.followingMessages = followingMessages
    }
}

/// A link someone shared.
nonisolated public struct RecapLink: Sendable, Hashable, Identifiable {
    public var id: String { url.absoluteString }
    public var url: URL
    /// `youtube.com`, without `www.`.
    public var host: String
    /// The page's title, when its preview is in memory.
    public var title: String?
    /// Who shared it first.
    public var nick: String
    public var reference: RecapReference
    /// How many times it was shared.
    public var shares: Int

    public init(url: URL, host: String, title: String? = nil, nick: String, reference: RecapReference, shares: Int = 1) {
        self.url = url
        self.host = host
        self.title = title
        self.nick = nick
        self.reference = reference
        self.shares = shares
    }

    /// The title, or the address without its scheme.
    public var displayTitle: String {
        if let title, !title.isEmpty { return title }
        var text = url.absoluteString
        for prefix in ["https://", "http://"] where text.hasPrefix(prefix) { text.removeFirst(prefix.count) }
        if text.hasPrefix("www.") { text.removeFirst(4) }
        if text.hasSuffix("/") { text.removeLast() }
        return text
    }
}

/// Links of one kind, or from one site.
nonisolated public struct RecapLinkGroup: Sendable, Hashable, Identifiable {
    public var id: String
    /// "Videos", "Images", "github.com", "Pages".
    public var title: String
    public var links: [RecapLink]

    public init(id: String, title: String, links: [RecapLink]) {
        self.id = id
        self.title = title
        self.links = links
    }
}

/// Someone who spoke, and how much.
nonisolated public struct RecapSpeaker: Sendable, Hashable, Identifiable {
    public var id: String { nick.lowercased() }
    public var nick: String
    public var messages: Int

    public init(nick: String, messages: Int) {
        self.nick = nick
        self.messages = messages
    }
}

/// What a Recap finds without Apple Intelligence.
nonisolated public struct RecapFindings: Sendable, Hashable {
    public var forYou: [RecapForYou]
    public var links: [RecapLinkGroup]
    /// Everyone but you who spoke, most messages first.
    public var speakers: [RecapSpeaker]

    /// At most this many items for you: the newest.
    public static let maximumForYou = 30
    /// At most this many links: the newest.
    public static let maximumLinks = 80
    /// A site with at least this many links gets a group of its own.
    static let siteGroupMinimum = 3
    /// Speaking in a channel this soon after a message for you counts as
    /// answering it.
    public static let answerWindow: TimeInterval = 30 * 60

    public init(forYou: [RecapForYou] = [], links: [RecapLinkGroup] = [], speakers: [RecapSpeaker] = []) {
        self.forYou = forYou
        self.links = links
        self.speakers = speakers
    }

    public init(_ input: RecapInput) {
        self.init(
            forYou: Self.forYou(in: input),
            links: Self.linkGroups(in: input),
            speakers: Self.speakers(in: input)
        )
    }

    public var linkCount: Int { links.reduce(0) { $0 + $1.links.count } }

    public var unansweredCount: Int { forYou.count { !$0.isAnswered } }

    /// Fills in link titles from the link previews in memory.
    public mutating func applyTitles(_ titles: [URL: String]) {
        guard !titles.isEmpty else { return }
        for group in links.indices {
            for link in links[group].links.indices {
                if let title = titles[links[group].links[link].url] {
                    links[group].links[link].title = title
                }
            }
        }
    }

    /// Every link's address, for looking up titles.
    public var linkURLs: [URL] { links.flatMap { $0.links.map(\.url) } }

    // MARK: For you

    static func forYou(in input: RecapInput) -> [RecapForYou] {
        var items: [RecapForYou] = []
        for conversation in input.conversations {
            items += conversation.isChannel ? mentions(in: conversation) : privateMessages(in: conversation)
        }
        items.sort { $0.reference.time < $1.reference.time }
        return Array(items.suffix(maximumForYou))
    }

    /// Other people's lines in a channel that name you (or a highlight word).
    private static func mentions(in conversation: RecapConversation) -> [RecapForYou] {
        let own = conversation.ownNick.lowercased()
        return conversation.lines.compactMap { line in
            guard !line.isSelf, line.nick.lowercased() != own else { return nil }
            let named = !own.isEmpty && CatchUpTranscript.containsWord(own, in: line.text.lowercased())
            guard named || line.isHighlight else { return nil }
            let quote = quote(line.text, removingAddress: conversation.ownNick)
            return RecapForYou(
                nick: line.nick,
                quote: quote,
                reference: RecapReference(conversation: conversation.id, lineID: line.id, time: line.time),
                conversationName: conversation.name,
                isPrivate: false,
                isRequest: isRequest(quote),
                isAnswered: isAnswered(line, in: conversation)
            )
        }
    }

    /// A private conversation: the first of each run of their messages.
    private static func privateMessages(in conversation: RecapConversation) -> [RecapForYou] {
        var items: [RecapForYou] = []
        var previous: RecapLine?
        for line in conversation.lines {
            defer { previous = line }
            guard !line.isSelf else { continue }
            if let last = items.last, let previous, !previous.isSelf, line.time.timeIntervalSince(previous.time) < answerWindow {
                // The same run: count it, and let a question in it mark the run.
                items[items.count - 1].followingMessages += 1
                if !last.isRequest, isRequest(line.text) { items[items.count - 1].isRequest = true }
                continue
            }
            items.append(RecapForYou(
                nick: line.nick,
                quote: quote(line.text, removingAddress: conversation.ownNick),
                reference: RecapReference(conversation: conversation.id, lineID: line.id, time: line.time),
                conversationName: conversation.name,
                isPrivate: true,
                isRequest: isRequest(line.text),
                isAnswered: isAnswered(line, in: conversation)
            ))
        }
        return items
    }

    /// Whether you answered `line`: you replied to it, named its author
    /// after it, wrote back in a private conversation, or spoke in the
    /// channel within ``answerWindow``.
    static func isAnswered(_ line: RecapLine, in conversation: RecapConversation) -> Bool {
        let author = line.nick.lowercased()
        for yours in conversation.yourLines where yours.time > line.time {
            if !conversation.isChannel { return true }
            if let msgid = line.msgid, yours.replyTo == msgid { return true }
            if CatchUpTranscript.containsWord(author, in: yours.text.lowercased()) { return true }
            if yours.time.timeIntervalSince(line.time) <= answerWindow { return true }
        }
        return false
    }

    private static let requestOpenings = [
        "can you", "could you", "would you", "will you", "can u", "could u", "please", "pls", "plz",
        "let me know", "lmk", "mind ", "any chance", "do you", "did you", "are you", "have you", "when you get",
    ]

    /// A question, or a request ("can you…", "please…").
    static func isRequest(_ text: String) -> Bool {
        if text.contains("?") { return true }
        let lowered = text.lowercased()
        return requestOpenings.contains { lowered.hasPrefix($0) || lowered.contains(" \($0)") }
    }

    /// `text` without a leading "doug: " or "doug, " and cut to a
    /// readable length.
    static func quote(_ text: String, removingAddress nick: String, maximumLength: Int = 200) -> String {
        var quote = text.trimmingCharacters(in: .whitespaces)
        if !nick.isEmpty, let range = quote.range(of: nick, options: [.caseInsensitive, .anchored]) {
            let rest = quote[range.upperBound...]
            if let first = rest.first, first == ":" || first == "," {
                quote = rest.dropFirst().trimmingCharacters(in: .whitespaces)
            }
        }
        guard quote.count > maximumLength else { return quote }
        return quote.prefix(maximumLength - 1).trimmingCharacters(in: .whitespaces) + "…"
    }

    // MARK: Links

    static func linkGroups(in input: RecapInput) -> [RecapLinkGroup] {
        var order: [String] = []
        var links: [String: RecapLink] = [:]
        for conversation in input.conversations {
            for line in conversation.lines where LinkDetector.mayContainLinks(line.text) {
                for detected in LinkDetector.links(in: line.text) {
                    let key = detected.url.absoluteString
                    if links[key] != nil {
                        links[key]?.shares += 1
                        continue
                    }
                    order.append(key)
                    links[key] = RecapLink(
                        url: detected.url,
                        host: CatchUpTranscript.host(of: key),
                        nick: line.nick,
                        reference: RecapReference(conversation: conversation.id, lineID: line.id, time: line.time)
                    )
                }
            }
        }
        let all = order.compactMap { links[$0] }
            .sorted { $0.reference.time < $1.reference.time }
            .suffix(maximumLinks)
        return group(Array(all))
    }

    /// Videos, images, then sites with several links each, then the rest.
    static func group(_ links: [RecapLink]) -> [RecapLinkGroup] {
        var videos: [RecapLink] = []
        var images: [RecapLink] = []
        var pages: [RecapLink] = []
        for link in links {
            switch MediaClassifier.classify(link.url) {
            case .embed, .video: videos.append(link)
            case .image, .gif: images.append(link)
            case .page: pages.append(link)
            }
        }
        var groups: [RecapLinkGroup] = []
        if !videos.isEmpty { groups.append(RecapLinkGroup(id: "videos", title: "Videos", links: videos)) }
        if !images.isEmpty { groups.append(RecapLinkGroup(id: "images", title: "Images", links: images)) }
        var byHost: [String: [RecapLink]] = [:]
        for page in pages { byHost[page.host, default: []].append(page) }
        let sites = byHost.filter { $0.value.count >= siteGroupMinimum }
            .sorted { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key }
        for (host, links) in sites {
            groups.append(RecapLinkGroup(id: "site:\(host)", title: host, links: links))
        }
        let rest = pages.filter { (byHost[$0.host]?.count ?? 0) < siteGroupMinimum }
        if !rest.isEmpty {
            groups.append(RecapLinkGroup(id: "pages", title: sites.isEmpty ? "Pages" : "Other pages", links: rest))
        }
        return groups
    }

    // MARK: People

    static func speakers(in input: RecapInput) -> [RecapSpeaker] {
        var counts: [String: Int] = [:]
        var names: [String: String] = [:]
        var order: [String] = []
        for conversation in input.conversations {
            let own = conversation.ownNick.lowercased()
            for line in conversation.lines where !line.isSelf && line.nick.lowercased() != own && !line.nick.isEmpty {
                let key = line.nick.lowercased()
                if counts[key] == nil {
                    order.append(key)
                    names[key] = line.nick
                }
                counts[key, default: 0] += 1
            }
        }
        return order
            .map { RecapSpeaker(nick: names[$0] ?? $0, messages: counts[$0] ?? 0) }
            .enumerated()
            .sorted { $0.element.messages != $1.element.messages ? $0.element.messages > $1.element.messages : $0.offset < $1.offset }
            .map(\.element)
    }
}
