// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaIntelligence

@Suite("Catch me up chunking")
struct CatchUpChunkingTests {
    @Test func chunksStayWithinBudgetInOrder() {
        let costs = [3, 4, 2, 5, 1, 6, 2]
        let chunks = CatchUpChunker.chunks(Array(costs.indices), budget: 8) { costs[$0] }
        #expect(chunks.map { Array($0) } == [[0, 1], [2, 3, 4], [5, 6]])
        for chunk in chunks {
            #expect(chunk.reduce(0) { $0 + costs[$1] } <= 8)
        }
        #expect(chunks.flatMap { $0 } == Array(costs.indices))
    }

    @Test func anOversizedItemGetsItsOwnChunk() {
        let costs = [2, 20, 2]
        let chunks = CatchUpChunker.chunks(Array(costs.indices), budget: 5) { costs[$0] }
        #expect(chunks.map { Array($0) } == [[0], [1], [2]])
    }

    @Test func emptyInputHasNoChunks() {
        #expect(CatchUpChunker.chunks([Int](), budget: 10) { $0 }.isEmpty)
    }

    @Test func balancedChunksAreEven() {
        // Greedy at 10 would give 10, 10, 1; balanced gives three of 7.
        let items = Array(repeating: 1, count: 21)
        let greedy = CatchUpChunker.chunks(items, budget: 10) { $0 }
        #expect(greedy.map(\.count) == [10, 10, 1])
        let balanced = CatchUpChunker.balanced(items, budget: 10) { $0 }
        #expect(balanced.map(\.count) == [7, 7, 7])
    }

    @Test func estimatesAboutThreeBytesPerToken() {
        #expect(CatchUpChunker.estimatedTokens("") == 1)
        #expect(CatchUpChunker.estimatedTokens(String(repeating: "a", count: 300)) == 101)
        // CJK: three bytes, about one token, per character.
        #expect(CatchUpChunker.estimatedTokens(String(repeating: "語", count: 100)) == 101)
    }

    @Test func budgetLeavesRoomForEverythingElse() {
        let budget = CatchUpBudget(contextSize: 4096, instructionTokens: 600, responseTokens: 750)
        #expect(budget.transcriptTokens == 4096 - 600 - 750 - 60)
        #expect(budget.shrunk(by: 0.5).transcriptTokens == (4096 - 600 - 750 - 60) / 2)
        let tiny = CatchUpBudget(contextSize: 1000, instructionTokens: 600, responseTokens: 750)
        #expect(tiny.transcriptTokens == CatchUpBudget.minimumTranscriptTokens)
    }
}
