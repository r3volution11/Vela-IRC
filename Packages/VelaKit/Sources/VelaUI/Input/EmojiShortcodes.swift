// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// A curated set of `:shortcode:` emoji for the composer: Tab completes a
/// partial `:code`, and typing a complete `:code:` turns into the emoji.
/// Names follow the common Slack/GitHub/Discord spellings.
nonisolated enum EmojiShortcodes {
    /// Ordered roughly by popularity, so completion offers likely ones first.
    static let all: [(code: String, emoji: String)] = [
        ("thumbsup", "👍"), ("+1", "👍"), ("heart", "❤️"), ("joy", "😂"), ("smile", "😄"), ("tada", "🎉"),
        ("pray", "🙏"), ("fire", "🔥"), ("eyes", "👀"), ("rocket", "🚀"), ("thinking", "🤔"), ("wave", "👋"),
        ("ok_hand", "👌"), ("clap", "👏"), ("100", "💯"), ("sob", "😭"), ("sweat_smile", "😅"), ("wink", "😉"),
        ("slightly_smiling_face", "🙂"), ("grinning", "😀"), ("laughing", "😆"), ("rofl", "🤣"), ("blush", "😊"),
        ("heart_eyes", "😍"), ("sunglasses", "😎"), ("smirk", "😏"), ("upside_down", "🙃"), ("relieved", "😌"),
        ("yum", "😋"), ("stuck_out_tongue", "😛"), ("zany_face", "🤪"), ("star_struck", "🤩"), ("hugs", "🤗"),
        ("shrug", "🤷"), ("facepalm", "🤦"), ("raised_hands", "🙌"), ("muscle", "💪"), ("thumbsdown", "👎"),
        ("-1", "👎"), ("point_up", "☝️"), ("point_right", "👉"), ("point_left", "👈"), ("v", "✌️"),
        ("crossed_fingers", "🤞"), ("handshake", "🤝"), ("salute", "🫡"), ("melting_face", "🫠"),
        ("neutral_face", "😐"), ("expressionless", "😑"), ("unamused", "😒"), ("roll_eyes", "🙄"),
        ("grimacing", "😬"), ("confused", "😕"), ("worried", "😟"), ("frowning", "☹️"), ("cry", "😢"),
        ("scream", "😱"), ("flushed", "😳"), ("open_mouth", "😮"), ("astonished", "😲"), ("sleeping", "😴"),
        ("sleepy", "😪"), ("yawning_face", "🥱"), ("rage", "😡"), ("angry", "😠"), ("triumph", "😤"),
        ("skull", "💀"), ("ghost", "👻"), ("clown", "🤡"), ("nerd", "🤓"), ("partying_face", "🥳"),
        ("pleading_face", "🥺"), ("innocent", "😇"), ("mask", "😷"), ("nauseated_face", "🤢"),
        ("exploding_head", "🤯"), ("zipper_mouth", "🤐"), ("shushing_face", "🤫"), ("monocle", "🧐"),
        ("saluting_face", "🫡"), ("see_no_evil", "🙈"), ("hear_no_evil", "🙉"), ("speak_no_evil", "🙊"),
        ("sparkles", "✨"), ("star", "⭐"), ("zap", "⚡"), ("boom", "💥"), ("dizzy", "💫"), ("rainbow", "🌈"),
        ("sunny", "☀️"), ("cloud", "☁️"), ("snowflake", "❄️"), ("umbrella", "☔"), ("crescent_moon", "🌙"),
        ("earth_americas", "🌎"), ("ocean", "🌊"), ("seedling", "🌱"), ("cactus", "🌵"), ("rose", "🌹"),
        ("cherry_blossom", "🌸"), ("four_leaf_clover", "🍀"), ("purple_heart", "💜"), ("blue_heart", "💙"),
        ("green_heart", "💚"), ("yellow_heart", "💛"), ("orange_heart", "🧡"), ("black_heart", "🖤"),
        ("white_heart", "🤍"), ("broken_heart", "💔"), ("sparkling_heart", "💖"), ("two_hearts", "💕"),
        ("white_check_mark", "✅"), ("heavy_check_mark", "✔️"), ("x", "❌"), ("warning", "⚠️"),
        ("no_entry", "⛔"), ("question", "❓"), ("exclamation", "❗"), ("bangbang", "‼️"), ("bulb", "💡"),
        ("lock", "🔒"), ("key", "🔑"), ("bell", "🔔"), ("mag", "🔍"), ("link", "🔗"), ("hammer", "🔨"),
        ("wrench", "🔧"), ("gear", "⚙️"), ("bug", "🐛"), ("computer", "💻"), ("keyboard", "⌨️"),
        ("floppy_disk", "💾"), ("package", "📦"), ("memo", "📝"), ("books", "📚"), ("pushpin", "📌"),
        ("calendar", "📅"), ("chart_with_upwards_trend", "📈"), ("hourglass", "⌛"), ("alarm_clock", "⏰"),
        ("coffee", "☕"), ("tea", "🍵"), ("beer", "🍺"), ("beers", "🍻"), ("wine_glass", "🍷"), ("pizza", "🍕"),
        ("hamburger", "🍔"), ("taco", "🌮"), ("popcorn", "🍿"), ("cookie", "🍪"), ("cake", "🍰"),
        ("birthday", "🎂"), ("apple", "🍎"), ("avocado", "🥑"), ("doughnut", "🍩"), ("gift", "🎁"),
        ("balloon", "🎈"), ("confetti_ball", "🎊"), ("trophy", "🏆"), ("medal", "🏅"), ("crown", "👑"),
        ("gem", "💎"), ("moneybag", "💰"), ("video_game", "🎮"), ("musical_note", "🎵"), ("headphones", "🎧"),
        ("guitar", "🎸"), ("art", "🎨"), ("camera", "📷"), ("movie_camera", "🎥"), ("tv", "📺"),
        ("telescope", "🔭"), ("satellite", "🛰️"), ("airplane", "✈️"), ("car", "🚗"), ("bike", "🚲"),
        ("ship", "🚢"), ("house", "🏠"), ("cat", "🐱"), ("dog", "🐶"), ("fox", "🦊"), ("panda", "🐼"),
        ("penguin", "🐧"), ("unicorn", "🦄"), ("crab", "🦀"), ("snake", "🐍"), ("turtle", "🐢"), ("bee", "🐝"),
        ("butterfly", "🦋"), ("octopus", "🐙"), ("whale", "🐳"), ("dragon", "🐉"), ("sloth", "🦥"),
        ("parrot", "🦜"), ("owl", "🦉"), ("frog", "🐸"), ("monkey", "🐒"), ("poop", "💩"), ("robot", "🤖"),
        ("alien", "👽"), ("point_down", "👇"),
    ]

    private static let table: [String: String] = {
        var table: [String: String] = [:]
        for (code, emoji) in all where table[code] == nil {
            table[code] = emoji
        }
        return table
    }()

    /// The emoji for `code` (without colons), if it's in the set.
    static func emoji(for code: String) -> String? {
        table[code.lowercased()]
    }

    /// Emoji whose shortcode starts with `prefix` (without the leading colon),
    /// most popular first, without repeating an emoji.
    static func completions(forPrefix prefix: String) -> [(code: String, emoji: String)] {
        let needle = prefix.lowercased()
        guard !needle.isEmpty else { return [] }
        var seen = Set<String>()
        var exact: [(String, String)] = []
        var rest: [(String, String)] = []
        for entry in all where entry.code.hasPrefix(needle) {
            guard seen.insert(entry.emoji).inserted else { continue }
            if entry.code == needle { exact.append(entry) } else { rest.append(entry) }
        }
        return exact + rest
    }
}
