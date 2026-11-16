// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Observation
import SwiftUI
import VelaCore
import VelaIRC
import VelaMedia
import VelaTheme

/// Inline media for the links in one chat line: images, link cards, video
/// facades and players. Renders nothing when the line has no links or inline
/// media is disabled for the buffer.
///
/// Up to `maxPreviews` distinct links get a preview. Links the media policy
/// won't fetch automatically (`media.autoLoad` off) get a "Load preview" chip
/// instead; links it won't fetch at all are skipped. Hovering shows a chevron
/// that hides this line's previews.
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
            let policy = app.mediaPolicy(for: bufferID)
            let items = links.compactMap { link -> EmbedItem? in
                let mode = EmbedDisplayMode(for: link, policy: policy)
                return mode == .hidden ? nil : EmbedItem(link: link, mode: mode)
            }
            if !items.isEmpty {
                if EmbedCollapseStore.shared.isCollapsed(line.id) {
                    collapsedRow(count: items.count)
                } else {
                    embeds(items, policy: policy)
                }
            }
        }
    }

    private func embeds(_ items: [EmbedItem], policy: MediaPolicy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                LinkEmbedView(link: item.link, mode: item.mode, policy: policy, onHide: hide)
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
        .accessibilityLabel(items.count == 1 ? "Link preview" : "\(items.count) link previews")
        .accessibilityAction(named: "Hide previews", hide)
    }

    private func collapsedRow(count: Int) -> some View {
        Button {
            EmbedCollapseStore.shared.setCollapsed(false, for: line.id)
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
        EmbedCollapseStore.shared.setCollapsed(true, for: line.id)
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

/// How a link is previewed under the current media policy.
enum EmbedDisplayMode: Hashable {
    /// Fetch and show without a click.
    case automatic
    /// Show a "Load preview" chip; fetch on click.
    case clickToLoad
    /// Not previewed at all (blocked domain, or that kind of preview is off).
    case hidden

    init(for link: EmbedLink, policy: MediaPolicy) {
        if policy.permitsAutomaticPreview(of: link.url) {
            self = .automatic
            return
        }
        guard policy.allows(link.url) else {
            self = .hidden
            return
        }
        switch link.classification {
        case .embed where !policy.loadVideoEmbeds:
            // Videos fall back to an ordinary link card when embeds are off.
            if policy.showLinkCards {
                self = policy.autoLoad ? .automatic : .clickToLoad
            } else {
                self = .hidden
            }
        case .page where !policy.showLinkCards:
            self = .hidden
        default:
            self = .clickToLoad
        }
    }
}

private struct EmbedItem: Identifiable {
    var id: String { link.id }
    let link: EmbedLink
    let mode: EmbedDisplayMode
}

/// Lines whose previews the user hid. Kept outside the row views so the
/// choice survives rows being re-created while scrolling.
@Observable
final class EmbedCollapseStore {
    static let shared = EmbedCollapseStore()

    private var collapsed: Set<UUID> = []

    func isCollapsed(_ lineID: UUID) -> Bool { collapsed.contains(lineID) }

    func setCollapsed(_ value: Bool, for lineID: UUID) {
        if value { collapsed.insert(lineID) } else { collapsed.remove(lineID) }
    }
}

// MARK: - One link

/// Fetches the preview for one link and picks the view that shows it.
private struct LinkEmbedView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.chatStyle) private var style
    let link: EmbedLink
    let mode: EmbedDisplayMode
    let policy: MediaPolicy
    let onHide: () -> Void

    private enum Phase {
        case idle
        case loading
        case loaded(LinkPreview)
        case failed
    }

    private struct TaskKey: Equatable {
        var mode: EmbedDisplayMode
        var requested: Bool
        var treatAsPage: Bool
    }

    @State private var phase: Phase
    @State private var loadRequested = false
    /// An "image" URL that served HTML: preview it as a page instead.
    @State private var treatAsPage = false
    @State private var arrivedAsync = false

    init(link: EmbedLink, mode: EmbedDisplayMode, policy: MediaPolicy, onHide: @escaping () -> Void) {
        self.link = link
        self.mode = mode
        self.policy = policy
        self.onHide = onHide
        _phase = State(initialValue: EmbedMemory.shared.previews.value(for: link.url).map(Phase.loaded) ?? .idle)
    }

    private var compact: Bool { style.mediaPresentation == .compact }

    private var preview: LinkPreview? {
        if case .loaded(let preview) = phase { return preview }
        return nil
    }

    var body: some View {
        content
            .task(id: TaskKey(mode: mode, requested: loadRequested, treatAsPage: treatAsPage)) {
                await loadPreview()
            }
    }

    @ViewBuilder
    private var content: some View {
        if mode == .clickToLoad && !loadRequested && preview == nil {
            loadChip.padding(.top, 6)
        } else if case .image(let imageURL) = link.classification, !treatAsPage {
            InlineImageView(
                linkURL: link.url,
                imageURL: imageURL,
                policy: policy,
                compact: compact,
                maxImageHeight: style.maxImageHeight,
                onUnsupported: { treatAsPage = true },
                onHide: onHide
            )
            .padding(.top, 6)
        } else if case .embed(let info) = link.classification, policy.loadVideoEmbeds {
            VideoEmbedView(
                linkURL: link.url,
                embed: preview?.embed ?? info,
                policy: policy,
                compact: compact,
                onHide: onHide
            )
            .padding(.top, 6)
        } else if let preview {
            loaded(preview).padding(.top, 6)
        } else {
            // Nothing to show yet (or the fetch failed): take no space.
            Color.clear.frame(width: 0, height: 0)
        }
    }

    @ViewBuilder
    private func loaded(_ preview: LinkPreview) -> some View {
        switch preview.kind {
        case .image:
            InlineImageView(
                linkURL: preview.url,
                imageURL: preview.mediaURL ?? preview.finalURL,
                policy: policy,
                compact: compact,
                maxImageHeight: style.maxImageHeight,
                onHide: onHide
            )
        case .video:
            DirectVideoView(
                linkURL: preview.url,
                videoURL: preview.finalURL,
                compact: compact,
                animateAppearance: arrivedAsync,
                onHide: onHide
            )
        case .embed:
            if policy.loadVideoEmbeds, let embed = preview.embed {
                VideoEmbedView(linkURL: preview.url, embed: embed, policy: policy, compact: compact, animateAppearance: arrivedAsync, onHide: onHide)
            } else if preview.hasCardContent {
                LinkCardView(preview: preview, policy: policy, compact: compact, animateAppearance: arrivedAsync, onHide: onHide)
            }
        case .page:
            if preview.hasCardContent {
                LinkCardView(preview: preview, policy: policy, compact: compact, animateAppearance: arrivedAsync, onHide: onHide)
            }
        }
    }

    private var loadChip: some View {
        let (icon, title): (String, String) = switch link.classification {
        case .image: ("photo", "Load image")
        case .video: ("film", "Load video")
        case .embed(let info) where policy.loadVideoEmbeds: ("play.rectangle", "Load \(info.provider.displayName) video")
        case .embed, .page: ("link", "Load preview")
        }
        return EmbedChip(
            systemImage: icon,
            title: title,
            detail: EmbedActions.displayHost(link.url),
            help: "Fetch a preview of \(link.url.absoluteString)"
        ) {
            loadRequested = true
        }
        .contextMenu { EmbedLinkMenuItems(url: link.url, onHide: onHide) }
    }

    /// Whether this link's rendering depends on a fetched `LinkPreview`.
    private var needsPreview: Bool {
        if mode == .clickToLoad && !loadRequested { return false }
        if case .image = link.classification, !treatAsPage { return false }
        return true
    }

    private func loadPreview() async {
        guard needsPreview, preview == nil else { return }
        let service = app.previewService
        let url = link.url
        if let cached = await service.cachedPreview(for: url) {
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
                phase = .failed
            }
        }
    }

    private func finish(_ preview: LinkPreview, async: Bool) {
        EmbedMemory.shared.previews.insert(preview, for: link.url)
        arrivedAsync = async
        phase = .loaded(preview)
    }
}
