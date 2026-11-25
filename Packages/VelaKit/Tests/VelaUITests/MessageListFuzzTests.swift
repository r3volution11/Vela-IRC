// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import Testing
@testable import VelaCore
import VelaIntelligence
import VelaMedia
import VelaStore
import VelaTheme
@testable import VelaUI

/// The real message list (`ChatColumnView`), driven every way a reader
/// drives it, as fast as it goes: new lines and bursts, sends, the window
/// resized, Page Up and Down, Home and End, messages picked with the arrow
/// keys, the unread marker moved, jumps to a line, the message box growing
/// and emptied, the typing line, the reply bar and switching channels, in a
/// long channel where one-line messages sit between video players and long
/// messages. 45 seconds for each of four presets.
///
/// It finds freezes, not wrong results: on macOS 26 SwiftUI's lazy stack
/// could lock up the main thread for good (`MessageListView`'s
/// `sizeChangeAnchor`). A run that freezes stops logging and never ends.
/// `scripts/fuzz-message-list.sh` runs it over and over with a watchdog and
/// samples a run that stops; run that on macOS 26 (a VM) after changing how
/// the list scrolls.
///
/// Opt-in, as it takes three minutes: `VELA_LIST_FUZZ=1`. And:
/// - `VELA_LIST_FUZZ_SECONDS`: seconds per preset (45).
/// - `VELA_LIST_FUZZ_PAUSE`: the longest pause between steps, in ms (60).
/// - `VELA_LIST_FUZZ_ONLY`: only these kinds of step, comma-separated (see
///   `fuzz`). `0,1,2,3,4,5,10,11,12,13`, the list changing size and nothing
///   else, with a pause of 20, froze macOS 26 most often.
/// - `VELA_LIST_FUZZ_SCROLLING=1`: the reader scrolls too (kind 16). Swipes
///   and the mouse wheel scroll only a window on screen, which
///   `VELA_LIST_FUZZ_ONSCREEN=1` puts at the bottom left of the main
///   display: in a VM, never on your own screen.
///
/// Each step goes to standard error as `FUZZ <time> op <n> kind <kind>`.
@MainActor
@Suite("Message list fuzz", .serialized, .enabled(if: ProcessInfo.processInfo.environment["VELA_LIST_FUZZ"] == "1"))
struct MessageListFuzzTests {
    private static let environment = ProcessInfo.processInfo.environment
    private static let seconds = Double(environment["VELA_LIST_FUZZ_SECONDS"] ?? "") ?? 45
    private static let pause = Int(environment["VELA_LIST_FUZZ_PAUSE"] ?? "") ?? 60
    private static let only = environment["VELA_LIST_FUZZ_ONLY"].map { $0.split(separator: ",").compactMap { Int($0) } }
    private static let scrolls = environment["VELA_LIST_FUZZ_SCROLLING"] == "1"
    private static let onScreen = environment["VELA_LIST_FUZZ_ONSCREEN"] == "1"

    private static var lineNumber = 0

    private static func log(_ text: String) {
        let time = String(format: "%.3f", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 10_000))
        FileHandle.standardError.write(Data("FUZZ \(time) \(text)\n".utf8))
    }

    private static func findAll(in view: NSView, where matches: (NSView) -> Bool) -> [NSView] {
        (matches(view) ? [view] : []) + view.subviews.flatMap { findAll(in: $0, where: matches) }
    }

    private static func line(_ nick: String, _ text: String, at time: Date, isHistory: Bool, highlight: Bool = false) -> ChatLine {
        lineNumber += 1
        return ChatLine(msgid: "fuzz-\(lineNumber)", time: time, kind: .message, nick: nick, userHost: "\(nick)@x", text: text, isHighlight: highlight, isHistory: isHistory)
    }

    /// Mostly one-liners; a video every 9 lines, and long messages.
    private static func text(_ index: Int) -> String {
        if index % 9 == 0 { return "watch this https://www.youtube.com/watch?v=aqz-KE-bpKQ&t=\(index)" }
        if index % 7 == 2 {
            return String(repeating: "a long message that wraps over several lines, number \(index), ", count: 1 + (index * 7919) % 30)
        }
        return "message number \(index)"
    }

    private static func key(_ code: Int, _ keyCode: UInt16, in window: NSWindow) {
        let characters = String(Character(UnicodeScalar(UInt32(code))!))
        guard let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .function, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: keyCode
        ) else { return }
        window.sendEvent(event)
    }

    private static func listScrollView(in host: NSView) -> NSScrollView? {
        findAll(in: host) { $0 is ListScrollViewProbe.ProbeView }.first?.enclosingScrollView
    }

    /// Scroll-wheel events over the middle of the list: a trackpad swipe
    /// (began, changed and ended phases, as `ScrollBenchmark` sends them)
    /// or mouse-wheel lines.
    private static func wheel(in window: NSWindow, host: NSView, distance: Double, events count: Int, trackpad: Bool) async {
        guard let list = listScrollView(in: host) else { return }
        let inWindow = list.convert(CGPoint(x: list.bounds.midX, y: list.bounds.midY), to: nil)
        // An event made this way belongs to no window: its location on
        // screen, flipped, is its location in the window.
        let location = CGPoint(x: inWindow.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - inWindow.y)
        var carry = 0.0
        for index in 0...count {
            let event: CGEvent?
            if trackpad {
                let exact = (index == count ? 0 : distance / Double(count)) + carry
                let whole = exact.rounded(.towardZero)
                carry = exact - whole
                event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(whole), wheel2: 0, wheel3: 0)
                event?.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
                event?.setIntegerValueField(.scrollWheelEventScrollPhase, value: index == 0 ? 1 : index == count ? 4 : 2)
            } else {
                guard index < count else { break }
                event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: Int32(max(-10, min(10, distance / 40))), wheel2: 0, wheel3: 0)
            }
            guard let event else { return }
            event.location = location
            guard let nsEvent = NSEvent(cgEvent: event) else { return }
            window.sendEvent(nsEvent)
            try? await Task.sleep(for: .milliseconds(trackpad ? 8 : 16))
        }
    }

    /// The scroll bar's knob dragged: the clip view scrolled step by step.
    private static func drag(host: NSView, distance: Double, steps: Int) async {
        guard let list = listScrollView(in: host), let document = list.documentView else { return }
        let clip = list.contentView
        let from = clip.bounds.minY
        for step in 1...steps {
            let maxY = max(0, document.frame.height - clip.bounds.height)
            clip.scroll(to: NSPoint(x: clip.bounds.minX, y: max(0, min(maxY, from - distance * Double(step) / Double(steps)))))
            list.reflectScrolledClipView(clip)
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    @Test(arguments: [(2, "focus"), (3, "classic"), (4, "tabbed"), (5, "modern")])
    func fuzz(_ seed: Int, _ preset: String) async throws {
        var rng = SystemRandomNumberGenerator()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VelaListFuzz-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = AppModel(
            settings: SettingsStore(fileURL: root.appendingPathComponent("settings.json")),
            networkStore: NetworkConfigStore(fileURL: root.appendingPathComponent("networks.json")),
            database: nil,
            isDemo: true
        )
        DemoContent.populate(app)
        app.settings.apply(SettingsPreset.all.first { $0.id == preset } ?? .tabbed)
        // Video thumbnails are never fetched; the players keep their size.
        app.settings[.mediaSiteRules] = ["ytimg.com": .string("block")]
        app.settings[.mediaShowLinkCards] = false
        app.settings[.chatScrollbackInMemory] = 500
        let session = try #require(app.sessions.first)
        let buffer = session.ensureBuffer(name: "##fuzz", kind: .channel, persist: false)
        buffer.isJoined = true
        let count = 450
        let start = Date().addingTimeInterval(-Double(count + 10) * 30)
        buffer.insertSorted((0..<count).map {
            Self.line(["ann", "bob", "cy", "dee"][$0 % 4], Self.text($0), at: start.addingTimeInterval(Double($0) * 30), isHistory: true)
        })
        app.select(buffer)
        let uiState = UIState()
        let view = ChatColumnView()
            .velaEnvironment(
                app: app,
                themeStore: ThemeStore(userThemesDirectory: root.appendingPathComponent("Themes")),
                uiState: uiState,
                services: SceneServices(intelligence: .demo()),
                isPrimary: false
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        let origin = Self.onScreen ? CGPoint(x: 20, y: 20) : CGPoint(x: -9000, y: -9000)
        let window = NSWindow(contentRect: CGRect(origin: origin, size: CGSize(width: 900, height: 640)), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        try await Task.sleep(for: .milliseconds(600))
        func composer() -> ComposerNSTextView? { Self.findAll(in: host) { $0 is ComposerNSTextView }.first as? ComposerNSTextView }
        let kinds = Self.only ?? Array(0..<(Self.scrolls ? 17 : 16))
        let began = Date()
        var ops = 0
        var index = count
        Self.log("start seed \(seed) \(preset)")
        while Date().timeIntervalSince(began) < Self.seconds {
            ops += 1
            let op = kinds.randomElement(using: &rng)!
            Self.log("op \(ops) kind \(op) lines \(buffer.lines.count) frame \(window.frame.size)")
            switch op {
            case 0, 1:
                // A line from someone else; every fifth a mention.
                index += 1
                session.add(Self.line(["eve", "fay"][index % 2], Self.text(index), at: Date(), isHistory: false, highlight: index % 5 == 0), to: buffer)
            case 2:
                // A burst.
                for _ in 0..<Int.random(in: 5...40, using: &rng) {
                    index += 1
                    session.add(Self.line("gus", Self.text(index), at: Date(), isHistory: false), to: buffer)
                }
            case 3:
                // A message sent, one line or two.
                if let composer = composer() {
                    window.makeFirstResponder(composer)
                    composer.insertText("sent \(ops)", replacementRange: composer.selectedRange())
                    if Bool.random(using: &rng) {
                        composer.insertNewlineIgnoringFieldEditor(nil)
                        composer.insertText("more", replacementRange: composer.selectedRange())
                    }
                    composer.doCommand(by: #selector(NSResponder.insertNewline(_:)))
                }
            case 4:
                var frame = window.frame
                frame.size.width = [883, 900, 917, 760].randomElement(using: &rng)!
                window.setFrame(frame, display: false)
            case 5:
                var frame = window.frame
                frame.size.height = [640, 575, 520, 700].randomElement(using: &rng)!
                window.setFrame(frame, display: false)
            case 6:
                // Page Up, Page Down, Home or End in the message box.
                if let composer = composer() { window.makeFirstResponder(composer) }
                let keys: [(Int, UInt16)] = [(NSPageUpFunctionKey, 116), (NSPageDownFunctionKey, 121), (NSHomeFunctionKey, 115), (NSEndFunctionKey, 119)]
                let (code, keyCode) = keys.randomElement(using: &rng)!
                Self.key(code, keyCode, in: window)
            case 7:
                // Messages picked with the arrow keys.
                uiState.focus(.messages)
                for _ in 0..<Int.random(in: 1...8, using: &rng) {
                    Self.key(Bool.random(using: &rng) ? NSUpArrowFunctionKey : NSDownArrowFunctionKey, Bool.random(using: &rng) ? 126 : 125, in: window)
                }
            case 8:
                buffer.unreadMarkerAfter = Bool.random(using: &rng) ? nil : buffer.lines.randomElement(using: &rng)?.time.addingTimeInterval(-1)
            case 9:
                // A jump to a line (a search result, a reply's quote).
                uiState.scrollTarget = buffer.lines.randomElement(using: &rng)?.id
            case 10:
                // The message box growing.
                if let composer = composer() {
                    window.makeFirstResponder(composer)
                    for _ in 0..<Int.random(in: 1...4, using: &rng) { composer.insertNewlineIgnoringFieldEditor(nil) }
                    composer.insertText("x", replacementRange: composer.selectedRange())
                }
            case 11:
                if let composer = composer() {
                    composer.string = ""
                    composer.didChangeText()
                }
            case 12:
                buffer.updateTyping(nick: "gus", state: Bool.random(using: &rng) ? .active : .done)
            case 13:
                uiState.replyTargets[buffer.id] = Bool.random(using: &rng) ? buffer.lines.last : nil
            case 14:
                if let other = session.buffer(named: "#vela") {
                    app.select(other)
                    try await Task.sleep(for: .milliseconds(Int.random(in: 0...100, using: &rng)))
                    app.select(buffer)
                }
            case 16:
                // The reader scrolls, mostly up.
                let distance = Double(Int.random(in: 40...1600, using: &rng)) * (Int.random(in: 0..<3, using: &rng) == 0 ? -1 : 1)
                switch Int.random(in: 0..<3, using: &rng) {
                case 0: await Self.wheel(in: window, host: host, distance: distance, events: Int.random(in: 4...30, using: &rng), trackpad: true)
                case 1: await Self.wheel(in: window, host: host, distance: distance, events: Int.random(in: 1...8, using: &rng), trackpad: false)
                default: await Self.drag(host: host, distance: distance, steps: Int.random(in: 1...12, using: &rng))
                }
            default:
                host.layoutSubtreeIfNeeded()
            }
            try await Task.sleep(for: .milliseconds(Int.random(in: 0...Self.pause, using: &rng)))
        }
        Self.log("done seed \(seed) ops \(ops)")
    }
}
