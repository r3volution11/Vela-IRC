// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaFoundation
import VelaIRC
import VelaStore

/// Sample networks, channels and conversations shown in demo mode
/// (`-VelaDemoMode YES`) and SwiftUI previews. Nothing connects.
enum DemoContent {
    static func populate(_ app: AppModel) {
        let libera = makeSession(name: "Libera.Chat", host: "irc.libera.chat", nick: "doug")
        let oftc = makeSession(name: "OFTC", host: "irc.oftc.net", nick: "doug")
        let soju = makeSession(name: "Ergo Testnet", host: "testnet.ergo.chat", nick: "doug")

        populateLibera(libera)
        populateOFTC(oftc)
        populateErgo(soju)
        oftc.connectionState = .disconnected

        app.installDemoSessions([libera, oftc, soju])
        applyDemoMediaSettings(app, libera: libera)
    }

    /// Demo-only media settings (written to the demo's throwaway settings
    /// file; `--set` can still override them): a site rule that blocks
    /// `blocked.example`, linked in #media, and #vela-offtopic blurred.
    /// `nsfw.example`, also linked in #media, is a demo-only adult domain
    /// (`AppModel.previewContext(for:)`).
    private static func applyDemoMediaSettings(_ app: AppModel, libera: NetworkSession) {
        app.settings[.mediaSiteRules] = ["blocked.example": .string("block")]
        if let offtopic = libera.buffer(named: "#vela-offtopic") {
            app.settings[.mediaBlurredBuffers] = [offtopic.id.description]
            // Its Spanish, Japanese and German lines show translations.
            app.settings[.translationAutoTranslate] = [offtopic.id.description]
        }
    }

    private static func makeSession(name: String, host: String, nick: String) -> NetworkSession {
        let config = NetworkConfig(name: name, host: host, nick: nick)
        let session = NetworkSession(config: config, database: nil)
        session.connectionState = .connected
        session.nick = nick
        session.capabilities = ["server-time", "message-tags", "echo-message", "batch", "draft/chathistory", "away-notify", "draft/message-redaction"]
        var support = ISupport()
        support.apply(["PREFIX=(qaohv)~&@%+", "CHANTYPES=#", "NETWORK=\(name)", "CASEMAPPING=rfc1459"])
        session.isupport = support
        return session
    }

    private static func time(_ minutesAgo: Double) -> Date {
        Date().addingTimeInterval(-minutesAgo * 60)
    }

    private static func say(
        _ nick: String,
        _ text: String,
        _ minutesAgo: Double,
        kind: ChatLineKind = .message,
        msgid: String? = nil,
        isSelf: Bool = false,
        highlight: Bool = false,
        replyTo: String? = nil
    ) -> ChatLine {
        ChatLine(
            msgid: msgid ?? UUID().uuidString,
            time: time(minutesAgo),
            kind: kind,
            nick: nick,
            userHost: "\(nick)@user/\(nick)",
            text: text,
            isSelf: isSelf,
            isHighlight: highlight,
            replyTo: replyTo,
            isHistory: true
        )
    }

    private static func event(_ kind: ChatLineKind, _ nick: String, _ text: String, _ minutesAgo: Double) -> ChatLine {
        ChatLine(time: time(minutesAgo), kind: kind, nick: nick, userHost: "\(nick)@user/\(nick)", text: text, isHistory: true)
    }

    private static func members(_ names: [(String, String)], in buffer: BufferModel, session: NetworkSession) {
        var map: [String: Member] = [:]
        for (prefix, nick) in names {
            map[session.fold(nick)] = Member(nick: nick, prefixes: prefix, userHost: "\(nick)@user/\(nick)", isAway: nick.hasSuffix("_away"))
        }
        buffer.replaceMembers(map)
        buffer.isJoined = true
    }

    private static func populateLibera(_ session: NetworkSession) {
        session.info("Connected as doug", in: session.serverBuffer)
        session.info("Welcome to the Libera.Chat Internet Relay Chat Network doug", in: session.serverBuffer)
        session.info("- Libera.Chat is a free and open source community.", in: session.serverBuffer, kind: .motd)

        let vela = session.ensureBuffer(name: "#vela", kind: .channel, persist: false)
        vela.topic = "Vela — a modern, deeply themable IRC client for macOS · https://github.com/r3volution11/Vela-IRC"
        vela.topicSetBy = "doug"
        members([
            ("~", "doug"), ("@", "marisol"), ("@", "kenji"), ("+", "ada"), ("+", "theo"),
            ("", "priya"), ("", "lukas"), ("", "nadia"), ("", "oskar_away"), ("", "wren"),
        ], in: vela, session: session)

        let lines: [ChatLine] = [
            event(.join, "priya", "priya (priya@user/priya) joined #vela", 182),
            say("marisol", "morning all ☕", 180),
            say("kenji", "o/ — the new theme engine landed on main last night", 179),
            say("kenji", "every surface reads from tokens now, even the title bar", 179),
            say("ada", "Palenight looks *so* good with the grouped layout", 176, msgid: "demo-ada-1"),
            event(.join, "lukas", "lukas (lukas@user/lukas) joined #vela", 170),
            event(.join, "nadia", "nadia (nadia@user/nadia) joined #vela", 169),
            event(.part, "wren", "wren left #vela (brb)", 168),
            event(.join, "wren", "wren (wren@user/wren) joined #vela", 166),
            say("theo", "here's the reference shot of the Crab Nebula I was talking about", 62),
            say("theo", "https://upload.wikimedia.org/wikipedia/commons/thumb/0/00/Crab_Nebula.jpg/1280px-Crab_Nebula.jpg", 62, msgid: "demo-theo-img"),
            say("priya", "gorgeous. that's the vibe for the Ocean theme", 60, replyTo: "demo-theo-img"),
            say("doug", "pushed the IRCv3 spec notes → https://ircv3.net/irc/", 45, msgid: "demo-doug-link", isSelf: true),
            say("lukas", "nice, chathistory + reactions are the big ones for me", 44),
            say("marisol", "has anyone tried the Blender open movie embed? https://www.youtube.com/watch?v=aqz-KE-bpKQ", 30, msgid: "demo-yt"),
            say("kenji", "plays inline, and the facade means no web view until you click ▶", 29, replyTo: "demo-yt"),
            say("ada", "spinning earth for no reason https://upload.wikimedia.org/wikipedia/commons/thumb/e/e1/Rotating_earth_animated.gif/250px-Rotating_earth_animated.gif", 20, msgid: "demo-gif"),
            say("nadia", "reads the release notes", 12, kind: .action),
            say("wren", "doug: can you review the sidebar rail PR when you get a sec?", 6, msgid: "demo-highlight", highlight: true),
            say("doug", "on it 👍", 5, isSelf: true),
            say("theo", "also the Swift blog has a post on the new concurrency defaults: https://www.swift.org/blog/", 2),
        ]
        vela.insertSorted(lines)
        vela.setReaction(msgid: "demo-ada-1", nick: "theo", emoji: "💜", active: true)
        vela.setReaction(msgid: "demo-ada-1", nick: "priya", emoji: "💜", active: true)
        vela.setReaction(msgid: "demo-ada-1", nick: "doug", emoji: "💜", active: true)
        vela.setReaction(msgid: "demo-theo-img", nick: "lukas", emoji: "🔭", active: true)
        vela.setReaction(msgid: "demo-yt", nick: "ada", emoji: "🍿", active: true)
        vela.setReaction(msgid: "demo-yt", nick: "wren", emoji: "🍿", active: true)
        vela.setReaction(msgid: "demo-gif", nick: "kenji", emoji: "😂", active: true)
        vela.typingExpiry = ["lukas": Date().addingTimeInterval(3600)]
        vela.refreshTyping()

        let swift = session.ensureBuffer(name: "#swift", kind: .channel, persist: false)
        swift.topic = "Swift programming language · Be kind · https://swift.org"
        members([("@", "ChanServ"), ("@", "jorge"), ("+", "mina"), ("", "doug"), ("", "felix"), ("", "hana")], in: swift, session: session)
        swift.insertSorted([
            say("felix", "is there a way to make a struct nonisolated when the module defaults to MainActor?", 40),
            say("mina", "yep, `nonisolated struct Foo {}` works since 6.2", 39),
            say("felix", "oh perfect, thanks", 38),
            say("hana", "SE-0466 has all the details", 37),
        ])
        swift.unreadCount = 4

        // #macdev's two unread lines are GIFs from GIPHY and Tenor (the
        // website's media-gifs screenshot): NASA's own uploads, public domain.
        // Both are real and load when shown.
        let macdev = session.ensureBuffer(name: "#macdev", kind: .channel, persist: false)
        macdev.topic = "macOS development"
        members([("@", "sam"), ("", "doug"), ("", "irene")], in: macdev, session: session)
        macdev.insertSorted([
            say("irene", "anyone else seeing the new Liquid Glass sidebar fight custom backgrounds?", 90),
            say("sam", "use your own split view if you want full control over the chrome", 88),
            say("irene", "did that. the rewrite ships tonight https://giphy.com/gifs/nasa-space-rocket-launch-x4vlKY5ocArL3SeVVU", 12),
            say("sam", "nice. now it can have a background like this https://tenor.com/view/nasa-nasa-gifs-earth-space-station-space-gif-9368490", 9),
        ])
        macdev.unreadCount = 2
        macdev.highlightCount = 0

        populateMedia(session)

        let query = session.ensureBuffer(name: "marisol", kind: .query, persist: false)
        query.insertSorted([
            say("marisol", "hey! do you have a minute to look at the theme credits doc?", 15),
            say("doug", "sure, sending notes in a bit", 14, isSelf: true),
            say("marisol", "thank you 🙏", 13),
        ])
        query.unreadCount = 1
        query.highlightCount = 1
    }

    /// #media shows each kind of preview: a video player, an adult site's
    /// chip, a blocked site's chip (`applyDemoMediaSettings`) and, last so
    /// it's in view, a link card.
    /// #vela-offtopic is blurred, so its photo shows blurred until clicked.
    /// The video, article and photo are real and load when shown.
    private static func populateMedia(_ session: NetworkSession) {
        let media = session.ensureBuffer(name: "#media", kind: .channel, persist: false)
        media.topic = "Inline media testing · cards, players, site rules · keep it SFW"
        media.topicSetBy = "kenji"
        members([
            ("~", "doug"), ("@", "kenji"), ("+", "ada"), ("+", "theo"),
            ("", "marisol"), ("", "nadia"), ("", "wren"),
        ], in: media, session: session)
        media.insertSorted([
            event(.join, "nadia", "nadia (nadia@user/nadia) joined #media", 75),
            say("kenji", "preview sizes are split up now: links, videos and images each get their own setting", 52),
            say("ada", "same bunny as in #vela, but on Vimeo this time https://vimeo.com/1084537", 48, msgid: "demo-media-vimeo"),
            say("kenji", "▶ swaps the player in right there, and Expand fills the window", 47),
            say("wren", "a random nick just PMed me this, no idea what it is https://nsfw.example/gallery/2291", 30),
            say("doug", "the adult filter caught it before anything was fetched 👌", 29, isSelf: true),
            say("kenji", "and the spam domain from yesterday is back https://blocked.example/free-gift-card", 14),
            say("doug", "I added a site rule for that one, so it stays a chip", 13, isSelf: true),
            say("theo", "something nicer: ESO imaged a star cluster in Vela, so obviously I have to post it https://www.eso.org/public/news/eso2503/", 6, msgid: "demo-media-eso"),
            say("marisol", "link cards come in Minimal, Standard and Large now. Standard is the new default", 5),
        ])
        media.setReaction(msgid: "demo-media-eso", nick: "nadia", emoji: "🔭", active: true)
        media.setReaction(msgid: "demo-media-eso", nick: "ada", emoji: "🔭", active: true)
        media.setReaction(msgid: "demo-media-vimeo", nick: "wren", emoji: "🐰", active: true)

        let offtopic = session.ensureBuffer(name: "#vela-offtopic", kind: .channel, persist: false)
        offtopic.topic = "Off-topic chat for #vela · be nice"
        members([("@", "marisol"), ("", "doug"), ("", "kenji"), ("", "lukas"), ("", "priya"), ("", "wren")], in: offtopic, session: session)
        // The Spanish, Japanese and German lines are translated automatically
        // (`applyDemoMediaSettings`), with canned translations
        // (`CannedTranslator.demo()`, which must match them exactly).
        offtopic.insertSorted([
            event(.join, "lukas", "lukas (lukas@user/lukas) joined #vela-offtopic", 70),
            say("wren", "is it just me or is everyone in #vela talking about themes today", 66),
            say("marisol", "it's theme week, every week", 65),
            say("priya", "anyone else up late for the geomagnetic storm alerts?", 54),
            say("lukas", "clouds here. found this on Commons instead https://upload.wikimedia.org/wikipedia/commons/thumb/d/d3/Aurora_borealis_over_Eielson_Air_Force_Base%2C_Alaska.jpg/1280px-Aurora_borealis_over_Eielson_Air_Force_Base%2C_Alaska.jpg", 52),
            say("wren", "ok I need to move north", 50),
            say("priya", "the colours on that one 😍", 49),
            say("marisol", "¡Qué envidia! Aquí en Madrid el cielo estaba despejado, pero no se veía nada.", 46),
            say("kenji", "北海道でもオーロラが見えたらしいよ。写真を撮りに行けばよかったな。", 44),
            say("lukas", "Bei uns in Hamburg war es leider die ganze Nacht bewölkt.", 41),
            say("wren", "this channel went international overnight 🌍", 38),
        ])
    }

    private static func populateOFTC(_ session: NetworkSession) {
        session.info("Disconnected: Connection reset by peer", in: session.serverBuffer)
        let debian = session.ensureBuffer(name: "#debian", kind: .channel, persist: false)
        debian.topic = "Debian GNU/Linux support"
        debian.insertSorted([
            say("rafael", "apt full-upgrade went smoothly on trixie", 300),
            say("bea", "nice — any issues with the new kernel?", 298),
        ])
    }

    private static func populateErgo(_ session: NetworkSession) {
        session.info("Connected as doug", in: session.serverBuffer)
        let ergo = session.ensureBuffer(name: "#ergo", kind: .channel, persist: false)
        ergo.topic = "Ergo IRCd · IRCv3 testing ground"
        members([("@", "slingamn"), ("", "doug"), ("", "tester")], in: ergo, session: session)
        ergo.insertSorted([
            say("tester", "testing \u{02}bold\u{02}, \u{1D}italic\u{1D}, \u{1F}underline\u{1F} and \u{03}04red\u{03} \u{03}09,01green on black\u{03} formatting", 50),
            say("tester", "\u{11}monospace code()\u{11} and \u{1E}strikethrough\u{1E}", 49),
            say("slingamn", "reactions and typing indicators work here", 48, msgid: "demo-ergo-1"),
        ])
        ergo.setReaction(msgid: "demo-ergo-1", nick: "doug", emoji: "🎉", active: true)
    }
}
