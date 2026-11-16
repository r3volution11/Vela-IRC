// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import WebKit

/// The web view a provider's player plays in. `WebPlayerSurface` (in
/// `EmbedPlayerStore.swift`) creates and configures it, and
/// `EmbedPlayerHost` shows it.
///
/// It passes scroll gestures on to the chat, so scrolling the message list
/// doesn't get stuck while the pointer is over a player.
final class EmbedWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }
}
