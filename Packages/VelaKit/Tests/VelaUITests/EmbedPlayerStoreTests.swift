// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Foundation
import Testing
import VelaMedia
@testable import VelaUI

/// Stands in for a web view or AVKit player.
@MainActor
private final class FakeSurface: EmbedPlaybackSurface {
    let source: EmbedPlayerSource
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
    var isInFullscreen = false
    var onEvent: ((EmbedPlaybackEvent) -> Void)?
    private(set) var pauseCount = 0
    private(set) var isStopped = false

    init(source: EmbedPlayerSource) {
        self.source = source
    }

    func pause() { pauseCount += 1 }

    func stop() {
        isStopped = true
        view.removeFromSuperview()
    }
}

/// A store with fake surfaces and deferred work that runs only when asked.
@MainActor
private final class Harness {
    private(set) var surfaces: [FakeSurface] = []
    private var deferred: [@MainActor () -> Void] = []
    lazy var store = EmbedPlayerStore(
        makeSurface: { [unowned self] source in
            let surface = FakeSurface(source: source)
            surfaces.append(surface)
            return surface
        },
        deferral: { [unowned self] _, work in deferred.append(work) }
    )

    /// Runs deferred work, as if the grace period passed.
    func runDeferred() {
        while !deferred.isEmpty {
            let work = deferred
            deferred = []
            work.forEach { $0() }
        }
    }

    var hasDeferredWork: Bool { !deferred.isEmpty }

    @discardableResult
    func start(_ key: EmbedPlayerKey) -> FakeSurface {
        store.start(key, source: .file(URL(string: "https://example.com/\(key.linkID).mp4")!), info: info(key))
        return surface(key)
    }

    func surface(_ key: EmbedPlayerKey) -> FakeSurface {
        // swiftlint:disable:next force_cast
        store.surface(for: key) as! FakeSurface
    }

    func info(_ key: EmbedPlayerKey) -> EmbedPlayerInfo {
        EmbedPlayerInfo(
            linkURL: URL(string: "https://example.com/\(key.linkID).mp4")!,
            title: key.linkID,
            provider: nil,
            siteName: "example.com",
            aspectRatio: 16.0 / 9.0
        )
    }
}

private func key(_ name: String, line: UUID = UUID()) -> EmbedPlayerKey {
    EmbedPlayerKey(lineID: line, linkID: name)
}

@MainActor
@Suite("Embed player store")
struct EmbedPlayerStoreTests {
    // MARK: One at a time

    @Test func startingAPlayerPausesTheOthers() {
        let harness = Harness()
        let a = harness.start(key("a"))
        let b = harness.start(key("b"))
        #expect(a.pauseCount == 1)
        #expect(b.pauseCount == 0)

        // Pressing play in A's own controls pauses B.
        a.onEvent?(.startedPlaying)
        #expect(b.pauseCount == 1)
        #expect(a.pauseCount == 1)
    }

    @Test func startingALivePlayerAgainKeepsItsSurface() {
        let harness = Harness()
        let k = key("a")
        let a = harness.start(k)
        let again = harness.start(k)
        #expect(a === again)
        #expect(harness.surfaces.count == 1)
    }

    @Test func stoppingRemovesThePlayer() {
        let harness = Harness()
        let k = key("a")
        let a = harness.start(k)
        harness.store.stop(k)
        #expect(a.isStopped)
        #expect(!harness.store.isLive(k))
        #expect(harness.store.placement(of: k) == nil)
        #expect(a.onEvent == nil)
    }

    // MARK: LRU

    @Test func keepsAtMostThreeLivePlayers() {
        let harness = Harness()
        let keys = (0..<4).map { key("v\($0)") }
        let first = harness.start(keys[0])
        for k in keys.dropFirst() { harness.start(k) }
        #expect(first.isStopped)
        #expect(!harness.store.isLive(keys[0]))
        #expect(keys.dropFirst().allSatisfy { harness.store.isLive($0) })
        #expect(harness.store.placements.count == EmbedPlayerStore.liveLimit)
    }

    @Test func playingCountsAsUse() {
        let harness = Harness()
        let a = harness.start(key("a"))
        let b = harness.start(key("b"))
        harness.start(key("c"))
        a.onEvent?(.startedPlaying)
        harness.start(key("d"))
        #expect(!a.isStopped)
        #expect(b.isStopped)
    }

    @Test func neverEvictsTheExpandedPlayer() {
        let harness = Harness()
        let ka = key("a")
        let a = harness.start(ka)
        #expect(harness.store.expand(ka))
        let b = harness.start(key("b"))
        harness.start(key("c"))
        harness.start(key("d"))
        #expect(!a.isStopped)
        #expect(b.isStopped)
        #expect(harness.store.expandedKey == ka)
    }

    // MARK: Hosts

    @Test func hostAdoptsTheViewWhenPlacementMatches() {
        let harness = Harness()
        let k = key("a")
        let a = harness.start(k)
        let inline = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        let expanded = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 450))
        harness.store.attach(expanded, for: k, placement: .expanded)
        #expect(a.view.superview == nil)
        harness.store.attach(inline, for: k, placement: .inline)
        #expect(a.view.superview === inline)
        #expect(a.view.frame == inline.bounds)
        #expect(a.view.autoresizingMask == [.width, .height])
    }

    @Test func detachedPlayerPausesAfterTheGracePeriod() {
        let harness = Harness()
        let k = key("a")
        let a = harness.start(k)
        let row = NSView()
        harness.store.attach(row, for: k, placement: .inline)
        harness.store.detach(row, for: k)
        #expect(a.view.superview == nil)
        #expect(a.pauseCount == 0)
        #expect(harness.hasDeferredWork)
        harness.runDeferred()
        #expect(a.pauseCount == 1)
        #expect(harness.store.isLive(k))
    }

    @Test func rowRebuiltWithinTheGracePeriodKeepsPlaying() {
        let harness = Harness()
        let k = key("a")
        let a = harness.start(k)
        let oldRow = NSView()
        harness.store.attach(oldRow, for: k, placement: .inline)
        harness.store.detach(oldRow, for: k)
        let newRow = NSView()
        harness.store.attach(newRow, for: k, placement: .inline)
        #expect(a.view.superview === newRow)
        harness.runDeferred()
        #expect(a.pauseCount == 0)
    }

    @Test func newHostBeforeOldOneGoesAwayMovesTheViewAtOnce() {
        let harness = Harness()
        let k = key("a")
        let a = harness.start(k)
        let oldRow = NSView()
        let newRow = NSView()
        harness.store.attach(oldRow, for: k, placement: .inline)
        harness.store.attach(newRow, for: k, placement: .inline)
        #expect(a.view.superview === newRow)
        // An update of the old host doesn't take it back.
        harness.store.attach(oldRow, for: k, placement: .inline)
        #expect(a.view.superview === newRow)
        // The old host no longer holds the view, so it leaves it alone.
        harness.store.detach(oldRow, for: k)
        #expect(a.view.superview === newRow)
        #expect(!harness.hasDeferredWork)
        #expect(a.pauseCount == 0)
    }

    @Test func oldHostLeavingHandsTheViewToTheRemainingHost() {
        let harness = Harness()
        let k = key("a")
        let a = harness.start(k)
        let first = NSView()
        let second = NSView()
        harness.store.attach(first, for: k, placement: .inline)
        harness.store.attach(second, for: k, placement: .inline)
        harness.store.detach(second, for: k)
        #expect(a.view.superview === first)
        harness.runDeferred()
        #expect(a.pauseCount == 0)
    }

    // MARK: Pause rules

    @Test func scrollingOutOfViewPausesInlinePlayers() {
        let harness = Harness()
        let k = key("a")
        let a = harness.start(k)
        harness.store.inlineVisibilityChanged(k, isVisible: true)
        #expect(a.pauseCount == 0)
        harness.store.inlineVisibilityChanged(k, isVisible: false)
        #expect(a.pauseCount == 1)
        #expect(harness.store.isLive(k))
    }

    @Test func scrollingTheLineAwayDoesNotPauseTheExpandedPlayer() {
        let harness = Harness()
        let k = key("a")
        let a = harness.start(k)
        harness.store.expand(k)
        harness.store.inlineVisibilityChanged(k, isVisible: false)
        #expect(a.pauseCount == 0)
    }

    @Test func switchingConversationsPausesAllAndCollapses() {
        let harness = Harness()
        let ka = key("a")
        let kb = key("b")
        let a = harness.start(ka)
        let b = harness.start(kb)
        harness.store.expand(kb)
        let pausesBefore = (a.pauseCount, b.pauseCount)
        #expect(harness.store.selectedBufferChanged())
        #expect(a.pauseCount == pausesBefore.0 + 1)
        #expect(b.pauseCount == pausesBefore.1 + 1)
        #expect(harness.store.expandedKey == nil)
        #expect(harness.store.placement(of: kb) == .inline)
        #expect(harness.store.isLive(ka) && harness.store.isLive(kb))
    }

    @Test func automaticPausesLeaveFullscreenPlayersAlone() {
        let harness = Harness()
        let k = key("a")
        let a = harness.start(k)
        let row = NSView()
        harness.store.attach(row, for: k, placement: .inline)
        a.isInFullscreen = true
        harness.store.inlineVisibilityChanged(k, isVisible: false)
        harness.store.selectedBufferChanged()
        // The row went away while the view was in the full-screen window.
        a.view.removeFromSuperview()
        harness.store.detach(row, for: k)
        harness.runDeferred()
        #expect(a.pauseCount == 0)
    }

    @Test func stopAllStopsEverything() {
        let harness = Harness()
        let ka = key("a")
        let a = harness.start(ka)
        let b = harness.start(key("b"))
        harness.store.expand(ka)
        harness.store.stopAll()
        #expect(a.isStopped && b.isStopped)
        #expect(harness.store.placements.isEmpty)
        #expect(harness.store.expandedKey == nil)
    }

    // MARK: Expand and collapse

    @Test func expandMovesTheViewToTheExpandedHostAndBack() {
        let harness = Harness()
        let k = key("a")
        let a = harness.start(k)
        let row = NSView()
        harness.store.attach(row, for: k, placement: .inline)
        harness.store.inlineVisibilityChanged(k, isVisible: true)

        #expect(harness.store.expand(k))
        #expect(harness.store.placement(of: k) == .expanded)
        #expect(harness.store.expandedKey == k)
        // No expanded host yet: the view stays where it is.
        #expect(a.view.superview === row)

        // The overlay's host appears, then the row swaps its host for the placeholder.
        let overlay = NSView(frame: NSRect(x: 0, y: 0, width: 960, height: 540))
        harness.store.attach(overlay, for: k, placement: .expanded)
        #expect(a.view.superview === overlay)
        #expect(a.view.frame == overlay.bounds)
        harness.store.detach(row, for: k)
        #expect(a.view.superview === overlay)

        let result = harness.store.collapse()
        #expect(result == EmbedPlayerStore.CollapseResult(key: k, inlineSpotVisible: true))
        #expect(harness.store.placement(of: k) == .inline)
        #expect(harness.store.expandedKey == nil)

        // The row shows its host again, then the overlay goes away.
        let newRow = NSView()
        harness.store.attach(newRow, for: k, placement: .inline)
        #expect(a.view.superview === newRow)
        harness.store.detach(overlay, for: k)
        #expect(a.view.superview === newRow)
        harness.runDeferred()
        #expect(a.pauseCount == 0)
    }

    @Test func collapseReportsAnInlineSpotOutOfView() {
        let harness = Harness()
        let k = key("a")
        harness.start(k)
        harness.store.expand(k)
        harness.store.inlineSpotDisappeared(k)
        #expect(harness.store.collapse()?.inlineSpotVisible == false)
    }

    @Test func expandingAnotherPlayerReturnsTheFirst() {
        let harness = Harness()
        let ka = key("a")
        let kb = key("b")
        harness.start(ka)
        harness.start(kb)
        harness.store.expand(ka)
        harness.store.expand(kb)
        #expect(harness.store.expandedKey == kb)
        #expect(harness.store.placement(of: ka) == .inline)
        #expect(harness.store.placement(of: kb) == .expanded)
    }

    @Test func noExpandOrCollapseDuringFullscreen() {
        let harness = Harness()
        let ka = key("a")
        let kb = key("b")
        let a = harness.start(ka)
        harness.start(kb)
        a.isInFullscreen = true
        #expect(!harness.store.expand(kb))
        #expect(harness.store.expandedKey == nil)

        a.isInFullscreen = false
        harness.store.expand(ka)
        a.isInFullscreen = true
        #expect(harness.store.collapse() == nil)
        #expect(harness.store.expandedKey == ka)
    }

    @Test func fullscreenPlayerIsNotMovedUntilItExits() {
        let harness = Harness()
        let k = key("a")
        let a = harness.start(k)
        let row = NSView()
        harness.store.attach(row, for: k, placement: .inline)
        let fullscreenWindowContent = NSView()
        a.isInFullscreen = true
        fullscreenWindowContent.addSubview(a.view)
        // A rebuilt row registers while the player is in full screen.
        let newRow = NSView()
        harness.store.attach(newRow, for: k, placement: .inline)
        #expect(a.view.superview === fullscreenWindowContent)

        // Leaving full screen puts it back in the old row; the store moves it.
        a.isInFullscreen = false
        row.addSubview(a.view)
        a.onEvent?(.exitedFullscreen)
        harness.runDeferred()
        #expect(a.view.superview === newRow)
        #expect(a.pauseCount == 0)
    }

    @Test func expandStartsNothingByItself() {
        let harness = Harness()
        #expect(!harness.store.expand(key("a")))
        #expect(harness.store.collapse() == nil)
    }
}
