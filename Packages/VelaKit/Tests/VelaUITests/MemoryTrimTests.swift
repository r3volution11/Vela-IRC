// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import Foundation
import ImageIO
import QuartzCore
import SwiftUI
import Testing
import UniformTypeIdentifiers
import VelaCore
import VelaMedia
@testable import VelaUI

@MainActor
@Suite("Memo cache eviction")
struct MemoCacheTests {
    @Test func evictsTheOldestQuarterWhenFull() {
        var cache = MemoCache<Int, Int>(countLimit: 8)
        for key in 0..<8 { cache.insert(key, for: key) }
        _ = cache.value(for: 0)
        cache.insert(8, for: 8)
        // 9 entries over a limit of 8: down to 6 in one go.
        #expect(cache.count == 6)
        #expect(cache.peek(0) != nil)
        #expect(cache.peek(8) != nil)
        #expect(cache.peek(1) == nil)
        #expect(cache.peek(2) == nil)
        #expect(cache.peek(3) == nil)
        #expect(cache.peek(4) != nil)
        // The next inserts don't evict until it's full again.
        cache.insert(9, for: 9)
        cache.insert(10, for: 10)
        #expect(cache.count == 8)
    }

    @Test func costOverflowKeepsTheNewest() {
        var cache = MemoCache<Int, Int>(countLimit: 100, costLimit: 100)
        cache.insert(1, for: 1, cost: 40)
        cache.insert(2, for: 2, cost: 40)
        cache.insert(3, for: 3, cost: 40)
        #expect(cache.peek(1) == nil)
        #expect(cache.peek(2) != nil)
        #expect(cache.peek(3) != nil)
        // One item over the whole budget still stays, alone.
        cache.insert(4, for: 4, cost: 500)
        #expect(cache.count == 1)
        #expect(cache.peek(4) != nil)
    }

    @Test func trimKeepsAFraction() {
        var cache = MemoCache<Int, Int>(countLimit: 100)
        for key in 0..<10 { cache.insert(key, for: key) }
        cache.trim(keeping: 0.5)
        #expect(cache.count == 5)
        #expect(cache.peek(9) != nil)
        #expect(cache.peek(4) == nil)
        cache.removeAll()
        #expect(cache.count == 0)
    }
}

@MainActor
@Suite("Memory pressure")
struct MemoryPressureTests {
    private func image(side: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }

    @Test func embedMemoryDropsImagesButKeepsSizes() {
        let memory = EmbedMemory()
        let policy = MediaPolicy()
        for index in 0..<8 {
            let url = URL(string: "https://example.com/\(index).png")!
            memory.remember(still: image(side: 8), for: StillImageKey(url: url, maxPixelSize: 8))
            memory.remember(pixelSize: CGSize(width: 8, height: 8), for: url)
        }
        memory.trim(for: .warning)
        #expect(memory.stills.count == 4)
        memory.trim(for: .critical)
        #expect(memory.stills.count == 0)
        #expect(memory.pixelSize(for: URL(string: "https://example.com/0.png")!, policy: policy) != nil)
    }

    @Test func textCacheTrimsTheLeastRecentlyUsedHalf() {
        let palette = MessageTextPalette(theme: .fallbackDark, style: ChatStyle())
        let cache = MessageTextCache(capacity: 4)
        cache.prepare(palette: palette, options: MessageTextOptions(selfNick: "doug"))
        let lines = (0..<5).map { ChatLine(kind: .message, nick: "a", text: "line \($0)") }
        for line in lines.prefix(4) { _ = cache.rendered(line) }
        _ = cache.rendered(lines[0])
        // Full: the two least recently used go, the rest stay.
        _ = cache.rendered(lines[4])
        #expect(cache.count == 3)
        cache.trim(for: .warning)
        #expect(cache.count == 1)
        cache.trim(for: .critical)
        #expect(cache.count == 0)
        #expect(cache.rendered(lines[1]).plain == "line 1")
    }

    @Test func monitorCallsLiveObjectsAndForgetsGoneOnes() {
        final class Client { var levels: [MemoryPressureLevel] = [] }
        let monitor = MemoryPressureMonitor()
        let kept = Client()
        var gone: Client? = Client()
        var goneCalls = 0
        monitor.register(kept) { client, level in client.levels.append(level) }
        monitor.register(gone!) { _, _ in goneCalls += 1 }
        monitor.handle(.warning)
        gone = nil
        monitor.handle(.critical)
        #expect(kept.levels == [.warning, .critical])
        #expect(goneCalls == 1)
    }
}

@MainActor
@Suite("Link pre-check")
struct EmbedLinkPreCheckTests {
    @Test func skipsLinesWithoutLinks() {
        #expect(!EmbedLinkExtractor.mayContainLinks("good morning, everyone"))
        #expect(!EmbedLinkExtractor.mayContainLinks("\u{02}bold\u{02} and plain"))
        #expect(EmbedLinkExtractor.mayContainLinks("look: https://example.com/a.png"))
        // Formatting codes splitting the scheme still count.
        #expect(EmbedLinkExtractor.mayContainLinks("https:\u{02}//example.com"))
    }

    @Test func linesWithoutLinksAreNotMemoized() {
        let plain = ChatLine(kind: .message, nick: "a", text: "no links here")
        #expect(EmbedLinkExtractor.links(for: plain).isEmpty)
        #expect(EmbedMemory.shared.links.peek(plain.id) == nil)
        let linked = ChatLine(kind: .message, nick: "a", text: "see https://example.com/page")
        #expect(EmbedLinkExtractor.links(for: linked).count == 1)
        #expect(EmbedMemory.shared.links.peek(linked.id) != nil)
    }
}

@MainActor
@Suite("Animated images")
struct AnimatedFramesTests {
    /// A three-frame 400×200 GIF.
    private func gif() -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, 3, nil)!
        for shade in [0.0, 0.5, 1.0] {
            let context = CGContext(
                data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.setFillColor(CGColor(gray: shade, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
            let properties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.05]] as CFDictionary
            CGImageDestinationAddImage(destination, context.makeImage()!, properties)
        }
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    @Test func framesAreDecodedAtTheDrawnSize() throws {
        let source = try #require(CGImageSourceCreateWithData(gif() as CFData, nil))
        #expect(CGImageSourceGetCount(source) == 3)
        let frame = try #require(AnimatedFrames.frame(at: 2, in: source, maxPixelSize: 100))
        #expect(max(frame.width, frame.height) == 100)
        #expect(abs(AnimatedFrames.frameDelay(in: source, at: 1) - 0.05) < 0.001)
    }

    @Test func pixelBudgetFollowsTheLayoutAndScale() {
        let wide = CGSize(width: 2000, height: 1000)
        // Fits 600×300 points under a 300-point cap: 1,200 pixels at 2×.
        #expect(AnimatedFrames.pixelBudget(pixelSize: wide, maxWidth: 720, maxHeight: 300, scale: 2) == 1200)
        #expect(AnimatedFrames.pixelBudget(pixelSize: wide, maxWidth: 720, maxHeight: 300, scale: 1) == 600)
        // Never more than the image's own pixels.
        let small = CGSize(width: 100, height: 80)
        #expect(AnimatedFrames.pixelBudget(pixelSize: small, maxWidth: 720, maxHeight: 300, scale: 2) == 100)
    }

    @Test func playerShowsDownsampledFramesInItsLayer() async throws {
        let player = AnimatedImagePlayer()
        // The app decodes at utility priority; on a 3-core CI runner busy
        // with every other UI test, that once got no time for 15 s.
        player.decodePriority = .userInitiated
        player.load(gif(), frameCount: 3, maxPixelSize: 50)
        #expect(player.canPlay)
        let layer = CALayer()
        player.attach(layer)
        player.play()
        // Generous: the main actor is shared with every other UI test.
        _ = await RunningDeadline.wait(timeout: .seconds(15)) { player.hasFrame }
        player.pause()
        #expect(player.hasFrame)
        #expect(!player.isPlaying)
        let shown = try #require(layer.contents.map { $0 as! CGImage })
        #expect(max(shown.width, shown.height) == 50)
    }
}

@MainActor
@Suite("Looping player pool")
struct LoopingPlayerPoolTests {
    private func url(_ name: String) -> URL {
        URL(filePath: "/nonexistent/\(name).mp4")
    }

    @Test func reusesPlayersByFileAndKeepsAFew() {
        var made = 0
        let pool = LoopingPlayerPool(capacity: 2) { url in
            made += 1
            return LoopingPlayer(fileURL: url)
        }
        let a = pool.checkOut(url("a"))
        pool.checkIn(a)
        #expect(pool.checkOut(url("a")) === a)
        #expect(made == 1)

        pool.checkIn(a)
        pool.checkIn(pool.checkOut(url("b")))
        pool.checkIn(pool.checkOut(url("c")))
        // Two kept: "a", the least recently returned, went.
        #expect(pool.idle.map(\.fileURL) == [url("b"), url("c")])
        _ = pool.checkOut(url("a"))
        #expect(made == 4)

        pool.trim(for: .warning)
        #expect(pool.idle.isEmpty)
    }

    @Test func oneIdlePlayerPerFile() {
        let pool = LoopingPlayerPool(capacity: 3)
        let first = pool.checkOut(url("a"))
        let second = pool.checkOut(url("a"))
        #expect(first !== second)
        pool.checkIn(first)
        pool.checkIn(second)
        #expect(pool.idle.count == 1)
        #expect(pool.checkOut(url("a")) === second)
    }
}
