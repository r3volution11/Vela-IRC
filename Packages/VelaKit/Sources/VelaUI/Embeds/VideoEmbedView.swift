// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaMedia
import VelaTheme

/// A YouTube/Vimeo/Twitch/Streamable video.
///
/// Player (full): a card with the provider badge, title and author over a
/// thumbnail facade up to `maxPlayerWidth` wide; clicking ▶ swaps in the real
/// player (a web view) at the video's aspect ratio, and × collapses it again.
/// Compact: a one-line title row with ▶ that expands the player underneath.
/// A playing player can be expanded to fill the window; its spot here then
/// shows a placeholder.
///
/// Nothing is loaded from the provider until the user clicks play; the
/// facade only fetches the thumbnail. The player itself lives in
/// `EmbedPlayerStore`, so it survives this view being re-created.
struct VideoEmbedView: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    @Environment(UIState.self) private var uiState
    @Environment(\.embedBlur) private var blur
    /// The line and link this video belongs to.
    let playerKey: EmbedPlayerKey
    let linkURL: URL
    let embed: EmbedInfo
    /// The link's policy; the thumbnail goes through it.
    let policy: MediaPolicy
    let compact: Bool
    var animateAppearance = false
    let onHide: () -> Void

    /// Widest a video player (or its facade) gets; 16:9 at this width is 315 tall.
    static let maxPlayerWidth: CGFloat = 560
    /// The player plus the card's accent bar and padding.
    private static let cardMaxWidth: CGFloat = maxPlayerWidth + 4 + 24
    /// The compact row's cap, the same as a Minimal link card's.
    private static let compactRowMaxWidth: CGFloat = LinkCardView.maxWidth

    /// The tallest a player gets: at least 315 (16:9 at full width), or the
    /// images' maximum height if that's taller. Portrait videos (Shorts) get
    /// more height so they aren't tiny.
    static func playerMaxHeight(aspectRatio: CGFloat, maxImageHeight: CGFloat) -> CGFloat {
        aspectRatio < 1 ? max(maxImageHeight, 490) : max(maxImageHeight, 315)
    }

    @State private var hoveringFacade = false
    @State private var hoveringTitle = false

    private var brand: Color {
        EmbedColors.color(hex: embed.provider.brandColor) ?? theme[ThemeKey.embedAccent]
    }

    private var playerMaxHeight: CGFloat {
        Self.playerMaxHeight(aspectRatio: embed.aspectRatio, maxImageHeight: style.maxImageHeight)
    }

    private var title: String? {
        embed.title.flatMap { $0.isEmpty ? nil : $0 }
    }

    private var store: EmbedPlayerStore { .shared }

    /// Inline, expanded, or nil while the facade shows.
    private var placement: EmbedPlayerPlacement? { store.placement(of: playerKey) }

    private var isPlaying: Bool { placement != nil }

    var body: some View {
        Group {
            if compact { compactBody } else { fullBody }
        }
        .embedFadeIn(animateAppearance)
        .contextMenu {
            Button(isPlaying ? "Stop Video" : "Play Video") { isPlaying ? stop() : play() }
            EmbedPlayerMenuItems(key: playerKey, onStartIfNeeded: play)
            Button("Open in Browser") { EmbedActions.open(linkURL) }
            Divider()
            EmbedLinkMenuItems(url: linkURL, onHide: onHide)
        }
    }

    private func play() {
        store.start(
            playerKey,
            source: .embed(embed),
            info: EmbedPlayerInfo(
                linkURL: linkURL,
                title: title,
                provider: embed.provider,
                siteName: embed.provider.displayName,
                aspectRatio: embed.aspectRatio
            )
        )
    }

    private func stop() {
        store.stop(playerKey)
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
            switch placement {
            case .expanded:
                ExpandedPlayerPlaceholder(cornerRadius: 6) {
                    ExpandedVideoOverlay.returnToChat(uiState: uiState)
                }
            case .inline:
                ZStack {
                    // Letterboxing behind the video is always black.
                    Color.black
                    EmbedPlayerHost(key: playerKey, placement: .inline)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    PlayerOverlayButtons(key: playerKey, onClose: stop)
                        .padding(8)
                }
            case nil:
                ZStack {
                    Color.black
                    facade
                        .blurredMedia(embed.thumbnailURL.map { .url($0) } ?? .none, policy: policy, kind: .video)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .embedPlayerVisibility(playerKey)
    }

    private var facade: some View {
        Button {
            play()
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
                // The first click on a blurred row only shows it.
                if !isPlaying, blur.isBlurred {
                    blur.reveal()
                    return
                }
                isPlaying ? stop() : play()
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
                        .blurredMedia(.url(thumbnail), policy: policy, kind: .video, cornerRadius: 4)
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
            .frame(maxWidth: Self.compactRowMaxWidth, alignment: .leading)
            .help(isPlaying ? "Close the player" : "Play \(title ?? "video") here")
            .accessibilityLabel("\(isPlaying ? "Close video" : "Play video"): \(title ?? linkURL.absoluteString), \(embed.provider.displayName)")

            if isPlaying {
                player(maxWidth: Self.maxPlayerWidth)
            }
        }
    }
}

// MARK: - Player chrome

/// Expand and × over a playing inline player.
struct PlayerOverlayButtons: View {
    let key: EmbedPlayerKey
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            MediaOverlayButton(systemImage: "arrow.up.left.and.arrow.down.right", label: "Expand video") {
                EmbedPlayerStore.shared.expand(key)
            }
            MediaOverlayButton(systemImage: "xmark", label: "Close player", action: onClose)
        }
    }
}

/// "Expand Video" (starting the player first if needed), or "Return Video
/// to Chat" while it's expanded.
struct EmbedPlayerMenuItems: View {
    @Environment(UIState.self) private var uiState
    let key: EmbedPlayerKey
    let onStartIfNeeded: () -> Void

    var body: some View {
        let store = EmbedPlayerStore.shared
        if store.placement(of: key) == .expanded {
            Button("Return Video to Chat") { ExpandedVideoOverlay.returnToChat(uiState: uiState) }
        } else {
            Button("Expand Video") {
                if !store.isLive(key) { onStartIfNeeded() }
                store.expand(key)
            }
        }
    }
}

/// What a player's spot in its line shows while the player is expanded:
/// the same size as the player, with a way back.
struct ExpandedPlayerPlaceholder: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    var cornerRadius: CGFloat = 6
    let onReturn: () -> Void

    @State private var hovering = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(theme[ThemeKey.embedPlaceholderBackground])
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(theme[ThemeKey.embedBorder], lineWidth: 1)
            )
            .overlay {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .foregroundStyle(theme[ThemeKey.embedSiteName])
                    Text("Playing in expanded view")
                        .foregroundStyle(theme[ThemeKey.embedSiteName])
                    Text("·")
                        .foregroundStyle(theme[ThemeKey.embedSiteName])
                    Button(action: onReturn) {
                        Text("Return")
                            .foregroundStyle(theme[ThemeKey.accent])
                            .underline(hovering)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering = $0 }
                    .pointerStyle(.link)
                    .help("Return the video to the chat")
                }
                .font(style.font(size: max(10, style.fontSize - 1), weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 12)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Playing in expanded view")
            .accessibilityAction(named: "Return video to chat", onReturn)
    }
}

extension View {
    /// Reports whether a player's spot in its line is in view: scrolling it
    /// out of view pauses an inline player (`EmbedPlayerStore`).
    func embedPlayerVisibility(_ key: EmbedPlayerKey) -> some View {
        onScrollVisibilityChange(threshold: 0.2) { visible in
            EmbedPlayerStore.shared.inlineVisibilityChanged(key, isVisible: visible)
        }
        .onDisappear {
            EmbedPlayerStore.shared.inlineSpotDisappeared(key)
        }
    }
}
