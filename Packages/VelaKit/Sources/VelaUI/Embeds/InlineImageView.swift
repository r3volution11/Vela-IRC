// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaMedia
import VelaTheme

/// An image posted in chat, sized to fit the column and
/// `chatStyle.maxImageHeight` (or an ~80 pt thumbnail in compact mode).
/// Animated GIF/APNG/WebP play inline; with Reduce Motion they show the first
/// frame and a play button. Clicking opens the full-size viewer. An image
/// over `media.maxImageSizeMB` (or one that fails) shows a chip saying so,
/// e.g. "Image larger than 10 MB", that opens the link in the browser.
///
/// While the link is blurred (`\.embedBlur`) only the image's size is read,
/// for its frame; it is decoded (and animated) once the user reveals it.
struct InlineImageView: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.embedBlur) private var blur
    @Environment(\.displayScale) private var displayScale

    /// The link as posted (opened by "Open in Browser").
    let linkURL: URL
    /// The image itself (may be rewritten, e.g. GitHub blob → raw).
    let imageURL: URL
    /// The link's policy; the image, its size and its memo go through it.
    let policy: MediaPolicy
    let compact: Bool
    let maxImageHeight: CGFloat
    /// Called instead of showing an error when the URL turns out not to be an
    /// image (e.g. an image host's HTML viewer page).
    var onUnsupported: (() -> Void)?
    /// Called instead of showing an error when the image redirects into a
    /// blocked site, so the link can show why (and offer "Show once").
    var onBlocked: ((SiteBlock) -> Void)?
    /// KLIPY's watermark goes in the corner while the picture shows (a
    /// KLIPY GIF; see `GIFCornerMarks`).
    var watermark = false
    let onHide: () -> Void

    /// Widest an inline image gets in full mode, even in a very wide window.
    static let fullMaxWidth: CGFloat = 720
    static let compactMaxWidth: CGFloat = 160
    static let compactHeight: CGFloat = 80

    @State private var still: CGImage?
    @State private var pixelSize: CGSize?
    /// Why the image shows a chip instead (too large, or it didn't load).
    @State private var failure: ImageLoadFailure?
    @State private var isAnimated = false
    @State private var player = AnimatedImagePlayer()
    @State private var hovering = false
    /// Set when the user explicitly plays or pauses an animation.
    @State private var userPlayback: Bool?
    @State private var arrivedAsync = false

    init(
        linkURL: URL,
        imageURL: URL,
        policy: MediaPolicy,
        compact: Bool,
        maxImageHeight: CGFloat,
        onUnsupported: (() -> Void)? = nil,
        onBlocked: ((SiteBlock) -> Void)? = nil,
        watermark: Bool = false,
        onHide: @escaping () -> Void
    ) {
        self.linkURL = linkURL
        self.imageURL = imageURL
        self.policy = policy
        self.compact = compact
        self.maxImageHeight = maxImageHeight
        self.onUnsupported = onUnsupported
        self.onBlocked = onBlocked
        self.watermark = watermark
        self.onHide = onHide
        let memory = EmbedMemory.shared
        _pixelSize = State(initialValue: memory.pixelSize(for: imageURL, policy: policy))
        // A too-large image gets another try once the size limit is raised.
        _failure = State(initialValue: memory.failedImages.value(for: imageURL).flatMap {
            $0.persists(under: policy) ? $0 : nil
        })
        _still = State(initialValue: EmbedImagePipeline.memoizedStill(
            imageURL, maxPixelSize: Self.pixelBudget(compact: compact, maxImageHeight: maxImageHeight), policy: policy
        ))
    }

    /// Reloads when the image, its size, the policy or the blur changes
    /// (or the display's scale, which animation frames are decoded for).
    private struct LoadKey: Equatable {
        var imageURL: URL
        var pixelBudget: Int
        var policy: MediaPolicy
        var blurred: Bool
        var displayScale: CGFloat
    }

    private static func pixelBudget(compact: Bool, maxImageHeight: CGFloat) -> Int {
        EmbedImagePipeline.pixelBudget(forPoints: compact ? compactMaxWidth : max(fullMaxWidth, maxImageHeight))
    }

    private var maxWidth: CGFloat { compact ? Self.compactMaxWidth : Self.fullMaxWidth }
    private var maxHeight: CGFloat { compact ? Self.compactHeight : max(40, maxImageHeight) }
    private var cornerRadius: CGFloat { compact ? 6 : 8 }

    private var shouldAnimate: Bool {
        guard isAnimated, failure == nil, !blur.isBlurred else { return false }
        if let userPlayback { return userPlayback }
        if reduceMotion { return false }
        return compact ? hovering : true
    }

    var body: some View {
        Group {
            if let failure {
                // "Image larger than 10 MB · upload.wikimedia.org · Open"
                EmbedChip(
                    systemImage: failure.systemImage,
                    title: failure.title,
                    detail: EmbedActions.displayHost(linkURL),
                    isError: failure.isError,
                    actionTitle: "Open",
                    help: "Open \(linkURL.absoluteString) in your browser"
                ) {
                    EmbedActions.open(linkURL)
                }
                .contextMenu { EmbedLinkMenuItems(url: linkURL, onHide: onHide) }
            } else if let pixelSize {
                FittedMediaLayout(
                    aspectRatio: pixelSize.width / max(1, pixelSize.height),
                    naturalSize: pixelSize,
                    maxWidth: maxWidth,
                    maxHeight: maxHeight
                ) {
                    imageContent
                        .blurredMedia(.url(imageURL), policy: policy, kind: .image, cornerRadius: cornerRadius)
                }
                .embedFadeIn(arrivedAsync)
            } else {
                MediaPlaceholder(cornerRadius: cornerRadius)
                    .frame(width: compact ? Self.compactHeight : 240, height: compact ? Self.compactHeight : min(160, maxHeight))
            }
        }
        .task(id: LoadKey(
            imageURL: imageURL,
            pixelBudget: Self.pixelBudget(compact: compact, maxImageHeight: maxImageHeight),
            policy: policy,
            blurred: blur.isBlurred,
            displayScale: displayScale
        )) { await load() }
        .onChange(of: shouldAnimate) { _, animate in
            animate ? player.play() : player.pause()
        }
        .onAppear { if shouldAnimate { player.play() } }
        .onDisappear { player.pause() }
    }

    private var imageContent: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return ZStack {
            if let still {
                Image(decorative: still, scale: 1)
                    .resizable()
                    .interpolation(.high)
            } else {
                theme[ThemeKey.embedPlaceholderBackground]
            }
            // Frames go straight to this view's layer; this body doesn't
            // run for them.
            if player.hasFrame {
                AnimatedFrameView(player: player, cornerRadius: cornerRadius)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(theme[ThemeKey.embedBorder], lineWidth: 1))
        .overlay(alignment: .bottomLeading) {
            GIFCornerMarks(watermark: watermark && (still != nil || player.hasFrame), compact: compact) {
                if isAnimated {
                    AnimationBadge(compact: compact, isPlaying: player.isPlaying, hovering: hovering, toggle: togglePlayback)
                }
            }
        }
        .overlay {
            if isAnimated, !compact, !player.isPlaying, reduceMotion || userPlayback == false {
                Button {
                    userPlayback = true
                } label: {
                    PlayGlyph(diameter: 44, hovering: hovering)
                }
                .buttonStyle(.plain)
                .help("Play animation")
                .accessibilityLabel("Play animation")
            }
        }
        .contentShape(shape)
        .onTapGesture { openViewer() }
        .onHover { hovering = $0 }
        .help(compact ? EmbedActions.displayName(linkURL) : "")
        .contextMenu {
            Button("Open Image Viewer") { openViewer() }
            Button("Open in Browser") { EmbedActions.open(linkURL) }
            Button("Copy Image") { copyImage() }
            if isAnimated {
                Button(player.isPlaying ? "Pause Animation" : "Play Animation") { togglePlayback() }
            }
            Divider()
            EmbedLinkMenuItems(url: linkURL, onHide: onHide)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits([.isImage, .isButton])
        .accessibilityHint("Opens the image viewer")
        .accessibilityAction { openViewer() }
        .accessibilityAction(named: isAnimated ? (player.isPlaying ? "Pause animation" : "Play animation") : "Open in browser") {
            if isAnimated { togglePlayback() } else { EmbedActions.open(linkURL) }
        }
    }

    private var accessibilityLabel: String {
        let kind = isAnimated ? "Animated image" : "Image"
        return "\(kind), \(EmbedActions.displayName(linkURL))"
    }

    private func togglePlayback() {
        userPlayback = !player.isPlaying
    }

    private func load() async {
        if let failure {
            guard !failure.persists(under: policy) else { return }
            self.failure = nil
        }
        let hadStill = still != nil
        do {
            if blur.isBlurred {
                // The stand-in draws from a tiny copy of its own; the image
                // only needs its size here, which reading it doesn't decode.
                guard pixelSize == nil else { return }
                let loaded = try await ImageLoader.shared.load(imageURL, policy: policy)
                EmbedMemory.shared.remember(pixelSize: loaded.pixelSize, for: imageURL)
                if !hadStill { arrivedAsync = true }
                pixelSize = loaded.pixelSize
                return
            }
            let result = try await EmbedImagePipeline.still(
                imageURL,
                maxPixelSize: Self.pixelBudget(compact: compact, maxImageHeight: maxImageHeight),
                policy: policy
            )
            if !hadStill && pixelSize == nil { arrivedAsync = true }
            pixelSize = result.info.pixelSize
            still = result.image
            if result.info.isAnimated {
                let frameBudget = AnimatedFrames.pixelBudget(
                    pixelSize: result.info.pixelSize, maxWidth: maxWidth, maxHeight: maxHeight, scale: displayScale
                )
                player.load(result.info.data, frameCount: result.info.frameCount, maxPixelSize: frameBudget)
                isAnimated = true
                if shouldAnimate { player.play() }
            }
        } catch MediaError.unsupportedContent where onUnsupported != nil {
            onUnsupported?()
        } catch MediaError.siteBlocked(let block) where onBlocked != nil {
            onBlocked?(block)
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            let failure = ImageLoadFailure(error, limitBytes: policy.maxImageBytes)
            EmbedMemory.shared.failedImages.insert(failure, for: imageURL)
            self.failure = failure
        }
    }

    private func openViewer() {
        let theme = theme
        let reduceMotion = reduceMotion
        Task {
            guard let loaded = try? await ImageLoader.shared.load(imageURL, policy: policy) else { return }
            ImageViewer.present(
                ImageViewerItem(linkURL: linkURL, imageURL: imageURL, image: loaded),
                theme: theme,
                reduceMotion: reduceMotion
            )
        }
    }

    private func copyImage() {
        Task {
            guard let loaded = try? await ImageLoader.shared.load(imageURL, policy: policy) else { return }
            EmbedActions.copyImage(data: loaded.data, utType: loaded.utType)
        }
    }
}

/// The "GIF" capsule in the corner of an animation. In full size it is a
/// button that pauses and plays, with ▶ or ❙❙ while hovered or paused;
/// without `toggle` (a facade that hasn't played yet) it's just the label.
struct AnimationBadge: View {
    @Environment(\.theme) private var theme
    let compact: Bool
    let isPlaying: Bool
    let hovering: Bool
    let toggle: (() -> Void)?

    var body: some View {
        let label = HStack(spacing: 3) {
            if !compact, toggle != nil, hovering || !isPlaying {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 8, weight: .bold))
            }
            Text("GIF")
                .font(.system(size: compact ? 8 : 9, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(theme[ThemeKey.chatForeground])
        .padding(.horizontal, compact ? 4 : 6)
        .padding(.vertical, compact ? 1.5 : 3)
        .background(Capsule().fill(theme[ThemeKey.chatBackground].opacity(0.82)))

        if compact || toggle == nil {
            label.accessibilityHidden(true)
        } else if let toggle {
            Button(action: toggle) { label }
                .buttonStyle(.plain)
                .help(isPlaying ? "Pause animation" : "Play animation")
                .accessibilityLabel(isPlaying ? "Pause animation" : "Play animation")
        }
    }
}
