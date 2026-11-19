// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaMedia

@Suite struct MemoryBudgetTests {
    private let gigabyte: UInt64 = 1024 * 1024 * 1024

    @Test func eightGigabyteMacsGetHalf() {
        #expect(MemoryBudget.scale(forPhysicalMemory: 8 * gigabyte) == 0.5)
        #expect(MemoryBudget.scaled(128 * 1024 * 1024, physicalMemory: 8 * gigabyte) == 64 * 1024 * 1024)
        #expect(MemoryBudget.scaled(4_000, physicalMemory: 8 * gigabyte) == 2_000)
    }

    @Test func biggerMacsGetTheFullBudgetAndNoMore() {
        for memory in [16, 18, 24, 32, 64, 128] as [UInt64] {
            #expect(MemoryBudget.scaled(96 * 1024 * 1024, physicalMemory: memory * gigabyte) == 96 * 1024 * 1024)
        }
    }

    @Test func budgetsNeverReachZero() {
        #expect(MemoryBudget.scaled(1, physicalMemory: 4 * gigabyte) == 1)
    }

    @Test func animatedImagesHaveASmallerPixelCap() {
        #expect(ImageLoader.maxAnimatedPixelArea <= 16_000_000)
        #expect(LoopingVideoLoader.maxPixelArea == ImageLoader.maxAnimatedPixelArea)
    }
}

@Suite struct LRUCacheTrimTests {
    @Test func trimKeepsTheMostRecentlyUsed() {
        var cache = LRUCache<Int, String>(countLimit: 10)
        for key in 0..<6 { cache.insert("\(key)", for: key, cost: 10) }
        _ = cache.value(for: 0)
        cache.trim(keeping: 0.5)
        #expect(cache.count == 3)
        #expect(cache.totalCost == 30)
        #expect(cache.peek(0) != nil)
        #expect(cache.peek(5) != nil)
        #expect(cache.peek(4) != nil)
        #expect(cache.peek(1) == nil)
    }

    @Test func trimToCost() {
        var cache = LRUCache<Int, String>(countLimit: 10)
        cache.insert("a", for: 1, cost: 50)
        cache.insert("b", for: 2, cost: 30)
        cache.insert("c", for: 3, cost: 20)
        cache.trim(toCount: 10, cost: 60)
        #expect(cache.peek(1) == nil)
        #expect(cache.totalCost == 50)
        cache.trim(keeping: 0)
        #expect(cache.count == 0)
        #expect(cache.totalCost == 0)
    }
}

@Suite struct LinkPreCheckTests {
    @Test func lineWithoutLinksIsSkipped() {
        #expect(!LinkDetector.mayContainLinks("good morning, everyone"))
        #expect(LinkDetector.mayContainLinks("see https://example.com"))
        #expect(LinkDetector.mayContainLinks("WWW.example.com"))
    }
}
