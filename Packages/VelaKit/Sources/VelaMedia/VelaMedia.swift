// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

// VelaMedia turns URLs found in IRC messages into rich content:
//
// - `LinkDetector` finds http(s) links in message text.
// - `MediaClassifier` decides offline whether a URL is a direct image,
//   a direct video, a known video embed (YouTube, Vimeo, Twitch, Streamable)
//   or an ordinary page.
// - `LinkPreviewService` fetches what is needed to render a card
//   (oEmbed for embeds, OpenGraph/Twitter metadata for pages).
// - `ImageLoader` downloads and validates images with a size cap.
// - `EmbedPlayerHTML` builds the page a web view loads to play an embed.
//
// `MediaPolicy` carries the user's privacy and size settings.
// Nothing in this module draws UI; VelaUI renders the results.

/// Errors thrown by `LinkPreviewService` and `ImageLoader`.
public enum MediaError: Error, Sendable, Hashable {
    /// The URL (or a redirect target) is not allowed by the `MediaPolicy`.
    case blockedByPolicy
    /// The response is larger than the allowed byte or pixel budget.
    case tooLarge
    /// The response is not something that can be previewed (e.g. a PDF,
    /// or bytes that ImageIO cannot decode).
    case unsupportedContent
    /// The server answered with a non-success HTTP status.
    case http(Int)
    /// The response was not an HTTP response or was otherwise malformed.
    case invalidResponse
}
