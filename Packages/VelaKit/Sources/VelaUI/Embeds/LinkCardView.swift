// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaMedia
import VelaTheme

/// A link preview card for an ordinary page (or a video when videos are off).
///
/// Large: accent bar, favicon + site name, linked title, a 2–3 line
/// description and the page image, large underneath when it's wide or small
/// on the right otherwise. Minimal: a single row with favicon, site, title
/// and a tiny thumbnail. Standard draws the large card for now.
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
    }

    private var compact: Bool { size == .minimal }

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
        var compact: Bool
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
            if compact { compactRow } else { fullCard }
        }
        .embedFadeIn(animateAppearance)
        .contextMenu {
            EmbedLinkMenuItems(url: preview.url, onHide: onHide)
        }
        .task(id: ShapeKey(imageURL: imageURL, compact: compact, policy: policy)) {
            // Learn the image's shape when the page didn't declare it (or
            // images just became allowed for a card that had none).
            guard imagePixelSize == nil, !compact, let url = imageURL else { return }
            if let declared = preview.imageSize {
                imagePixelSize = declared
                return
            }
            guard let loaded = try? await ImageLoader.shared.load(url, policy: policy) else { return }
            EmbedMemory.shared.remember(pixelSize: loaded.pixelSize, for: url)
            imagePixelSize = loaded.pixelSize
        }
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

    // MARK: Compact

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
