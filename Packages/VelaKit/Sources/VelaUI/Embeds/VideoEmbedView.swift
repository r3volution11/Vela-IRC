// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaMedia
import VelaTheme

/// A YouTube/Vimeo/Twitch/Streamable video.
///
/// Full: a card with the provider badge, title and author over a thumbnail
/// facade; clicking ▶ swaps in the real player (a web view) at the video's
/// aspect ratio, and × collapses it again. Compact: a one-line title row with
/// ▶ that expands the player underneath.
///
/// Nothing is loaded from the provider until the user clicks play; the
/// facade only fetches the thumbnail.
struct VideoEmbedView: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    let linkURL: URL
    let embed: EmbedInfo
    /// The link's policy; the thumbnail goes through it.
    let policy: MediaPolicy
    let compact: Bool
    var animateAppearance = false
    let onHide: () -> Void

    static let maxPlayerWidth: CGFloat = 480
    private static let cardMaxWidth: CGFloat = 520

    @State private var isPlaying = false
    @State private var hoveringFacade = false
    @State private var hoveringTitle = false

    private var brand: Color {
        EmbedColors.color(hex: embed.provider.brandColor) ?? theme[ThemeKey.embedAccent]
    }

    private var playerMaxHeight: CGFloat {
        // Portrait videos (Shorts) get more height so they aren't tiny.
        embed.aspectRatio < 1 ? max(style.maxImageHeight, 420) : max(style.maxImageHeight, 270)
    }

    private var title: String? {
        embed.title.flatMap { $0.isEmpty ? nil : $0 }
    }

    var body: some View {
        Group {
            if compact { compactBody } else { fullBody }
        }
        .embedFadeIn(animateAppearance)
        .contextMenu {
            Button(isPlaying ? "Stop Video" : "Play Video") { isPlaying.toggle() }
            Button("Open in Browser") { EmbedActions.open(linkURL) }
            Divider()
            EmbedLinkMenuItems(url: linkURL, onHide: onHide)
        }
    }

    // MARK: Full

    private var fullBody: some View {
        EmbedColumnLayout(spacing: 6, minWidth: 260, maxWidth: Self.cardMaxWidth - 4 - 24) {
            header
            if let title {
                titleButton(title, lineLimit: 2, size: style.fontSize + 1)
            }
            player(maxWidth: Self.maxPlayerWidth)
                .padding(.top, 2)
                .embedPrimaryMedia()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .embedCard(accent: brand)
        .frame(maxWidth: Self.cardMaxWidth, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 6) {
            ProviderBadge(provider: embed.provider)
            if let author = embed.authorName, !author.isEmpty {
                Text("·").foregroundStyle(theme[ThemeKey.embedSiteName])
                Text(author)
                    .foregroundStyle(theme[ThemeKey.embedSiteName])
                    .lineLimit(1)
            }
        }
        .font(style.font(size: max(9, style.fontSize - 2), weight: .medium))
    }

    private func titleButton(_ title: String, lineLimit: Int, size: Double) -> some View {
        Button {
            EmbedActions.open(linkURL)
        } label: {
            Text(title)
                .font(style.font(size: size, weight: .semibold))
                .foregroundStyle(theme[ThemeKey.embedTitle])
                .underline(hoveringTitle)
                .lineLimit(lineLimit)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: lineLimit > 1)
        }
        .buttonStyle(.plain)
        .onHover { hoveringTitle = $0 }
        .pointerStyle(.link)
        .help("Open \(linkURL.absoluteString)")
    }

    private func player(maxWidth: CGFloat) -> some View {
        FittedMediaLayout(aspectRatio: embed.aspectRatio, naturalSize: nil, maxWidth: maxWidth, maxHeight: playerMaxHeight) {
            ZStack {
                // Letterboxing behind the video is always black.
                Color.black
                if isPlaying {
                    EmbedPlayerWebView(embed: embed)
                } else {
                    facade
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if isPlaying {
                    MediaOverlayButton(systemImage: "xmark", label: "Close player") { isPlaying = false }
                        .padding(8)
                }
            }
        }
    }

    private var facade: some View {
        Button {
            isPlaying = true
        } label: {
            ZStack {
                if let thumbnail = embed.thumbnailURL {
                    RemoteImageView(
                        url: thumbnail,
                        maxPixelSize: EmbedImagePipeline.pixelBudget(forPoints: Self.maxPlayerWidth),
                        policy: policy
                    ) {
                        theme[ThemeKey.embedPlaceholderBackground]
                    }
                }
                PlayGlyph(diameter: 54, hovering: hoveringFacade)
            }
            .contentShape(Rectangle())
            .clipped()
        }
        .buttonStyle(.plain)
        .onHover { hoveringFacade = $0 }
        .animation(.easeOut(duration: 0.12), value: hoveringFacade)
        .help("Play \(title ?? "video") here")
        .accessibilityLabel("Play video: \(title ?? linkURL.absoluteString), \(embed.provider.displayName)")
        .accessibilityHint("Starts the \(embed.provider.displayName) player inline")
    }

    // MARK: Compact

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                isPlaying.toggle()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: max(12, style.fontSize + 1)))
                        .foregroundStyle(theme[ThemeKey.accent])
                    ProviderBadge(provider: embed.provider)
                    Text(title ?? EmbedActions.displayHost(linkURL))
                        .font(style.font(size: max(10, style.fontSize - 1), weight: .semibold))
                        .foregroundStyle(theme[ThemeKey.embedTitle])
                        .lineLimit(1)
                    if let author = embed.authorName, !author.isEmpty {
                        Text("· \(author)")
                            .font(style.font(size: max(9, style.fontSize - 2)))
                            .foregroundStyle(theme[ThemeKey.embedSiteName])
                            .lineLimit(1)
                    }
                    if !isPlaying, let thumbnail = embed.thumbnailURL {
                        RemoteImageView(url: thumbnail, maxPixelSize: EmbedImagePipeline.pixelBudget(forPoints: 40), policy: policy) {
                            theme[ThemeKey.embedPlaceholderBackground]
                        }
                        .frame(width: 34, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
                .padding(.leading, 8)
                .padding(.trailing, isPlaying || embed.thumbnailURL == nil ? 10 : 4)
                .padding(.vertical, 4)
                .frame(minHeight: 28)
                .embedCard(accent: brand, cornerRadius: 6, accentWidth: 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: Self.cardMaxWidth, alignment: .leading)
            .help(isPlaying ? "Close the player" : "Play \(title ?? "video") here")
            .accessibilityLabel("\(isPlaying ? "Close video" : "Play video"): \(title ?? linkURL.absoluteString), \(embed.provider.displayName)")

            if isPlaying {
                player(maxWidth: Self.maxPlayerWidth)
            }
        }
    }
}
