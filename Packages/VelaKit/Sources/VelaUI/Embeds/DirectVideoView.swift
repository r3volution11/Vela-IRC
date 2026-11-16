// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AVFoundation
import AVKit
import SwiftUI
import VelaMedia
import VelaTheme

/// A direct link to a video file (.mp4, .mov, Imgur .gifv).
///
/// Shows a poster frame with ▶; the AVKit player is only created (and the
/// video only streamed) when the user clicks play. Never autoplays.
struct DirectVideoView: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    let linkURL: URL
    /// The file after policy-checked redirects.
    let videoURL: URL
    let compact: Bool
    var animateAppearance = false
    let onHide: () -> Void

    private static let posterPixelSize = 960

    @State private var player: AVPlayer?
    @State private var poster: CGImage?
    @State private var hovering = false
    /// Compact mode: the player is showing under the title row.
    @State private var expanded = false

    init(linkURL: URL, videoURL: URL, compact: Bool, animateAppearance: Bool = false, onHide: @escaping () -> Void) {
        self.linkURL = linkURL
        self.videoURL = videoURL
        self.compact = compact
        self.animateAppearance = animateAppearance
        self.onHide = onHide
        _poster = State(initialValue: EmbedImagePipeline.memoizedStill(videoURL, maxPixelSize: Self.posterPixelSize))
    }

    private var aspectRatio: CGFloat {
        guard let poster, poster.height > 0 else { return 16.0 / 9.0 }
        return CGFloat(poster.width) / CGFloat(poster.height)
    }

    var body: some View {
        Group {
            if compact { compactBody } else { fullBody }
        }
        .embedFadeIn(animateAppearance)
        .task(id: videoURL) {
            // Compact rows start playing as soon as they expand, so they need no poster.
            guard poster == nil, !compact else { return }
            guard let image = try? await Self.makePoster(videoURL, maxPixelSize: Self.posterPixelSize) else { return }
            EmbedMemory.shared.stills.insert(
                image,
                for: StillImageKey(url: videoURL, maxPixelSize: Self.posterPixelSize),
                cost: image.bytesPerRow * image.height
            )
            poster = image
        }
        .onDisappear { player?.pause() }
        .contextMenu {
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
        .accessibilityHidden(true)
    }

    private var playerArea: some View {
        FittedMediaLayout(
            aspectRatio: aspectRatio,
            naturalSize: nil,
            maxWidth: VideoEmbedView.maxPlayerWidth,
            maxHeight: aspectRatio < 1 ? max(style.maxImageHeight, 420) : max(style.maxImageHeight, 270)
        ) {
            ZStack {
                // Letterboxing behind the video is always black.
                Color.black
                if let player {
                    VideoPlayer(player: player)
                } else {
                    posterFacade
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(theme[ThemeKey.embedBorder], lineWidth: player == nil ? 1 : 0)
            )
            .overlay(alignment: .topTrailing) {
                if player != nil {
                    MediaOverlayButton(systemImage: "xmark", label: "Close player", action: stop)
                        .padding(8)
                }
            }
        }
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
            Button {
                if expanded {
                    stop()
                } else {
                    expanded = true
                    play()
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: expanded ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: max(12, style.fontSize + 1)))
                        .foregroundStyle(theme[ThemeKey.accent])
                    Text(EmbedActions.displayName(linkURL))
                        .font(style.font(size: max(10, style.fontSize - 1), weight: .semibold))
                        .foregroundStyle(theme[ThemeKey.embedTitle])
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("· \(EmbedActions.displayHost(linkURL))")
                        .font(style.font(size: max(9, style.fontSize - 2)))
                        .foregroundStyle(theme[ThemeKey.embedSiteName])
                        .lineLimit(1)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .frame(minHeight: 28)
                .embedCard(accent: theme[ThemeKey.embedAccent], cornerRadius: 6, accentWidth: 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(expanded ? "Close video" : "Show video"): \(EmbedActions.displayName(linkURL))")

            if expanded {
                playerArea
            }
        }
        .frame(maxWidth: 520, alignment: .leading)
    }

    private func play() {
        let player = AVPlayer(url: videoURL)
        player.preventsDisplaySleepDuringVideoPlayback = true
        self.player = player
        player.play()
    }

    private func stop() {
        player?.pause()
        player = nil
        expanded = false
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
