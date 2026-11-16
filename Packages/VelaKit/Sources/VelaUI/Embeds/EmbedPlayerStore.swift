// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import AVFoundation
import AVKit
import Observation
import SwiftUI
import VelaMedia
import WebKit

// MARK: - Keys and descriptions

/// One player: the video link (`EmbedLink.id`) in one chat line.
struct EmbedPlayerKey: Hashable, Sendable {
    var lineID: UUID
    var linkID: String
}

/// Where a live player is shown.
enum EmbedPlayerPlacement: Hashable, Sendable {
    /// In its chat line.
    case inline
    /// Filling the window (`ExpandedVideoOverlay`).
    case expanded
}

/// What a player plays.
enum EmbedPlayerSource: Hashable {
    /// A provider's player (YouTube, Vimeo, …) in a web view.
    case embed(EmbedInfo)
    /// A video file, in AVKit.
    case file(URL)
}

/// What the expanded view shows around a player.
struct EmbedPlayerInfo: Hashable {
    /// The link as posted, for "Open in Browser".
    var linkURL: URL
    var title: String?
    /// The provider, for embeds; nil for video files.
    var provider: EmbedProvider?
    /// The provider's name, or the file's host.
    var siteName: String
    /// Width / height.
    var aspectRatio: CGFloat
}

/// What a playback surface reports to the store.
enum EmbedPlaybackEvent: Hashable {
    /// Media started playing, including when the user pressed play in the
    /// provider's own controls.
    case startedPlaying
    /// The player left its own full screen.
    case exitedFullscreen
}

/// Something that plays and has a view to host: a provider's player in a
/// web view, or an AVKit player. Tests use a fake.
@MainActor
protocol EmbedPlaybackSurface: AnyObject {
    /// The view hosts adopt. It moves between hosts and is never hidden.
    var view: NSView { get }
    /// In the player's own full screen, where the view belongs to the
    /// system's full-screen window: it isn't moved, and nothing pauses it.
    var isInFullscreen: Bool { get }
    var onEvent: ((EmbedPlaybackEvent) -> Void)? { get set }
    func pause()
    /// Stops playback and loading for good and removes the view from its superview.
    func stop()
}

// MARK: - Store

/// Owns the live video players, so a player outlives the chat row it's
/// shown in: rows are rebuilt and recycled while scrolling, and a player
/// moves between its line and the expanded view without reloading.
///
/// Rules:
/// - **One at a time.** Starting a player, or media starting in one (the
///   user pressed play in the provider's controls), pauses every other.
/// - **At most `liveLimit` live players.** Starting another stops the least
///   recently used one (never the expanded one or one in full screen); its
///   line shows the thumbnail again.
/// - **Hosts.** `EmbedPlayerHost`s register for a player and a placement;
///   the player's view goes into the most recently registered host for its
///   current placement, in the same run-loop turn, which WebKit doesn't
///   notice (no reload, no pause).
/// - **Pausing.** A player is paused when its line scrolls out of view,
///   when the selected conversation changes, or when it is left without a
///   host for `adoptionGrace` (a row rebuilt while visible re-adopts it
///   well within that). Paused players stay live, so scrolling back shows
///   them paused in place; the user presses play to resume.
/// - **Closing the window** stops every player.
/// - Nothing moves, collapses or pauses a player that is in its own full screen.
@MainActor
@Observable
final class EmbedPlayerStore {
    static let shared = EmbedPlayerStore()

    /// Live players (each a web content process or a streaming AVPlayer).
    static let liveLimit = 3
    /// How long a player may be without a host before it pauses.
    static let adoptionGrace: Duration = .milliseconds(300)

    typealias SurfaceFactory = @MainActor (EmbedPlayerSource) -> any EmbedPlaybackSurface
    typealias Deferral = @MainActor (Duration, @escaping @MainActor () -> Void) -> Void

    /// Live players and where each is shown. Views read this.
    private(set) var placements: [EmbedPlayerKey: EmbedPlayerPlacement] = [:]
    /// The player filling the window, if any.
    private(set) var expandedKey: EmbedPlayerKey?

    private struct Entry {
        var source: EmbedPlayerSource
        var info: EmbedPlayerInfo
        var surface: any EmbedPlaybackSurface
        var lastUsed: UInt64
    }

    private struct HostRecord {
        weak var container: NSView?
        var placement: EmbedPlayerPlacement
    }

    @ObservationIgnored private var entries: [EmbedPlayerKey: Entry] = [:]
    /// Registered hosts per player, oldest first.
    @ObservationIgnored private var hosts: [EmbedPlayerKey: [HostRecord]] = [:]
    /// Whether each live player's spot in its line was last reported in view
    /// (unknown counts as in view).
    @ObservationIgnored private var inlineSpotVisible: [EmbedPlayerKey: Bool] = [:]
    @ObservationIgnored private var clock: UInt64 = 0
    @ObservationIgnored private let makeSurface: SurfaceFactory
    @ObservationIgnored private let deferral: Deferral
    @ObservationIgnored private weak var hostWindow: NSWindow?
    @ObservationIgnored private var windowCloseObserver: (any NSObjectProtocol)?

    init(
        makeSurface: @escaping SurfaceFactory = EmbedPlayerStore.makeLiveSurface,
        deferral: @escaping Deferral = EmbedPlayerStore.mainQueueDeferral
    ) {
        self.makeSurface = makeSurface
        self.deferral = deferral
    }

    isolated deinit {
        if let windowCloseObserver { NotificationCenter.default.removeObserver(windowCloseObserver) }
    }

    // MARK: Reading

    func isLive(_ key: EmbedPlayerKey) -> Bool { placements[key] != nil }

    func placement(of key: EmbedPlayerKey) -> EmbedPlayerPlacement? { placements[key] }

    func info(for key: EmbedPlayerKey) -> EmbedPlayerInfo? { entries[key]?.info }

    func surface(for key: EmbedPlayerKey) -> (any EmbedPlaybackSurface)? { entries[key]?.surface }

    /// Some player is in its own full screen.
    var isAnyInFullscreen: Bool {
        entries.values.contains { $0.surface.isInFullscreen }
    }

    /// The window the expanded player is shown in.
    var expandedHostWindow: NSWindow? {
        guard let key = expandedKey else { return nil }
        return target(for: key, placement: .expanded)?.window
    }

    // MARK: Playing

    /// Starts `key`'s player (inline) and pauses every other. A player that
    /// is already live is left as it is.
    func start(_ key: EmbedPlayerKey, source: EmbedPlayerSource, info: EmbedPlayerInfo) {
        if entries[key] != nil {
            touch(key)
            return
        }
        let surface = makeSurface(source)
        surface.onEvent = { [weak self] event in self?.handle(event, for: key) }
        entries[key] = Entry(source: source, info: info, surface: surface, lastUsed: tick())
        placements[key] = .inline
        pauseAll(except: key, includingFullscreen: true)
        enforceLimit(keeping: key)
        place(key)
    }

    /// Stops `key`'s player for good; its line shows the thumbnail again.
    func stop(_ key: EmbedPlayerKey) {
        guard let entry = entries.removeValue(forKey: key) else { return }
        if expandedKey == key { expandedKey = nil }
        placements[key] = nil
        inlineSpotVisible[key] = nil
        entry.surface.onEvent = nil
        entry.surface.stop()
    }

    /// Stops every player (the window closed).
    func stopAll() {
        for key in Array(entries.keys) { stop(key) }
    }

    func pause(_ key: EmbedPlayerKey) {
        entries[key]?.surface.pause()
    }

    /// Pauses every player but `key`. Automatic pauses leave a player in
    /// its own full screen alone.
    func pauseAll(except key: EmbedPlayerKey? = nil, includingFullscreen: Bool = false) {
        for (other, entry) in entries where other != key {
            if !includingFullscreen && entry.surface.isInFullscreen { continue }
            entry.surface.pause()
        }
    }

    // MARK: Expanding

    /// Shows `key`'s player filling the window. Not while a player is in
    /// its own full screen.
    @discardableResult
    func expand(_ key: EmbedPlayerKey) -> Bool {
        guard entries[key] != nil, !isAnyInFullscreen else { return false }
        if let current = expandedKey, current != key {
            placements[current] = .inline
            place(current)
        }
        expandedKey = key
        placements[key] = .expanded
        touch(key)
        place(key)
        return true
    }

    struct CollapseResult: Hashable {
        var key: EmbedPlayerKey
        /// The player's spot in its line was in view, so there's no need to
        /// scroll back to it.
        var inlineSpotVisible: Bool
    }

    /// Returns the expanded player to its line. Nil when nothing is
    /// expanded or a player is in its own full screen.
    @discardableResult
    func collapse() -> CollapseResult? {
        guard let key = expandedKey, !isAnyInFullscreen else { return nil }
        expandedKey = nil
        if entries[key] != nil {
            placements[key] = .inline
            place(key)
        }
        return CollapseResult(key: key, inlineSpotVisible: inlineSpotVisible[key] ?? true)
    }

    // MARK: Hosts

    /// A host for `key` at `placement` appeared (or updated). The player's
    /// view moves into the newest host for its current placement.
    func attach(_ container: NSView, for key: EmbedPlayerKey, placement: EmbedPlayerPlacement) {
        var records = hosts[key, default: []].filter { $0.container != nil }
        if let index = records.firstIndex(where: { $0.container === container }) {
            if records[index].placement != placement {
                records.remove(at: index)
                records.append(HostRecord(container: container, placement: placement))
            }
        } else {
            records.append(HostRecord(container: container, placement: placement))
        }
        hosts[key] = records
        if let window = container.window { noteHostWindow(window) }
        place(key)
    }

    /// A host for `key` went away. It gives up the player's view only if it
    /// still holds it; the view moves to another host if there is one, and
    /// the player pauses if none adopts it within `adoptionGrace`.
    func detach(_ container: NSView, for key: EmbedPlayerKey) {
        hosts[key]?.removeAll { $0.container == nil || $0.container === container }
        if hosts[key]?.isEmpty == true { hosts[key] = nil }
        guard let entry = entries[key] else { return }
        let view = entry.surface.view
        if view.superview === container, !entry.surface.isInFullscreen {
            view.removeFromSuperview()
        }
        place(key)
        if view.superview == nil {
            deferral(Self.adoptionGrace) { [weak self] in self?.adoptionGraceEnded(for: key) }
        }
    }

    /// A host's container moved into a window: closing that window stops every player.
    func noteHostWindow(_ window: NSWindow) {
        guard window !== hostWindow else { return }
        hostWindow = window
        if let windowCloseObserver { NotificationCenter.default.removeObserver(windowCloseObserver) }
        windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopAll() }
        }
    }

    // MARK: Pause rules

    /// The player's spot in its line scrolled into or out of view. Out of
    /// view pauses an inline player.
    func inlineVisibilityChanged(_ key: EmbedPlayerKey, isVisible: Bool) {
        guard let entry = entries[key] else { return }
        inlineSpotVisible[key] = isVisible
        guard !isVisible, placements[key] == .inline, !entry.surface.isInFullscreen else { return }
        entry.surface.pause()
    }

    /// The player's spot in its line left the screen (its row was recycled).
    /// Only remembered, for scrolling back after collapsing: a row rebuilt
    /// in place also disappears, and the adoption grace handles pausing.
    func inlineSpotDisappeared(_ key: EmbedPlayerKey) {
        guard entries[key] != nil else { return }
        inlineSpotVisible[key] = false
    }

    /// The selected conversation changed: the expanded player returns to its
    /// line and every player pauses. Returns whether a player was expanded.
    @discardableResult
    func selectedBufferChanged() -> Bool {
        var collapsed = false
        if let key = expandedKey, !(entries[key]?.surface.isInFullscreen ?? false) {
            expandedKey = nil
            collapsed = true
            if entries[key] != nil {
                placements[key] = .inline
                place(key)
            }
        }
        pauseAll()
        return collapsed
    }

    // MARK: Internals

    private func handle(_ event: EmbedPlaybackEvent, for key: EmbedPlayerKey) {
        guard entries[key] != nil else { return }
        switch event {
        case .startedPlaying:
            touch(key)
            pauseAll(except: key, includingFullscreen: true)
        case .exitedFullscreen:
            // WebKit/AVKit put the view back where it was; it may belong
            // somewhere else by now.
            deferral(.zero) { [weak self] in
                guard let self, let entry = self.entries[key] else { return }
                self.place(key)
                if entry.surface.view.superview == nil {
                    self.deferral(Self.adoptionGrace) { [weak self] in self?.adoptionGraceEnded(for: key) }
                }
            }
        }
    }

    private func adoptionGraceEnded(for key: EmbedPlayerKey) {
        guard let entry = entries[key], entry.surface.view.superview == nil, !entry.surface.isInFullscreen else { return }
        entry.surface.pause()
    }

    /// The newest live host for `key` at `placement`.
    private func target(for key: EmbedPlayerKey, placement: EmbedPlayerPlacement) -> NSView? {
        hosts[key]?.last { $0.placement == placement && $0.container != nil }?.container
    }

    /// Moves `key`'s view into the newest host for its placement. Without
    /// one it stays where it is.
    private func place(_ key: EmbedPlayerKey) {
        guard let entry = entries[key], let placement = placements[key], !entry.surface.isInFullscreen,
              let target = target(for: key, placement: placement)
        else { return }
        let view = entry.surface.view
        let moved = view.superview !== target
        if moved {
            // addSubview takes it out of its old host in the same turn.
            target.addSubview(view)
        }
        view.autoresizingMask = [.width, .height]
        if view.frame != target.bounds { view.frame = target.bounds }
        if moved, placement == .expanded {
            // Keys go to the player, not the chat input hidden behind it
            // (Return would send whatever was typed there). The new host
            // may not be in its window yet.
            deferral(.zero) { [weak self] in self?.focusExpandedPlayer(key) }
        }
    }

    private func focusExpandedPlayer(_ key: EmbedPlayerKey) {
        guard expandedKey == key, let view = entries[key]?.surface.view, let window = view.window else { return }
        window.makeFirstResponder(view)
    }

    private func enforceLimit(keeping key: EmbedPlayerKey) {
        while entries.count > Self.liveLimit {
            let candidates = entries.filter { candidate, entry in
                candidate != key && candidate != expandedKey && !entry.surface.isInFullscreen
            }
            guard let oldest = candidates.min(by: { $0.value.lastUsed < $1.value.lastUsed })?.key else { return }
            stop(oldest)
        }
    }

    private func tick() -> UInt64 {
        clock &+= 1
        return clock
    }

    private func touch(_ key: EmbedPlayerKey) {
        entries[key]?.lastUsed = tick()
    }
}

// MARK: - Live surfaces

extension EmbedPlayerStore {
    static func makeLiveSurface(_ source: EmbedPlayerSource) -> any EmbedPlaybackSurface {
        switch source {
        case .embed(let embed): WebPlayerSurface(embed: embed)
        case .file(let url): FilePlayerSurface(url: url)
        }
    }

    static func mainQueueDeferral(_ delay: Duration, _ work: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            if delay > .zero { try? await Task.sleep(for: delay) }
            work()
        }
    }
}

/// A YouTube/Vimeo/Twitch/Streamable player.
///
/// Loads `EmbedPlayerHTML` with its https `baseURL` (without that origin the
/// iframe has no Referer and YouTube refuses to play: error 153). Playback
/// starts without another click, fullscreen is allowed, nothing is persisted
/// (non-persistent data store), and any navigation away from the player —
/// "Watch on YouTube", channel links — opens in the default browser instead.
///
/// A script in its own content world reports media starting in any frame
/// (the provider's iframe included), so pressing play in the provider's
/// controls pauses the other players. It sends nothing anywhere else.
final class WebPlayerSurface: NSObject, EmbedPlaybackSurface, WKNavigationDelegate, WKUIDelegate {
    let webView: EmbedWebView
    var view: NSView { webView }
    var onEvent: ((EmbedPlaybackEvent) -> Void)?
    var isInFullscreen: Bool { webView.fullscreenState != .notInFullscreen }

    private var fullscreenObservation: NSKeyValueObservation?
    private var wasInFullscreen = false

    private static let world = WKContentWorld.world(name: "VelaPlayer")
    private static let messageName = "velaPlayback"
    private static let playReporter = """
    (() => {
      const isMedia = (target) => target && (target.tagName === 'VIDEO' || target.tagName === 'AUDIO');
      document.addEventListener('play', (event) => {
        if (!isMedia(event.target)) return;
        try { window.webkit.messageHandlers.\(messageName).postMessage('play'); } catch (error) {}
      }, true);
    })();
    """

    init(embed: EmbedInfo) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let messages = PlaybackMessageProxy()
        configuration.userContentController.addUserScript(WKUserScript(
            source: Self.playReporter, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: Self.world
        ))
        configuration.userContentController.add(messages, contentWorld: Self.world, name: Self.messageName)

        webView = EmbedWebView(frame: .zero, configuration: configuration)
        super.init()
        messages.onPlay = { [weak self] in self?.onEvent?(.startedPlaying) }
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.underPageBackgroundColor = .black
        webView.allowsMagnification = false
        webView.allowsBackForwardNavigationGestures = false
        webView.autoresizingMask = [.width, .height]
        webView.setAccessibilityLabel("\(embed.provider.displayName) player\(embed.title.map { ": \($0)" } ?? "")")
        fullscreenObservation = webView.observe(\.fullscreenState, options: [.new]) { @Sendable [weak self] _, _ in
            Task { @MainActor [weak self] in self?.fullscreenStateChanged() }
        }
        webView.loadHTMLString(EmbedPlayerHTML.html(for: embed, autoplay: true), baseURL: EmbedPlayerHTML.baseURL)
    }

    func pause() {
        webView.pauseAllMediaPlayback(completionHandler: nil)
    }

    func stop() {
        fullscreenObservation = nil
        onEvent = nil
        webView.pauseAllMediaPlayback(completionHandler: nil)
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        webView.configuration.userContentController.removeAllUserScripts()
        webView.removeFromSuperview()
    }

    private func fullscreenStateChanged() {
        let inFullscreen = isInFullscreen
        defer { wasInFullscreen = inFullscreen }
        if wasInFullscreen, !inFullscreen { onEvent?(.exitedFullscreen) }
    }

    // MARK: WKNavigationDelegate, WKUIDelegate

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        // The player iframe (and anything inside it) may navigate freely.
        guard navigationAction.targetFrame?.isMainFrame ?? false else {
            decisionHandler(.allow)
            return
        }
        let url = navigationAction.request.url
        if url == nil || url == EmbedPlayerHTML.baseURL || url?.scheme == "about" {
            decisionHandler(.allow)
            return
        }
        // Something tried to replace the player page itself: hand it to the browser.
        if navigationAction.navigationType == .linkActivated, let url, url.scheme == "https" || url.scheme == "http" {
            NSWorkspace.shared.open(url)
        }
        decisionHandler(.cancel)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // target=_blank links ("Watch on YouTube") open in the browser.
        if let url = navigationAction.request.url, url.scheme == "https" || url.scheme == "http" {
            NSWorkspace.shared.open(url)
        }
        return nil
    }
}

/// Receives the play reports. It holds its surface only weakly (through
/// `onPlay`), so the content controller, which retains it, doesn't keep the
/// surface alive.
private final class PlaybackMessageProxy: NSObject, WKScriptMessageHandler {
    var onPlay: (() -> Void)?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.body as? String == "play" { onPlay?() }
    }
}

/// A video file in AVKit, playing as soon as it's created. Never created
/// before the user clicks play, so nothing streams until then.
final class FilePlayerSurface: NSObject, EmbedPlaybackSurface, @preconcurrency AVPlayerViewDelegate {
    let player: AVPlayer
    let playerView: EmbedAVPlayerView
    var view: NSView { playerView }
    var onEvent: ((EmbedPlaybackEvent) -> Void)?
    private(set) var isInFullscreen = false

    private var statusObservation: NSKeyValueObservation?

    init(url: URL) {
        player = AVPlayer(url: url)
        player.preventsDisplaySleepDuringVideoPlayback = true
        playerView = EmbedAVPlayerView()
        super.init()
        playerView.player = player
        playerView.controlsStyle = .floating
        playerView.showsFullScreenToggleButton = true
        playerView.autoresizingMask = [.width, .height]
        playerView.delegate = self
        statusObservation = player.observe(\.timeControlStatus, options: [.old, .new]) { @Sendable [weak self] _, change in
            guard change.newValue == .playing, change.oldValue != .playing else { return }
            Task { @MainActor [weak self] in self?.onEvent?(.startedPlaying) }
        }
        player.play()
    }

    func pause() {
        player.pause()
    }

    func stop() {
        statusObservation = nil
        onEvent = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        playerView.player = nil
        playerView.delegate = nil
        playerView.removeFromSuperview()
    }

    func playerViewWillEnterFullScreen(_ playerView: AVPlayerView) {
        isInFullscreen = true
    }

    func playerViewDidExitFullScreen(_ playerView: AVPlayerView) {
        isInFullscreen = false
        onEvent?(.exitedFullscreen)
    }
}

/// An AVKit player view that passes scroll gestures on to the chat, like `EmbedWebView`.
final class EmbedAVPlayerView: AVPlayerView {
    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }
}

// MARK: - Host

/// An empty container that shows a live player's view when the player's
/// placement matches its own. The store decides where the view goes; this
/// only registers and unregisters. It never pauses or stops anything.
struct EmbedPlayerHost: NSViewRepresentable {
    let key: EmbedPlayerKey
    let placement: EmbedPlayerPlacement
    var store: EmbedPlayerStore = .shared

    func makeNSView(context: Context) -> EmbedPlayerContainerView {
        let container = EmbedPlayerContainerView()
        container.store = store
        container.registration = (key, placement)
        store.attach(container, for: key, placement: placement)
        return container
    }

    func updateNSView(_ container: EmbedPlayerContainerView, context: Context) {
        if let old = container.registration, old.key != key {
            store.detach(container, for: old.key)
        }
        container.store = store
        container.registration = (key, placement)
        store.attach(container, for: key, placement: placement)
    }

    static func dismantleNSView(_ container: EmbedPlayerContainerView, coordinator: ()) {
        guard let registration = container.registration else { return }
        container.registration = nil
        container.store?.detach(container, for: registration.key)
    }
}

/// `EmbedPlayerHost`'s view. Subviews are sized with autoresizing masks:
/// Auto Layout constraints break the player's own full screen.
final class EmbedPlayerContainerView: NSView {
    weak var store: EmbedPlayerStore?
    var registration: (key: EmbedPlayerKey, placement: EmbedPlayerPlacement)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        autoresizesSubviews = true
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { store?.noteHostWindow(window) }
    }
}
