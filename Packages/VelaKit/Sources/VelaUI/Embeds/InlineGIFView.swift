// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import AVFoundation
import SwiftUI
import VelaMedia
import VelaTheme

/// A GIF from Tenor, GIPHY, Imgur (`.gifv`) or KLIPY, playing inline like a
/// GIF, with a "via Tenor · tenor.com" caption that opens the link when
/// clicked (and whose text can be selected). KLIPY's opens the GIF's page on
/// klipy.com instead, or klipy.com itself (see `GIFCaption`), and KLIPY's
/// GIFs carry its watermark in the bottom-left corner (`GIFCornerMarks`).
///
/// The site's MP4 rendition plays muted in a loop, with no controls: a tenth
/// of the GIF's size or less, and decoded by the GPU. Without one (stickers,
/// which need transparency), or when it fails to load, the GIF or WebP
/// rendition plays through `InlineImageView` instead.
///
/// Otherwise it behaves like an inline image: sized to the column and
/// `maxImageHeight` (or a thumbnail that plays while hovered), the "GIF"
/// badge pauses and plays, Reduce Motion shows the first frame and a play
/// button, it pauses out of view, clicking opens the viewer, it stays
/// blurred until clicked, and one over `media.maxImageSizeMB` shows a chip.
struct InlineGIFView: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    /// The link as posted (opened by the caption and "Open in Browser").
    let linkURL: URL
    let gif: GIFInfo
    /// The link's policy; every rendition goes through it.
    let policy: MediaPolicy
    let compact: Bool
    let maxImageHeight: CGFloat
    /// Called instead of showing an error when a rendition redirects into a
    /// blocked site, so the link can show why (and offer "Show once").
    var onBlocked: ((SiteBlock) -> Void)?
    let onHide: () -> Void

    /// Why the video shows a chip instead (too large, or nothing to fall back to).
    @State private var videoFailure: ImageLoadFailure?
    /// The video couldn't be loaded, so the image rendition plays instead.
    @State private var fellBack: Bool
    @State private var captionHovering = false

    init(
        linkURL: URL,
        gif: GIFInfo,
        policy: MediaPolicy,
        compact: Bool,
        maxImageHeight: CGFloat,
        onBlocked: ((SiteBlock) -> Void)? = nil,
        onHide: @escaping () -> Void
    ) {
        self.linkURL = linkURL
        self.gif = gif
        self.policy = policy
        self.compact = compact
        self.maxImageHeight = maxImageHeight
        self.onBlocked = onBlocked
        self.onHide = onHide
        // A re-created row starts where the last one ended: on the image
        // rendition, or with the video's chip.
        let failed = gif.videoURL.flatMap { EmbedMemory.shared.failedImages.peek($0) }
        let canFallBack = Self.fallbackImageURL(gif, policy: policy) != nil
        _fellBack = State(initialValue: failed == .unavailable && canFallBack)
        _videoFailure = State(initialValue: failed.flatMap { failure in
            failure.persists(under: policy) && (failure != .unavailable || !canFallBack) ? failure : nil
        })
    }

    /// The image rendition, if there is one the policy lets load.
    private static func fallbackImageURL(_ gif: GIFInfo, policy: MediaPolicy) -> URL? {
        gif.imageURL.flatMap { policy.allowsImage($0) ? $0 : nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let videoURL = gif.videoURL, !fellBack {
                LoopingGIFView(
                    linkURL: linkURL,
                    videoURL: videoURL,
                    gif: gif,
                    policy: policy,
                    compact: compact,
                    maxImageHeight: maxImageHeight,
                    failure: $videoFailure,
                    onFallBack: Self.fallbackImageURL(gif, policy: policy).map { _ in { fellBack = true } },
                    onBlocked: onBlocked,
                    onHide: onHide
                )
            } else if let imageURL = gif.imageURL {
                InlineImageView(
                    linkURL: linkURL,
                    imageURL: imageURL,
                    policy: policy,
                    compact: compact,
                    maxImageHeight: maxImageHeight,
                    onBlocked: onBlocked,
                    watermark: gif.provider.showsWatermark,
                    onHide: onHide
                )
            }
            // A failure chip already names the site.
            if videoFailure == nil || fellBack { caption }
        }
    }

    /// "via GIPHY · giphy.com": the site the GIF comes from, as GIF sites ask.
    /// A click opens what `GIFCaption` says; a drag selects the text.
    private var caption: some View {
        let caption = GIFCaption(provider: gif.provider, linkURL: linkURL)
        return HStack(spacing: 4) {
            Text("via \(caption.siteName)").fontWeight(.semibold)
            Text("· \(caption.host)")
        }
        .font(style.font(size: max(9, style.fontSize - 2)))
        .foregroundStyle(theme[ThemeKey.embedSiteName])
        .underline(captionHovering)
        .lineLimit(1)
        .truncationMode(.middle)
        .textSelection(.enabled)
        .linkClickArea(caption.url)
        .onHover { captionHovering = $0 }
        .help(caption.help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption.accessibilityLabel)
        .accessibilityAddTraits(.isLink)
        .accessibilityHint(caption.accessibilityHint)
        .accessibilityAction { EmbedActions.open(caption.url) }
        .contextMenu { EmbedLinkMenuItems(url: caption.url, onHide: onHide) }
    }
}

/// What a GIF's "via …" caption says, and what a click on it opens.
///
/// Most sites' captions open the link as posted: a GIPHY or Tenor page, or
/// a file on their servers. A KLIPY link is always a file, which names
/// neither the GIF's page nor anything else, so its caption reads
/// "via KLIPY · klipy.com" and opens the GIF's page on klipy.com when Vela
/// knows it (a GIF you sent from the picker since Vela opened, in
/// `SentGIFPages`), and klipy.com otherwise. Made when the caption is drawn:
/// one dictionary lookup, for KLIPY only.
struct GIFCaption: Equatable {
    enum Destination: Equatable {
        /// The link as posted.
        case link
        /// The GIF's own page on the site.
        case gifPage
        /// The site's home page, for a GIF whose page Vela doesn't know.
        case homepage
    }

    /// "KLIPY".
    let siteName: String
    /// "klipy.com", or the link's own host ("media.giphy.com").
    let host: String
    /// What a click opens.
    let url: URL
    let destination: Destination

    init(provider: GIFProvider, linkURL: URL, pages: SentGIFPages = .shared) {
        siteName = provider.displayName
        switch provider {
        case .klipy:
            let homepage = provider.homepage
            let page = pages.page(for: linkURL)
            host = EmbedActions.displayHost(homepage)
            url = page ?? homepage
            destination = page == nil ? .homepage : .gifPage
        case .tenor, .giphy, .imgur:
            host = EmbedActions.displayHost(linkURL)
            url = linkURL
            destination = .link
        }
    }

    var help: String { "Open \(url.absoluteString)" }

    var accessibilityLabel: String { "Via \(siteName), \(host)" }

    var accessibilityHint: String {
        switch destination {
        case .link: "Opens the link in your browser"
        case .gifPage: "Opens the GIF's page on \(siteName) in your browser"
        case .homepage: "Opens \(host) in your browser"
        }
    }
}

// MARK: - Video

/// The MP4 rendition, looping. Its first frame is drawn under the player,
/// so it shows before playback starts, with Reduce Motion, and in snapshots.
private struct LoopingGIFView: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.embedBlur) private var blur
    let linkURL: URL
    let videoURL: URL
    let gif: GIFInfo
    let policy: MediaPolicy
    let compact: Bool
    let maxImageHeight: CGFloat
    @Binding var failure: ImageLoadFailure?
    /// Switches to the image rendition; nil when there is none.
    let onFallBack: (() -> Void)?
    var onBlocked: ((SiteBlock) -> Void)?
    let onHide: () -> Void

    @State private var video: LoadedLoopingVideo?
    @State private var poster: CGImage?
    @State private var pixelSize: CGSize?
    @State private var hovering = false
    /// Set when the user explicitly plays or pauses.
    @State private var userPlayback: Bool?
    /// The GIF's spot is on screen; out of view it pauses.
    @State private var isVisible = true
    /// The player exists. It is made once the GIF has been on screen for
    /// `playerDelay` and kept while paused (so it holds its frame), until
    /// the row goes away.
    @State private var hasPlayer = false
    @State private var arrivedAsync = false

    init(
        linkURL: URL,
        videoURL: URL,
        gif: GIFInfo,
        policy: MediaPolicy,
        compact: Bool,
        maxImageHeight: CGFloat,
        failure: Binding<ImageLoadFailure?>,
        onFallBack: (() -> Void)?,
        onBlocked: ((SiteBlock) -> Void)?,
        onHide: @escaping () -> Void
    ) {
        self.linkURL = linkURL
        self.videoURL = videoURL
        self.gif = gif
        self.policy = policy
        self.compact = compact
        self.maxImageHeight = maxImageHeight
        _failure = failure
        self.onFallBack = onFallBack
        self.onBlocked = onBlocked
        self.onHide = onHide
        let memory = EmbedMemory.shared
        _video = State(initialValue: memory.loopingVideo(for: videoURL, policy: policy))
        // The page's own size reserves the space until the video says.
        _pixelSize = State(initialValue: memory.pixelSize(for: videoURL, policy: policy)
            ?? (policy.allowsImage(videoURL) ? gif.pixelSize : nil))
        _poster = State(initialValue: EmbedImagePipeline.memoizedStill(
            videoURL, maxPixelSize: Self.pixelBudget(compact: compact, maxImageHeight: maxImageHeight), policy: policy
        ))
    }

    private struct LoadKey: Equatable {
        var videoURL: URL
        var pixelBudget: Int
        var policy: MediaPolicy
    }

    private static func pixelBudget(compact: Bool, maxImageHeight: CGFloat) -> Int {
        EmbedImagePipeline.pixelBudget(
            forPoints: compact ? InlineImageView.compactMaxWidth : max(InlineImageView.fullMaxWidth, maxImageHeight)
        )
    }

    /// How long a GIF waits on screen before its player is made: rows that
    /// fly past in a fling show their poster and never build one.
    static let playerDelay: Duration = .milliseconds(200)

    private var pixelBudget: Int { Self.pixelBudget(compact: compact, maxImageHeight: maxImageHeight) }
    private var maxWidth: CGFloat { compact ? InlineImageView.compactMaxWidth : InlineImageView.fullMaxWidth }
    private var maxHeight: CGFloat { compact ? InlineImageView.compactHeight : max(40, maxImageHeight) }
    private var cornerRadius: CGFloat { compact ? 6 : 8 }

    private var shouldAnimate: Bool {
        GIFPlayback.shouldPlay(
            isReady: video != nil && failure == nil,
            isBlurred: blur.isBlurred,
            isVisible: isVisible,
            userChoice: userPlayback,
            reduceMotion: reduceMotion,
            compact: compact,
            hovering: hovering
        )
    }

    var body: some View {
        Group {
            if let failure {
                // "GIF larger than 10 MB · tenor.com · Open"
                EmbedChip(
                    systemImage: failure.systemImage,
                    title: failure.title(for: "GIF"),
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
                    content
                        .blurredMedia(.image(poster), policy: policy, kind: .gif, cornerRadius: cornerRadius)
                }
                .embedFadeIn(arrivedAsync)
            } else {
                MediaPlaceholder(systemImage: "photo.stack", cornerRadius: cornerRadius)
                    .frame(
                        width: compact ? InlineImageView.compactHeight : 240,
                        height: compact ? InlineImageView.compactHeight : min(160, maxHeight)
                    )
            }
        }
        .task(id: LoadKey(videoURL: videoURL, pixelBudget: pixelBudget, policy: policy)) { await load() }
        .onScrollVisibilityChange(threshold: 0.2) { isVisible = $0 }
        .task(id: shouldAnimate) {
            guard shouldAnimate, !hasPlayer else { return }
            // Cancelled if the GIF stops playing or leaves first. A click on
            // play starts it straight away.
            if userPlayback != true {
                do { try await Task.sleep(for: Self.playerDelay) } catch { return }
            }
            hasPlayer = true
        }
        .onAppear { isVisible = true }
        .onDisappear {
            // A recycled row lets its player go; the poster stands in again.
            isVisible = false
            hasPlayer = false
        }
    }

    private var content: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return ZStack {
            if let poster {
                Image(decorative: poster, scale: 1)
                    .resizable()
                    .interpolation(.high)
            } else {
                theme[ThemeKey.embedPlaceholderBackground]
            }
            if hasPlayer, let video {
                LoopingVideoView(fileURL: video.fileURL, isPlaying: shouldAnimate)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(theme[ThemeKey.embedBorder], lineWidth: 1))
        .overlay(alignment: .bottomLeading) {
            GIFCornerMarks(watermark: gif.provider.showsWatermark && (poster != nil || (hasPlayer && video != nil)), compact: compact) {
                AnimationBadge(compact: compact, isPlaying: shouldAnimate, hovering: hovering, toggle: togglePlayback)
            }
        }
        .overlay {
            if video != nil, !compact, !shouldAnimate, isVisible, reduceMotion || userPlayback == false {
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
        .help(compact ? EmbedActions.displayHost(linkURL) : "")
        .contextMenu {
            Button("Open Image Viewer") { openViewer() }
            Button("Open in Browser") { EmbedActions.open(linkURL) }
            Button(shouldAnimate ? "Pause Animation" : "Play Animation") { togglePlayback() }
            Divider()
            EmbedLinkMenuItems(url: linkURL, onHide: onHide)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits([.isImage, .isButton])
        .accessibilityHint("Opens the image viewer")
        .accessibilityAction { openViewer() }
        .accessibilityAction(named: shouldAnimate ? "Pause animation" : "Play animation") { togglePlayback() }
    }

    private var accessibilityLabel: String {
        let name = gif.title.flatMap { $0.isEmpty ? nil : $0 } ?? EmbedActions.displayName(linkURL)
        return "GIF, \(name), via \(gif.provider.displayName)"
    }

    private func togglePlayback() {
        userPlayback = !shouldAnimate
    }

    private func load() async {
        if let failure {
            guard !failure.persists(under: policy) else { return }
            self.failure = nil
        }
        let memory = EmbedMemory.shared
        do {
            let loaded = try await LoopingVideoLoader.shared.load(videoURL, policy: policy)
            memory.remember(loopingVideo: loaded, for: videoURL)
            memory.remember(pixelSize: loaded.pixelSize, for: videoURL)
            if pixelSize == nil, poster == nil { arrivedAsync = true }
            pixelSize = loaded.pixelSize
            video = loaded
            guard poster == nil else { return }
            let budget = pixelBudget
            let key = StillImageKey(url: videoURL, maxPixelSize: budget)
            guard let image = try? await Self.firstFrame(of: loaded.fileURL, maxPixelSize: budget) else { return }
            memory.remember(still: image, for: key)
            poster = image
        } catch MediaError.siteBlocked(let block) where onBlocked != nil {
            onBlocked?(block)
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            let failure = ImageLoadFailure(error, limitBytes: policy.maxImageBytes)
            memory.failedImages.insert(failure, for: videoURL)
            // An MP4 that's missing or unreadable: the GIF itself may still load.
            if failure == .unavailable, let onFallBack {
                onFallBack()
                return
            }
            self.failure = failure
        }
    }

    private func openViewer() {
        guard let video else { return }
        ImageViewer.present(
            ImageViewerItem(linkURL: linkURL, videoURL: videoURL, video: video, poster: poster),
            theme: theme,
            reduceMotion: reduceMotion
        )
    }

    /// The first frame, decoded off the main actor.
    @concurrent
    private static func firstFrame(of fileURL: URL, maxPixelSize: Int) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: fileURL))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        return try await generator.image(at: .zero).image
    }
}

// MARK: - Playback

/// When a GIF plays.
nonisolated enum GIFPlayback {
    /// Never while it's loading, failed, blurred or out of view. Otherwise
    /// as the user chose with play or pause; never by itself with Reduce
    /// Motion; and a thumbnail only while the pointer is over it.
    static func shouldPlay(
        isReady: Bool,
        isBlurred: Bool,
        isVisible: Bool,
        userChoice: Bool?,
        reduceMotion: Bool,
        compact: Bool,
        hovering: Bool
    ) -> Bool {
        guard isReady, !isBlurred, isVisible else { return false }
        if let userChoice { return userChoice }
        if reduceMotion { return false }
        return compact ? hovering : true
    }
}

// MARK: - Player

/// A muted video file playing in a loop: GIF sites' MP4s. No controls and
/// no sound; it never takes clicks or scrolls, which go to the SwiftUI view
/// around it. Hardware-decoded, so many can play at once cheaply.
struct LoopingVideoView: NSViewRepresentable {
    let fileURL: URL
    let isPlaying: Bool

    func makeNSView(context: Context) -> LoopingVideoNSView {
        let view = LoopingVideoNSView()
        view.update(fileURL: fileURL, isPlaying: isPlaying)
        return view
    }

    func updateNSView(_ view: LoopingVideoNSView, context: Context) {
        view.update(fileURL: fileURL, isPlaying: isPlaying)
    }

    static func dismantleNSView(_ view: LoopingVideoNSView, coordinator: ()) {
        view.tearDown()
    }
}

/// `LoopingVideoView`'s view: an `AVPlayerLayer` fed by an `AVPlayerLooper`
/// from `LoopingPlayerPool`.
final class LoopingVideoNSView: NSView {
    private let playerLayer = AVPlayerLayer()
    private var looping: LoopingPlayer?
    private var player: AVQueuePlayer? { looping?.player }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.clear.cgColor
        layer?.addSublayer(playerLayer)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }

    func update(fileURL: URL, isPlaying: Bool) {
        if fileURL != looping?.fileURL {
            tearDown()
            let looping = LoopingPlayerPool.shared.checkOut(fileURL)
            playerLayer.player = looping.player
            self.looping = looping
        }
        if isPlaying {
            if player?.rate == 0 { player?.play() }
        } else {
            player?.pause()
        }
    }

    /// Hands the player back to the pool, paused, for the next view of the
    /// same file (scrolling back to the GIF).
    func tearDown() {
        guard let looping else { return }
        looping.player.pause()
        playerLayer.player = nil
        self.looping = nil
        LoopingPlayerPool.shared.checkIn(looping)
    }
}

/// A muted `AVQueuePlayer` looping one file.
final class LoopingPlayer {
    let fileURL: URL
    let player: AVQueuePlayer
    private var looper: AVPlayerLooper?

    init(fileURL: URL) {
        self.fileURL = fileURL
        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.allowsExternalPlayback = false
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: fileURL))
        self.player = player
    }

    func invalidate() {
        player.pause()
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
    }
}

/// The few looping players most recently let go, by file, so a GIF scrolled
/// back into view reuses its player instead of building another (setting up
/// `AVPlayerLooper` is the expensive part).
final class LoopingPlayerPool {
    static let shared = LoopingPlayerPool()

    /// Paused players hold little but their decoder; a handful covers
    /// scrolling back and forth over the same GIFs.
    let capacity: Int
    /// Least recently returned first.
    private(set) var idle: [LoopingPlayer] = []
    private let makePlayer: @MainActor (URL) -> LoopingPlayer

    init(capacity: Int = 3, makePlayer: @escaping @MainActor (URL) -> LoopingPlayer = { LoopingPlayer(fileURL: $0) }) {
        self.capacity = capacity
        self.makePlayer = makePlayer
    }

    /// A pooled player for `fileURL`, or a new one.
    func checkOut(_ fileURL: URL) -> LoopingPlayer {
        if let index = idle.lastIndex(where: { $0.fileURL == fileURL }) {
            return idle.remove(at: index)
        }
        return makePlayer(fileURL)
    }

    /// Takes back a player no view shows any more.
    func checkIn(_ player: LoopingPlayer) {
        // One per file: the same GIF on two rows comes back twice.
        if let index = idle.firstIndex(where: { $0.fileURL == player.fileURL }) {
            idle.remove(at: index).invalidate()
        }
        idle.append(player)
        while idle.count > capacity {
            idle.removeFirst().invalidate()
        }
    }

    func trim(for level: MemoryPressureLevel) {
        for player in idle { player.invalidate() }
        idle.removeAll()
    }
}
