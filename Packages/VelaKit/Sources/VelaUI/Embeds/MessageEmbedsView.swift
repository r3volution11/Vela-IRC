// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaIRC
import VelaMedia
import VelaTheme

/// Inline media for the links in one chat line: images, link cards, video
/// facades and players. Renders nothing when the line has no links or inline
/// media is disabled for the buffer.
///
/// Up to `maxPreviews` distinct links get a preview. What each one shows is
/// `PreviewDecider`'s call: the preview, a "Load preview" chip (auto-load
/// off), a chip saying why its site is blocked, or nothing. Hovering shows a
/// chevron that hides this line's previews.
struct MessageEmbedsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    let line: ChatLine
    let bufferID: BufferID

    static let maxPreviews = 4

    @State private var hovering = false

    var body: some View {
        let links = EmbedLinkExtractor.links(for: line)
        if !links.isEmpty, bufferID.foldedName != BufferID.serverBufferName, app.isMediaEnabled(for: bufferID) {
            let context = app.previewContext(for: bufferID)
            let store = EmbedLineStore.shared
            // Links that would show nothing (a private-network host, link
            // cards turned off) take no room and don't count as hidden.
            let shown = links.filter {
                store.rememberedDecision(for: $0, in: line.id, context: context).plan != .none
            }
            if !shown.isEmpty {
                if store.isCollapsed(line.id) {
                    collapsedRow(count: shown.count)
                } else {
                    embeds(shown, context: context)
                }
            }
        }
    }

    private func embeds(_ links: [EmbedLink], context: VelaMedia.PreviewContext) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(links) { link in
                LinkEmbedView(link: link, lineID: line.id, context: context, onHide: hide)
            }
        }
        // Room for the hover chevron, so moving onto it keeps the hover.
        .padding(.trailing, 28)
        .overlay(alignment: .topTrailing) {
            HidePreviewsButton(action: hide)
                .padding(.top, 6)
                .opacity(hovering ? 1 : 0)
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(links.count == 1 ? "Link preview" : "\(links.count) link previews")
        .accessibilityAction(named: "Hide previews", hide)
    }

    private func collapsedRow(count: Int) -> some View {
        Button {
            EmbedLineStore.shared.setCollapsed(false, for: line.id)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .font(.system(size: max(8, style.fontSize - 4), weight: .bold))
                Text(count == 1 ? "Preview hidden" : "\(count) previews hidden")
            }
            .font(style.font(size: max(9, style.fontSize - 2)))
            .foregroundStyle(theme[ThemeKey.chatSecondaryForeground])
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
        .help("Show previews")
        .accessibilityLabel(count == 1 ? "Preview hidden. Show preview" : "\(count) previews hidden. Show previews")
    }

    private func hide() {
        EmbedLineStore.shared.setCollapsed(true, for: line.id)
    }
}

/// The chevron shown at the top right of a line's previews on hover.
private struct HidePreviewsButton: View {
    @Environment(\.theme) private var theme
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.up")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(theme[hovering ? ThemeKey.chatForeground : ThemeKey.chatSecondaryForeground])
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(hovering ? theme[ThemeKey.chatHoverBackground] : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Hide previews")
        .accessibilityLabel("Hide previews")
    }
}

// MARK: - Links

/// A link worth previewing, with its offline classification.
struct EmbedLink: Identifiable, Hashable {
    /// De-duplication key: the same video or file posted twice previews once.
    let id: String
    let url: URL
    let classification: MediaClassification

    init(url: URL) {
        self.url = url
        classification = MediaClassifier.classify(url)
        switch classification {
        case .embed(let info):
            id = "\(info.provider.rawValue):\(info.videoID)"
        case .image(let media), .video(let media):
            id = media.absoluteString
        case .page(let page):
            var text = page.absoluteString
            if let hash = text.firstIndex(of: "#") { text = String(text[..<hash]) }
            while text.hasSuffix("/") { text.removeLast() }
            id = text.lowercased()
        }
    }
}

enum EmbedLinkExtractor {
    /// The distinct previewable links in a conversation line (memoized per line).
    static func links(for line: ChatLine) -> [EmbedLink] {
        guard line.kind.isConversation, !line.isRedacted else { return [] }
        if let memo = EmbedMemory.shared.links.value(for: line.id), memo.text == line.text {
            return memo.links
        }
        var seen = Set<String>()
        var result: [EmbedLink] = []
        for detected in LinkDetector.links(in: IRCFormatting.strip(line.text)) {
            let link = EmbedLink(url: detected.url)
            guard seen.insert(link.id).inserted else { continue }
            result.append(link)
            if result.count == MessageEmbedsView.maxPreviews { break }
        }
        EmbedMemory.shared.links.insert((line.text, result), for: line.id)
        return result
    }
}

// MARK: - One link

private extension MediaClassification {
    var isEmbed: Bool {
        if case .embed = self { return true }
        return false
    }
}

/// The view a link's `PreviewDecision` calls for, with what it draws.
/// Kept apart from the views so the mapping is testable.
///
/// Until the Standard card arrives, `card(.standard)` draws the full card
/// (`LinkCardView` decides), like `card(.large)`.
enum EmbedPresentation: Hashable {
    /// Nothing, taking no space: not previewed, still fetching, or the fetch failed.
    case nothing
    case loadChip(LoadChipKind)
    case blocked(SiteBlock)
    case image(URL, PreviewImageSize)
    case directVideo(URL, PreviewVideoStyle)
    case videoEmbed(EmbedInfo, PreviewVideoStyle)
    case card(LinkPreview, PreviewLinkSize)

    init(plan: PreviewPlan, link: EmbedLink, preview: LinkPreview?) {
        switch plan {
        case .none, .pending:
            self = .nothing
        case .loadChip(let kind):
            self = .loadChip(kind)
        case .blocked(let block):
            self = .blocked(block)
        case .image(let size):
            // The URL as classified (it may be rewritten, e.g. GitHub blob →
            // raw), else the image a page-looking link turned out to be.
            if case .image(let imageURL) = link.classification {
                self = .image(imageURL, size)
            } else if let preview, preview.kind == .image {
                self = .image(preview.mediaURL ?? preview.finalURL, size)
            } else {
                self = .nothing
            }
        case .directVideo(let style):
            self = preview.map { .directVideo($0.finalURL, style) } ?? .nothing
        case .videoEmbed(let style):
            let classified: EmbedInfo? = if case .embed(let info) = link.classification { info } else { nil }
            self = (preview?.embed ?? classified).map { .videoEmbed($0, style) } ?? .nothing
        case .card(let size):
            self = preview.map { .card($0, size) } ?? .nothing
        }
    }

    /// The "Load …" chip's icon and title.
    static func loadChipLabel(_ kind: LoadChipKind) -> (systemImage: String, title: String) {
        switch kind {
        case .image: ("photo", "Load image")
        case .video: ("film", "Load video")
        case .videoEmbed(let provider): ("play.rectangle", "Load \(provider.displayName) video")
        case .page: ("link", "Load preview")
        }
    }
}

/// Fetches the preview for one link when its decision calls for it and
/// draws what the decision says.
private struct LinkEmbedView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.chatStyle) private var style
    let link: EmbedLink
    let lineID: UUID
    let context: VelaMedia.PreviewContext
    let onHide: () -> Void

    private enum Phase {
        case idle
        case loading
        case loaded(LinkPreview)
        case failed
    }

    /// The fetch restarts when the link's policy changes ("Show once", a new
    /// site rule) or the decision starts wanting a preview ("Load preview").
    private struct FetchKey: Equatable {
        var shouldFetch: Bool
        var policy: MediaPolicy
    }

    @State private var phase: Phase
    /// The site block the last fetch failed with (a redirect into a blocked site).
    @State private var fetchBlock: SiteBlock?
    @State private var arrivedAsync = false

    init(link: EmbedLink, lineID: UUID, context: VelaMedia.PreviewContext, onHide: @escaping () -> Void) {
        self.link = link
        self.lineID = lineID
        self.context = context
        self.onHide = onHide
        let preview = EmbedLineStore.shared.rememberedPreview(for: link, in: lineID, context: context)
        _phase = State(initialValue: preview.map(Phase.loaded) ?? .idle)
        _fetchBlock = State(initialValue: EmbedMemory.shared.fetchBlocks.peek(link.url))
    }

    private var preview: LinkPreview? {
        if case .loaded(let preview) = phase { return preview }
        return nil
    }

    var body: some View {
        let decision = EmbedLineStore.shared.decision(
            for: link, in: lineID, preview: preview, fetchBlock: fetchBlock, context: context
        )
        content(EmbedPresentation(plan: decision.plan, link: link, preview: preview), decision: decision)
            .task(id: FetchKey(shouldFetch: decision.shouldFetch, policy: decision.policy)) {
                await loadPreview(decision)
            }
    }

    @ViewBuilder
    private func content(_ presentation: EmbedPresentation, decision: PreviewDecision) -> some View {
        switch presentation {
        case .nothing:
            Color.clear.frame(width: 0, height: 0)
        case .loadChip(let kind):
            loadChip(kind).padding(.top, 6)
        case .blocked(let block):
            BlockedPreviewChip(
                block: block,
                url: link.url,
                onShowOnce: { EmbedLineStore.shared.allowOnce(block.domain, in: lineID) },
                onHide: onHide
            )
            .padding(.top, 6)
        case .image(let imageURL, let size):
            InlineImageView(
                linkURL: link.url,
                imageURL: imageURL,
                policy: decision.policy,
                compact: size == .thumbnail,
                maxImageHeight: style.maxImageHeight,
                onUnsupported: onUnsupportedImage,
                onBlocked: { block in
                    fetchBlock = block
                    EmbedMemory.shared.fetchBlocks.insert(block, for: link.url)
                },
                onHide: onHide
            )
            .padding(.top, 6)
        case .directVideo(let videoURL, let videoStyle):
            DirectVideoView(
                linkURL: link.url,
                videoURL: videoURL,
                policy: decision.policy,
                compact: videoStyle == .compact,
                animateAppearance: arrivedAsync,
                onHide: onHide
            )
            .padding(.top, 6)
        case .videoEmbed(let embed, let videoStyle):
            VideoEmbedView(
                linkURL: link.url,
                embed: embed,
                policy: decision.policy,
                compact: videoStyle == .compact,
                // A recognized video link shows its facade at once; only one
                // found by fetching a page fades in.
                animateAppearance: arrivedAsync && !link.classification.isEmbed,
                onHide: onHide
            )
            .padding(.top, 6)
        case .card(let preview, let size):
            LinkCardView(
                preview: preview,
                policy: decision.policy,
                size: size,
                showsImages: decision.showsImages,
                animateAppearance: arrivedAsync,
                onHide: onHide
            )
            .padding(.top, 6)
        }
    }

    /// A link classified as an image that isn't one is previewed as a page.
    private var onUnsupportedImage: (() -> Void)? {
        guard case .image = link.classification else { return nil }
        return { [lineID, linkID = link.id] in EmbedLineStore.shared.treatAsPage(lineID: lineID, linkID: linkID) }
    }

    private func loadChip(_ kind: LoadChipKind) -> some View {
        let label = EmbedPresentation.loadChipLabel(kind)
        return EmbedChip(
            systemImage: label.systemImage,
            title: label.title,
            detail: EmbedActions.displayHost(link.url),
            help: "Fetch a preview of \(link.url.absoluteString)"
        ) {
            EmbedLineStore.shared.requestLoad(lineID: lineID, linkID: link.id)
        }
        .contextMenu { EmbedLinkMenuItems(url: link.url, onHide: onHide) }
    }

    private func loadPreview(_ decision: PreviewDecision) async {
        guard decision.shouldFetch, preview == nil else { return }
        let service = app.previewService
        let url = link.url
        let policy = decision.policy
        if let cached = await service.cachedPreview(for: url, policy: policy) {
            finish(cached, async: false)
            return
        }
        phase = .loading
        do {
            let preview = try await service.preview(for: url, policy: policy)
            finish(preview, async: true)
        } catch {
            if Task.isCancelled || error is CancellationError {
                // Leaving the screen cancels the fetch; retry when it comes back.
                phase = .idle
            } else {
                if let block = (error as? MediaError)?.siteBlock {
                    fetchBlock = block
                    EmbedMemory.shared.fetchBlocks.insert(block, for: url)
                }
                phase = .failed
            }
        }
    }

    private func finish(_ preview: LinkPreview, async: Bool) {
        let memory = EmbedMemory.shared
        memory.remember(preview, for: link.url)
        memory.fetchBlocks.removeValue(for: link.url)
        fetchBlock = nil
        arrivedAsync = async
        phase = .loaded(preview)
    }
}
