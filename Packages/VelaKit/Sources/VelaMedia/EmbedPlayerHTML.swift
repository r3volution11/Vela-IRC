// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// The tiny page a `WKWebView` loads to play an embed.
///
/// Load it with `webView.loadHTMLString(html, baseURL: EmbedPlayerHTML.baseURL)`.
/// The https base URL gives the page an origin, so the iframe request carries
/// a `Referer` (YouTube refuses to play without one: error 153) and Twitch's
/// `parent` parameter matches the embedding host.
public enum EmbedPlayerHTML {
    public static let baseURL: URL = {
        guard let url = URL(string: "https://r3volution11.github.io/Vela-IRC/") else {
            preconditionFailure("Invalid embed base URL")
        }
        return url
    }()

    public static func html(for embed: EmbedInfo, autoplay: Bool) -> String {
        let src = escape(playerURL(for: embed, autoplay: autoplay).absoluteString)
        let title = escape(embed.title ?? "\(embed.provider.displayName) video")
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; frame-src https:">
        <title>\(title)</title>
        <style>
        html, body { margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden; background: #000; }
        iframe { position: fixed; inset: 0; width: 100%; height: 100%; border: 0; display: block; }
        </style>
        </head>
        <body>
        <iframe src="\(src)" title="\(title)" referrerpolicy="strict-origin-when-cross-origin" \
        allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen></iframe>
        </body>
        </html>
        """
    }

    /// `embed.embedURL` with the provider's autoplay parameter set.
    public static func playerURL(for embed: EmbedInfo, autoplay: Bool) -> URL {
        guard var components = URLComponents(url: embed.embedURL, resolvingAgainstBaseURL: false) else {
            return embed.embedURL
        }
        let (name, value): (String, String) = switch embed.provider {
        case .youtube, .vimeo, .streamable, .reddit: ("autoplay", autoplay ? "1" : "0")
        // Twitch players autoplay unless told otherwise and expect true/false.
        case .twitch: ("autoplay", autoplay ? "true" : "false")
        }
        var items = components.queryItems ?? []
        items.removeAll { $0.name == name }
        items.append(URLQueryItem(name: name, value: value))
        components.queryItems = items
        return components.url ?? embed.embedURL
    }

    /// Escapes text for use in HTML content and double-quoted attributes.
    static func escape(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.utf8.count)
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            default: result.append(character)
            }
        }
        return result
    }
}
