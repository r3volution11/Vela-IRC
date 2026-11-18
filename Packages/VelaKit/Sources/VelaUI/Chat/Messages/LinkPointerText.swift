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
///   `.pointerStyle(.link)`. Clicks, drags and scrolls go to the text,
///   which selects as it does anywhere else. Inside a
///   `selectableTextContextMenu` (a message), it also takes right-clicks
///   and Control-clicks anywhere on the text, so they open that menu
///   rather than the text's own; elsewhere they go to the text too;
/// - `LinkClickMonitor`, which watches mouse events go by and opens a link
///   that was clicked: pressed and released in place, as a single click.
///   It opens on the release, at once. A double- or triple-click selects a
///   word or the line; its first click has opened the link, and the others
///   open nothing.
///
/// The visible text draws exactly as it would with its links. Text without
/// links is just that `Text` (with only the right-click view over it,
/// inside a `selectableTextContextMenu`). Nothing updates view state while
/// the pointer moves. `linkClickArea(_:)` makes a whole view (a link
/// preview) one link the same way.
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
                .contextClicksOpenMenu()
        } else {
            LinkRegionsText(text: LinkRuns.removingLinks(from: text), links: links, style: style)
        }
    }
}

private struct LinkRegionsText: View {
    @Environment(\.textOpensContextMenu) private var opensContextMenu
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
                    LinkPointerRegions(regions: regions, urls: links.map(\.url), takesContextClicks: opensContextMenu)
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
    let takesContextClicks: Bool

    func makeNSView(context: Context) -> LinkPointerRegionView {
        let view = LinkPointerRegionView(regions: regions)
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: LinkPointerRegionView, context: Context) {
        view.regions = regions
        view.urls = urls
        view.takesContextClicks = takesContextClicks
        // The list's handler joins channels; the rest go to the system.
        let openURL = context.environment.openURL
        view.open = { openURL($0) }
    }
}

/// Answers hit tests at the link rects while the pointer moves, so the
/// pointer style above it applies there, and lets every other event through
/// to the text underneath. Tells `LinkClickMonitor` which link a click
/// landed on.
///
/// The links are the runs of a text's links (`regions`), or, with
/// `coversBounds`, the whole view is one link (`linkClickArea(_:)`). A
/// whole-view link also takes right-clicks and Control-clicks, so they open
/// the context menu around it: selectable text shows only its own text menu
/// (Cut, Copy, Paste, Font…), never a SwiftUI `.contextMenu`. On text with
/// a selection, they still reach the text, whose menu copies it.
///
/// With `takesContextClicks` (text in a `selectableTextContextMenu`), it
/// takes right-clicks and Control-clicks anywhere over the text, on
/// selected text too, and they open the menu around it. On selected text
/// that menu starts with the selection's items from the text's own menu
/// (`SelectionMenuItems`).
final class LinkPointerRegionView: NSView {
    var regions: LinkRegions
    /// The whole view is link 0, apart from `excluded`; `regions` is unused.
    var coversBounds = false
    /// Right-clicks and Control-clicks anywhere over the view open the
    /// context menu around it, with the selection's items on top over
    /// selected text.
    var takesContextClicks = false
    /// Spots in a whole-view link that aren't part of it (controls of their
    /// own), in this view's coordinates.
    var excluded: [CGRect] = []
    /// Where each link goes, by its index in `regions`.
    var urls: [URL] = [] {
        didSet {
            if urls.isEmpty != oldValue.isEmpty { updateClickMonitoring() }
        }
    }
    /// Opens a clicked link.
    var open: (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// The type of the event being handled (tests stand in their own).
    var currentEventType: () -> NSEvent.EventType? = { NSApplication.shared.currentEvent?.type }
    /// The modifier keys of the event being handled (tests stand in their own).
    var currentModifiers: () -> NSEvent.ModifierFlags = { NSApplication.shared.currentEvent?.modifierFlags ?? [] }
    /// Set while checking that nothing covers the view.
    private var claimsEverything = false
    /// Set while looking at what's underneath.
    private var claimsNothing = false

    init(regions: LinkRegions) {
        self.regions = regions
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateClickMonitoring()
    }

    /// Only views with links need `LinkClickMonitor` (a view that only takes
    /// right-clicks doesn't).
    private func updateClickMonitoring() {
        if window != nil, !urls.isEmpty {
            LinkClickMonitor.shared.add(self)
        } else {
            LinkClickMonitor.shared.remove(self)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !claimsNothing else { return nil }
        let local = convert(point, from: superview)
        let eventType = currentEventType()
        if claimsEverything || Self.claimsPointer(during: eventType) {
            return linkIndex(at: local) != nil ? self : nil
        }
        guard Self.isContextClick(eventType, modifiers: currentModifiers()) else { return nil }
        if takesContextClicks {
            // Selected text too: `menu(for:)` adds the selection's items.
            return bounds.contains(local) ? self : nil
        }
        guard coversBounds, linkIndex(at: local) != nil,
              selectedText(atWindowPoint: superview.map { $0.convert(point, to: nil) } ?? point) == nil
        else { return nil }
        return self
    }

    /// A press that opens a context menu.
    static func isContextClick(_ eventType: NSEvent.EventType?, modifiers: NSEvent.ModifierFlags) -> Bool {
        eventType == .rightMouseDown || (eventType == .leftMouseDown && modifiers.contains(.control))
    }

    /// The view underneath at a point in the window when it's text with a
    /// selection, being the first responder (its selection is the one
    /// shown). Its own menu copies the selection.
    private func selectedText(atWindowPoint point: CGPoint) -> NSView? {
        guard let window, let root = window.contentView?.superview ?? window.contentView else { return nil }
        claimsNothing = true
        defer { claimsNothing = false }
        guard let below = root.hitTest(point), below === window.firstResponder,
              below.accessibilitySelectedTextRange().length > 0
        else { return nil }
        return below
    }

    /// With `takesContextClicks`, on selected text: the menu around the text
    /// (a message's), headed by the selection's items from the text's own
    /// menu. Otherwise none, so the click goes on up to the menu around.
    override func menu(for event: NSEvent) -> NSMenu? {
        guard takesContextClicks, let text = selectedText(atWindowPoint: event.locationInWindow),
              let textMenu = text.menu(for: event)
        else { return super.menu(for: event) }
        guard let menu = surroundingMenu(for: event) else { return textMenu }
        SelectionMenuItems.move(from: textMenu, of: text, to: menu)
        return menu
    }

    /// The context menu the views around this one show for `event`.
    private func surroundingMenu(for event: NSEvent) -> NSMenu? {
        var view = superview
        while let current = view {
            if let menu = current.menu(for: event) { return menu }
            view = current.superview
        }
        return nil
    }

    /// The link at `point`, in this view's coordinates.
    func linkIndex(at point: CGPoint) -> Int? {
        guard coversBounds else { return regions.link(at: point) }
        guard bounds.contains(point), !excluded.contains(where: { $0.contains(point) }) else { return nil }
        return 0
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
              let index = linkIndex(at: convert(point, from: nil)), urls.indices.contains(index),
              let root = window.contentView?.superview ?? window.contentView else { return nil }
        claimsEverything = true
        defer { claimsEverything = false }
        return root.hitTest(point) === self ? urls[index] : nil
    }
}

// MARK: Clicks

/// Opens the links in `LinkPointerText` (and `linkClickArea(_:)`) when
/// they're clicked, on the click's release. One local event monitor for the
/// app, installed while any such text is in a window. It only watches mouse
/// events go by and never changes or keeps one, so the text selects, and
/// everything else handles clicks, exactly as it would without it.
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
            tracker.mouseDown(at: event.locationInWindow, clickCount: event.clickCount, modifiers: event.modifierFlags, target: target)
        case .leftMouseDragged:
            tracker.mouseDragged(to: event.locationInWindow)
        case .leftMouseUp:
            if let clicked = tracker.mouseUp(at: event.locationInWindow, clickCount: event.clickCount) {
                clicked.open(clicked.url)
            }
        case .rightMouseDown:
            contextURL = linkTarget(at: event)?.url
        case .pressure:
            // A force click looks the word up rather than opening the link.
            if event.stage >= 2 { tracker.cancelPress() }
        default:
            break
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
/// further) opens the link on its release, at once, as in Messages or
/// Slack. Only a first click opens: the second click of a double-click (or
/// the rest of a triple-click), which selects a word (or the line), opens
/// nothing more.
nonisolated struct LinkClickTracker<Target> {
    /// How far, in points, the pointer can wander during a click.
    static var slop: CGFloat { 4 }

    private var press: (location: CGPoint, target: Target)?

    /// Whether a press like this can open a link: a single click, perhaps
    /// with Command or Option, but not Shift (which extends the selection)
    /// or Control (the context menu).
    static func opensLinks(clickCount: Int, modifiers: NSEvent.ModifierFlags) -> Bool {
        clickCount <= 1 && modifiers.isDisjoint(with: [.shift, .control])
    }

    /// A press, on `target` when it's on a link.
    mutating func mouseDown(at location: CGPoint, clickCount: Int, modifiers: NSEvent.ModifierFlags, target: Target?) {
        if let target, Self.opensLinks(clickCount: clickCount, modifiers: modifiers) {
            press = (location, target)
        } else {
            press = nil
        }
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

    /// The release: the link to open now, when it ends a click on one.
    mutating func mouseUp(at location: CGPoint, clickCount: Int) -> Target? {
        defer { press = nil }
        guard let press, clickCount <= 1, Self.distance(press.location, location) <= Self.slop else { return nil }
        return press.target
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
