// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Observation
import VelaMedia

/// What the user did to the previews in each chat line: hid them, clicked
/// "Load preview", chose "Show once" on a blocked site, revealed a blurred
/// image, or found that an "image" link is really a page.
///
/// Kept outside the row views so the choices survive rows being re-created
/// while scrolling, and in memory only: a relaunch starts from the settings
/// again ("Show once" really is once).
@Observable
final class EmbedLineStore {
    static let shared = EmbedLineStore()

    /// One link (`EmbedLink.id`) in one line.
    struct LinkKey: Hashable {
        var lineID: UUID
        var linkID: String
    }

    private var collapsed: Set<UUID> = []
    /// "Show once" domains per line. They cover every link in the line, so a
    /// site that two of its links (or one link's redirect) lead to opens once.
    private var allowedOnce: [UUID: Set<String>] = [:]
    private var loadRequested: Set<LinkKey> = []
    private var revealed: Set<LinkKey> = []
    private var treatAsPage: Set<LinkKey> = []

    init() {}

    // MARK: Lines

    func isCollapsed(_ lineID: UUID) -> Bool { collapsed.contains(lineID) }

    func setCollapsed(_ value: Bool, for lineID: UUID) {
        if value { collapsed.insert(lineID) } else { collapsed.remove(lineID) }
    }

    /// The domains the user chose "Show once" for in this line.
    func allowedOnce(in lineID: UUID) -> Set<String> {
        allowedOnce[lineID] ?? []
    }

    /// "Show once" on a blocked chip: previews from `domain` (and its
    /// subdomains) load in this line until relaunch.
    func allowOnce(_ domain: String, in lineID: UUID) {
        allowedOnce[lineID, default: []].insert(domain)
    }

    // MARK: Links

    /// Everything the user did to one link, for `PreviewDecider`.
    func overrides(lineID: UUID, linkID: String) -> PreviewOverrides {
        let key = LinkKey(lineID: lineID, linkID: linkID)
        return PreviewOverrides(
            loadRequested: loadRequested.contains(key),
            allowedOnce: allowedOnce(in: lineID),
            revealed: revealed.contains(key),
            treatAsPage: treatAsPage.contains(key)
        )
    }

    /// Clicked "Load preview" while auto-load is off.
    func requestLoad(lineID: UUID, linkID: String) {
        loadRequested.insert(LinkKey(lineID: lineID, linkID: linkID))
    }

    /// Revealed (or, with false, blurred again) a blurred image.
    func setRevealed(_ value: Bool, lineID: UUID, linkID: String) {
        let key = LinkKey(lineID: lineID, linkID: linkID)
        if value { revealed.insert(key) } else { revealed.remove(key) }
    }

    /// An "image" link served something ImageIO can't read (an image host's
    /// HTML viewer page, say): preview it as a page from now on.
    func treatAsPage(lineID: UUID, linkID: String) {
        treatAsPage.insert(LinkKey(lineID: lineID, linkID: linkID))
    }
}

// MARK: - Decisions

extension EmbedLineStore {
    /// `PreviewDecider`'s decision for `link` in `lineID`, given what its
    /// fetch has produced so far.
    func decision(
        for link: EmbedLink,
        in lineID: UUID,
        preview: LinkPreview?,
        fetchBlock: SiteBlock?,
        context: VelaMedia.PreviewContext
    ) -> PreviewDecision {
        PreviewDecider.decide(
            url: link.url,
            classification: link.classification,
            preview: preview,
            fetchBlock: fetchBlock,
            context: context,
            overrides: overrides(lineID: lineID, linkID: link.id)
        )
    }

    /// The preview remembered for `link`, if the line's policy (with its
    /// "Show once" sites) lets the link load at all.
    func rememberedPreview(
        for link: EmbedLink, in lineID: UUID, context: VelaMedia.PreviewContext, memory: EmbedMemory = .shared
    ) -> LinkPreview? {
        var policy = context.policy
        policy.allowedOnce.formUnion(allowedOnce(in: lineID))
        return memory.preview(for: link.url, policy: policy)
    }

    /// The decision from what is remembered about `link`, before any fetch:
    /// what a re-created row draws on its first frame.
    func rememberedDecision(
        for link: EmbedLink, in lineID: UUID, context: VelaMedia.PreviewContext, memory: EmbedMemory = .shared
    ) -> PreviewDecision {
        decision(
            for: link,
            in: lineID,
            preview: rememberedPreview(for: link, in: lineID, context: context, memory: memory),
            fetchBlock: memory.fetchBlocks.peek(link.url),
            context: context
        )
    }
}
