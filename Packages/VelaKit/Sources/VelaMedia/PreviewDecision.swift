// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

// MARK: - Layout settings

/// How big link cards are. Mirrors VelaStore's `LinkPreviewSize` by raw value.
public enum PreviewLinkSize: String, Sendable, Hashable, CaseIterable {
    /// One row: favicon, site, title, tiny thumbnail.
    case minimal
    /// Title and description beside a small thumbnail.
    case standard
    /// The full card with a large image.
    case large
}

/// How video links are shown. Mirrors VelaStore's `VideoEmbedStyle` by raw value.
public enum PreviewVideoStyle: String, Sendable, Hashable, CaseIterable {
    /// A large thumbnail that turns into the provider's player on click.
    case player
    /// A one-line row with a small thumbnail.
    case compact
    /// No player: the link gets an ordinary link card.
    case off
}

/// How inline images are shown. Mirrors VelaStore's `InlineImageSize` by raw value.
public enum PreviewImageSize: String, Sendable, Hashable, CaseIterable {
    case full
    case thumbnail
}

public struct PreviewLayout: Sendable, Hashable {
    public var linkSize: PreviewLinkSize
    public var videoStyle: PreviewVideoStyle
    public var imageSize: PreviewImageSize

    public init(
        linkSize: PreviewLinkSize = .standard,
        videoStyle: PreviewVideoStyle = .player,
        imageSize: PreviewImageSize = .full
    ) {
        self.linkSize = linkSize
        self.videoStyle = videoStyle
        self.imageSize = imageSize
    }
}

/// Everything about a buffer that decides how its links are previewed.
public struct PreviewContext: Sendable, Hashable {
    public var policy: MediaPolicy
    public var layout: PreviewLayout
    /// Blur images, thumbnails and posters until clicked.
    public var blurImages: Bool

    public init(policy: MediaPolicy = MediaPolicy(), layout: PreviewLayout = PreviewLayout(), blurImages: Bool = false) {
        self.policy = policy
        self.layout = layout
        self.blurImages = blurImages
    }
}

/// What the user did to one link's preview.
public struct PreviewOverrides: Sendable, Hashable {
    /// Clicked "Load preview" (matters when auto-load is off).
    public var loadRequested: Bool
    /// Domains the user chose "Show once" for on this link's blocked chip.
    public var allowedOnce: Set<String>
    /// Clicked a blurred image to reveal it.
    public var revealed: Bool
    /// An inline image turned out not to be an image (e.g. ImageIO couldn't
    /// read it): preview the link as a page instead.
    public var treatAsPage: Bool

    public init(
        loadRequested: Bool = false,
        allowedOnce: Set<String> = [],
        revealed: Bool = false,
        treatAsPage: Bool = false
    ) {
        self.loadRequested = loadRequested
        self.allowedOnce = allowedOnce
        self.revealed = revealed
        self.treatAsPage = treatAsPage
    }
}

// MARK: - Decision

/// What a "Load …" chip offers, for its icon and title.
public enum LoadChipKind: Sendable, Hashable {
    case image
    case video
    case videoEmbed(EmbedProvider)
    case page
}

/// What to draw for one link.
public enum PreviewPlan: Sendable, Hashable {
    /// Nothing, taking no space.
    case none
    /// A card is coming once the preview is fetched; draw nothing yet.
    case pending
    /// Auto-load is off: offer to load.
    case loadChip(LoadChipKind)
    /// A quiet chip saying why, with "Show once" and "Always allow" / "Unblock".
    case blocked(SiteBlock)
    /// The image inline (`preview?.mediaURL`, or the classified image URL).
    case image(PreviewImageSize)
    /// The direct video file (`preview.finalURL`).
    case directVideo(PreviewVideoStyle)
    /// The provider's facade and player (`preview?.embed`, or the classified one).
    case videoEmbed(PreviewVideoStyle)
    /// A link card; without any image when `showsImages` is false.
    case card(PreviewLinkSize)
}

public struct PreviewDecision: Sendable, Hashable {
    public var plan: PreviewPlan
    /// Fetch the preview (with `policy`) because the plan needs it.
    public var shouldFetch: Bool
    /// The policy for this link: the buffer's, plus the link's "Show once"
    /// domains (lifting the allowed-sites restriction or the adult filter for
    /// this preview when that is what blocked it), and with images turned off
    /// when `showsImages` is false. Use it for the fetch and every image load.
    public var policy: MediaPolicy
    /// Whether the views may draw images (thumbnails, favicons, posters) at all.
    public var showsImages: Bool
    /// Draw images blurred until the user reveals them.
    public var blurred: Bool

    public init(plan: PreviewPlan, shouldFetch: Bool, policy: MediaPolicy, showsImages: Bool, blurred: Bool) {
        self.plan = plan
        self.shouldFetch = shouldFetch
        self.policy = policy
        self.showsImages = showsImages
        self.blurred = blurred
    }
}

/// Decides, purely, how one link in a message is previewed.
public enum PreviewDecider {
    /// - Parameters:
    ///   - url: The link as written in the message.
    ///   - classification: `MediaClassifier.classify(url)`.
    ///   - preview: The fetched preview, if any.
    ///   - fetchBlock: The site block the last fetch for this link failed with
    ///     (e.g. a redirect into a blocked site); ignored once lifted.
    ///   - context: The buffer's policy, layout and blur setting.
    ///   - overrides: What the user did to this link.
    public static func decide(
        url: URL,
        classification: MediaClassification,
        preview: LinkPreview? = nil,
        fetchBlock: SiteBlock? = nil,
        context: PreviewContext,
        overrides: PreviewOverrides = PreviewOverrides()
    ) -> PreviewDecision {
        let layout = context.layout
        var policy = linkPolicy(
            url: url, classification: classification, preview: preview, fetchBlock: fetchBlock,
            context: context, overrides: overrides
        )

        // The kind of preview: what the fetch found, else what the URL looks like.
        var kind: LinkPreview.Kind = preview?.kind ?? {
            switch classification {
            case .image: .image
            case .video: .video
            case .embed: .embed
            case .page: .page
            }
        }()
        if overrides.treatAsPage, kind == .image { kind = .page }

        func decision(_ plan: PreviewPlan, fetch: Bool = false, showsImages: Bool = false, blurred: Bool = false)
            -> PreviewDecision {
            PreviewDecision(plan: plan, shouldFetch: fetch, policy: policy, showsImages: showsImages, blurred: blurred)
        }
        /// A blocked chip, unless this kind of preview is turned off anyway.
        func blocked(_ block: SiteBlock) -> PreviewDecision {
            isShown(kind, policy: policy, layout: layout) ? decision(.blocked(block)) : decision(.none)
        }

        // 1. The link itself.
        switch policy.verdict(for: url) {
        case .forbidden: return decision(.none)
        case .blocked(let block): return blocked(block)
        case .everything, .textOnly: break
        }

        // 2. A site met while fetching (a redirect hop), unless since lifted.
        if let fetchBlock, case .blocked(let current) = policy.verdict(forHost: fetchBlock.domain) {
            return blocked(current)
        }

        // 3. Where the preview actually led, and what the page says about itself.
        if let preview {
            for target in [preview.finalURL, preview.mediaURL].compactMap({ $0 }) {
                switch policy.verdict(for: target) {
                case .forbidden: return decision(.none)
                case .blocked(let block): return blocked(block)
                case .everything, .textOnly: break
                }
            }
            if preview.declaresAdult == true, policy.filterAdultSites,
               !hasExplicitRule(policy, for: [url, preview.finalURL]),
               !isAllowedOnce(policy, any: [url, preview.finalURL]) {
                let domain = SiteRules.suggestedRuleDomain(for: preview.finalURL)
                    ?? SiteRules.normalizedHost(preview.finalURL) ?? preview.finalURL.absoluteString
                return blocked(SiteBlock(reason: .adultPage, domain: domain))
            }
        }

        // 4. Images only when the link and where it led both get everything.
        var imageTargets = [url]
        if let preview {
            imageTargets.append(preview.finalURL)
            if let mediaURL = preview.mediaURL { imageTargets.append(mediaURL) }
        } else {
            switch classification {
            case .image(let mediaURL), .video(let mediaURL): imageTargets.append(mediaURL)
            case .embed, .page: break
            }
        }
        let showsImages = imageTargets.allSatisfy { policy.verdict(for: $0) == .everything }
        if !showsImages { policy.imagesAllowed = false }

        // 5. The plan once loaded.
        var plan: PreviewPlan = .none
        var fetch = false
        var chip: LoadChipKind = .page

        func cardPlan() {
            chip = .page
            if !policy.showLinkCards {
                plan = .none
            } else if let preview {
                plan = preview.hasCardContent(showingImages: showsImages) ? .card(layout.linkSize) : .none
            } else {
                plan = .pending
                fetch = true
            }
        }

        switch kind {
        case .image:
            if showsImages {
                plan = .image(layout.imageSize)
                chip = .image
            } else {
                cardPlan()
            }
        case .video:
            if showsImages, layout.videoStyle != .off {
                chip = .video
                if preview == nil {
                    plan = .pending
                    fetch = true
                } else {
                    plan = .directVideo(layout.videoStyle)
                }
            } else {
                cardPlan()
            }
        case .embed:
            let provider: EmbedProvider? = preview?.embed?.provider ?? {
                if case .embed(let info) = classification { return info.provider }
                return nil
            }()
            if showsImages, layout.videoStyle != .off, let provider {
                plan = .videoEmbed(layout.videoStyle)
                chip = .videoEmbed(provider)
                fetch = preview == nil
            } else {
                cardPlan()
            }
        case .page:
            cardPlan()
        }

        if plan == .none { return decision(.none) }

        // 6. Auto-load off: nothing is fetched or drawn until asked.
        if !policy.autoLoad, !overrides.loadRequested {
            return decision(.loadChip(chip))
        }

        // 7. Blur whatever image the plan draws.
        let drawsImage: Bool = switch plan {
        case .image, .directVideo, .videoEmbed: true
        case .card: preview?.imageURL != nil
        case .none, .pending, .loadChip, .blocked: false
        }
        let blurred = context.blurImages && showsImages && !overrides.revealed && drawsImage
        return decision(plan, fetch: fetch, showsImages: showsImages, blurred: blurred)
    }

    // MARK: - Helpers

    /// The buffer's policy plus the link's "Show once" domains. When "Show
    /// once" lifted an allowed-sites block, the restriction is off for this
    /// preview (its images and redirects may live elsewhere); likewise the
    /// adult filter after "Show once" on an adult chip.
    static func linkPolicy(
        url: URL,
        classification: MediaClassification,
        preview: LinkPreview?,
        fetchBlock: SiteBlock?,
        context: PreviewContext,
        overrides: PreviewOverrides
    ) -> MediaPolicy {
        var policy = context.policy
        policy.allowedOnce.formUnion(overrides.allowedOnce)
        guard !policy.allowedOnce.isEmpty else { return policy }

        var strict = context.policy
        strict.allowedOnce = []
        var lifted: Set<BlockReason> = []
        var targets = [url]
        switch classification {
        case .image(let mediaURL), .video(let mediaURL): targets.append(mediaURL)
        case .embed, .page: break
        }
        if let preview {
            targets.append(preview.finalURL)
            if let mediaURL = preview.mediaURL { targets.append(mediaURL) }
        }
        for target in targets {
            if case .blocked(let block) = strict.verdict(for: target),
               let host = SiteRules.normalizedHost(target), policy.isAllowedOnce(host: host) {
                lifted.insert(block.reason)
            }
        }
        if let fetchBlock, policy.isAllowedOnce(host: fetchBlock.domain) { lifted.insert(fetchBlock.reason) }
        if preview?.declaresAdult == true, let preview, isAllowedOnce(policy, any: [url, preview.finalURL]) {
            lifted.insert(.adultPage)
        }

        if lifted.contains(.notAllowed) { policy.restrictToAllowedDomains = false }
        if lifted.contains(.adultSite) || lifted.contains(.adultPage) { policy.filterAdultSites = false }
        return policy
    }

    /// Whether a preview of this kind would show anything if it weren't blocked.
    private static func isShown(_ kind: LinkPreview.Kind, policy: MediaPolicy, layout: PreviewLayout) -> Bool {
        switch kind {
        case .image: true
        case .video, .embed: layout.videoStyle != .off || policy.showLinkCards
        case .page: policy.showLinkCards
        }
    }

    private static func hasExplicitRule(_ policy: MediaPolicy, for urls: [URL]) -> Bool {
        urls.contains { url in SiteRules.normalizedHost(url).map { policy.rule(forHost: $0) != nil } ?? false }
    }

    private static func isAllowedOnce(_ policy: MediaPolicy, any urls: [URL]) -> Bool {
        urls.contains { url in SiteRules.normalizedHost(url).map { policy.isAllowedOnce(host: $0) } ?? false }
    }
}
