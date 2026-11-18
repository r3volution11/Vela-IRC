// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AVFoundation
import SwiftUI
import VelaMedia
import VelaTheme

/// A direct link to a video file (.mp4, .mov, Imgur .gifv).
///
/// Shows a poster frame with ▶; the AVKit player is only created (and the
/// video only streamed) when the user clicks play. Never autoplays. The
/// player lives in `EmbedPlayerStore` like the provider players: one plays
/// at a time, it pauses when scrolled out of view, and it can be expanded.
/// The file name and site under it (or on the compact row, where a click
/// plays) can be selected and copied.
struct DirectVideoView: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    @Environment(UIState.self) private var uiState
    @Environment(\.embedBlur) private var blur
    /// The line and link this video belongs to.
    let playerKey: EmbedPlayerKey
    let linkURL: URL
    /// The file after policy-checked redirects.
    let videoURL: URL
    /// The link's policy: no poster is made (and nothing played) unless it
    /// lets the file load like an image.
    let policy: MediaPolicy
    let compact: Bool
    var animateAppearance = false
    let onHide: () -> Void

    private static let posterPixelSize = EmbedImagePipeline.pixelBudget(forPoints: VideoEmbedView.maxPlayerWidth)

    @State private var poster: CGImage?
    @State private var hovering = false

    init(
        playerKey: EmbedPlayerKey,
        linkURL: URL,
        videoURL: URL,
        policy: MediaPolicy,
        compact: Bool,
        animateAppearance: Bool = false,
        onHide: @escaping () -> Void
    ) {
        self.playerKey = playerKey
        self.linkURL = linkURL
        self.videoURL = videoURL
        self.policy = policy
        self.compact = compact
        self.animateAppearance = animateAppearance
        self.onHide = onHide
        _poster = State(initialValue: EmbedImagePipeline.memoizedStill(videoURL, maxPixelSize: Self.posterPixelSize, policy: policy))
    }

    private var isAllowed: Bool { policy.allowsImage(videoURL) }

    private var aspectRatio: CGFloat {
        guard let poster, poster.height > 0 else { return 16.0 / 9.0 }
        return CGFloat(poster.width) / CGFloat(poster.height)
    }

    private var store: EmbedPlayerStore { .shared }

    /// Inline, expanded, or nil while the poster shows.
    private var placement: EmbedPlayerPlacement? { store.placement(of: playerKey) }

    /// The player exists (in compact mode, it shows under the title row).
    private var isPlaying: Bool { placement != nil }

    var body: some View {
        Group {
            if compact { compactBody } else { fullBody }
        }
        .embedFadeIn(animateAppearance)
        .task(id: videoURL) {
            // Compact rows start playing as soon as they expand, so they need no poster.
            guard poster == nil, !compact, isAllowed else { return }
            guard let image = try? await Self.makePoster(videoURL, maxPixelSize: Self.posterPixelSize) else { return }
            EmbedMemory.shared.remember(still: image, for: StillImageKey(url: videoURL, maxPixelSize: Self.posterPixelSize))
            poster = image
        }
        .contextMenu {
            if isAllowed {
                Button(isPlaying ? "Stop Video" : "Play Video") { isPlaying ? stop() : play() }
                EmbedPlayerMenuItems(key: playerKey, onStartIfNeeded: play)
            }
            Button("Open in Browser") { EmbedActions.open(linkURL) }
            Divider()
            EmbedLinkMenuItems(url: linkURL, onHide: onHide)
        }
    }

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: 5) {
            playerArea
            caption
        }
    }

    private var caption: some View {
        HStack(spacing: 5) {
            Image(systemName: "film")
            Text(EmbedActions.displayName(linkURL)).lineLimit(1).truncationMode(.middle)
            Text("· \(EmbedActions.displayHost(linkURL))").lineLimit(1)
        }
        .font(style.font(size: max(9, style.fontSize - 2)))
        .foregroundStyle(theme[ThemeKey.embedSiteName])
        .textSelection(.enabled)
        .accessibilityHidden(true)
    }

    private var playerArea: some View {
        FittedMediaLayout(
            aspectRatio: aspectRatio,
            naturalSize: nil,
            maxWidth: VideoEmbedView.maxPlayerWidth,
            maxHeight: VideoEmbedView.playerMaxHeight(aspectRatio: aspectRatio, maxImageHeight: style.maxImageHeight)
        ) {
            if placement == .expanded {
                ExpandedPlayerPlaceholder(cornerRadius: 8) {
                    ExpandedVideoOverlay.returnToChat(uiState: uiState)
                }
            } else {
                ZStack {
                    // Letterboxing behind the video is always black.
                    Color.black
                    if isPlaying {
                        EmbedPlayerHost(key: playerKey, placement: .inline)
                    } else {
                        posterFacade
                            .blurredMedia(.image(poster), policy: policy, kind: .video, cornerRadius: 8)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(theme[ThemeKey.embedBorder], lineWidth: isPlaying ? 0 : 1)
                )
                .overlay(alignment: .topTrailing) {
                    if isPlaying {
                        PlayerOverlayButtons(key: playerKey, onClose: stop)
                            .padding(8)
                    }
                }
            }
        }
        .embedPlayerVisibility(playerKey)
    }

    private var posterFacade: some View {
        Button(action: play) {
            ZStack {
                if let poster {
                    Image(decorative: poster, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                }
                PlayGlyph(diameter: 50, hovering: hovering)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help("Play \(EmbedActions.displayName(linkURL))")
        .accessibilityLabel("Play video: \(EmbedActions.displayName(linkURL))")
    }

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Button(action: toggleCompactPlayer) {
                    Image(systemName: isPlaying ? "stop.circle.fill" : (blur.isBlurred ? "eye.slash" : "play.circle.fill"))
                        .font(.system(size: max(12, style.fontSize + 1)))
                        .foregroundStyle(theme[ThemeKey.accent])
                }
                .buttonStyle(.plain)
                .outsideLinkClickArea()
                Text(EmbedActions.displayName(linkURL))
                    .font(style.font(size: max(10, style.fontSize - 1), weight: .semibold))
                    .foregroundStyle(theme[ThemeKey.embedTitle])
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Text("· \(EmbedActions.displayHost(linkURL))")
                    .font(style.font(size: max(9, style.fontSize - 2)))
                    .foregroundStyle(theme[ThemeKey.embedSiteName])
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .frame(minHeight: 28)
            .embedCard(accent: theme[ThemeKey.embedAccent], cornerRadius: 6, accentWidth: 3)
            // A click anywhere plays (or closes) the video; a drag selects.
            .linkClickArea(linkURL, perform: toggleCompactPlayer)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(isPlaying ? "Close video" : "Show video"): \(EmbedActions.displayName(linkURL))")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { toggleCompactPlayer() }

            if isPlaying {
                playerArea
            }
        }
        .frame(maxWidth: VideoEmbedView.maxPlayerWidth, alignment: .leading)
    }

    /// The compact row's ▶ (or a click on the row): plays the video, or
    /// closes the player. The first click on a blurred row only shows it.
    private func toggleCompactPlayer() {
        if !isPlaying, blur.isBlurred {
            blur.reveal()
            return
        }
        isPlaying ? stop() : play()
    }

    private func play() {
        guard isAllowed else { return }
        store.start(
            playerKey,
            source: .file(videoURL),
            info: EmbedPlayerInfo(
                linkURL: linkURL,
                title: EmbedActions.displayName(linkURL),
                provider: nil,
                siteName: EmbedActions.displayHost(linkURL),
                aspectRatio: aspectRatio
            )
        )
    }

    private func stop() {
        store.stop(playerKey)
    }

    /// The first frame, decoded off the main actor.
    @concurrent
    private static func makePoster(_ url: URL, maxPixelSize: Int) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        return try await generator.image(at: .zero).image
    }
}
