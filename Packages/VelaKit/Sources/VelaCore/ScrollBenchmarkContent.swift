// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaIRC

/// The channel the scroll benchmark scrolls (`--demo --scroll-benchmark`;
/// VelaUI's `ScrollBenchmark` drives it, `scripts/benchmark-scroll.sh` runs it).
///
/// About 2,000 lines over five days, made from a fixed seed so every run
/// sees the same conversation: mostly one-liners, long wrapped messages,
/// actions, mentions, IRC formatting, emoji, replies, reactions, joins,
/// parts and quits (and one long netsplit), day dividers, and links: photos,
/// animated GIFs (plain files and GIPHY's MP4s), YouTube videos and pages
/// with link cards. Every link points at a host that VelaUI's
/// `ScrollBenchmarkMedia` answers for in the app, so nothing is fetched
/// from the network.
///
/// The `text` mix has the same lines with every link replaced by words, for
/// telling what the media costs.
nonisolated public enum ScrollBenchmarkContent {
    nonisolated public enum Mix: String, Sendable, CaseIterable {
        case full
        case text
    }

    public static let channelName = "#scroll-bench"
    public static let defaultLineCount = 2_000

    /// Hosts the links point at (`ScrollBenchmarkMedia` serves them).
    public static let photoHost = "photos.example.org"
    public static let gifHost = "media.example.org"
    public static let pageHosts = [
        "news.example.com", "blog.example.net", "docs.example.org",
        "forum.example.com", "wiki.example.org", "dev.example.net",
    ]

    /// Adds the channel to the first demo network, selects it, and returns it.
    @MainActor @discardableResult
    public static func install(in app: AppModel, mix: Mix, lineCount: Int = defaultLineCount) -> BufferModel? {
        guard let session = app.sessions.first else { return nil }
        let buffer = session.ensureBuffer(name: channelName, kind: .channel, persist: false)
        buffer.topic = "Scroll benchmark · the same 2,000 lines every run · https://docs.example.org/scroll-benchmark"
        buffer.topicSetBy = "doug"
        var generator = Generator(mix: mix, selfNick: session.nick)
        let generated = generator.lines(count: lineCount)
        var members: [String: Member] = [:]
        for (index, nick) in ([session.nick] + Generator.nicks).enumerated() {
            let prefix = index == 0 ? "~" : index < 4 ? "@" : index < 9 ? "+" : ""
            members[session.fold(nick)] = Member(nick: nick, prefixes: prefix, userHost: "\(nick)@user/\(nick)")
        }
        buffer.replaceMembers(members)
        buffer.isJoined = true
        buffer.insertSorted(generated.lines)
        for reaction in generated.reactions {
            buffer.setReaction(msgid: reaction.msgid, nick: reaction.nick, emoji: reaction.emoji, active: true)
        }
        // No history to load: the top is the beginning of the channel.
        buffer.hasMoreHistory = false
        app.select(buffer)
        return buffer
    }

    // MARK: - Generation

    nonisolated struct Reaction {
        var msgid: String
        var nick: String
        var emoji: String
    }

    /// SplitMix64: small, fast and the same on every Mac.
    nonisolated public struct Random: Sendable {
        private var state: UInt64

        public init(seed: UInt64) {
            state = seed
        }

        public mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        /// A value in `0..<bound`.
        public mutating func int(_ bound: Int) -> Int {
            Int(next() % UInt64(max(1, bound)))
        }

        public mutating func int(in range: ClosedRange<Int>) -> Int {
            range.lowerBound + int(range.count)
        }

        /// True `percent` percent of the time.
        public mutating func chance(_ percent: Double) -> Bool {
            Double(next() % 10_000) < percent * 100
        }

        public mutating func pick<T>(_ items: [T]) -> T {
            items[int(items.count)]
        }
    }

    nonisolated struct Generator {
        static let nicks = [
            "marisol", "kenji", "ada", "theo", "priya", "lukas", "nadia", "oskar", "wren", "felix",
            "mina", "hana", "jorge", "irene", "sam", "rafael", "bea", "tomas", "leila", "dmitri",
            "yuki", "amara", "colin", "freya", "ravi", "sofia", "noah", "elif", "mateo", "ingrid",
            "kwame", "lena", "pablo", "zoe", "arjun", "chloe", "emil", "farah", "gus", "helga",
            "ivo", "juno", "kai", "lior", "milo", "nora", "otto", "pia",
        ]

        static let words = [
            "the", "a", "build", "theme", "sidebar", "scrolling", "release", "patch", "server", "client",
            "channel", "message", "layout", "font", "render", "swift", "macOS", "bouncer", "history", "link",
            "preview", "image", "video", "players", "cache", "memory", "thread", "main", "actor", "queue",
            "works", "broke", "again", "today", "yesterday", "maybe", "probably", "definitely", "nice", "weird",
            "fast", "slow", "smooth", "janky", "glass", "tabs", "colors", "nick", "away", "typing",
            "reaction", "reply", "IRCv3", "SASL", "TLS", "certificate", "network", "proxy", "znc", "soju",
            "ergo", "libera", "oftc", "commit", "branch", "merge", "review", "test", "CI", "flaky",
            "benchmark", "profile", "instruments", "hitch", "frame", "display", "retina", "pixels", "points", "window",
            "and", "but", "so", "because", "with", "without", "after", "before", "while", "until",
            "is", "was", "looks", "feels", "seems", "should", "could", "would", "might", "will",
            "really", "pretty", "kind of", "super", "totally", "barely", "mostly", "still", "already", "never",
            "on", "in", "for", "from", "over", "under", "into", "onto", "about", "around",
            "coffee", "lunch", "weekend", "keyboard", "trackpad", "mouse", "monitor", "laptop", "desk", "chair",
        ]

        static let short = [
            "lol", "same", "+1", "brb", "back", "o/", "\\o", "nice!", "thanks 🙏", "ty", "haha", "yep",
            "nope", "ok", "agreed", "hmm", "interesting", "wait what", "😂", "👍", "🎉", "ship it",
            "morning ☕", "night all", "lgtm", "ah right", "fair", "TIL", "that's the one", "same here",
        ]

        static let reactions = ["👍", "😂", "🎉", "❤️", "🔥", "👀", "💜", "🙏", "🚀", "😮"]

        static let pageTitles = [
            "release-notes", "scrolling-deep-dive", "theme-engine", "irc-v3-chathistory", "swiftui-lists",
            "core-animation-tips", "font-rendering", "bouncers-compared", "accessibility-audit", "dark-mode",
            "memory-budgets", "image-decoding", "link-previews", "network-stack", "keyboard-shortcuts",
        ]

        let mix: Mix
        let selfNick: String
        var random = Random(seed: 0x5643_524F_4C4C_0001)
        var photoCount = 0
        var gifCount = 0
        var giphyCount = 0
        var videoCount = 0
        var pageCount = 0

        init(mix: Mix, selfNick: String) {
            self.mix = mix
            self.selfNick = selfNick
        }

        /// 09:00 local time on Monday 2 March 2026: a fixed start, so the
        /// day dividers fall in the same places in every run.
        static var start: Date {
            let components = DateComponents(year: 2026, month: 3, day: 2, hour: 9)
            return Calendar.current.date(from: components) ?? Date(timeIntervalSince1970: 1_772_442_000)
        }

        mutating func lines(count: Int) -> (lines: [ChatLine], reactions: [Reaction]) {
            var lines: [ChatLine] = []
            var reactions: [Reaction] = []
            var messageIDs: [String] = []
            let days = 5
            let perDay = max(1, count / days)
            var time = Self.start
            var day = 0
            var lastNick = Self.nicks[0]
            let netsplitAt = count / 2 + 37

            while lines.count < count {
                // A new day: overnight quiet, then 09:00 again.
                if lines.count >= (day + 1) * perDay, day < days - 1 {
                    day += 1
                    time = Calendar.current.date(byAdding: .day, value: day, to: Self.start) ?? time.addingTimeInterval(86_400)
                }
                time = time.addingTimeInterval(Double(random.int(in: 4...110)))

                if lines.count == netsplitAt {
                    appendNetsplit(to: &lines, at: &time)
                    continue
                }

                let roll = random.int(100)
                if roll < 6 {
                    lines.append(membershipLine(at: time))
                    continue
                }

                // Runs of messages from one person make continuations.
                let nick = random.chance(35) ? lastNick : (random.chance(5) ? selfNick : random.pick(Self.nicks))
                lastNick = nick
                let isSelf = nick == selfNick
                let index = lines.count
                let msgid = "bench-\(index)"
                var kind: ChatLineKind = .message
                var text = messageText()
                if random.chance(2.5) {
                    kind = .action
                    text = "\(random.pick(["reads", "waves", "tries", "rebuilds", "restarts"])) \(phrase(3...8))"
                } else if random.chance(0.6) {
                    kind = .notice
                }
                var isHighlight = false
                if !isSelf, random.chance(1.5) {
                    text = "\(selfNick): \(text)"
                    isHighlight = true
                } else if random.chance(9) {
                    text = "\(random.pick(Self.nicks)): \(text)"
                }
                var replyTo: String?
                if random.chance(3), !messageIDs.isEmpty {
                    replyTo = messageIDs[max(0, messageIDs.count - 1 - random.int(30))]
                }
                lines.append(ChatLine(
                    msgid: msgid,
                    time: time,
                    kind: kind,
                    nick: nick,
                    userHost: "\(nick)@user/\(nick)",
                    text: text,
                    isSelf: isSelf,
                    isHighlight: isHighlight,
                    replyTo: replyTo,
                    isHistory: true
                ))
                messageIDs.append(msgid)

                if random.chance(7) {
                    for _ in 0..<random.int(in: 1...3) {
                        let emoji = random.pick(Self.reactions)
                        for _ in 0..<random.int(in: 1...4) {
                            reactions.append(Reaction(msgid: msgid, nick: random.pick(Self.nicks), emoji: emoji))
                        }
                    }
                }
            }
            return (lines, reactions)
        }

        private mutating func phrase(_ length: ClosedRange<Int>) -> String {
            (0..<random.int(in: length)).map { _ in random.pick(Self.words) }.joined(separator: " ")
        }

        private mutating func sentence(_ length: ClosedRange<Int>) -> String {
            var text = phrase(length)
            text = text.prefix(1).uppercased() + text.dropFirst()
            return text + random.pick([".", ".", ".", "!", "?", "…"])
        }

        /// One message's text, by kind: one-liners mostly, some long ones,
        /// some with links.
        private mutating func messageText() -> String {
            let roll = random.int(1_000)
            switch roll {
            case 0..<300:
                return random.pick(Self.short)
            case 300..<680:
                return phrase(3...14)
            case 680..<770:
                // Long enough to wrap over several lines.
                return (0..<random.int(in: 3...7)).map { _ in sentence(8...16) }.joined(separator: " ")
            case 770..<790:
                return "\u{02}\(phrase(1...3))\u{02} \(phrase(2...6)) \u{03}0\(random.int(in: 2...9))\(phrase(1...3))\u{03} \(phrase(1...4))"
            case 790..<810:
                return "\(phrase(2...8)) \(random.pick(["🚀", "✨", "🙈", "😅", "🔥", "🫠"]))"
            case 810..<845:
                return link(photo(), around: true)
            case 845..<855:
                return link(gif(), around: random.chance(50))
            case 855..<865:
                return link(giphy(), around: random.chance(50))
            case 865..<877:
                return link(video(), around: true)
            case 877..<915:
                return link(page(), around: true)
            case 915..<925:
                return mix == .text
                    ? phrase(8...16)
                    : "\(phrase(2...6)) \(page()) and \(photo())"
            default:
                return phrase(4...10)
            }
        }

        /// `url`, with words around it when asked; in the `text` mix,
        /// words of about the same length instead.
        private mutating func link(_ url: String, around: Bool) -> String {
            let body = mix == .text ? phrase(2...4) : url
            return around ? "\(phrase(2...7)) \(body)" : body
        }

        private mutating func photo() -> String {
            photoCount += 1
            return "https://\(ScrollBenchmarkContent.photoHost)/p/\(photoCount).jpg"
        }

        private mutating func gif() -> String {
            gifCount += 1
            return "https://\(ScrollBenchmarkContent.gifHost)/gifs/\(gifCount).gif"
        }

        private mutating func giphy() -> String {
            giphyCount += 1
            return "https://media.giphy.com/media/BenchGif\(String(format: "%04d", giphyCount))/giphy.gif"
        }

        private mutating func video() -> String {
            videoCount += 1
            return "https://www.youtube.com/watch?v=bench\(String(format: "%06d", videoCount))"
        }

        private mutating func page() -> String {
            pageCount += 1
            let host = ScrollBenchmarkContent.pageHosts[pageCount % ScrollBenchmarkContent.pageHosts.count]
            return "https://\(host)/articles/\(pageCount)-\(random.pick(Self.pageTitles))"
        }

        private mutating func membershipLine(at time: Date) -> ChatLine {
            let nick = random.pick(Self.nicks)
            let userHost = "\(nick)@user/\(nick)"
            switch random.int(3) {
            case 0:
                return ChatLine(time: time, kind: .join, nick: nick, userHost: userHost,
                                text: "\(nick) (\(userHost)) joined \(ScrollBenchmarkContent.channelName)", isHistory: true)
            case 1:
                return ChatLine(time: time, kind: .part, nick: nick, userHost: userHost,
                                text: "\(nick) left \(ScrollBenchmarkContent.channelName)", isHistory: true)
            default:
                return ChatLine(time: time, kind: .quit, nick: nick, userHost: userHost,
                                text: "\(nick) quit (\(random.pick(["Ping timeout: 240 seconds", "Quit: bye", "Read error: Connection reset by peer"])))",
                                isHistory: true)
            }
        }

        /// A netsplit: everyone quits within a few seconds, a couple of
        /// lines pass, and they all come back. Collapsed into long runs.
        private mutating func appendNetsplit(to lines: inout [ChatLine], at time: inout Date) {
            let split = Self.nicks.shuffledDeterministically(&random)
            for nick in split {
                time = time.addingTimeInterval(0.05)
                lines.append(ChatLine(time: time, kind: .quit, nick: nick, userHost: "\(nick)@user/\(nick)",
                                      text: "\(nick) quit (*.net *.split)", isHistory: true))
            }
            for nick in split {
                time = time.addingTimeInterval(0.08)
                lines.append(ChatLine(time: time, kind: .join, nick: nick, userHost: "\(nick)@user/\(nick)",
                                      text: "\(nick) (\(nick)@user/\(nick)) joined \(ScrollBenchmarkContent.channelName)", isHistory: true))
            }
        }
    }
}

private extension Array {
    /// The elements in an order picked by `random` (Fisher–Yates).
    nonisolated func shuffledDeterministically(_ random: inout ScrollBenchmarkContent.Random) -> [Element] {
        var result = self
        guard result.count > 1 else { return result }
        for index in stride(from: result.count - 1, to: 0, by: -1) {
            result.swapAt(index, random.int(index + 1))
        }
        return result
    }
}
