// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaMedia
import VelaTheme

/// A link preview card for an ordinary page (or a video when videos are off).
///
/// Standard: accent bar, favicon + site name, a 2-line linked title and a
/// 2-line description, with a small cropped thumbnail on the right
/// (`StandardCardLayout`). Large: the same text with a 3-line description and
/// the page image, large underneath when it's wide or small on the right
/// otherwise. Minimal: a single row with favicon, site, title and a tiny
/// thumbnail.
///
/// Without `showsImages` (a text-only site) the card has no image, thumbnail
/// or favicon; a neutral glyph stands in for the favicon.
struct LinkCardView: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    let preview: LinkPreview
    /// The link's policy; every image goes through it.
    let policy: MediaPolicy
    let size: PreviewLinkSize
    let showsImages: Bool
    var animateAppearance = false
    let onHide: () -> Void

    static let maxWidth: CGFloat = 520
    private static let thumbnailSide: CGFloat = 80

    @State private var imagePixelSize: CGSize?
    /// The Standard card's thumbnail couldn't be loaded, so it takes no room.
    @State private var thumbnailFailed: Bool
    @State private var titleHovering = false

    init(
        preview: LinkPreview,
        policy: MediaPolicy,
        size: PreviewLinkSize,
        showsImages: Bool,
        animateAppearance: Bool = false,
        onHide: @escaping () -> Void
    ) {
        self.preview = preview
        self.policy = policy
        self.size = size
        self.showsImages = showsImages
        self.animateAppearance = animateAppearance
        self.onHide = onHide
        let imageURL = Self.imageURL(of: preview, policy: policy, showsImages: showsImages)
        let known = imageURL.flatMap { preview.imageSize ?? EmbedMemory.shared.pixelSize(for: $0, policy: policy) }
        _imagePixelSize = State(initialValue: known)
        _thumbnailFailed = State(initialValue: imageURL.flatMap { EmbedMemory.shared.failedImages.peek($0) } ?? false)
    }

    /// The page image, unless images are off for this link or its host
    /// (a CDN with its own rule, say) may not serve one.
    private var imageURL: URL? {
        Self.imageURL(of: preview, policy: policy, showsImages: showsImages)
    }

    static func imageURL(of preview: LinkPreview, policy: MediaPolicy, showsImages: Bool) -> URL? {
        guard showsImages, let url = preview.imageURL, policy.allowsImage(url) else { return nil }
        return url
    }

    private struct ShapeKey: Equatable {
        var imageURL: URL?
        var size: PreviewLinkSize
        var policy: MediaPolicy
    }

    private var accent: Color {
        EmbedColors.pageAccent(hex: preview.themeColor, theme: theme)
    }

    /// Wide images go under the text; square-ish or small ones sit on the right.
    private var imageIsWide: Bool {
        guard let size = imagePixelSize, size.height > 0 else { return false }
        return size.width / size.height >= 1.3 && size.width >= 300
    }

    var body: some View {
        Group {
            switch size {
            case .minimal: compactRow
            case .standard: standardCard
            case .large: fullCard
            }
        }
        .embedFadeIn(animateAppearance)
        .contextMenu {
            EmbedLinkMenuItems(url: preview.url, onHide: onHide)
        }
        .task(id: ShapeKey(imageURL: imageURL, size: size, policy: policy)) {
            // Learn the image's shape when the page didn't declare it (or
            // images just became allowed for a card that had none). Only the
            // Large card lays out by it.
            guard imagePixelSize == nil, size == .large, let url = imageURL else { return }
            if let declared = preview.imageSize {
                imagePixelSize = declared
                return
            }
            guard let loaded = try? await ImageLoader.shared.load(url, policy: policy) else { return }
            EmbedMemory.shared.remember(pixelSize: loaded.pixelSize, for: url)
            imagePixelSize = loaded.pixelSize
        }
    }

    // MARK: Standard

    /// The Standard card's thumbnail, unless it failed to load.
    private var standardThumbnailURL: URL? {
        thumbnailFailed ? nil : imageURL
    }

    private var standardCard: some View {
        StandardCardLayout {
            EmbedColumnLayout(spacing: 4, minWidth: 0, maxWidth: StandardCardLayout.maxContentWidth) {
                siteRow
                    .padding(.bottom, 1)
                if let title = preview.displayTitle {
                    titleLink(title, size: style.fontSize + 1, lineLimit: 2)
                }
                if let summary = preview.displaySummary {
                    Text(summary)
                        .font(style.font(size: max(10, style.fontSize - 1)))
                        .foregroundStyle(theme[ThemeKey.embedDescription])
                        .lineLimit(2)
                        .lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            if let url = standardThumbnailURL {
                standardThumbnail(url)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .embedCard(accent: accent)
        .frame(maxWidth: StandardCardLayout.maxCardWidth, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityAddTraits(.isLink)
        .accessibilityAction { EmbedActions.open(preview.url) }
    }

    private func standardThumbnail(_ url: URL) -> some View {
        RemoteImageView(
            url: url,
            // Enough pixels to fill the frame from a wide (1.91:1) page image.
            maxPixelSize: EmbedImagePipeline.pixelBudget(forPoints: StandardCardLayout.thumbnailSize.width * 2),
            policy: policy,
            onFailure: {
                EmbedMemory.shared.failedImages.insert(true, for: url)
                thumbnailFailed = true
            }
        ) {
            theme[ThemeKey.embedPlaceholderBackground]
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { EmbedActions.open(preview.url) }
        .help(preview.url.absoluteString)
        .accessibilityHidden(true)
    }

    // MARK: Full

    private var fullCard: some View {
        HStack(alignment: .top, spacing: 12) {
            EmbedColumnLayout(spacing: 5, minWidth: 0, maxWidth: textColumnMaxWidth) {
                siteRow
                if let title = preview.displayTitle {
                    titleLink(title, size: style.fontSize + 1, lineLimit: 2)
                }
                if let summary = preview.displaySummary {
                    Text(summary)
                        .font(style.font(size: max(10, style.fontSize - 1)))
                        .foregroundStyle(theme[ThemeKey.embedDescription])
                        .lineLimit(3)
                        .lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                if imageIsWide, let imageURL, let size = imagePixelSize {
                    largeImage(imageURL, pixelSize: size)
                        .padding(.top, 4)
                }
            }
            if !imageIsWide, imagePixelSize != nil, let imageURL {
                RemoteImageView(
                    url: imageURL,
                    maxPixelSize: EmbedImagePipeline.pixelBudget(forPoints: Self.thumbnailSide),
                    policy: policy
                ) {
                    theme[ThemeKey.embedPlaceholderBackground]
                }
                .frame(width: Self.thumbnailSide, height: Self.thumbnailSide)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .embedCard(accent: accent)
        .frame(maxWidth: Self.maxWidth, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityAddTraits(.isLink)
        .accessibilityAction { EmbedActions.open(preview.url) }
    }

    private var textColumnMaxWidth: CGFloat {
        // Card width minus accent bar, padding and (if shown) the side thumbnail.
        let base = Self.maxWidth - 4 - 24
        let hasSideThumbnail = !imageIsWide && imagePixelSize != nil && imageURL != nil
        return hasSideThumbnail ? base - Self.thumbnailSide - 12 : base
    }

    private var siteRow: some View {
        HStack(spacing: 6) {
            Favicon(url: preview.faviconURL, policy: policy, showsImages: showsImages, size: 14)
            Text(preview.displaySiteName)
                .font(style.font(size: max(9, style.fontSize - 2), weight: .medium))
                .foregroundStyle(theme[ThemeKey.embedSiteName])
                .lineLimit(1)
        }
    }

    private func titleLink(_ title: String, size: Double, lineLimit: Int) -> some View {
        Button {
            EmbedActions.open(preview.url)
        } label: {
            Text(title)
                .font(style.font(size: size, weight: .semibold))
                .foregroundStyle(theme[ThemeKey.embedTitle])
                .underline(titleHovering)
                .lineLimit(lineLimit)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: lineLimit > 1)
        }
        .buttonStyle(.plain)
        .onHover { titleHovering = $0 }
        .pointerStyle(.link)
        .help(preview.url.absoluteString)
    }

    private func largeImage(_ url: URL, pixelSize: CGSize) -> some View {
        FittedMediaLayout(
            aspectRatio: pixelSize.width / max(1, pixelSize.height),
            naturalSize: nil,
            maxWidth: textColumnMaxWidth,
            maxHeight: max(120, style.maxImageHeight)
        ) {
            RemoteImageView(
                url: url,
                maxPixelSize: EmbedImagePipeline.pixelBudget(forPoints: textColumnMaxWidth),
                policy: policy
            ) {
                theme[ThemeKey.embedPlaceholderBackground]
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { EmbedActions.open(preview.url) }
            .accessibilityHidden(true)
        }
    }

    // MARK: Minimal

    private var compactRow: some View {
        HStack(spacing: 7) {
            Favicon(url: preview.faviconURL, policy: policy, showsImages: showsImages, size: 13)
            Text(preview.displaySiteName)
                .font(style.font(size: max(9, style.fontSize - 2), weight: .medium))
                .foregroundStyle(theme[ThemeKey.embedSiteName])
                .lineLimit(1)
                .layoutPriority(1)
            if let title = preview.displayTitle {
                Text("·")
                    .font(style.font(size: max(9, style.fontSize - 2)))
                    .foregroundStyle(theme[ThemeKey.embedSiteName])
                titleLink(title, size: max(10, style.fontSize - 1), lineLimit: 1)
            }
            if let imageURL {
                RemoteImageView(url: imageURL, maxPixelSize: EmbedImagePipeline.pixelBudget(forPoints: 40), policy: policy) {
                    theme[ThemeKey.embedPlaceholderBackground]
                }
                .frame(width: 34, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .accessibilityHidden(true)
            }
        }
        .padding(.leading, 9)
        .padding(.trailing, imageURL == nil ? 10 : 4)
        .padding(.vertical, 4)
        .frame(minHeight: 28)
        .embedCard(accent: accent, cornerRadius: 6, accentWidth: 3)
        .frame(maxWidth: Self.maxWidth, alignment: .leading)
        .help(preview.displaySummary ?? preview.url.absoluteString)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityAddTraits(.isLink)
        .accessibilityAction { EmbedActions.open(preview.url) }
    }

    private var accessibilitySummary: String {
        var parts = ["Link preview", preview.displaySiteName]
        if let title = preview.displayTitle { parts.append(title) }
        if let summary = preview.displaySummary { parts.append(summary) }
        return parts.joined(separator: ", ")
    }
}

/// Lays out a Standard link card's content: the text column on the left and,
/// when there is one, the thumbnail on the right, top-aligned at
/// `thumbnailSize`. The text hugs its content up to the room the thumbnail
/// leaves. When the row is too narrow for both, the thumbnail is dropped
/// (placed at zero size) and the text takes the whole row.
///
/// Subviews: the text column, then optionally the thumbnail.
struct StandardCardLayout: Layout {
    static let maxCardWidth: CGFloat = 480
    /// The card less its accent bar (4) and horizontal padding (2 × 12).
    static let maxContentWidth: CGFloat = maxCardWidth - 4 - 24
    static let thumbnailSize = CGSize(width: 104, height: 78)
    static let spacing: CGFloat = 12
    /// Below this the text needs the room more than the thumbnail does.
    static let minTextWidth: CGFloat = 150

    /// The width the text column may use, and whether the thumbnail sits
    /// beside it, for `contentWidth` points of card content.
    static func columns(contentWidth: CGFloat, hasThumbnail: Bool) -> (textWidth: CGFloat, showsThumbnail: Bool) {
        let width = max(0, min(contentWidth, maxContentWidth))
        guard hasThumbnail else { return (width, false) }
        let beside = width - thumbnailSize.width - spacing
        return beside >= minTextWidth ? (beside, true) : (width, false)
    }

    /// The content's size given the text column's size at its width.
    static func contentSize(text: CGSize, showsThumbnail: Bool) -> CGSize {
        guard showsThumbnail else { return text }
        return CGSize(
            width: text.width + spacing + thumbnailSize.width,
            height: max(text.height, thumbnailSize.height)
        )
    }

    private struct Arrangement {
        var text: CGSize
        var showsThumbnail: Bool
        var size: CGSize
    }

    private func arrange(width: CGFloat?, subviews: Subviews) -> Arrangement {
        let available = width.flatMap { $0.isFinite ? $0 : nil } ?? Self.maxContentWidth
        let columns = Self.columns(contentWidth: available, hasThumbnail: subviews.count > 1)
        let text = subviews.first?.sizeThatFits(ProposedViewSize(width: columns.textWidth, height: nil)) ?? .zero
        let textSize = CGSize(width: min(text.width, columns.textWidth), height: text.height)
        return Arrangement(
            text: textSize,
            showsThumbnail: columns.showsThumbnail,
            size: Self.contentSize(text: textSize, showsThumbnail: columns.showsThumbnail)
        )
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(width: proposal.width ?? bounds.width, subviews: subviews)
        guard let text = subviews.first else { return }
        text.place(at: bounds.origin, proposal: ProposedViewSize(width: arrangement.text.width, height: nil))
        guard subviews.count > 1 else { return }
        let thumbnail = subviews[1]
        if arrangement.showsThumbnail {
            thumbnail.place(
                at: CGPoint(x: bounds.minX + arrangement.text.width + Self.spacing, y: bounds.minY),
                proposal: ProposedViewSize(Self.thumbnailSize)
            )
        } else {
            thumbnail.place(at: bounds.origin, proposal: .zero)
        }
    }
}

/// A site's favicon, or a globe while it loads (or when there is none).
/// Text-only links get a page glyph instead: no favicon is requested.
struct Favicon: View {
    @Environment(\.theme) private var theme
    let url: URL?
    let policy: MediaPolicy
    var showsImages = true
    var size: CGFloat = 14

    var body: some View {
        Group {
            if !showsImages {
                Image(systemName: "doc.text")
                    .font(.system(size: size * 0.8))
                    .foregroundStyle(theme[ThemeKey.embedSiteName])
                    .help("Text only: no images from this site")
            } else if let url {
                RemoteImageView(url: url, maxPixelSize: EmbedImagePipeline.pixelBudget(forPoints: size), policy: policy, contentMode: .fit) {
                    globe
                }
            } else {
                globe
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .accessibilityHidden(true)
    }

    private var globe: some View {
        Image(systemName: "globe")
            .font(.system(size: size * 0.8))
            .foregroundStyle(theme[ThemeKey.embedSiteName])
    }
}
