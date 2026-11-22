// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreSpotlight
import Foundation
import Testing
@testable import VelaCore
@testable import VelaIntents
import VelaStore

/// What indexing a busy channel's messages costs, printed:
///
///     VELA_SPOTLIGHT_MEASURE=1 swift test --package-path Packages/VelaKit --filter SpotlightMessageMeasurement
///
/// - the main actor's part of each saved batch (naming its buffers),
/// - making the items, off the main actor,
/// - Core Spotlight taking them, 500 at a time, in a throwaway index of
///   this test process (emptied afterwards).
@MainActor
@Suite("Spotlight message indexing cost", .enabled(if: ProcessInfo.processInfo.environment["VELA_SPOTLIGHT_MEASURE"] == "1"))
struct SpotlightMessageMeasurement {
    private static let count = 10_000

    private func records(network: UUID) -> [MessageRecord] {
        let start = Date().addingTimeInterval(-86_400)
        return (0..<Self.count).map { number in
            MessageRecord(
                networkID: network, bufferName: "#busy", time: start.addingTimeInterval(Double(number) * 2),
                kind: number % 20 == 0 ? "action" : "message", nick: "user\(number % 40)",
                text: "message \(number): the quick brown fox jumps over the lazy dog, again and again, in a busy channel"
            )
        }
    }

    private func milliseconds(_ duration: Duration) -> String {
        let ms = Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
        return String(format: "%.2f ms", ms)
    }

    @Test func busyChannel() async throws {
        let session = NetworkSession(config: NetworkConfig(name: "Libera.Chat", host: "irc.example.invalid", nick: "doug"), database: nil)
        _ = session.ensureBuffer(name: "#busy", kind: .channel, persist: false)
        let records = records(network: session.id)
        let clock = ContinuousClock()

        // The main actor's part: naming the batch's buffers, per flush. A
        // bouncer's replay can save thousands at once; live, a flush holds
        // what arrived in 400 ms.
        var context: SavedMessagesContext?
        let big = clock.measure { context = session.savedMessagesContext(for: Array(records.prefix(2_000))) }
        let small = clock.measure {
            for start in stride(from: 0, to: 1_000, by: 10) { _ = session.savedMessagesContext(for: Array(records[start..<start + 10])) }
        }
        print("main actor, naming a 2,000-message batch: \(milliseconds(big))")
        print("main actor, 100 live batches of 10: \(milliseconds(small)) in all")

        // Off the main actor: making the items.
        let made = try #require(context)
        var items: [SpotlightMessageItem] = []
        let making = clock.measure {
            for start in stride(from: 0, to: records.count, by: 2_000) {
                items += SpotlightMessageItem.items(for: Array(records[start..<start + 2_000]), context: made, retentionDays: 0)
            }
        }
        print("background, making \(items.count) items: \(milliseconds(making))")

        // Core Spotlight, in a named index of this test process.
        let index = CSSearchableIndex(name: "VelaMeasurement-\(UUID().uuidString)")
        let searchable = items.map { item in
            let attributes = CSSearchableItemAttributeSet(contentType: .message)
            attributes.title = item.title
            attributes.contentDescription = item.text
            attributes.textContent = item.text
            attributes.contentCreationDate = item.time
            return CSSearchableItem(uniqueIdentifier: item.identifier, domainIdentifier: "vela-measurement", attributeSet: attributes)
        }
        do {
            var chunks: [Duration] = []
            for start in stride(from: 0, to: searchable.count, by: SpotlightMessageQueue.chunkSize) {
                let chunk = Array(searchable[start..<min(start + SpotlightMessageQueue.chunkSize, searchable.count)])
                chunks.append(try await clock.measure { try await index.indexSearchableItems(chunk) })
            }
            let total = chunks.reduce(.zero, +)
            print("Core Spotlight, \(searchable.count) items in \(chunks.count) calls of 500: \(milliseconds(total)) (slowest call \(milliseconds(chunks.max() ?? .zero)))")
            let removal = try await clock.measure { try await index.deleteSearchableItems(withDomainIdentifiers: ["vela-measurement"]) }
            print("Core Spotlight, removing them by domain: \(milliseconds(removal))")
        } catch {
            print("Core Spotlight wasn't available to the test process: \(error)")
            try? await index.deleteSearchableItems(withDomainIdentifiers: ["vela-measurement"])
        }
    }
}
