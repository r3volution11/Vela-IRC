// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import CoreImage
import SwiftUI
import VelaMedia
import VelaTheme

// "Blur images until clicked" (`media.blurImages`, `media.blurredBuffers`).
//
// `LinkEmbedView` puts each link's blur state in the environment
// (`\.embedBlur`); media views mark their images with `.blurredMedia(…)`.
// While blurred, the marked view is replaced by a stand-in drawn from a
// 24-pixel copy of the image, so the real view never loads, decodes, plays
// or opens anything. The first click only reveals.

// MARK: - State

/// Whether the link being drawn has its media blurred, and how to reveal it
/// (or blur it again). The default blurs nothing.
nonisolated struct EmbedBlur: Hashable, Sendable {
    /// Draw the link's images as blurred stand-ins until clicked.
    var isBlurred = false
    /// Revealed in a buffer that blurs images: menus offer "Blur Again".
    var canBlurAgain = false
    /// The link these apply to; nil outside a link preview.
    var target: Target?

    struct Target: Hashable, Sendable {
        var lineID: UUID
        /// `EmbedLink.id`.
        var linkID: String
        /// The link as posted, for the stand-in's menu and VoiceOver label.
        var linkURL: URL
    }

    /// Shows the link's media (until relaunch or "Blur Again").
    @MainActor func reveal(in store: EmbedLineStore = .shared) {
        guard let target else { return }
        store.setRevealed(true, lineID: target.lineID, linkID: target.linkID)
    }

    /// "Blur Again" on revealed media.
    @MainActor func blurAgain(in store: EmbedLineStore = .shared) {
        guard let target else { return }
        store.setRevealed(false, lineID: target.lineID, linkID: target.linkID)
    }

    /// "Hide Previews" for the link's line.
    @MainActor func hidePreviews(in store: EmbedLineStore = .shared) {
        guard let target else { return }
        store.setCollapsed(true, for: target.lineID)
    }
}

extension EnvironmentValues {
    /// The blur state of the link preview being drawn (see ``EmbedBlur``).
    @Entry var embedBlur = EmbedBlur()
}

extension EmbedLineStore {
    /// The blur state for `link`, given its `decision`: blurred when the
    /// decision says so; once revealed, whether it would be blurred again
    /// (so "Blur Again" is only offered where blurring applies).
    func blur(
        for link: EmbedLink,
        in lineID: UUID,
        decision: PreviewDecision,
        preview: LinkPreview?,
        fetchBlock: SiteBlock?,
        context: VelaMedia.PreviewContext
    ) -> EmbedBlur {
        var blur = EmbedBlur(
            isBlurred: decision.blurred,
            target: EmbedBlur.Target(lineID: lineID, linkID: link.id, linkURL: link.url)
        )
        var overrides = overrides(lineID: lineID, linkID: link.id)
        if !decision.blurred, context.blurImages, overrides.revealed {
            overrides.revealed = false
            blur.canBlurAgain = PreviewDecider.decide(
                url: link.url,
                classification: link.classification,
                preview: preview,
                fetchBlock: fetchBlock,
                context: context,
                overrides: overrides
            ).blurred
        }
        return blur
    }
}

// MARK: - Modifier

/// What a blurred stand-in draws its blur from.
enum BlurredMediaSource {
    /// An image to load (through the link's policy). Only a
    /// ``BlurredMedia/pixelSize``-pixel copy is ever decoded for it.
    case url(URL)
    /// An image already in memory (a video's poster frame), shrunk first.
    case image(CGImage?)
    /// Nothing to show: a plain tinted stand-in.
    case none
}

/// What is blurred, for the stand-in's menu and VoiceOver label.
enum BlurredMediaKind {
    case image
    /// A link card's image or thumbnail.
    case thumbnail
    /// A video's thumbnail or poster frame.
    case video

    var noun: String {
        switch self {
        case .image: "image"
        case .thumbnail: "preview image"
        case .video: "video thumbnail"
        }
    }

    var showTitle: String {
        switch self {
        case .image: "Show Image"
        case .thumbnail: "Show Preview Image"
        case .video: "Show Video Thumbnail"
        }
    }
}

extension View {
    /// While the link's media is blurred (`\.embedBlur`), draws a blurred
    /// stand-in instead of this view, and the view itself isn't created: it
    /// loads, decodes, plays and opens nothing until the first click
    /// reveals it.
    ///
    /// Put it on the clickable media itself (a video's whole ▶ facade, so
    /// the first click doesn't play), inside any fixed `.frame`: the
    /// stand-in fills the size it's offered.
    ///
    ///     facade.blurredMedia(.url(thumbnailURL), policy: policy, kind: .video)
    func blurredMedia(
        _ source: BlurredMediaSource,
        policy: MediaPolicy,
        kind: BlurredMediaKind = .image,
        cornerRadius: CGFloat = 6
    ) -> some View {
        modifier(BlurredMediaModifier(source: source, policy: policy, kind: kind, cornerRadius: cornerRadius))
    }
}

private struct BlurredMediaModifier: ViewModifier {
    @Environment(\.embedBlur) private var blur
    let source: BlurredMediaSource
    let policy: MediaPolicy
    let kind: BlurredMediaKind
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if blur.isBlurred {
            BlurredMediaStandIn(source: source, policy: policy, kind: kind, cornerRadius: cornerRadius)
                .transition(.opacity)
        } else {
            content
        }
    }
}

nonisolated enum BlurredMedia {
    /// The longest side, in pixels, of the copy a stand-in is drawn from:
    /// enough for the image's colors and rough shapes, nothing more.
    static let pixelSize = 24
    /// The longest side of the softened copy that is actually drawn.
    static let softenedSize = 96

    /// Stand-in images by image URL, ready to draw.
    @MainActor static var memo = MemoCache<URL, CGImage>(countLimit: 300)

    /// The remembered stand-in image for `url`, if `policy` lets it load.
    @MainActor static func memoized(_ url: URL, policy: MediaPolicy) -> CGImage? {
        guard policy.allowsImage(url) else { return nil }
        return memo.value(for: url)
    }

    /// Loads `url` through the image pipeline at `pixelSize` (only that much
    /// is decoded) and softens it.
    @MainActor static func standIn(for url: URL, policy: MediaPolicy) async throws -> CGImage? {
        if let memoized = memoized(url, policy: policy) { return memoized }
        let still = try await EmbedImagePipeline.still(url, maxPixelSize: pixelSize, policy: policy).image
        let tiny = EmbedImagePipeline.trimmingLetterbox(still, of: url)
        guard let softened = await soften(tiny) else { return nil }
        memo.insert(softened, for: url)
        return softened
    }

    /// A stand-in image for a picture already in memory (a poster frame).
    static func standIn(for image: CGImage) async -> CGImage? {
        guard let tiny = await shrink(image) else { return nil }
        return await soften(tiny)
    }

    /// `image` shrunk to `pixelSize` on its longest side, off the main actor.
    @concurrent
    static func shrink(_ image: CGImage, to side: Int = pixelSize) async -> CGImage? {
        let longest = max(image.width, image.height)
        guard longest > 0 else { return nil }
        guard longest > side else { return image }
        let scale = Double(side) / Double(longest)
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// The few-pixel `image` scaled up smoothly to `softenedSize` and
    /// blurred, so it reads as soft shapes at any size it's drawn (and
    /// costs no live blur filter while scrolling).
    @concurrent
    static func soften(_ image: CGImage) async -> CGImage? {
        let longest = max(image.width, image.height)
        guard longest > 0 else { return nil }
        let scale = CGFloat(softenedSize) / CGFloat(longest)
        let source = CIImage(cgImage: image).samplingLinear()
        let extent = CGRect(
            x: 0, y: 0,
            width: (CGFloat(image.width) * scale).rounded(),
            height: (CGFloat(image.height) * scale).rounded()
        )
        let blurred = source
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .clampedToExtent()
            // About one source pixel: the blocks melt into each other.
            .applyingGaussianBlur(sigma: Double(scale))
            .cropped(to: extent)
        return ciContext.createCGImage(blurred, from: extent)
    }

    /// CIContext is thread-safe and costly to make; one is shared.
    nonisolated(unsafe) private static let ciContext = CIContext(options: [.cacheIntermediates: false])
}

// MARK: - Stand-in

/// A softened, upscaled 24-pixel copy of the image with an eye-slash and
/// "Click to show". Clicking reveals the link's media; with Reduce Motion
/// the image appears at once instead of fading in.
private struct BlurredMediaStandIn: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.embedBlur) private var blur
    let source: BlurredMediaSource
    let policy: MediaPolicy
    let kind: BlurredMediaKind
    let cornerRadius: CGFloat

    @State private var tiny: CGImage?
    @State private var hovering = false

    init(source: BlurredMediaSource, policy: MediaPolicy, kind: BlurredMediaKind, cornerRadius: CGFloat) {
        self.source = source
        self.policy = policy
        self.kind = kind
        self.cornerRadius = cornerRadius
        if case .url(let url) = source {
            _tiny = State(initialValue: BlurredMedia.memoized(url, policy: policy))
        }
    }

    private struct LoadKey: Equatable {
        var url: URL?
        var image: ObjectIdentifier?
        var policy: MediaPolicy
    }

    private var loadKey: LoadKey {
        switch source {
        case .url(let url): LoadKey(url: url, policy: policy)
        case .image(let image): LoadKey(image: image.map { ObjectIdentifier($0) }, policy: policy)
        case .none: LoadKey(policy: policy)
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Button(action: reveal) {
            // Exactly the offered size, whatever the image's shape.
            Color.clear
                .overlay { backdrop }
                .overlay { label.padding(3) }
                .clipShape(shape)
                .overlay(shape.strokeBorder(theme[ThemeKey.embedBorder], lineWidth: 1))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
        .help("Click to show")
        .contextMenu {
            Button(kind.showTitle, action: reveal)
            if let url = blur.target?.linkURL {
                Divider()
                EmbedLinkMenuItems(url: url, onHide: { blur.hidePreviews() })
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Shows the \(kind.noun)")
        .accessibilityAction { reveal() }
        .accessibilityAction(named: "Show", reveal)
        .task(id: loadKey) { await load() }
    }

    private var accessibilityLabel: String {
        let name = blur.target.map { ", \(EmbedActions.displayName($0.linkURL))" } ?? ""
        return "Blurred \(kind.noun)\(name)"
    }

    private var backdrop: some View {
        ZStack {
            theme[ThemeKey.embedPlaceholderBackground]
            if let tiny {
                Image(decorative: tiny, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            }
            // Keeps the label readable on any image; lifts a little on hover.
            theme[ThemeKey.chatBackground].opacity(hovering ? 0.12 : 0.24)
        }
    }

    /// "Click to show" when there's room, else just the eye.
    private var label: some View {
        let text = theme[ThemeKey.chatForeground]
        let chip = theme[ThemeKey.chatBackground].opacity(hovering ? 0.92 : 0.8)
        return ViewThatFits {
            HStack(spacing: 6) {
                Image(systemName: "eye.slash.fill")
                Text("Click to show")
            }
            .font(style.font(size: max(10, style.fontSize - 1), weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(chip))

            Image(systemName: "eye.slash.fill")
                .font(.system(size: 11, weight: .semibold))
                .padding(6)
                .background(Circle().fill(chip))

            // A Minimal card's tiny thumbnail.
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 7, weight: .bold))
                .padding(.horizontal, 3)
                .padding(.vertical, 2)
                .background(Capsule().fill(chip))
        }
        .foregroundStyle(text)
    }

    private func reveal() {
        if reduceMotion {
            blur.reveal()
        } else {
            withAnimation(.easeOut(duration: 0.22)) { blur.reveal() }
        }
    }

    private func load() async {
        switch source {
        case .url(let url):
            // A site that turned text-only or blocked drops what it showed.
            guard policy.allowsImage(url) else {
                tiny = nil
                return
            }
            guard tiny == nil else { return }
            // Failures keep the plain stand-in; the image itself reports them once revealed.
            tiny = try? await BlurredMedia.standIn(for: url, policy: policy)
        case .image(let image):
            guard let image else {
                tiny = nil
                return
            }
            tiny = await BlurredMedia.standIn(for: image)
        case .none:
            tiny = nil
        }
    }
}
