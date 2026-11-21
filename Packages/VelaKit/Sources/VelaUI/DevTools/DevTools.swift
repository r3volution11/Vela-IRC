// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if DEBUG

import AppKit
import Observation
import SwiftUI
import VelaCore
import VelaTheme

/// Vela Dev's developer tools: which are on, and what they share. One per
/// process; the Developer menu (Debug builds only) turns them on and off.
/// See CONTRIBUTING.md, "Developer tools".
///
/// Everything here is compiled out of release builds.
@Observable
final class DevTools {
    static let shared = DevTools()

    /// Inspect Element (⌥⌘I): hovering a tagged view shows its theme
    /// tokens, font, size and padding; clicking pins that; Esc leaves.
    /// While it's on, the windows' content gets no clicks or hovers, as in
    /// a browser's inspector.
    var isInspecting = false {
        didSet { if isInspecting != oldValue { inspectingChanged() } }
    }

    /// Layout Outlines (⌥⌘O): every tagged view outlined with its size,
    /// its padding and the gaps to its neighbors.
    var showsOutlines = false

    /// The Performance HUD (⌥⌘P), in the main window. Its numbers start
    /// afresh each time it's shown.
    var showsPerformanceHUD = false {
        didSet { if showsPerformanceHUD && !oldValue { performance.reset() } }
    }

    /// Set by "Open in Theme Editor": the theme editor searches for this
    /// token when it sees it, and clears it.
    var requestedThemeToken: String?

    /// Tagged views report where they are only while this is on (see
    /// `DevTagModifier`).
    var isTagging: Bool { isInspecting || showsOutlines }

    /// The HUD's numbers.
    let performance = DevPerformanceMonitor()

    /// The state simulator, made the first time the menu uses it.
    private(set) var simulator: DevSimulator?
    @ObservationIgnored private var escapeMonitor: Any?

    init() {}

    func simulator(for app: AppModel) -> DevSimulator {
        if let simulator, simulator.app === app { return simulator }
        let simulator = DevSimulator(app: app)
        self.simulator = simulator
        return simulator
    }

    /// Opens the theme editor on `key`, leaving inspect mode so the
    /// editor can be used.
    func openInThemeEditor(_ key: String, openWindow: OpenWindowAction) {
        requestedThemeToken = key
        isInspecting = false
        openWindow(id: WindowID.themeEditor)
    }

    // MARK: Inspect mode

    private func inspectingChanged() {
        if isInspecting {
            installEscapeMonitor()
        } else {
            removeEscapeMonitor()
        }
    }

    /// Esc leaves inspect mode, wherever the focus is.
    private func installEscapeMonitor() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53,   // Escape
                  event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
            else { return event }
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.isInspecting else { return false }
                self.isInspecting = false
                return true
            }
            return handled ? nil : event
        }
    }

    private func removeEscapeMonitor() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
    }
}

/// Counters the HUD reads, bumped where the work happens. Only in Debug
/// builds; a bump is one addition.
enum DevCounters {
    /// Message list rows built or rebuilt (`DisplayItemRow.body`).
    static var messageRowBodies = 0
}

// MARK: - Registry

/// The tagged views of one window, where they are, and what Inspect
/// Element is pointing at there. Made by `DevToolsHost`.
@Observable
final class DevTagRegistry {
    struct Entry: Identifiable {
        let id: Int
        var tag: DevTag?
        var font: Font?
        var fontContext: Font.Context?
        var frame: CGRect = .null
        var visibleFrame: CGRect = .null

        /// Where it's drawn on screen: the part its scroll view shows.
        var shownFrame: CGRect { visibleFrame }
        var isShown: Bool { tag != nil && !visibleFrame.isNull && visibleFrame.width > 0 && visibleFrame.height > 0 }
    }

    private(set) var entries: [Int: Entry] = [:]
    /// Inspect Element: the pointer in window coordinates, while it's over
    /// the window.
    var pointer: CGPoint?
    /// The view clicked in inspect mode, until Esc or another click.
    var pinnedID: Int?

    private static var lastID = 0

    static func makeID() -> Int {
        lastID += 1
        return lastID
    }

    func update(_ id: Int, geometry: DevTagGeometry) {
        var entry = entries[id] ?? Entry(id: id)
        guard entry.frame != geometry.frame || entry.visibleFrame != geometry.visibleFrame else { return }
        entry.frame = geometry.frame
        entry.visibleFrame = geometry.visibleFrame
        entries[id] = entry
    }

    func update(_ id: Int, tag: DevTag, font: Font?, fontContext: Font.Context) {
        var entry = entries[id] ?? Entry(id: id)
        entry.tag = tag
        entry.font = font
        entry.fontContext = fontContext
        entries[id] = entry
    }

    func remove(_ id: Int) {
        entries[id] = nil
        if pinnedID == id { pinnedID = nil }
    }

    /// Every tagged view on screen, outermost (largest) first.
    var shownEntries: [Entry] {
        entries.values.filter(\.isShown).sorted(by: Self.outerFirst)
    }

    /// The tagged views under `point`, outermost first: the last is the
    /// one Inspect Element shows.
    func entries(at point: CGPoint) -> [Entry] {
        entries.values.filter { $0.isShown && $0.shownFrame.contains(point) }.sorted(by: Self.outerFirst)
    }

    /// The tagged views `entry` is inside, outermost first, ending with
    /// `entry`: the inspector's breadcrumb.
    func path(to entry: Entry) -> [Entry] {
        let frame = entry.shownFrame.insetBy(dx: 0.5, dy: 0.5)
        let outer = entries.values.filter { other in
            other.id != entry.id && other.isShown && other.shownFrame.contains(frame)
                && other.frame.width * other.frame.height >= entry.frame.width * entry.frame.height
        }
        return outer.sorted(by: Self.outerFirst) + [entry]
    }

    /// What Inspect Element shows: the pinned view, or the one under the
    /// pointer.
    var inspected: Entry? {
        if let pinnedID, let entry = entries[pinnedID], entry.isShown { return entry }
        return pointer.flatMap { entries(at: $0).last }
    }

    /// A click in inspect mode: pins the view under `point`, or unpins it
    /// when it's the one already pinned (or there's nothing there).
    func pin(at point: CGPoint) {
        let hit = entries(at: point).last?.id
        pinnedID = hit == pinnedID ? nil : hit
    }

    func clearInspection() {
        pointer = nil
        pinnedID = nil
    }

    /// Larger first; between equal frames, the one tagged later (deeper in
    /// the hierarchy, usually) last.
    private static func outerFirst(_ a: Entry, _ b: Entry) -> Bool {
        let areaA = a.frame.width * a.frame.height
        let areaB = b.frame.width * b.frame.height
        if areaA != areaB { return areaA > areaB }
        return a.id < b.id
    }
}

// MARK: - Inspection

/// What Inspect Element reports about a tagged view.
struct DevInspection: Equatable {
    struct Token: Equatable, Identifiable {
        var key: String
        var hex: String
        /// Not a registry token: a typo, or a key only this theme defines.
        var isKnown: Bool
        var id: String { key }
    }

    struct FontInfo: Equatable {
        var family: String
        var size: CGFloat
        var weight: String
    }

    var name: String
    /// The tagged views it's inside, outermost first, ending with it.
    var path: [String]
    var size: CGSize
    var padding: EdgeInsets?
    var font: FontInfo?
    var tokens: [Token]

    init(_ entry: DevTagRegistry.Entry, path: [DevTagRegistry.Entry] = [], theme: ResolvedTheme) {
        let tag = entry.tag ?? DevTag(name: "?", tokens: [])
        name = tag.name
        self.path = path.compactMap { $0.tag?.name }
        size = entry.frame.size
        padding = tag.padding
        if let tagFont = entry.font, let context = entry.fontContext {
            font = Self.describe(tagFont.resolve(in: context))
        } else {
            font = nil
        }
        var seen = Set<String>()
        tokens = tag.tokens.filter { seen.insert($0).inserted }.map { key in
            Token(key: key, hex: theme.color(key).hex, isKnown: ThemeRegistry.token(key) != nil)
        }
    }

    static func describe(_ font: Font.Resolved) -> FontInfo {
        let family = CTFontCopyFamilyName(font.ctFont) as String
        // The system font's family is a private name (".AppleSystemUIFont").
        let shown = family.hasPrefix(".") ? (font.isMonospaced ? "SF Mono" : "SF Pro (system)") : family
        return FontInfo(family: shown, size: font.pointSize, weight: weightName(font.ctFont))
    }

    /// The font's weight trait, named after the nearest standard weight.
    static func weightName(_ font: CTFont) -> String {
        let traits = CTFontCopyTraits(font) as NSDictionary
        let weight = (traits[kCTFontWeightTrait] as? NSNumber)?.doubleValue ?? 0
        let names: [(NSFont.Weight, String)] = [
            (.ultraLight, "Ultralight"), (.thin, "Thin"), (.light, "Light"), (.regular, "Regular"),
            (.medium, "Medium"), (.semibold, "Semibold"), (.bold, "Bold"), (.heavy, "Heavy"), (.black, "Black"),
        ]
        return names.min { abs($0.0.rawValue - weight) < abs($1.0.rawValue - weight) }?.1 ?? "Regular"
    }
}

#endif
