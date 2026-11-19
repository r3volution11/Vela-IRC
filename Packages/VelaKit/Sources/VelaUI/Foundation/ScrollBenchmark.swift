// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Darwin
import OSLog
import QuartzCore
import SwiftUI
import Synchronization
import VelaCore
import VelaStore
import VelaTheme

/// Demo-mode scroll benchmark: scrolls a big, fixed channel the way a person
/// does, measures how smoothly and how cheaply, writes the numbers and quits.
///
///     Vela --demo --scroll-benchmark --bench-output /path/result.json
///          [--bench-scenarios slow,medium,fling,jump,sweep,sweep-a11y] [--bench-mix full|text]
///          [--bench-size 1280x800] [--bench-window invisible|visible]
///          [--bench-pointer none|list] [--bench-screen <n>]
///          [--bench-accessibility auto|on] [--bench-label <text>]
///          [--preset <id>] [--set key=value] [--theme <name>]
///
/// `scripts/benchmark-scroll.sh` builds a Release copy, runs this several
/// times (also on throttled cores, as a stand-in for slower Macs) and
/// compares the medians with `benchmarks/scroll-baseline.json`.
///
/// - The channel is `ScrollBenchmarkContent` (about 2,000 lines, the same
///   every run), and its media and link previews come from local stand-ins
///   (`ScrollBenchmarkMedia`): nothing is fetched. `--bench-mix text` swaps
///   every link for words. The theme is Palenight unless `--theme` says.
/// - Scrolling is synthetic trackpad input: precise scroll-wheel events
///   with gesture phases, sent to the main window at 120 a second, for each
///   swipe and the glide after it (see `swipe(at:distance:duration:velocity:)`).
///   No accessibility permission is needed.
/// - It never needs your attention: the window is put on screen, in front,
///   where it draws and its display link runs as usual, but it's fully
///   transparent and lets clicks through (`--bench-window visible` shows
///   it). The app isn't activated and the window never becomes key, so
///   whatever you're typing into keeps the keyboard. Nothing is clicked,
///   and the pointer stays where it is (`--bench-pointer list` moves it over
///   the list and back; an inactive window gets no hover events either way).
/// - Scenarios, in order: `slow` (short swipes up, as when reading back),
///   `medium` (steady swipes that glide), `fling` (hard flings up to the
///   top, then down to the bottom), `jump` (to the top and back to the
///   bottom, as the Home and End keys do, three times), `sweep` (exactly
///   48 points every frame, up and down, for costs that don't depend on the
///   frame rate), and `sweep-a11y` (the same with SwiftUI's accessibility
///   turned on, see below).
/// - Accessibility: once any accessibility client looks at the window
///   (VoiceOver, window managers, launchers…), SwiftUI builds accessibility
///   for every row it lays out, which doubles the cost of scrolling, and
///   that can happen mid-run. Each scenario reports which way it ran;
///   `sweep-a11y` turns it on for the rest of the run, and
///   `--bench-accessibility on` from the start (see
///   `ScrollBenchmarkHostingView`).
/// - Measured per scenario: frame intervals from the window's display link
///   while the list moves (p50/p95/p99, frames over 1.5× and 2× the refresh
///   interval, hitch time per second), how far the list moved, process CPU
///   time (and, on Apple silicon, instructions) per second, per 1,000
///   points scrolled and per frame the list moved in, the main thread's CPU
///   and busy time, the display link's rate, and memory (`phys_footprint`).
///   Results are JSON at `--bench-output` (sandboxed: somewhere in the app's
///   container), with a summary next to it (`.txt`) and on standard output. Each scenario is also a Points of Interest
///   interval, so a trace of a run (`xctrace record`) shows where it is.
///
/// Nothing here runs unless both `--demo` and `--scroll-benchmark` are given.
@MainActor
enum ScrollBenchmark {
    static let arguments = ProcessInfo.processInfo.arguments

    static var isActive: Bool { arguments.contains("--demo") && arguments.contains("--scroll-benchmark") }

    private static var runner: ScrollBenchmarkRunner?

    /// Before the app model exists: the media sessions answer from local
    /// stand-ins from the start.
    static func prepareMedia() {
        ScrollBenchmarkMedia.install()
    }

    /// After the demo model exists: the benchmark channel, selected, and
    /// settings that keep runs comparable.
    static func prepare(_ app: AppModel) {
        let settings = app.settings
        // Previews come from the stand-ins only; never a web view.
        settings[.mediaBrowserFallback] = false
        if !arguments.contains("--theme") {
            settings[.appearanceFollowSystem] = false
            settings[.appearanceTheme] = "Palenight"
        }
        let mix = value(after: "--bench-mix").flatMap(ScrollBenchmarkContent.Mix.init(rawValue:)) ?? .full
        ScrollBenchmarkContent.install(in: app, mix: mix)
    }

    /// Starts the run once the app has launched.
    static func schedule(app: AppModel, themeStore: ThemeStore, uiState: UIState, services: SceneServices) {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                let runner = ScrollBenchmarkRunner(
                    options: .init(arguments: arguments), app: app, themeStore: themeStore, uiState: uiState, services: services
                )
                self.runner = runner
                runner.start()
            }
        }
    }

    static func value(after flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}

// MARK: - Options

struct ScrollBenchmarkOptions {
    enum Scenario: String, CaseIterable {
        case slow, medium, fling, jump, sweep
        /// `sweep` again with SwiftUI's accessibility on.
        case sweepAccessibility = "sweep-a11y"
    }

    var scenarios: [Scenario] = Scenario.allCases
    var mix = "full"
    var size = CGSize(width: 1280, height: 800)
    /// `--bench-pointer list`: the pointer is moved over the list for the
    /// run. Off by default: it would take your pointer, and the window,
    /// which never becomes key, gets no hover events anyway.
    var movesPointer = false
    /// `--bench-accessibility on`: SwiftUI's accessibility is turned on
    /// before the first scenario (see `ScrollBenchmarkHostingView`).
    var forcesAccessibility = false
    /// `--bench-window visible`: the window can be seen. By default it's
    /// on screen, drawing as usual, but fully transparent.
    var showsWindow = false
    /// Index into `NSScreen.screens`; 0 is the display with the menu bar.
    var screen = 0
    var label = ""
    var output: URL

    @MainActor
    init(arguments: [String]) {
        func value(_ flag: String) -> String? { ScrollBenchmark.value(after: flag) }
        if let list = value("--bench-scenarios") {
            let parsed = list.split(separator: ",").compactMap { Scenario(rawValue: $0.trimmingCharacters(in: .whitespaces)) }
            if !parsed.isEmpty { scenarios = parsed }
        }
        mix = value("--bench-mix") ?? "full"
        if let text = value("--bench-size") {
            let parts = text.lowercased().split(separator: "x").compactMap { Double($0) }
            if parts.count == 2 { size = CGSize(width: parts[0], height: parts[1]) }
        }
        movesPointer = value("--bench-pointer") == "list"
        forcesAccessibility = value("--bench-accessibility") == "on"
        screen = value("--bench-screen").flatMap(Int.init) ?? 0
        showsWindow = value("--bench-window") == "visible"
        label = value("--bench-label") ?? ""
        output = value("--bench-output").map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? FileManager.default.temporaryDirectory.appending(path: "ScrollBenchmark.json")
    }
}

// MARK: - Runner

/// Drives one benchmark run: sets up the window, plays the scenarios and
/// records what happened.
@MainActor
final class ScrollBenchmarkRunner: NSObject {
    private let options: ScrollBenchmarkOptions
    private let app: AppModel

    private var window: NSWindow?
    private var hosting: ScrollBenchmarkHostingView?
    private var scrollView: NSScrollView?
    private var displayLink: CADisplayLink?
    /// The middle of the list on screen (Quartz coordinates: top left).
    private var pointer: CGPoint = .zero
    /// Where synthetic events say they are (see `send(_:)`).
    private var eventLocation: CGPoint = .zero
    private var originalPointer: CGPoint?
    private let probe = ScrollBenchmarkProbe()
    private var results: [[String: Any]] = []
    private var census: [[String: Any]] = []
    private var notes: [String] = []
    private let launchedAt = CACurrentMediaTime()
    /// Whether the app or the window had the focus when the scenarios
    /// started, for the report (they shouldn't).
    private var appWasActive = false
    private var windowWasKey = false
    /// Whether the app came to the front at any point (it never asks to).
    private var becameActive = false

    // Event playback, fed by the scenarios and sent from the display link.
    private struct PlannedEvent {
        var time: CFTimeInterval
        /// Points; positive moves toward the top (older lines).
        var delta: Double
        var phase: Int64
    }

    private var plan: [PlannedEvent] = []
    private var carry: Double = 0
    private var drained: [CheckedContinuation<Void, Never>] = []

    // The scenario being measured.
    private var recording: ScenarioRecorder?
    /// Each scenario shows as a Points of Interest interval in Instruments.
    private let signposter = OSSignposter(subsystem: Bundle.main.bundleIdentifier ?? "Vela", category: .pointsOfInterest)
    private var interval: OSSignpostIntervalState?

    private let themeStore: ThemeStore
    private let uiState: UIState
    private let services: SceneServices

    init(options: ScrollBenchmarkOptions, app: AppModel, themeStore: ThemeStore, uiState: UIState, services: SceneServices) {
        self.options = options
        self.app = app
        self.themeStore = themeStore
        self.uiState = uiState
        self.services = services
    }

    func start() {
        // A run that hangs (no window, say) still ends, with what it has.
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) { [weak self] in
            self?.finish(error: "timed out after 300 s")
        }
        Task { await run() }
    }

    private func run() async {
        let window = makeMainWindow()
        self.window = window
        // In the middle of the chosen display (the one with the menu bar
        // unless --bench-screen says).
        let screens = NSScreen.screens
        if let screen = screens.indices.contains(options.screen) ? screens[options.screen] : screens.first {
            let visible = screen.visibleFrame
            let size = CGSize(width: min(options.size.width, visible.width), height: min(options.size.height, visible.height))
            window.setFrame(CGRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2, width: size.width, height: size.height), display: true)
        }
        // On screen, so it draws and its display link runs, but never
        // activated or made key: whatever you're doing keeps the focus.
        // Unless --bench-window visible, it's also fully transparent and
        // lets clicks through, so it never needs your attention.
        if !options.showsWindow {
            window.alphaValue = 0
            window.ignoresMouseEvents = true
        }
        window.orderFrontRegardless()
        // Should macOS bring the app forward anyway, it steps straight back.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.becameActive = true
                NSApp.deactivate()
            }
        }
        // The channel lays out and its media arrives; then everything rests.
        guard let scrollView = await messageList(in: window) else {
            finish(error: "couldn't find the message list's scroll view")
            return
        }
        self.scrollView = scrollView
        await sleep(3)
        probe.start()
        startDisplayLink(window)
        movePointer(into: scrollView)
        await sleep(1)
        takeCensus("start")
        if options.forcesAccessibility { turnOnAccessibility(in: window) }
        appWasActive = NSApp.isActive
        windowWasKey = window.isKeyWindow

        for scenario in options.scenarios {
            if scenario == .sweepAccessibility {
                turnOnAccessibility(in: window)
                await sleep(0.5)
            }
            let accessibilityBefore = accessibilityIsActive()
            let requestsBefore = hosting?.accessibilityRequests ?? 0
            switch scenario {
            case .slow: await slow()
            case .medium: await medium()
            case .fling: await fling()
            case .jump: await jump()
            case .sweep: await sweep()
            case .sweepAccessibility: await sweep(named: "sweep-a11y")
            }
            let accessibilityAfter = accessibilityIsActive()
            if !results.isEmpty {
                results[results.count - 1]["accessibility"] = accessibilityBefore == accessibilityAfter
                    ? (accessibilityAfter ? "on" : "off")
                    : "turned on"
                results[results.count - 1]["accessibilityRequests"] = (hosting?.accessibilityRequests ?? 0) - requestsBefore
            }
            await sleep(0.8)
        }
        finish(error: nil)
    }

    // MARK: Scenarios

    /// Reading back: short swipes up with a short glide, a pause after each.
    private func slow() async {
        begin("slow")
        for _ in 0..<14 {
            if atTop { break }
            let start = CACurrentMediaTime()
            schedule(swipe(at: start, distance: 120, duration: 0.28, velocity: 320))
            await sleep(until: start + 1.1)
        }
        await planDrained()
        await sleep(0.3)
        end()
    }

    /// Steady scrolling: a swipe every 0.6 s, each cutting the last one's
    /// glide short, as a new touch does.
    private func medium() async {
        begin("medium")
        for _ in 0..<24 {
            if atTop { break }
            let start = CACurrentMediaTime()
            schedule(swipe(at: start, distance: 320, duration: 0.18, velocity: 2_200))
            await sleep(until: start + 0.6)
        }
        await planDrained()
        await sleep(0.3)
        end()
        takeCensus("after medium")
    }

    /// Hard, repeated flings up to the top of the channel, then down to the bottom.
    private func fling() async {
        begin("fling")
        for direction in [1.0, -1.0] {
            for _ in 0..<60 {
                if direction > 0 ? atTop : atBottom { break }
                let start = CACurrentMediaTime()
                schedule(swipe(at: start, distance: 520 * direction, duration: 0.12, velocity: 10_000 * direction))
                await sleep(until: start + 0.4)
            }
            await planDrained()
            await sleep(0.4)
        }
        end()
    }

    /// The cost of scrolling, apart from how fast the Mac is: from the
    /// bottom of the channel, the list moves exactly `sweepStep` points every
    /// frame, 24,000 points up and back down. However long a frame takes, the
    /// next one moves it the same distance, so the work done (instructions,
    /// CPU time) depends on the app, not on the frame rate; slow frames only
    /// make it take longer.
    private func sweep(named name: String = "sweep") async {
        // Always from the bottom, so it covers the same lines whatever ran
        // before (a jump the app's pinning undid, say).
        if let scrollView, !atBottom {
            scroll(scrollView, toOffset: maxOffset)
            await sleep(1)
        }
        begin(name)
        for direction in [1.0, -1.0] {
            sweepEvents = [PlannedEvent(time: 0, delta: 0, phase: Self.began)]
            let steps = Int(Self.sweepDistance / Self.sweepStep)
            sweepEvents += Array(repeating: PlannedEvent(time: 0, delta: Self.sweepStep * direction, phase: Self.changed), count: steps)
            sweepEvents.append(PlannedEvent(time: 0, delta: 0, phase: Self.ended))
            await withCheckedContinuation { sweepDone = $0 }
            await sleep(0.3)
        }
        end()
    }

    /// Points per frame in `sweep`: 2,880 points a second at 60 Hz.
    private static let sweepStep = 48.0
    private static let sweepDistance = 24_000.0
    /// What `sweep` sends, one per display frame.
    private var sweepEvents: [PlannedEvent] = []
    private var sweepDone: CheckedContinuation<Void, Never>?

    /// To the top and back to the bottom, as the Home and End keys do,
    /// three times: each lands on rows nothing has laid out yet.
    private func jump() async {
        begin("jump")
        for _ in 0..<3 {
            guard let scrollView else { break }
            recording?.markActive(for: 1.0)
            scroll(scrollView, toOffset: 0)
            await sleep(1.3)
            recording?.markActive(for: 1.0)
            scroll(scrollView, toOffset: maxOffset)
            await sleep(1.3)
        }
        end()
    }

    // MARK: Gestures

    /// A trackpad swipe: the fingers' part (began, then changed events
    /// that speed up and slow down), then the glide after the fingers
    /// lift, from `velocity` points a second, slowing down the way
    /// scrolling momentum does, then ended.
    ///
    /// The glide is sent as more changed events rather than as momentum
    /// events: AppKit ignores momentum-phase events that don't come from
    /// the window server. The list moves the same way; the app's scroll
    /// phase reads `.interacting` rather than `.decelerating` for it, which
    /// Vela treats alike (`MessageListController.isUserScrolling`).
    private func swipe(at start: CFTimeInterval, distance: Double, duration: Double, velocity: Double) -> [PlannedEvent] {
        let rate = 120.0
        let count = max(2, Int((duration * rate).rounded()))
        let weights = (0..<count).map { index -> Double in
            let x = (Double(index) + 0.5) / Double(count)
            return pow(sin(.pi * x), 2)
        }
        let total = weights.reduce(0, +)
        var events: [PlannedEvent] = []
        for (index, weight) in weights.enumerated() {
            events.append(PlannedEvent(
                time: start + Double(index) / rate,
                delta: distance * weight / total,
                phase: index == 0 ? Self.began : Self.changed
            ))
        }
        var time = start + Double(count - 1) / rate
        // UIKit's normal deceleration: 0.998 per millisecond.
        let decay = pow(0.998, 1_000 / rate)
        var speed = velocity
        while abs(speed) > 20 {
            time += 1 / rate
            events.append(PlannedEvent(time: time, delta: speed / rate, phase: Self.changed))
            speed *= decay
        }
        events.append(PlannedEvent(time: time + 1 / rate, delta: 0, phase: Self.ended))
        return events
    }

    // CGScrollPhase values.
    private static let began: Int64 = 1
    private static let changed: Int64 = 2
    private static let ended: Int64 = 4

    /// Adds a gesture. A new touch cuts the glide still playing short.
    private func schedule(_ events: [PlannedEvent]) {
        guard let start = events.first?.time else { return }
        let cut = plan.contains { $0.time >= start }
        plan.removeAll { $0.time >= start }
        if cut { plan.append(PlannedEvent(time: start - 0.001, delta: 0, phase: Self.ended)) }
        plan.append(contentsOf: events)
        plan.sort { $0.time < $1.time }
    }

    private func planDrained() async {
        guard !plan.isEmpty else { return }
        await withCheckedContinuation { drained.append($0) }
    }

    // MARK: Display link

    private func startDisplayLink(_ window: NSWindow) {
        guard let view = window.contentView else { return }
        let link = view.displayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        if !sweepEvents.isEmpty {
            send(sweepEvents.removeFirst())
            recording?.markActive(until: now + 0.1)
            if sweepEvents.isEmpty {
                sweepDone?.resume()
                sweepDone = nil
            }
        }
        while let next = plan.first, next.time <= now {
            plan.removeFirst()
            send(next)
            recording?.markActive(until: now + 0.1)
        }
        if plan.isEmpty, !drained.isEmpty {
            let waiting = drained
            drained.removeAll()
            for continuation in waiting { continuation.resume() }
        }
        recording?.frame(at: link.timestamp, offset: offset)
    }

    private func send(_ planned: PlannedEvent) {
        guard let window else { return }
        // Whole points, carrying the rest, so the distances add up.
        let exact = planned.delta + carry
        let whole = exact.rounded(.towardZero)
        carry = exact - whole
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(whole), wheel2: 0, wheel3: 0
        ) else { return }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: planned.phase)
        // An event made this way belongs to no window, so its
        // `locationInWindow` is its location on screen, flipped: place it so
        // that reads as the list's middle in this window.
        event.location = eventLocation
        guard let nsEvent = NSEvent(cgEvent: event) else { return }
        window.sendEvent(nsEvent)
    }

    // MARK: Window and list

    /// The main window: Vela's main view in a window of the same kind as
    /// the main scene's, which the benchmark opens itself. (SwiftUI opens
    /// the scene's window only once the app may come forward, which a
    /// process started from a script isn't always allowed to do; the
    /// scene's own window is suppressed in benchmark runs.)
    private func makeMainWindow() -> NSWindow {
        let hosting = ScrollBenchmarkHostingView(rootView: AnyView(MainWindowView()
            .velaEnvironment(app: app, themeStore: themeStore, uiState: uiState, services: services, isPrimary: true)))
        self.hosting = hosting
        hosting.sceneBridgingOptions = [.toolbars, .title]
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: options.size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        return window
    }

    /// The tallest scroll view in the window: the channel's.
    private func messageList(in window: NSWindow) async -> NSScrollView? {
        for _ in 0..<200 {
            window.contentView?.layoutSubtreeIfNeeded()
            let candidates = scrollViews(in: window.contentView)
            if let best = candidates.max(by: { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }),
               (best.documentView?.frame.height ?? 0) > 5_000 {
                return best
            }
            await sleep(0.1)
        }
        return nil
    }

    private func scrollViews(in root: NSView?) -> [NSScrollView] {
        guard let root else { return [] }
        var found: [NSScrollView] = []
        var queue = [root]
        while let view = queue.popLast() {
            if let scrollView = view as? NSScrollView, !scrollView.isHiddenOrHasHiddenAncestor { found.append(scrollView) }
            queue.append(contentsOf: view.subviews)
        }
        return found
    }

    /// How far down the channel the list is, in points from the top.
    private var offset: Double {
        guard let scrollView, let document = scrollView.documentView else { return 0 }
        let clip = scrollView.contentView
        let y = clip.bounds.origin.y
        return document.isFlipped ? y : document.frame.height - clip.bounds.height - y
    }

    private var maxOffset: Double {
        guard let scrollView, let document = scrollView.documentView else { return 0 }
        return max(0, document.frame.height - scrollView.contentView.bounds.height)
    }

    private var atTop: Bool { offset <= 1 }
    private var atBottom: Bool { offset >= maxOffset - 1 }

    /// Moves the pointer to the middle of the list, as when a person
    /// scrolls with the trackpad, so hover effects happen as they would.
    private func movePointer(into scrollView: NSScrollView) {
        guard let window, let primary = NSScreen.screens.first else { return }
        let inWindow = scrollView.convert(CGPoint(x: scrollView.bounds.midX, y: scrollView.bounds.midY), to: nil)
        let onScreen = window.convertPoint(toScreen: inWindow)
        pointer = CGPoint(x: onScreen.x, y: primary.frame.maxY - onScreen.y)
        eventLocation = CGPoint(x: inWindow.x, y: primary.frame.maxY - inWindow.y)
        guard options.movesPointer else { return }
        if let current = CGEvent(source: nil)?.location { originalPointer = current }
        CGWarpMouseCursorPosition(pointer)
        if let moved = NSEvent.mouseEvent(
            with: .mouseMoved, location: inWindow, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0
        ) {
            window.sendEvent(moved)
        }
    }

    /// Scrolls straight to `offset` points from the top, as the Home and
    /// End keys (or dragging the scroller) do.
    private func scroll(_ scrollView: NSScrollView, toOffset target: Double) {
        guard let document = scrollView.documentView else { return }
        let clip = scrollView.contentView
        let y = document.isFlipped ? target : document.frame.height - clip.bounds.height - target
        clip.scroll(to: CGPoint(x: clip.bounds.origin.x, y: y))
        scrollView.reflectScrolledClipView(clip)
    }

    /// NSViews in the list, by class: what each row costs AppKit.
    private func takeCensus(_ moment: String) {
        guard let document = scrollView?.documentView else { return }
        var counts: [String: Int] = [:]
        var total = 0
        var queue: [NSView] = [document]
        while let view = queue.popLast() {
            total += 1
            counts[String(describing: type(of: view)), default: 0] += 1
            queue.append(contentsOf: view.subviews)
        }
        let top = counts.sorted { $0.value > $1.value }.prefix(20).map { ["class": $0.key, "count": $0.value] as [String: Any] }
        census.append(["moment": moment, "views": total, "byClass": top, "contentHeight": document.frame.height])
    }

    // MARK: Recording

    private func begin(_ name: String) {
        recording = ScenarioRecorder(name: name, refreshInterval: refreshInterval, probe: probe, offset: offset)
        interval = signposter.beginInterval("Scroll benchmark", id: signposter.makeSignpostID(), "\(name, privacy: .public)")
    }

    private func end() {
        guard let recording else { return }
        if let interval { signposter.endInterval("Scroll benchmark", interval) }
        interval = nil
        results.append(recording.finish(offset: offset))
        self.recording = nil
    }

    private var refreshInterval: Double {
        let fps = window?.screen?.maximumFramesPerSecond ?? NSScreen.main?.maximumFramesPerSecond ?? 60
        return 1 / Double(max(1, fps))
    }

    private func finish(error: String?) {
        guard !finished else { return }
        finished = true
        displayLink?.invalidate()
        if let originalPointer { CGWarpMouseCursorPosition(originalPointer) }
        let report = makeReport(error: error)
        let summary = ScrollBenchmarkReport.summary(report)
        do {
            try FileManager.default.createDirectory(at: options.output.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: options.output)
            try Data(summary.utf8).write(to: options.output.deletingPathExtension().appendingPathExtension("txt"))
        } catch {
            FileHandle.standardError.write(Data("scroll benchmark: couldn't write \(options.output.path): \(error.localizedDescription)\n".utf8))
        }
        FileHandle.standardOutput.write(Data((summary + "\n").utf8))
        if let error { FileHandle.standardError.write(Data("scroll benchmark failed: \(error)\n".utf8)) }
        DemoScratch.removeOwn()
        exit(error == nil ? 0 : 1)
    }

    private var finished = false

    private func makeReport(error: String?) -> [String: Any] {
        let settings = app.settings
        let info = Bundle.main.infoDictionary ?? [:]
        let screen = window?.screen ?? NSScreen.main
        let memory = probe.sample()
        var media = ScrollBenchmarkMedia.counts.withLock { $0 }
        media.notFound.sort()
        var report: [String: Any] = [
            "schema": 1,
            "label": options.label,
            "date": ISO8601DateFormatter().string(from: Date()),
            "app": [
                "version": info["CFBundleShortVersionString"] as? String ?? "?",
                "build": info["CFBundleVersion"] as? String ?? "?",
                "bundleID": Bundle.main.bundleIdentifier ?? "?",
            ],
            "machine": ScrollBenchmarkProbe.machine(),
            "display": [
                "name": screen?.localizedName ?? "?",
                "refreshHz": screen?.maximumFramesPerSecond ?? 0,
                "scale": screen?.backingScaleFactor ?? 0,
            ],
            "appActive": appWasActive || becameActive,
            "windowKey": windowWasKey,
            "processPriority": getpriority(PRIO_DARWIN_PROCESS, 0),
            "config": [
                "layout": settings[.chatLayout].rawValue,
                "preset": settings.matchingPreset()?.id ?? "custom",
                "theme": settings[.appearanceFollowSystem] ? "system" : settings[.appearanceTheme],
                "avatars": settings[.chatShowAvatars],
                "mix": options.mix,
                "window": "\(Int(window?.frame.width ?? 0))x\(Int(window?.frame.height ?? 0))",
                "pointer": options.movesPointer ? "list" : "none",
                "windowShown": options.showsWindow,
                "accessibility": options.forcesAccessibility ? "on" : "auto",
                "lines": app.selectedBuffer?.lines.count ?? 0,
                "arguments": Array(ScrollBenchmark.arguments.dropFirst()),
            ],
            "scenarios": results,
            "memory": [
                "peakMB": Double(memory.peakFootprint) / 1_048_576,
                "endMB": Double(memory.footprint) / 1_048_576,
            ],
            "media": [
                "served": media.served,
                "notFound": media.notFoundCount,
                "notFoundExamples": media.notFound,
            ],
            "viewCensus": census,
            "notes": notes,
            "thermalState": ProcessInfo.processInfo.thermalState.rawValue,
            "lowPowerMode": ProcessInfo.processInfo.isLowPowerModeEnabled,
            "elapsedS": CACurrentMediaTime() - launchedAt,
        ]
        if let error { report["error"] = error }
        return report
    }

    // MARK: Accessibility

    /// Whether SwiftUI is building accessibility for the views yet (see
    /// `ScrollBenchmarkHostingView`).
    private func accessibilityIsActive() -> Bool {
        (hosting?.accessibilityRequests ?? 0) > 0
    }

    /// Asks for the window's accessibility elements, as a client does when
    /// it first looks at a window, which turns SwiftUI's accessibility on
    /// for the rest of the run.
    private func turnOnAccessibility(in window: NSWindow) {
        var queue: [Any] = [window]
        var visited = 0
        while !queue.isEmpty, visited < 50 {
            let element = queue.removeFirst()
            visited += 1
            guard let element = element as? NSAccessibilityProtocol else { continue }
            _ = element.accessibilityRole()
            _ = element.accessibilityFrame()
            queue.append(contentsOf: element.accessibilityChildren() ?? [])
        }
    }

    // MARK: Time

    private func sleep(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private func sleep(until time: CFTimeInterval) async {
        let wait = time - CACurrentMediaTime()
        if wait > 0 { await sleep(wait) }
    }
}

// MARK: - Accessibility

/// The main view's hosting view, which notices accessibility clients.
///
/// Once an accessibility client has asked the app about its views
/// (VoiceOver, but also window managers, launchers, menu bar organizers and
/// the like, such as BetterTouchTool, Bartender or Alfred, whenever they look
/// at a window), SwiftUI builds accessibility for its views from then on:
/// it evaluates every row's accessibility label and actions as the row is
/// built, which makes scrolling cost about twice as much. A client can ask
/// at any time, even in the middle of a run, and nothing in the app can stop
/// it. Clients reach SwiftUI's views through this view's children, so it
/// counts how often they're asked for, and each scenario says how it ran
/// (`accessibility`: on, off, or turned on during it). `--bench-accessibility on`
/// turns it on before the first scenario by asking for them itself, so
/// every run measures the same thing.
final class ScrollBenchmarkHostingView: NSHostingView<AnyView> {
    private(set) var accessibilityRequests = 0

    override func accessibilityChildren() -> [Any]? {
        accessibilityRequests += 1
        return super.accessibilityChildren()
    }
}

// MARK: - One scenario

/// Collects a scenario's frames, distance and costs.
@MainActor
final class ScenarioRecorder {
    let name: String
    let refreshInterval: Double
    private let probe: ScrollBenchmarkProbe
    private let startSample: ScrollBenchmarkProbe.Sample
    private let startTime = CACurrentMediaTime()
    private var lastFrame: CFTimeInterval?
    private var lastOffset: Double
    private var activeUntil: CFTimeInterval = 0
    private var intervals: [Double] = []
    private var activeSeconds: Double = 0
    private var distance: Double = 0
    private var frames = 0
    /// Frames in which the list moved.
    private var movedFrames = 0
    private var peakFootprint: UInt64 = 0

    init(name: String, refreshInterval: Double, probe: ScrollBenchmarkProbe, offset: Double) {
        self.name = name
        self.refreshInterval = refreshInterval
        self.probe = probe
        lastOffset = offset
        startSample = probe.sample()
        intervals.reserveCapacity(4_096)
    }

    func markActive(until time: CFTimeInterval) {
        activeUntil = max(activeUntil, time)
    }

    func markActive(for seconds: Double) {
        markActive(until: CACurrentMediaTime() + seconds)
    }

    func frame(at timestamp: CFTimeInterval, offset: Double) {
        let moved = abs(offset - lastOffset)
        if moved > 0.01 {
            distance += moved
            movedFrames += 1
            markActive(until: timestamp + 0.1)
        }
        lastOffset = offset
        if let lastFrame, lastFrame < activeUntil {
            let interval = timestamp - lastFrame
            intervals.append(interval)
            activeSeconds += interval
        }
        lastFrame = timestamp
        frames += 1
        if frames % 30 == 0 { peakFootprint = max(peakFootprint, probe.footprint()) }
    }

    func finish(offset: Double) -> [String: Any] {
        let end = probe.sample()
        let duration = CACurrentMediaTime() - startTime
        let sorted = intervals.sorted()
        func percentile(_ p: Double) -> Double {
            guard !sorted.isEmpty else { return 0 }
            return sorted[min(sorted.count - 1, Int((Double(sorted.count - 1) * p).rounded()))] * 1_000
        }
        let late = intervals.filter { $0 > refreshInterval * 1.5 }
        let hitchMs = late.reduce(0) { $0 + ($1 - refreshInterval) } * 1_000
        let cpuMs = (end.cpu - startSample.cpu) * 1_000
        let mainCPUMs = (end.mainThreadCPU - startSample.mainThreadCPU) * 1_000
        let busyMs = (end.mainBusy - startSample.mainBusy) * 1_000
        let instructions = Double(end.instructions &- startSample.instructions)
        let cycles = Double(end.cycles &- startSample.cycles)
        let per1000 = distance > 0 ? 1_000 / distance : 0
        peakFootprint = max(peakFootprint, end.footprint)
        return [
            "name": name,
            "durationS": duration,
            "activeS": activeSeconds,
            "distancePt": distance,
            "speedPtPerS": activeSeconds > 0 ? distance / activeSeconds : 0,
            "frames": intervals.count,
            "refreshMs": refreshInterval * 1_000,
            "ticksPerS": duration > 0 ? Double(frames) / duration : 0,
            "frameP50Ms": percentile(0.5),
            "frameP95Ms": percentile(0.95),
            "frameP99Ms": percentile(0.99),
            "frameMaxMs": (sorted.last ?? 0) * 1_000,
            "framesOver1_5x": late.count,
            "framesOver2x": intervals.filter { $0 > refreshInterval * 2 }.count,
            "hitchMs": hitchMs,
            "hitchMsPerS": activeSeconds > 0 ? hitchMs / activeSeconds : 0,
            "cpuMs": cpuMs,
            "cpuMsPerS": duration > 0 ? cpuMs / duration : 0,
            "cpuMsPer1000Pt": cpuMs * per1000,
            "mainThreadCpuMs": mainCPUMs,
            "mainThreadCpuMsPerS": duration > 0 ? mainCPUMs / duration : 0,
            "mainBusyMs": busyMs,
            "mainBusyPct": duration > 0 ? busyMs / (duration * 1_000) * 100 : 0,
            "instructionsM": instructions / 1e6,
            "instructionsMPer1000Pt": instructions / 1e6 * per1000,
            "movedFrames": movedFrames,
            "cpuMsPerMovedFrame": movedFrames > 0 ? cpuMs / Double(movedFrames) : 0,
            "instructionsMPerMovedFrame": movedFrames > 0 ? instructions / 1e6 / Double(movedFrames) : 0,
            "cyclesM": cycles / 1e6,
            "footprintStartMB": Double(startSample.footprint) / 1_048_576,
            "footprintEndMB": Double(end.footprint) / 1_048_576,
            "footprintPeakMB": Double(peakFootprint) / 1_048_576,
            "endOffsetPt": offset,
        ]
    }
}

// MARK: - Process measurements

/// CPU time, instructions, main-thread time and memory of this process.
@MainActor
final class ScrollBenchmarkProbe {
    struct Sample {
        var cpu: Double
        var mainThreadCPU: Double
        var mainBusy: Double
        var instructions: UInt64
        var cycles: UInt64
        var footprint: UInt64
        var peakFootprint: UInt64
    }

    private let mainThread = mach_thread_self()
    private var busy: Double = 0
    private var busySince: CFTimeInterval?
    private var observer: CFRunLoopObserver?

    /// Counts the main run loop's time between waking and going back to sleep.
    func start() {
        guard observer == nil else { return }
        let observer = CFRunLoopObserverCreateWithHandler(
            nil, CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue, true, 0
        ) { [weak self] _, activity in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = CACurrentMediaTime()
                if activity == .afterWaiting {
                    self.busySince = now
                } else if let since = self.busySince {
                    self.busy += now - since
                    self.busySince = nil
                }
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        self.observer = observer
        busySince = CACurrentMediaTime()
    }

    func sample() -> Sample {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
        var info = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0) }
        }
        var busy = self.busy
        if let busySince { busy += CACurrentMediaTime() - busySince }
        return Sample(
            cpu: cpu,
            mainThreadCPU: mainThreadCPU(),
            mainBusy: busy,
            instructions: status == 0 ? info.ri_instructions : 0,
            cycles: status == 0 ? info.ri_cycles : 0,
            footprint: status == 0 ? info.ri_phys_footprint : footprint(),
            peakFootprint: status == 0 ? info.ri_lifetime_max_phys_footprint : 0
        )
    }

    func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? info.phys_footprint : 0
    }

    private func mainThreadCPU() -> Double {
        var info = thread_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                thread_info(mainThread, thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return 0 }
        return Double(info.user_time.seconds + info.system_time.seconds)
            + Double(info.user_time.microseconds + info.system_time.microseconds) / 1e6
    }

    static func machine() -> [String: Any] {
        func sysctlString(_ name: String) -> String {
            var size = 0
            guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }
            var buffer = [CChar](repeating: 0, count: size)
            guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "" }
            return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
        let process = ProcessInfo.processInfo
        return [
            "model": sysctlString("hw.model"),
            "cpu": sysctlString("machdep.cpu.brand_string"),
            "cores": process.processorCount,
            "memoryGB": Double(process.physicalMemory) / 1_073_741_824,
            "os": process.operatingSystemVersionString,
            "arch": sysctlString("hw.machine"),
        ]
    }
}

// MARK: - Summary

enum ScrollBenchmarkReport {
    /// A few lines a person can read: one row per scenario.
    static func summary(_ report: [String: Any]) -> String {
        let config = report["config"] as? [String: Any] ?? [:]
        let machine = report["machine"] as? [String: Any] ?? [:]
        let display = report["display"] as? [String: Any] ?? [:]
        let memory = report["memory"] as? [String: Any] ?? [:]
        let label = (report["label"] as? String).flatMap { $0.isEmpty ? nil : " · \($0)" } ?? ""
        let columns: [(title: String, key: String, decimals: Int)] = [
            ("moved pt", "distancePt", 0), ("frames", "frames", 0),
            ("p50 ms", "frameP50Ms", 1), ("p95 ms", "frameP95Ms", 1), ("p99 ms", "frameP99Ms", 1),
            (">1.5x", "framesOver1_5x", 0), (">2x", "framesOver2x", 0), ("hitch ms/s", "hitchMsPerS", 1),
            ("CPU ms/s", "cpuMsPerS", 0), ("CPU ms/1kpt", "cpuMsPer1000Pt", 1), ("CPU ms/frame", "cpuMsPerMovedFrame", 2),
            ("main busy %", "mainBusyPct", 0),
        ]
        func pad(_ text: String, _ width: Int, left: Bool = false) -> String {
            let padding = String(repeating: " ", count: max(0, width - text.count))
            return left ? text + padding : padding + text
        }
        var lines = [
            "Vela scroll benchmark\(label) · \(config["layout"] ?? "?") layout · \(config["mix"] ?? "?") mix · \(config["window"] ?? "?") · \(display["refreshHz"] ?? "?") Hz · \(machine["cpu"] ?? "?")",
            pad("scenario", 9, left: true) + columns.map { pad($0.title, max(8, $0.title.count + 2)) }.joined() + "  a11y",
        ]
        for scenario in report["scenarios"] as? [[String: Any]] ?? [] {
            var row = pad(scenario["name"] as? String ?? "?", 9, left: true)
            for column in columns {
                let value = scenario[column.key] as? Double ?? Double(scenario[column.key] as? Int ?? 0)
                row += pad(String(format: "%.\(column.decimals)f", value), max(8, column.title.count + 2))
            }
            lines.append(row + "  " + (scenario["accessibility"] as? String ?? "?"))
        }
        lines.append("a11y: whether SwiftUI was serving an accessibility client, which makes scrolling cost more")
        lines.append(String(format: "memory: peak %.0f MB, at the end %.0f MB", memory["peakMB"] as? Double ?? 0, memory["endMB"] as? Double ?? 0))
        if let error = report["error"] as? String { lines.append("error: \(error)") }
        return lines.joined(separator: "\n")
    }
}
