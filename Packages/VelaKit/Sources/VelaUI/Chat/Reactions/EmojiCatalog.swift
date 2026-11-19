// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// A curated emoji set for the reaction picker. Names come from Unicode
/// character names (flags from the region name), plus common chat aliases
/// such as "+1", "lol" or "tada", so search works without a data file.
nonisolated enum EmojiCatalog {
    struct Category: Identifiable, Sendable {
        let id: String
        let title: String
        let systemImage: String
        let emoji: [String]
    }

    struct Entry: Sendable {
        let emoji: String
        let name: String
        /// Lowercased words searched by prefix.
        let words: [String]
    }

    static let categories: [Category] = [
        Category(id: "smileys", title: "Smileys & Emotion", systemImage: "face.smiling", emoji: split("""
            😀 😃 😄 😁 😆 😅 🤣 😂 🙂 🙃 🫠 😉 😊 😇 🥰 😍 🤩 😘 😗 ☺️ 😚 😙 🥲 😋 😛 😜 🤪 😝 🤑 🤗 🤭 🫢 🫣 🤫 🤔 🫡 \
            🤐 🤨 😐 😑 😶 🫥 😏 😒 🙄 😬 😮‍💨 🤥 🫨 😌 😔 😪 🤤 😴 😷 🤒 🤕 🤢 🤮 🤧 🥵 🥶 🥴 😵 😵‍💫 🤯 🤠 🥳 🥸 \
            😎 🤓 🧐 😕 🫤 😟 🙁 ☹️ 😮 😯 😲 😳 🥺 🥹 😦 😧 😨 😰 😥 😢 😭 😱 😖 😣 😞 😓 😩 😫 🥱 😤 😡 😠 🤬 \
            😈 👿 💀 ☠️ 💩 🤡 👹 👺 👻 👽 👾 🤖 😺 😸 😹 😻 😼 😽 🙀 😿 😾 🙈 🙉 🙊 💋 💌 💘 💝 💖 💗 💓 💞 💕 \
            💟 ❣️ 💔 ❤️‍🔥 ❤️‍🩹 ❤️ 🩷 🧡 💛 💚 💙 🩵 💜 🤎 🖤 🩶 🤍 💯 💢 💥 💫 💦 💨 💬 💭 💤
            """)),
        Category(id: "people", title: "People & Body", systemImage: "hand.wave", emoji: split("""
            👋 🤚 🖐️ ✋ 🖖 🫱 🫲 🫳 🫴 👌 🤌 🤏 ✌️ 🤞 🫰 🤟 🤘 🤙 👈 👉 👆 👇 ☝️ 🫵 👍 👎 ✊ 👊 🤛 🤜 👏 🙌 🫶 👐 \
            🤲 🤝 🙏 ✍️ 💅 🤳 💪 🦾 🦿 🦵 🦶 👂 🦻 👃 🧠 🫀 🫁 🦷 🦴 👀 👁️ 👅 👄 🫦 👶 🧒 👦 👧 🧑 👱 👨 🧔 👩 \
            🧓 👴 👵 🙍 🙎 🙅 🙆 💁 🙋 🧏 🙇 🤦 🤷 🧑‍💻 🧑‍🔬 🧑‍🎨 🧑‍🚀 🧑‍🍳 🧑‍🏫 🧑‍🔧 🥷 🦸 🦹 🧙 🧚 🧛 🧜 🧝 🧞 🧟 💃 🕺 \
            🚶 🏃 🧘 👯 🗣️ 👤 👥 🫂
            """)),
        Category(id: "nature", title: "Animals & Nature", systemImage: "leaf", emoji: split("""
            🐶 🐱 🐭 🐹 🐰 🦊 🐻 🐼 🐻‍❄️ 🐨 🐯 🦁 🐮 🐷 🐸 🐵 🐔 🐧 🐦 🐤 🦆 🦅 🦉 🦇 🐺 🐗 🐴 🦄 🐝 🪱 🐛 🦋 🐌 🐞 \
            🐜 🪲 🦗 🕷️ 🦂 🐢 🐍 🦎 🦖 🦕 🐙 🦑 🦐 🦞 🦀 🪼 🐡 🐠 🐟 🐬 🐳 🐋 🦈 🦭 🐊 🐅 🐆 🦓 🦍 🦧 🐘 🦛 🦏 🐪 \
            🦒 🦘 🦬 🐃 🐄 🐎 🐖 🐑 🦙 🐐 🦌 🐕 🐩 🐈 🐈‍⬛ 🪶 🐓 🦃 🦚 🦜 🦢 🦩 🕊️ 🐇 🦝 🦨 🦡 🦫 🦦 🦥 🐁 🐿️ 🦔 \
            🐾 🐉 🐲 🌵 🎄 🌲 🌳 🌴 🪵 🌱 🌿 ☘️ 🍀 🪴 🍃 🍂 🍁 🍄 🐚 🪸 🪨 🌾 💐 🌷 🌹 🥀 🪷 🌺 🌸 🌼 🌻 🌞 🌝 🌚 \
            🌕 🌗 🌑 🌙 🌎 🌍 🌏 🪐 ⭐ 🌟 ✨ ⚡ ☄️ 🔥 🌪️ 🌈 ☀️ 🌤️ ⛅ ☁️ 🌧️ ⛈️ 🌩️ 🌨️ ❄️ ☃️ ⛄ 🌬️ 💧 🫧 ☔ 🌊 🌫️
            """)),
        Category(id: "food", title: "Food & Drink", systemImage: "fork.knife", emoji: split("""
            🍏 🍎 🍐 🍊 🍋 🍌 🍉 🍇 🍓 🫐 🍈 🍒 🍑 🥭 🍍 🥥 🥝 🍅 🍆 🥑 🫛 🥦 🥬 🥒 🌶️ 🫑 🌽 🥕 🫒 🧄 🧅 🥔 🍠 🥐 \
            🥯 🍞 🥖 🥨 🧀 🥚 🍳 🧈 🥞 🧇 🥓 🥩 🍗 🍖 🌭 🍔 🍟 🍕 🫓 🥪 🥙 🧆 🌮 🌯 🫔 🥗 🥘 🫕 🥫 🍝 🍜 🍲 🍛 🍣 \
            🍱 🥟 🦪 🍤 🍙 🍚 🍘 🍥 🥠 🥮 🍢 🍡 🍧 🍨 🍦 🥧 🧁 🍰 🎂 🍮 🍭 🍬 🍫 🍿 🍩 🍪 🌰 🥜 🍯 🥛 🍼 🫖 ☕ 🍵 \
            🧃 🥤 🧋 🍶 🍺 🍻 🥂 🍷 🥃 🍸 🍹 🧉 🍾 🧊 🥄 🍴 🍽️ 🥣 🥡 🥢 🧂
            """)),
        Category(id: "activities", title: "Activities", systemImage: "soccerball", emoji: split("""
            ⚽ 🏀 🏈 ⚾ 🥎 🎾 🏐 🏉 🥏 🎱 🪀 🏓 🏸 🏒 🏑 🥍 🏏 🪃 🥅 ⛳ 🪁 🏹 🎣 🤿 🥊 🥋 🎽 🛹 🛼 🛷 ⛸️ 🥌 🎿 ⛷️ \
            🏂 🪂 🏋️ 🤸 ⛹️ 🤺 🏌️ 🏇 🏄 🏊 🚣 🧗 🚵 🚴 🏆 🥇 🥈 🥉 🏅 🎖️ 🎗️ 🎫 🎟️ 🎪 🤹 🎭 🩰 🎨 🎬 🎤 🎧 🎼 🎹 \
            🥁 🪘 🎷 🎺 🪗 🎸 🪕 🎻 🪈 🎲 ♟️ 🎯 🎳 🎮 🕹️ 🎰 🧩 🎉 🎊 🎈 🎁 🎀 🪅 🪩
            """)),
        Category(id: "travel", title: "Travel & Places", systemImage: "car", emoji: split("""
            🚗 🚕 🚙 🚌 🚎 🏎️ 🚓 🚑 🚒 🚐 🛻 🚚 🚛 🚜 🛴 🚲 🛵 🏍️ 🛺 🚨 🚔 🚍 🚘 🚖 🚡 🚠 🚃 🚋 🚝 🚄 🚅 🚈 🚂 🚆 \
            🚇 🚊 🚉 ✈️ 🛫 🛬 🛩️ 💺 🛰️ 🚀 🛸 🚁 🛶 ⛵ 🚤 🛥️ 🛳️ ⛴️ 🚢 ⚓ 🛟 ⛽ 🚧 🚦 🚥 🚏 🗺️ 🗿 🗽 🗼 🏰 🏯 🏟️ 🎡 \
            🎢 🎠 ⛲ ⛱️ 🏖️ 🏝️ 🏜️ 🌋 ⛰️ 🏔️ 🗻 🏕️ ⛺ 🏠 🏡 🏘️ 🏚️ 🏗️ 🏭 🏢 🏬 🏣 🏥 🏦 🏨 🏪 🏫 💒 🏛️ ⛪ 🕌 🕍 🛕 \
            ⛩️ 🛤️ 🛣️ 🗾 🏞️ 🌅 🌄 🌠 🎇 🎆 🌇 🌆 🏙️ 🌃 🌌 🌉 🌁
            """)),
        Category(id: "objects", title: "Objects", systemImage: "lightbulb", emoji: split("""
            ⌚ 📱 💻 ⌨️ 🖥️ 🖨️ 🖱️ 💽 💾 💿 📀 📼 📷 📸 📹 🎥 📽️ 🎞️ 📞 ☎️ 📟 📠 📺 📻 🎙️ 🎚️ 🎛️ 🧭 ⏱️ ⏲️ ⏰ 🕰️ ⌛ ⏳ \
            📡 🔋 🪫 🔌 💡 🔦 🕯️ 🧯 🛢️ 💸 💵 💴 💶 💷 🪙 💰 💳 💎 ⚖️ 🪜 🧰 🪛 🔧 🔨 ⚒️ 🛠️ ⛏️ 🪚 🔩 ⚙️ 🧱 ⛓️ 🧲 💣 \
            🧨 🪓 🔪 🗡️ ⚔️ 🛡️ ⚰️ 🏺 🔮 📿 🧿 💈 ⚗️ 🔭 🔬 🩹 🩺 💊 💉 🩸 🧬 🦠 🧫 🧪 🌡️ 🧹 🧺 🧻 🚽 🚿 🛁 🧼 🪥 🧽 \
            🧴 🛎️ 🔑 🗝️ 🚪 🪑 🛋️ 🛏️ 🧸 🪆 🖼️ 🪞 🪟 🛍️ 🛒 🪄 🏮 🧧 ✉️ 📩 📨 📧 📥 📤 📦 🏷️ 📪 📫 📬 📭 📮 📜 📃 \
            📄 📑 🧾 📊 📈 📉 🗒️ 🗓️ 📆 📅 🗑️ 📇 🗃️ 🗳️ 🗄️ 📋 📁 📂 🗂️ 🗞️ 📰 📓 📔 📒 📕 📗 📘 📙 📚 📖 🔖 🧷 🔗 📎 \
            🖇️ 📐 📏 🧮 📌 📍 ✂️ 🖊️ 🖋️ ✒️ 🖌️ 🖍️ 📝 ✏️ 🔍 🔎 🔏 🔐 🔒 🔓
            """)),
        Category(id: "symbols", title: "Symbols", systemImage: "number", emoji: split("""
            ✅ ☑️ ✔️ ❌ ❎ ➕ ➖ ➗ ✖️ 🟰 ♾️ ‼️ ⁉️ ❓ ❔ ❗ ❕ ⚠️ 🚸 ⛔ 🚫 🛑 📛 🔞 📵 🚭 ♻️ 🔰 ⚜️ 🔱 〽️ ✳️ ✴️ ❇️ \
            💠 🌀 🌐 🏧 ♿ 🅿️ 🚻 🚮 📶 ℹ️ 🔤 🔡 🔠 🆗 🆙 🆒 🆕 🆓 🆘 🆚 0️⃣ 1️⃣ 2️⃣ 3️⃣ 4️⃣ 5️⃣ 6️⃣ 7️⃣ 8️⃣ 9️⃣ 🔟 🔢 #️⃣ *️⃣ \
            ▶️ ⏸️ ⏯️ ⏹️ ⏺️ ⏭️ ⏮️ ⏩ ⏪ ⏫ ⏬ ◀️ 🔼 🔽 ➡️ ⬅️ ⬆️ ⬇️ ↗️ ↘️ ↙️ ↖️ ↕️ ↔️ ↪️ ↩️ ⤴️ ⤵️ 🔀 🔁 🔂 🔄 🔃 🎵 🎶 \
            💲 💱 ™️ ©️ ®️ 〰️ ➰ ➿ 🔚 🔙 🔛 🔝 🔜 🔘 🔴 🟠 🟡 🟢 🔵 🟣 ⚫ ⚪ 🟤 🔺 🔻 🔸 🔹 🔶 🔷 🔳 🔲 🟥 🟧 🟨 🟩 \
            🟦 🟪 ⬛ ⬜ 🟫 🔈 🔇 🔉 🔊 🔔 🔕 📣 📢 ♠️ ♣️ ♥️ ♦️ 🃏 🎴 🀄 ☮️ ☯️ ⚛️ ☢️ ☣️ ♈ ♉ ♊ ♋ ♌ ♍ ♎ ♏ ♐ ♑ ♒ ♓
            """)),
        Category(id: "flags", title: "Flags", systemImage: "flag", emoji: split("""
            🏁 🚩 🎌 🏴 🏳️ 🏳️‍🌈 🏳️‍⚧️ 🏴‍☠️ 🇺🇳 🇪🇺 🇦🇷 🇦🇺 🇦🇹 🇧🇪 🇧🇷 🇨🇦 🇨🇱 🇨🇳 🇨🇴 🇨🇿 🇩🇰 🇪🇬 🇫🇮 🇫🇷 🇩🇪 🇬🇷 🇭🇰 🇭🇺 🇮🇸 \
            🇮🇳 🇮🇩 🇮🇪 🇮🇱 🇮🇹 🇯🇵 🇰🇪 🇰🇷 🇲🇽 🇳🇱 🇳🇿 🇳🇬 🇳🇴 🇵🇰 🇵🇪 🇵🇭 🇵🇱 🇵🇹 🇷🇴 🇸🇦 🇿🇦 🇪🇸 🇸🇪 🇨🇭 🇹🇼 🇹🇭 🇹🇷 🇺🇦 \
            🇦🇪 🇬🇧 🇺🇸 🇻🇳
            """)),
    ]

    /// Chat-friendly aliases for popular emoji.
    static let aliases: [String: String] = [
        "👍": "+1 thumbsup yes like ok agree", "👎": "-1 thumbsdown no dislike disagree",
        "❤️": "heart love", "😂": "lol laugh joy haha", "🤣": "rofl lol laugh lmao",
        "🎉": "tada party celebrate hooray congrats", "🔥": "fire lit hot", "👀": "eyes look see watching",
        "🙏": "pray thanks please thank you", "✅": "check done yes ok complete", "😍": "love heart eyes",
        "🚀": "rocket launch ship", "💯": "100 hundred perfect", "😭": "cry sob", "🤔": "thinking hmm",
        "👏": "clap applause bravo", "🙌": "hooray raised hands praise yay", "😅": "sweat smile phew",
        "😊": "blush smile happy", "😢": "sad cry tear", "😮": "wow surprised", "🤯": "mind blown exploding",
        "🥳": "party celebrate birthday", "🍿": "popcorn drama", "☕": "coffee tea", "🐛": "bug",
        "⭐": "star favorite", "✨": "sparkles shiny new", "💜": "purple heart", "👋": "wave hello hi bye",
        "🤷": "shrug dunno", "🤦": "facepalm", "😎": "cool sunglasses", "🙂": "smile", "🙃": "upside down",
        "😉": "wink", "😬": "grimace awkward yikes", "🫡": "salute", "🤝": "handshake deal agree",
        "💪": "strong muscle flex", "🎯": "target bullseye", "🧠": "brain smart", "💡": "idea lightbulb",
        "⚠️": "warning caution", "❌": "x no cross wrong fail", "🚢": "ship it", "🍕": "pizza", "🍺": "beer",
        "💀": "skull dead dying", "😱": "scream shocked", "😡": "angry mad rage", "🫠": "melting",
        "🥲": "smile tear", "🤗": "hug", "😴": "sleep zzz tired", "🤓": "nerd geek", "🐧": "linux penguin tux",
        "🦀": "rust crab", "🐍": "python snake", "🌊": "wave ocean sea", "🔭": "telescope space",
        "🐞": "bug ladybug", "🫶": "heart hands love", "😁": "grin", "😀": "grin smile", "😆": "laugh",
        "🥺": "pleading puppy eyes", "😤": "huff triumph", "🤌": "pinch chef kiss", "👌": "ok perfect",
        "✌️": "peace victory", "🤞": "fingers crossed luck", "🆗": "ok", "➕": "plus add", "🔗": "link",
        "📌": "pin pushpin", "🗑️": "trash delete", "🔒": "lock secure", "🍻": "cheers beers",
        "🥂": "cheers champagne toast", "🎂": "cake birthday", "🌈": "rainbow pride", "☀️": "sun sunny",
        "🌙": "moon night", "⚡": "lightning zap fast", "💤": "zzz sleep", "🤖": "robot bot",
        "👻": "ghost boo", "💩": "poop", "🤡": "clown", "🙈": "see no evil monkey", "🙊": "speak no evil monkey",
    ]

    static let defaultFrequent = ["👍", "❤️", "😂", "🎉", "👀", "🙏", "🔥", "✅", "😮", "😢", "🚀", "💯", "🙌", "🤔", "👏", "😅"]

    static let entries: [String: Entry] = {
        var result: [String: Entry] = [:]
        for category in categories {
            for emoji in category.emoji where result[emoji] == nil {
                let name = displayName(for: emoji)
                let aliasWords = (aliases[emoji] ?? "").split(separator: " ").map(String.init)
                let words = (name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init) + aliasWords)
                result[emoji] = Entry(emoji: emoji, name: name, words: words)
            }
        }
        return result
    }()

    /// Emoji whose name or aliases start with every word of `query`, in catalog order.
    static func search(_ query: String) -> [String] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return [] }
        var seen = Set<String>()
        var results: [String] = []
        for category in categories {
            for emoji in category.emoji where !seen.contains(emoji) {
                guard let entry = entries[emoji] else { continue }
                let matches = terms.allSatisfy { term in entry.words.contains { $0.hasPrefix(term) } }
                if matches {
                    seen.insert(emoji)
                    results.append(emoji)
                }
            }
        }
        return results
    }

    /// "Thumbs Up Sign", "Flag: Japan"…
    static func displayName(for emoji: String) -> String {
        let scalars = Array(emoji.unicodeScalars)
        let indicators = scalars.filter { (0x1F1E6...0x1F1FF).contains($0.value) }
        if indicators.count == 2 {
            let code = String(String.UnicodeScalarView(indicators.compactMap { Unicode.Scalar($0.value - 0x1F1E6 + 0x41) }))
            return "Flag: " + (Locale.current.localizedString(forRegionCode: code) ?? code)
        }
        let ignored: Set<UInt32> = [0x200D, 0xFE0F, 0xFE0E, 0x20E3]
        let names = scalars.filter { !ignored.contains($0.value) }.compactMap { $0.properties.name }
        guard !names.isEmpty else { return emoji }
        return names.joined(separator: " ").lowercased().capitalized
    }

    private static func split(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }
}

/// Recently used reactions, most recent first. Stored in UserDefaults: it's
/// usage history, not a preference, so it stays out of settings.json.
enum EmojiRecents {
    private static let key = "Vela.recentEmoji"
    private static let limit = 24

    /// `frequent`, kept until the next `record`: the hover toolbar asks
    /// every time it's built.
    private static var cachedFrequent: [String]?

    static var recent: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func record(_ emoji: String) {
        var list = recent.filter { $0 != emoji }
        list.insert(emoji, at: 0)
        UserDefaults.standard.set(Array(list.prefix(limit)), forKey: key)
        cachedFrequent = nil
    }

    /// Recent emoji topped up with popular defaults.
    static func frequent(count: Int = 16) -> [String] {
        if let cachedFrequent { return Array(cachedFrequent.prefix(count)) }
        var result = recent
        for emoji in EmojiCatalog.defaultFrequent where !result.contains(emoji) {
            result.append(emoji)
        }
        cachedFrequent = result
        return Array(result.prefix(count))
    }
}
