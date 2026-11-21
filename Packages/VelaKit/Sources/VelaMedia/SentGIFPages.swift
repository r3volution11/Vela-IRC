// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Synchronization

/// The pages of GIFs sent from the GIF picker, by the link that was sent.
///
/// On IRC a GIF is its file's link, exactly as the service gave it, and a
/// KLIPY file link names neither the GIF's page nor its slug. The picker
/// knows the page (`GIFSearchResult.pageURL`), so sending a GIF records it
/// here, and the "via KLIPY" caption under the message (or under the same
/// GIF posted again) opens it. Any other KLIPY GIF's caption opens klipy.com.
///
/// In memory only, for as long as Vela is open, and bounded: the pages of
/// the last `capacity` GIFs sent. Nothing is written to disk or sent
/// anywhere. A lookup is a dictionary read under a lock, cheap enough for a
/// row's body; recording, once per message sent, may scan the entries.
public final class SentGIFPages: Sendable {
    public static let shared = SentGIFPages()
    public static let defaultCapacity = 500

    public let capacity: Int
    /// Page by the sent link's text; recording a link again makes it the newest.
    private let pages: Mutex<LRUCache<String, URL>>

    public init(capacity: Int = SentGIFPages.defaultCapacity) {
        self.capacity = max(1, capacity)
        pages = Mutex(LRUCache(countLimit: max(1, capacity)))
    }

    /// Remembers `page` as the page of the GIF sent as `link`, forgetting
    /// the oldest once there are more than `capacity`.
    public func record(page: URL, for link: URL) {
        pages.withLock { $0.insert(page, for: link.absoluteString) }
    }

    /// The page recorded for `link`, if it's among the last `capacity` sent.
    public func page(for link: URL) -> URL? {
        pages.withLock { $0.peek(link.absoluteString) }
    }

    /// How many pages are remembered.
    public var count: Int {
        pages.withLock { $0.count }
    }
}
