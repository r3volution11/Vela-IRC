// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import Synchronization

/// Message text whose links you can click, and also select and copy like
/// the rest of the text, with the pointing hand over links and the I-beam
/// elsewhere. Apply `.textSelection(.enabled)` (and any other view
/// modifiers) outside, as for a plain `Text`.
///
/// Selectable SwiftUI text won't begin a selection on a `.link` run (it
/// leaves the press to the link), so a drag or double-click that starts on
/// a link selects nothing. So text with links is drawn without its `.link`
/// attributes, styled as before (the renderer colors links itself), and the
/// links are handled here instead:
///
/// - an invisible twin, laid out from the same proposal in a `ZStack`,
///   whose `LinkRegionRecorder` notes where each link landed;
/// - a transparent AppKit view over the text (`LinkPointerRegionView`) that
///   answers hit tests at those spots for pointer movement only, under
///   `.pointerStyle(.link)`. Clicks, drags, scrolls and right-clicks go to
///   the text, which selects and shows menus as it does anywhere else;
/// - `LinkClickMonitor`, which watches mouse events go by and opens a link
///   that was clicked: pressed and released in place, as a single click.
///   It opens once the double-click interval has passed, as a double- or
///   triple-click selects a word or the line instead.
///
/// The visible text draws exactly as it would with its links. Text without
/// links is just that `Text`. Nothing updates view state while the pointer
/// moves.
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
        let links = LinkRuns.links(in: text)
        if links.isEmpty {
            style(Text(text))
        } else {
            LinkRegionsText(text: LinkRuns.removingLinks(from: text), links: links, style: style)
        }
    }
}

private struct LinkRegionsText: View {
    /// The text without its links.
    let text: AttributedString
    let links: [LinkRuns.Link]
    let style: (Text) -> Text

    @State private var regions = LinkRegions()

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Same text and proposal as the visible one, so the same lines.
            // It draws nothing.
            style(Text(text))
                .textRenderer(LinkRegionRecorder(links: links.map(\.range), regions: regions))
                .textSelection(.disabled)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            style(Text(text))
                .overlay {
                    LinkPointerRegions(regions: regions, urls: links.map(\.url))
                        .pointerStyle(.link)
                        .accessibilityHidden(true)
                }
        }
    }
}

// MARK: Link runs

nonisolated enum LinkRuns {
    struct Link: Equatable, Sendable {
        /// UTF-16 offsets (how `Text.Layout` counts characters).
        var range: Range<Int>
        var url: URL
        /// The text the link shows.
        var title: String
    }

    /// The runs of `text` that carry a link, in order.
    static func links(in text: AttributedString) -> [Link] {
        var links: [Link] = []
        for (link, range) in text.runs[\.link] {
            guard let link else { continue }
            let utf16 = NSRange(range, in: text)
            guard utf16.location != NSNotFound, utf16.length > 0 else { continue }
            links.append(Link(range: utf16.location..<NSMaxRange(utf16), url: link, title: String(text[range].characters)))
        }
        return links
    }

    /// The runs of `text` that carry a link, as UTF-16 offsets.
    static func ranges(in text: AttributedString) -> [Range<Int>] {
        links(in: text).map(\.range)
    }

    /// `text` with the same characters and styling but no links, which
    /// selectable text treats like any other text.
    static func removingLinks(from text: AttributedString) -> AttributedString {
        var plain = text
        plain.link = nil
        return plain
    }
}

// MARK: Recording

/// Where a text's links landed, in the text's own (top-left origin)
/// coordinates. Written while SwiftUI draws the text, possibly off the main
/// thread; read when AppKit hit-tests the pointer or a click comes in.
nonisolated final class LinkRegions: Sendable {
    struct Region: Equatable, Sendable {
        var rect: CGRect
        /// Which link (its index among the text's links).
        var link: Int
    }

    private let storage = Mutex<[Region]>([])

    var regions: [Region] { storage.withLock { $0 } }
    var rects: [CGRect] { regions.map(\.rect) }

    func update(_ regions: [Region]) {
        storage.withLock { $0 = regions }
    }

    func contains(_ point: CGPoint) -> Bool {
        link(at: point) != nil
    }

    /// The link at `point`, if any.
    func link(at point: CGPoint) -> Int? {
        storage.withLock { regions in regions.first { $0.rect.contains(point) }?.link }
    }
}

/// Draws nothing; records the rects of the link runs into `regions`.
nonisolated struct LinkRegionRecorder: TextRenderer {
    let links: [Range<Int>]
    let regions: LinkRegions

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        regions.update(Self.linkRegions(in: layout, links: links))
    }

    /// One rect per stretch of a link's glyphs on each line, in the
    /// coordinates of the text's frame.
    static func linkRegions(in layout: Text.Layout, links: [Range<Int>]) -> [LinkRegions.Region] {
        guard !links.isEmpty, let firstLine = layout.first else { return [] }

        func link(at index: Text.Layout.CharacterIndex) -> Int? {
            guard let offset = characterOffset(index) else { return nil }
            return links.firstIndex { $0.contains(offset) }
        }

        var regions: [LinkRegions.Region] = []
        for line in layout {
            var pending: LinkRegions.Region?
            func flush() {
                if let region = pending, region.rect.width > 0, region.rect.height > 0 { regions.append(region) }
                pending = nil
            }
            func extend(_ rect: CGRect, link: Int) {
                if let region = pending, region.link == link {
                    pending?.rect = region.rect.union(rect)
                } else {
                    flush()
                    pending = LinkRegions.Region(rect: rect, link: link)
                }
            }
            for run in line {
                let runLinks = run.characterIndices.map(link)
                if let first = runLinks.first, let only = first, runLinks.allSatisfy({ $0 == only }) {
                    extend(run.typographicBounds.rect, link: only)
                } else if runLinks.allSatisfy({ $0 == nil }) {
                    flush()
                } else {
                    // A run that's only partly link: go glyph by glyph.
                    for (glyph, glyphLink) in zip(run.indices, runLinks) {
                        if let glyphLink { extend(run[glyph].typographicBounds.rect, link: glyphLink) } else { flush() }
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
        return regions.map { LinkRegions.Region(rect: $0.rect.offsetBy(dx: -left, dy: -top), link: $0.link) }
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
    let urls: [URL]

    func makeNSView(context: Context) -> LinkPointerRegionView {
        let view = LinkPointerRegionView(regions: regions)
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: LinkPointerRegionView, context: Context) {
        view.regions = regions
        view.urls = urls
        // The list's handler joins channels; the rest go to the system.
        let openURL = context.environment.openURL
        view.open = { openURL($0) }
    }
}

/// Answers hit tests at the link rects while the pointer moves, so the
/// pointer style above it applies there, and lets every other event through
/// to the text underneath. Tells `LinkClickMonitor` which link a click
/// landed on.
final class LinkPointerRegionView: NSView {
    var regions: LinkRegions
    /// Where each link goes, by its index in `regions`.
    var urls: [URL] = []
    /// Opens a clicked link.
    var open: (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// The type of the event being handled (tests stand in their own).
    var currentEventType: () -> NSEvent.EventType? = { NSApplication.shared.currentEvent?.type }
    /// Set while checking that nothing covers the view.
    private var claimsEverything = false

    init(regions: LinkRegions) {
        self.regions = regions
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            LinkClickMonitor.shared.add(self)
        } else {
            LinkClickMonitor.shared.remove(self)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard claimsEverything || Self.claimsPointer(during: currentEventType()) else { return nil }
        return regions.contains(convert(point, from: superview)) ? self : nil
    }

    /// Pointer movement only: clicks, drags, scrolls and the rest go to the
    /// text, so selecting and context menus work as for any text.
    static func claimsPointer(during eventType: NSEvent.EventType?) -> Bool {
        switch eventType {
        case .mouseMoved?, .mouseEntered?, .mouseExited?, .cursorUpdate?: true
        default: false
        }
    }

    /// The link at a point in the window, when it's this view's and nothing
    /// covers it there (the hover toolbar, a popover's arrow).
    func link(atWindowPoint point: CGPoint) -> URL? {
        guard let window, !isHiddenOrHasHiddenAncestor,
              let index = regions.link(at: convert(point, from: nil)), urls.indices.contains(index),
              let root = window.contentView?.superview ?? window.contentView else { return nil }
        claimsEverything = true
        defer { claimsEverything = false }
        return root.hitTest(point) === self ? urls[index] : nil
    }
}

// MARK: Clicks

/// Opens the links in `LinkPointerText` when they're clicked. One local
/// event monitor for the app, installed while any such text is in a
/// window. It only watches mouse events go by and never changes or keeps
/// one, so the text selects, and everything else handles clicks, exactly
/// as it would without it.
@MainActor
final class LinkClickMonitor {
    static let shared = LinkClickMonitor()

    /// Whether clicks in a window reach its content: in another app, or a
    /// window that isn't key, the first click only brings the window forward.
    /// (Tests stand in their own.)
    var acceptsClicks: (NSWindow) -> Bool = { window in
        NSApp.isActive && window.isKeyWindow && window.attachedSheet == nil
            && (NSApp.modalWindow == nil || NSApp.modalWindow === window)
    }

    /// How long a click waits to be sure it isn't the start of a double-click.
    var doubleClickInterval: () -> TimeInterval = { NSEvent.doubleClickInterval }

    private struct Target {
        let url: URL
        let open: (URL) -> Void
    }

    private let views = NSHashTable<LinkPointerRegionView>.weakObjects()
    private var monitor: Any?
    private var tracker = LinkClickTracker<Target>()
    /// The link under the pointer at the last right-click or Control-click.
    private var contextURL: URL?

    func add(_ view: LinkPointerRegionView) {
        views.add(view)
        guard monitor == nil else { return }
        tracker = LinkClickTracker()
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .pressure]
        ) { event in
            MainActor.assumeIsolated { LinkClickMonitor.shared.handle(event) }
            return event
        }
    }

    func remove(_ view: LinkPointerRegionView) {
        views.remove(view)
        if views.allObjects.isEmpty, let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    /// For a message's context menu: the link that was right-clicked, if
    /// it's one of `links`.
    func contextLink(among links: [URL]) -> URL? {
        guard let contextURL, links.contains(contextURL) else { return nil }
        return contextURL
    }

    func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            let isContextClick = event.modifierFlags.contains(.control)
            contextURL = isContextClick ? linkTarget(at: event)?.url : nil
            var target: Target?
            if !isContextClick, LinkClickTracker<Target>.opensLinks(clickCount: event.clickCount, modifiers: event.modifierFlags),
               let window = event.window, acceptsClicks(window) {
                target = linkTarget(at: event)
            }
            if let clicked = tracker.mouseDown(at: event.locationInWindow, clickCount: event.clickCount, modifiers: event.modifierFlags, target: target) {
                clicked.open(clicked.url)
            }
        case .leftMouseDragged:
            tracker.mouseDragged(to: event.locationInWindow)
        case .leftMouseUp:
            guard let pending = tracker.mouseUp(at: event.locationInWindow, clickCount: event.clickCount) else { return }
            // A run loop timer, so it fires during menu tracking too.
            let timer = Timer(timeInterval: doubleClickInterval(), repeats: false) { _ in
                MainActor.assumeIsolated { LinkClickMonitor.shared.openPending(pending) }
            }
            RunLoop.main.add(timer, forMode: .common)
        case .rightMouseDown:
            contextURL = linkTarget(at: event)?.url
        case .pressure:
            // A force click looks the word up rather than opening the link.
            if event.stage >= 2 { tracker.cancelPress() }
        default:
            break
        }
    }

    private func openPending(_ id: Int) {
        if let clicked = tracker.takePending(id) {
            clicked.open(clicked.url)
        }
    }

    private func linkTarget(at event: NSEvent) -> Target? {
        guard let window = event.window else { return nil }
        for view in views.allObjects where view.window === window {
            if let url = view.link(atWindowPoint: event.locationInWindow) {
                return Target(url: url, open: view.open)
            }
        }
        return nil
    }
}

/// Tells a click on a link from the other things a press on one can start:
/// a selection drag, a double- or triple-click, a Shift-click that extends
/// the selection, a Control-click for the menu. Pure state, fed the mouse
/// events by `LinkClickMonitor`; `Target` is the link.
///
/// A click (pressed and released within a few points, never dragged
/// further) becomes pending on release. It opens when the double-click
/// interval passes, or at once when the next press turns out not to be a
/// second click; a second click cancels it.
nonisolated struct LinkClickTracker<Target> {
    /// How far, in points, the pointer can wander during a click.
    static var slop: CGFloat { 4 }

    private var press: (location: CGPoint, target: Target)?
    private var pending: (id: Int, target: Target)?
    private var lastID = 0

    /// Whether a press like this can open a link: a single click, perhaps
    /// with Command or Option, but not Shift (which extends the selection)
    /// or Control (the context menu).
    static func opensLinks(clickCount: Int, modifiers: NSEvent.ModifierFlags) -> Bool {
        clickCount <= 1 && modifiers.isDisjoint(with: [.shift, .control])
    }

    /// A press, on `target` when it's on a link. Returns a link clicked just
    /// before that can open now, this press not being its second click.
    mutating func mouseDown(at location: CGPoint, clickCount: Int, modifiers: NSEvent.ModifierFlags, target: Target?) -> Target? {
        var settled: Target?
        if let pending {
            self.pending = nil
            if clickCount <= 1 { settled = pending.target }
        }
        if let target, Self.opensLinks(clickCount: clickCount, modifiers: modifiers) {
            press = (location, target)
        } else {
            press = nil
        }
        return settled
    }

    /// Moving further than `slop` from the press makes it a drag.
    mutating func mouseDragged(to location: CGPoint) {
        if let press, Self.distance(press.location, location) > Self.slop {
            self.press = nil
        }
    }

    /// Forgets the press, so its release opens nothing.
    mutating func cancelPress() {
        press = nil
    }

    /// The release. When it ends a click on a link, returns the id of the
    /// now-pending click: `takePending` it once the double-click interval
    /// has passed.
    mutating func mouseUp(at location: CGPoint, clickCount: Int) -> Int? {
        defer { press = nil }
        guard let press, clickCount <= 1, Self.distance(press.location, location) <= Self.slop else { return nil }
        lastID += 1
        pending = (lastID, press.target)
        return lastID
    }

    /// The link to open, if click `id` is still pending.
    mutating func takePending(_ id: Int) -> Target? {
        guard let pending, pending.id == id else { return nil }
        self.pending = nil
        return pending.target
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}

// MARK: Accessibility

/// VoiceOver actions that open each link in `text`, named for what the link
/// shows ("Open https://swift.org", "Open #vela").
struct LinkAccessibilityActions: View {
    @Environment(\.openURL) private var openURL
    let text: AttributedString

    var body: some View {
        ForEach(Array(LinkRuns.links(in: text).enumerated()), id: \.offset) { _, link in
            Button("Open \(link.title)") { openURL(link.url) }
        }
    }
}
