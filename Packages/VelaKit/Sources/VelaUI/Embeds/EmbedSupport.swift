// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VelaCore
import VelaMedia
import VelaTheme

// Shared building blocks for inline media: main-actor memo caches, image
// loading, layouts that reserve exact space for media, chips, placeholders.

// MARK: - Memo caches

/// A small least-recently-used cache for the main actor. The media services
/// are actors, so asking them costs an async hop; rows that SwiftUI re-creates
/// (scrolling a lazy list, switching buffers) seed their state from these
/// memos instead and render known media on the first frame.
struct MemoCache<Key: Hashable, Value> {
    private struct Entry {
        var value: Value
        var cost: Int
        var tick: UInt64
    }

    private var entries: [Key: Entry] = [:]
    private var tick: UInt64 = 0
    private var totalCost = 0
    let countLimit: Int
    let costLimit: Int

    init(countLimit: Int, costLimit: Int = .max) {
        self.countLimit = countLimit
        self.costLimit = costLimit
    }

    mutating func value(for key: Key) -> Value? {
        guard var entry = entries[key] else { return nil }
        tick &+= 1
        entry.tick = tick
        entries[key] = entry
        return entry.value
    }

    func peek(_ key: Key) -> Value? { entries[key]?.value }

    mutating func insert(_ value: Value, for key: Key, cost: Int = 1) {
        tick &+= 1
        if let old = entries[key] { totalCost -= old.cost }
        entries[key] = Entry(value: value, cost: cost, tick: tick)
        totalCost += cost
        while entries.count > countLimit || (totalCost > costLimit && entries.count > 1) {
            guard let oldest = entries.min(by: { $0.value.tick < $1.value.tick }) else { break }
            totalCost -= oldest.value.cost
            entries.removeValue(forKey: oldest.key)
        }
    }

    mutating func removeValue(for key: Key) {
        if let old = entries.removeValue(forKey: key) { totalCost -= old.cost }
    }
}

nonisolated struct StillImageKey: Hashable, Sendable {
    var url: URL
    var maxPixelSize: Int
}

/// What the embed views remember on the main actor between re-creations.
///
/// Previews, decoded images and image sizes are only handed out under a
/// policy that allows them, so a site that became text-only or blocked never
/// draws (or lays out for) an image remembered from before.
final class EmbedMemory {
    static let shared = EmbedMemory()

    private var previews = MemoCache<URL, LinkPreview>(countLimit: 500)
    /// Decoded, downsampled images ready to draw (≈96 MB budget).
    private var stills = MemoCache<StillImageKey, CGImage>(countLimit: 400, costLimit: 96 * 1024 * 1024)
    /// Pixel sizes of images seen so far, to reserve their space up front.
    private var pixelSizes = MemoCache<URL, CGSize>(countLimit: 2_000)
    /// Images that failed to load, and why, so a re-created row shows its
    /// chip immediately instead of flashing a placeholder.
    var failedImages = MemoCache<URL, ImageLoadFailure>(countLimit: 500)
    /// The site block a link's last fetch failed with (a redirect into a
    /// blocked site), so a re-created row shows its chip on the first frame.
    /// `PreviewDecider` ignores it once the block is lifted.
    var fetchBlocks = MemoCache<URL, SiteBlock>(countLimit: 500)
    /// Links detected per chat line.
    var links = MemoCache<UUID, (text: String, links: [EmbedLink])>(countLimit: 2_000)

    init() {}

    /// The remembered preview for the link `url`, unless `policy` refuses the link.
    func preview(for url: URL, policy: MediaPolicy) -> LinkPreview? {
        guard policy.allows(url) else { return nil }
        return previews.value(for: url)
    }

    func remember(_ preview: LinkPreview, for url: URL) {
        previews.insert(preview, for: url)
    }

    /// A decoded image, if `policy` lets `key.url` load as an image.
    func still(_ key: StillImageKey, policy: MediaPolicy) -> CGImage? {
        guard policy.allowsImage(key.url) else { return nil }
        return stills.value(for: key)
    }

    func remember(still image: CGImage, for key: StillImageKey) {
        stills.insert(image, for: key, cost: image.bytesPerRow * image.height)
    }

    /// An image's pixel size, if `policy` lets `url` load as an image.
    func pixelSize(for url: URL, policy: MediaPolicy) -> CGSize? {
        guard policy.allowsImage(url) else { return nil }
        return pixelSizes.value(for: url)
    }

    func remember(pixelSize: CGSize, for url: URL) {
        pixelSizes.insert(pixelSize, for: url)
    }
}

// MARK: - Image pipeline

enum EmbedImagePipeline {
    /// Downloads (policy-checked) and decodes `url` to at most `maxPixelSize`
    /// on its longest side. Records the image's pixel size in `EmbedMemory`.
    static func still(_ url: URL, maxPixelSize: Int, policy: MediaPolicy) async throws -> (image: CGImage, info: LoadedImage) {
        let loaded = try await ImageLoader.shared.load(url, policy: policy)
        let memory = EmbedMemory.shared
        memory.remember(pixelSize: loaded.pixelSize, for: url)
        let key = StillImageKey(url: url, maxPixelSize: maxPixelSize)
        if let memo = memory.still(key, policy: policy) { return (memo, loaded) }
        let longest = Int(max(loaded.pixelSize.width, loaded.pixelSize.height).rounded(.up))
        let target = max(1, min(maxPixelSize, longest))
        // `load(_:policy:)` above put the bytes in the loader's cache, so this
        // decodes without a second download.
        let image = try await ImageLoader.shared.downsampledImage(url, maxPixelSize: target, policy: policy)
        memory.remember(still: image, for: key)
        return (image, loaded)
    }

    /// The decoded image from an earlier `still(_:maxPixelSize:policy:)`,
    /// if `policy` still allows it.
    static func memoizedStill(_ url: URL, maxPixelSize: Int, policy: MediaPolicy) -> CGImage? {
        EmbedMemory.shared.still(StillImageKey(url: url, maxPixelSize: maxPixelSize), policy: policy)
    }

    /// `image` (decoded from `url`) without the black bars baked into
    /// letterboxed video thumbnails (`LetterboxedThumbnail`), for views that
    /// fill or fit a frame with it. Other images are returned as they are.
    static func trimmingLetterbox(_ image: CGImage, of url: URL) -> CGImage {
        guard let rect = LetterboxedThumbnail.pictureRect(url: url, pixelWidth: image.width, pixelHeight: image.height)
        else { return image }
        return image.cropping(to: rect) ?? image
    }

    /// Pixel budget for an image drawn at most `points` wide/high on a Retina display.
    static func pixelBudget(forPoints points: CGFloat) -> Int {
        Int((points * 2).rounded(.up))
    }
}

/// A remote image (thumbnail, favicon) loaded through `ImageLoader` with the
/// media policy, drawn with `placeholder` until it arrives. A video
/// thumbnail with black bars baked in is drawn without them.
struct RemoteImageView<Placeholder: View>: View {
    let url: URL
    let maxPixelSize: Int
    let policy: MediaPolicy
    var contentMode: ContentMode = .fill
    var onLoad: ((CGSize) -> Void)?
    /// Called when the image can't be loaded or decoded (not when the task
    /// is cancelled), so a layout that reserved room for it can drop it.
    var onFailure: (() -> Void)?
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: CGImage?

    init(
        url: URL,
        maxPixelSize: Int,
        policy: MediaPolicy,
        contentMode: ContentMode = .fill,
        onLoad: ((CGSize) -> Void)? = nil,
        onFailure: (() -> Void)? = nil,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.maxPixelSize = maxPixelSize
        self.policy = policy
        self.contentMode = contentMode
        self.onLoad = onLoad
        self.onFailure = onFailure
        self.placeholder = placeholder
        _image = State(initialValue: EmbedImagePipeline.memoizedStill(url, maxPixelSize: maxPixelSize, policy: policy)
            .map { EmbedImagePipeline.trimmingLetterbox($0, of: url) })
    }

    private struct LoadKey: Equatable {
        var still: StillImageKey
        var policy: MediaPolicy
    }

    var body: some View {
        // Always exactly the proposed size: a filled image is centered and
        // cropped rather than spilling out of its frame.
        Color.clear
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: contentMode)
                } else {
                    placeholder()
                }
            }
            .clipped()
            .task(id: LoadKey(still: StillImageKey(url: url, maxPixelSize: maxPixelSize), policy: policy)) {
            // A site that turned text-only or blocked drops what it showed.
            guard policy.allowsImage(url) else {
                image = nil
                return
            }
            if let image {
                onLoad?(CGSize(width: image.width, height: image.height))
                return
            }
            // Failures keep the placeholder; thumbnails and favicons are optional.
            do {
                let result = try await EmbedImagePipeline.still(url, maxPixelSize: maxPixelSize, policy: policy)
                image = EmbedImagePipeline.trimmingLetterbox(result.image, of: url)
                onLoad?(LetterboxedThumbnail.pictureSize(url: url, pixelSize: result.info.pixelSize))
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                onFailure?()
            }
        }
    }
}

// MARK: - Layouts

/// Sizes media to its aspect ratio within a width cap (the column width or
/// `maxWidth`, whichever is smaller), `maxHeight`, and optionally its natural
/// size, so the exact space is reserved as soon as the dimensions are known.
struct FittedMediaLayout: Layout {
    /// Width divided by height.
    var aspectRatio: CGFloat
    /// The media's own size in points; it is never scaled up past this.
    var naturalSize: CGSize?
    var maxWidth: CGFloat
    var maxHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let proposed = proposal.width ?? .infinity
        return fittedSize(availableWidth: proposed.isFinite ? min(proposed, maxWidth) : maxWidth)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
        }
    }

    func fittedSize(availableWidth: CGFloat) -> CGSize {
        let ratio = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 16.0 / 9.0
        var width = max(0, availableWidth)
        var height = maxHeight
        if let naturalSize, naturalSize.width > 0, naturalSize.height > 0 {
            width = min(width, naturalSize.width)
            height = min(height, naturalSize.height)
        }
        // Fit the ratio inside width × height.
        if width / ratio > height {
            width = height * ratio
        } else {
            height = width / ratio
        }
        return CGSize(width: width.rounded(), height: height.rounded())
    }
}

/// Marks the subview whose width an `EmbedColumnLayout` should hug.
nonisolated private struct PrimaryMediaKey: LayoutValueKey {
    static let defaultValue = false
}

extension View {
    /// The column around this view takes its width (e.g. a video player).
    func embedPrimaryMedia() -> some View {
        layoutValue(key: PrimaryMediaKey.self, value: true)
    }
}

/// A leading-aligned vertical stack for card content. It hugs the width of
/// the subview marked `embedPrimaryMedia()` (at least `minWidth`) or, without
/// one, the widest subview's ideal width, capped at `maxWidth` and the
/// proposal. Text wraps to that width. Zero-height subviews get no spacing.
struct EmbedColumnLayout: Layout {
    var spacing: CGFloat = 6
    var minWidth: CGFloat = 220
    var maxWidth: CGFloat = 520

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = columnWidth(proposal: proposal, subviews: subviews)
        var height: CGFloat = 0
        var placedAny = false
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            guard size.height > 0 else { continue }
            height += size.height + (placedAny ? spacing : 0)
            placedAny = true
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        var placedAny = false
        for subview in subviews {
            let childProposal = ProposedViewSize(width: bounds.width, height: nil)
            let size = subview.sizeThatFits(childProposal)
            guard size.height > 0 else {
                subview.place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: bounds.width, height: 0))
                continue
            }
            if placedAny { y += spacing }
            subview.place(at: CGPoint(x: bounds.minX, y: y), proposal: childProposal)
            y += size.height
            placedAny = true
        }
    }

    private func columnWidth(proposal: ProposedViewSize, subviews: Subviews) -> CGFloat {
        let proposed = proposal.width ?? .infinity
        let available = proposed.isFinite ? min(proposed, maxWidth) : maxWidth
        if let media = subviews.first(where: { $0[PrimaryMediaKey.self] }) {
            let mediaWidth = media.sizeThatFits(ProposedViewSize(width: available, height: nil)).width
            return min(available, max(mediaWidth, min(minWidth, available)))
        }
        let ideal = subviews.reduce(CGFloat(0)) { widest, subview in
            max(widest, subview.sizeThatFits(.unspecified).width)
        }
        return min(available, max(ideal, 0))
    }
}

// MARK: - Chrome

/// The rounded card every embed sits in: `embed.background`, `embed.border`
/// and an optional accent bar on the leading edge.
struct EmbedCardChrome: ViewModifier {
    @Environment(\.theme) private var theme
    var accent: Color?
    var cornerRadius: CGFloat = 8
    var accentWidth: CGFloat = 4

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        HStack(spacing: 0) {
            if let accent {
                Rectangle().fill(accent).frame(width: accentWidth)
            }
            content
        }
        .background(theme[ThemeKey.embedBackground])
        .clipShape(shape)
        .overlay(shape.strokeBorder(theme[ThemeKey.embedBorder], lineWidth: 1))
    }
}

extension View {
    func embedCard(accent: Color?, cornerRadius: CGFloat = 8, accentWidth: CGFloat = 4) -> some View {
        modifier(EmbedCardChrome(accent: accent, cornerRadius: cornerRadius, accentWidth: accentWidth))
    }

    /// Fades the view in when it first appears, unless Reduce Motion is on or
    /// `enabled` is false (content that was already known shouldn't flash).
    func embedFadeIn(_ enabled: Bool) -> some View {
        modifier(EmbedFadeIn(enabled: enabled))
    }
}

private struct EmbedFadeIn: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let enabled: Bool
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(!enabled || reduceMotion || visible ? 1 : 0)
            .onAppear {
                guard !visible else { return }
                // Shown without a fade: stay shown if `enabled` turns on later
                // (a video facade whose oEmbed details arrive after it appeared).
                guard enabled, !reduceMotion else {
                    visible = true
                    return
                }
                withAnimation(.easeOut(duration: 0.22)) { visible = true }
            }
    }
}

/// Space-holding box shown while an image or video loads.
struct MediaPlaceholder: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var systemImage = "photo"
    var cornerRadius: CGFloat = 8
    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(theme[ThemeKey.embedPlaceholderBackground])
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(theme[ThemeKey.embedSiteName].opacity(0.55))
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(theme[ThemeKey.embedBorder], lineWidth: 1)
            )
            .opacity(pulse ? 0.6 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
            }
            .accessibilityLabel("Loading")
    }
}

/// A small capsule button under a message: "Load preview", "Couldn't load image", …
struct EmbedChip: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    let systemImage: String
    let title: String
    var detail: String?
    var isError = false
    /// What clicking does, shown last like a link (e.g. "Open").
    var actionTitle: String?
    var help: String?
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: max(9, style.fontSize - 3), weight: .semibold))
                    .foregroundStyle(theme[isError ? ThemeKey.chatError : ThemeKey.embedSiteName])
                // With an action word, the title only states what happened
                // (like `BlockedPreviewChip`); the action stands out instead.
                Text(title)
                    .foregroundStyle(theme[
                        isError ? ThemeKey.chatError : actionTitle == nil ? ThemeKey.embedTitle : ThemeKey.embedDescription
                    ])
                if let detail {
                    Text(detail)
                        .foregroundStyle(theme[ThemeKey.embedSiteName])
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let actionTitle {
                    Text(actionTitle)
                        .fontWeight(.semibold)
                        .foregroundStyle(theme[ThemeKey.embedTitle])
                        .underline(hovering)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.leading, 4)
                }
            }
            .font(style.font(size: max(9, style.fontSize - 2), weight: .medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(hovering ? theme[ThemeKey.chatHoverBackground] : theme[ThemeKey.embedBackground])
            )
            .overlay(Capsule().strokeBorder(theme[ThemeKey.embedBorder], lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pointerStyle(.link)
        .help(help ?? title)
        .accessibilityLabel(detail.map { "\(title), \($0)" } ?? title)
        .accessibilityHint(actionTitle != nil ? help ?? "" : "")
    }
}

/// Why an image couldn't be shown, as its chip says.
enum ImageLoadFailure: Hashable {
    /// Bigger than the `media.maxImageSizeMB` limit it was loaded under.
    case tooLarge(limitBytes: Int)
    /// More pixels than Vela decodes, however small the file.
    case tooManyPixels
    /// It couldn't be downloaded or decoded.
    case unavailable

    /// The failure `error` means for an image loaded with a `limitBytes` cap.
    init(_ error: any Error, limitBytes: Int) {
        switch error as? MediaError {
        case .tooLarge: self = .tooLarge(limitBytes: limitBytes)
        case .tooManyPixels: self = .tooManyPixels
        default: self = .unavailable
        }
    }

    /// Whether loading under `policy` would fail the same way. A raised
    /// size limit gives a too-large image another try.
    func persists(under policy: MediaPolicy) -> Bool {
        if case .tooLarge(let limit) = self { return policy.maxImageBytes <= limit }
        return true
    }

    var title: String {
        switch self {
        case .tooLarge(let limit): "Image larger than \(Self.megabytes(limit))"
        case .tooManyPixels: "Image too large to show inline"
        case .unavailable: "Couldn't load image"
        }
    }

    var systemImage: String {
        self == .unavailable ? "exclamationmark.triangle.fill" : "photo"
    }

    var isError: Bool { self == .unavailable }

    /// `bytes` in (binary) megabytes as the setting shows them: "10 MB", "2.5 MB".
    static func megabytes(_ bytes: Int) -> String {
        let value = Double(bytes) / (1024 * 1024)
        if abs(value - value.rounded()) < 0.05 { return "\(Int(value.rounded())) MB" }
        return String(format: "%.1f MB", value)
    }
}

/// Provider name with a brand-colored dot, e.g. "● YouTube".
struct ProviderBadge: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    let provider: EmbedProvider

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(EmbedColors.color(hex: provider.brandColor) ?? theme[ThemeKey.embedAccent])
                .frame(width: 7, height: 7)
            Text(provider.displayName)
                .font(style.font(size: max(9, style.fontSize - 2), weight: .semibold))
                .foregroundStyle(theme[ThemeKey.embedSiteName])
        }
        .accessibilityElement(children: .combine)
    }
}

/// The circular ▶ drawn over video thumbnails.
struct PlayGlyph: View {
    @Environment(\.theme) private var theme
    var diameter: CGFloat = 52
    var hovering = false

    var body: some View {
        ZStack {
            Circle()
                .fill(theme[ThemeKey.accent])
                .shadow(color: theme[ThemeKey.chatBackground].opacity(0.45), radius: 8, y: 2)
            Image(systemName: "play.fill")
                .font(.system(size: diameter * 0.38, weight: .bold))
                .foregroundStyle(theme[ThemeKey.accentForeground])
                .offset(x: diameter * 0.04)
        }
        .frame(width: diameter, height: diameter)
        .scaleEffect(hovering ? 1.08 : 1)
        .accessibilityHidden(true)
    }
}

/// A round × button drawn over media (close player, etc.).
struct MediaOverlayButton: View {
    @Environment(\.theme) private var theme
    let systemImage: String
    let label: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(theme[ThemeKey.chatForeground])
                .frame(width: 24, height: 24)
                .background(Circle().fill(theme[ThemeKey.chatBackground].opacity(hovering ? 0.95 : 0.8)))
                .overlay(Circle().strokeBorder(theme[ThemeKey.embedBorder], lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - Helpers

enum EmbedColors {
    /// Parses a `#RRGGBB` page or brand color.
    static func color(hex: String?) -> Color? {
        guard let hex, let parsed = ThemeColor(hex: hex) else { return nil }
        return parsed.withAlpha(1).color
    }

    /// A page's `theme-color` for the card's accent bar, or `embed.accent`
    /// when the page has none or it would vanish against the card
    /// (a white theme-color on a light theme, say).
    static func pageAccent(hex: String?, theme: ResolvedTheme) -> Color {
        let background = theme.color(ThemeKey.embedBackground)
        guard let hex, let parsed = ThemeColor(hex: hex)?.withAlpha(1),
              parsed.contrastRatio(against: background) >= 1.6
        else { return theme[ThemeKey.embedAccent] }
        return parsed.color
    }
}

enum EmbedActions {
    static func copy(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
        pasteboard.setString(url.absoluteString, forType: .string)
    }

    /// Copies image bytes in their own format plus TIFF for apps that only read that.
    static func copyImage(data: Data, utType: String?) {
        let item = NSPasteboardItem()
        if let utType {
            item.setData(data, forType: NSPasteboard.PasteboardType(utType))
        }
        if let image = NSImage(data: data), let tiff = image.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// "example.com" for display, without a leading "www.".
    static func displayHost(_ url: URL) -> String {
        var host = url.host(percentEncoded: false) ?? url.absoluteString
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    /// The last path component when it looks like a file name, else the host.
    static func displayName(_ url: URL) -> String {
        let last = url.lastPathComponent
        if !last.isEmpty, last != "/", last.contains(".") { return last.removingPercentEncoding ?? last }
        return displayHost(url)
    }
}

/// Context-menu items shared by every embed: open/copy, the link's site
/// rule, "Blur Again" on revealed media where blurring applies, and hiding
/// the line's previews.
struct EmbedLinkMenuItems: View {
    @Environment(AppModel.self) private var app
    @Environment(\.embedBlur) private var blur
    let url: URL
    let onHide: () -> Void

    var body: some View {
        Button("Open Link") { EmbedActions.open(url) }
        Button("Copy Link") { EmbedActions.copy(url) }
        if let site = EmbedSiteTarget.resolve(for: url, rule: app.siteRule(for:)) {
            Divider()
            EmbedSiteMenuItems(site: site)
        }
        Divider()
        if blur.canBlurAgain {
            Button("Blur Again") { blur.blurAgain() }
        }
        Button("Hide Previews") { onHide() }
    }
}

/// "Block Previews from ‹domain›" and the "Previews from ‹domain›" rule
/// picker. Rules are settings, so every visible preview from the site
/// updates as soon as one is chosen.
struct EmbedSiteMenuItems: View {
    @Environment(AppModel.self) private var app
    let site: EmbedSiteTarget

    var body: some View {
        if site.access != .block {
            Button("Block Previews from \(site.domain)") { app.setSiteRule(.block, forDomain: site.domain) }
        }
        Menu("Previews from \(site.domain)") {
            Picker("Previews from \(site.domain)", selection: Binding(
                get: { site.access },
                set: { app.setSiteRule($0, forDomain: site.domain) }
            )) {
                ForEach(EmbedSiteTarget.choices, id: \.self) { choice in
                    Text(choice.title).tag(choice.access)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }
}

/// The site a link's rule items act on, and the rule it has now.
struct EmbedSiteTarget: Hashable {
    /// The domain a rule is written for.
    var domain: String
    /// The rule that applies to the link today; nil is "Default".
    var access: SiteAccess?

    struct Choice: Hashable {
        var title: String
        var access: SiteAccess?
    }

    /// The picker's choices, in menu order.
    static let choices: [Choice] = [
        Choice(title: "Default", access: nil),
        Choice(title: "Everything", access: .allow),
        Choice(title: "Text Only", access: .textOnly),
        Choice(title: "Nothing", access: .block),
    ]

    /// The rule matching `url` (`AppModel.siteRule(for:)`) acts on its own
    /// domain, so a rule for `example.com` is edited from `news.example.com`.
    /// Without one, the suggested domain: no `www.`, and a video provider's
    /// main domain, whose rule also covers its short links (`youtu.be`).
    /// Nil for links that can't have a rule (not `http(s)`).
    static func resolve(for url: URL, rule: (URL) -> (domain: String, access: SiteAccess)?) -> EmbedSiteTarget? {
        guard let suggested = SiteRules.suggestedRuleDomain(for: url) else { return nil }
        let match = rule(url) ?? URL(string: "https://\(suggested)/").flatMap(rule)
        if let match { return EmbedSiteTarget(domain: match.domain, access: match.access) }
        return EmbedSiteTarget(domain: suggested, access: nil)
    }
}
