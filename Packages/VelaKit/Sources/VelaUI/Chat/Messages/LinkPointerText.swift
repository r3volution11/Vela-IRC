// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import Synchronization

/// Message text that shows the pointing hand over its links and the I-beam
/// over the rest. Apply `.textSelection(.enabled)` (and any other view
/// modifiers) outside, as for a plain `Text`.
///
/// Selectable text claims the I-beam everywhere, links included, and a
/// `.pointerStyle` on the text can't override it. So text with links gets
/// two helpers:
///
/// - an invisible twin, laid out from the same proposal in a `ZStack`, whose
///   `LinkRegionRecorder` notes where the link runs landed;
/// - a transparent AppKit view over the text (`LinkPointerRegionView`) that
///   answers hit tests at those spots for pointer movement only, under
///   `.pointerStyle(.link)`. Clicks, drags, scrolls and right-clicks fall
///   through to the text, which selects, opens links and shows menus as
///   before.
///
/// The visible text is the very `Text` it would be without links, so it
/// draws identically. Text without links is just that `Text`. Nothing
/// updates view state while the pointer moves.
struct LinkPointerText: View {
    let text: AttributedString
    /// `Text` modifiers (font, italic, color), applied to the visible text
    /// and its twin alike so both lay out the same.
    let style: (Text) -> Text

    init(_ text: AttributedString, style: @escaping (Text) -> Text = { $0 }) {
        self.text = text
        self.style = style
    }

    var body: some View {
        let links = LinkRuns.ranges(in: text)
        if links.isEmpty {
            style(Text(text))
        } else {
            LinkRegionsText(text: text, links: links, style: style)
        }
    }
}

private struct LinkRegionsText: View {
    let text: AttributedString
    let links: [Range<Int>]
    let style: (Text) -> Text

    @State private var regions = LinkRegions()

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Same text and proposal as the visible one, so the same lines.
            // It draws nothing.
            style(Text(text))
                .textRenderer(LinkRegionRecorder(links: links, regions: regions))
                .textSelection(.disabled)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            style(Text(text))
                .overlay {
                    LinkPointerRegions(regions: regions)
                        .pointerStyle(.link)
                        .accessibilityHidden(true)
                }
        }
    }
}

// MARK: Link runs

nonisolated enum LinkRuns {
    /// The runs of `text` that carry a link, as UTF-16 offsets (how
    /// `Text.Layout` counts characters).
    static func ranges(in text: AttributedString) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        for (link, range) in text.runs[\.link] where link != nil {
            let utf16 = NSRange(range, in: text)
            guard utf16.location != NSNotFound, utf16.length > 0 else { continue }
            ranges.append(utf16.location..<NSMaxRange(utf16))
        }
        return ranges
    }
}

// MARK: Recording

/// Where a text's links landed, in the text's own (top-left origin)
/// coordinates. Written while SwiftUI draws the text, possibly off the main
/// thread; read when AppKit hit-tests the pointer.
nonisolated final class LinkRegions: Sendable {
    private let storage = Mutex<[CGRect]>([])

    var rects: [CGRect] { storage.withLock { $0 } }

    func update(_ rects: [CGRect]) {
        storage.withLock { $0 = rects }
    }

    func contains(_ point: CGPoint) -> Bool {
        storage.withLock { $0.contains { $0.contains(point) } }
    }
}

/// Draws nothing; records the rects of the link runs into `regions`.
nonisolated struct LinkRegionRecorder: TextRenderer {
    let links: [Range<Int>]
    let regions: LinkRegions

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        regions.update(Self.linkRects(in: layout, links: links))
    }

    /// One rect per stretch of link glyphs on each line, in the coordinates
    /// of the text's frame.
    static func linkRects(in layout: Text.Layout, links: [Range<Int>]) -> [CGRect] {
        guard !links.isEmpty, let firstLine = layout.first else { return [] }

        func isLink(_ index: Text.Layout.CharacterIndex) -> Bool {
            guard let offset = characterOffset(index) else { return false }
            return links.contains { $0.contains(offset) }
        }

        var rects: [CGRect] = []
        for line in layout {
            var pending: CGRect?
            func extend(with rect: CGRect) { pending = pending?.union(rect) ?? rect }
            func flush() {
                if let rect = pending, rect.width > 0, rect.height > 0 { rects.append(rect) }
                pending = nil
            }
            for run in line {
                let flags = run.characterIndices.map(isLink)
                if flags.allSatisfy({ $0 }) {
                    extend(with: run.typographicBounds.rect)
                } else if !flags.contains(true) {
                    flush()
                } else {
                    // A run that's only partly link: go glyph by glyph.
                    for (glyph, linked) in zip(run.indices, flags) {
                        if linked { extend(with: run[glyph].typographicBounds.rect) } else { flush() }
                    }
                }
            }
            flush()
        }

        // Layout coordinates are outset from the text's frame (more for
        // italics and emoji). The first line's top and the leftmost line's
        // start sit on the frame's edges.
        let left = layout.map { $0.typographicBounds.rect.minX }.min() ?? 0
        let top = firstLine.typographicBounds.rect.minY
        return rects.map { $0.offsetBy(dx: -left, dy: -top) }
    }

    /// The UTF-16 offset of a layout character index. `CharacterIndex` is a
    /// frozen wrapper around that offset with no public accessor.
    static func characterOffset(_ index: Text.Layout.CharacterIndex) -> Int? {
        guard MemoryLayout<Text.Layout.CharacterIndex>.size == MemoryLayout<Int>.size else { return nil }
        return unsafeBitCast(index, to: Int.self)
    }
}

// MARK: Pointer regions

/// The transparent AppKit view over a text's links.
private struct LinkPointerRegions: NSViewRepresentable {
    let regions: LinkRegions

    func makeNSView(context: Context) -> LinkPointerRegionView {
        LinkPointerRegionView(regions: regions)
    }

    func updateNSView(_ view: LinkPointerRegionView, context: Context) {
        view.regions = regions
    }
}

/// Answers hit tests at the link rects while the pointer moves, so the
/// pointer style above it applies there, and lets every other event through
/// to the text underneath.
final class LinkPointerRegionView: NSView {
    var regions: LinkRegions
    /// The type of the event being handled (tests stand in their own).
    var currentEventType: () -> NSEvent.EventType? = { NSApplication.shared.currentEvent?.type }

    init(regions: LinkRegions) {
        self.regions = regions
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard Self.claimsPointer(during: currentEventType()) else { return nil }
        return regions.contains(convert(point, from: superview)) ? self : nil
    }

    /// Pointer movement only: clicks, drags, scrolls and the rest go to the
    /// text, so selecting, opening links and context menus work as before.
    static func claimsPointer(during eventType: NSEvent.EventType?) -> Bool {
        switch eventType {
        case .mouseMoved?, .mouseEntered?, .mouseExited?, .cursorUpdate?: true
        default: false
        }
    }
}
