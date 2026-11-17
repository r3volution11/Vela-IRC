// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaCore
import VelaIntelligence
import VelaStore
@testable import VelaUI

@MainActor
@Suite("Catch me up in the message list")
struct CatchUpUITests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func line(_ minutes: Double, _ kind: ChatLineKind = .message, nick: String = "alice") -> ChatLine {
        ChatLine(time: start.addingTimeInterval(minutes * 60), kind: kind, nick: nick, text: "hi")
    }

    // MARK: Eligibility

    @Test func countsConversationAfterTheMarker() {
        let lines = [line(0), line(1), line(2, .join), line(3, .action), line(4, .notice), line(5, .topic)]
        #expect(CatchUpEligibility.unreadLineCount(lines, after: start.addingTimeInterval(60)) == 2)
        #expect(CatchUpEligibility.unreadLineCount(lines, after: .distantPast) == 4)
        #expect(CatchUpEligibility.unreadLineCount(lines, after: start.addingTimeInterval(600)) == 0)
        #expect(CatchUpEligibility.unreadLineCount(lines, after: nil) == 0)
        #expect(CatchUpEligibility.unreadLineCount([], after: start) == 0)
    }

    @Test func theButtonNeedsTheSettingAvailabilityAndEnoughNew() {
        #expect(CatchUpEligibility.showsButton(isEnabled: true, status: .available, unreadLines: 25, threshold: 25))
        #expect(!CatchUpEligibility.showsButton(isEnabled: true, status: .available, unreadLines: 24, threshold: 25))
        #expect(!CatchUpEligibility.showsButton(isEnabled: false, status: .available, unreadLines: 99, threshold: 25))
        #expect(!CatchUpEligibility.showsButton(isEnabled: true, status: .turnedOff, unreadLines: 99, threshold: 25))
        #expect(!CatchUpEligibility.showsButton(isEnabled: true, status: .modelNotReady, unreadLines: 99, threshold: 25))
        // A threshold of 0 still needs something new.
        #expect(!CatchUpEligibility.showsButton(isEnabled: true, status: .available, unreadLines: 0, threshold: 0))
        #expect(CatchUpEligibility.showsButton(isEnabled: true, status: .available, unreadLines: 1, threshold: 0))
    }

    @Test func menusAndThePaletteOfferItWhenAnythingIsNew() {
        #expect(CatchUpEligibility.canOffer(status: .available, hasUnread: true, kind: .channel))
        #expect(CatchUpEligibility.canOffer(status: .available, hasUnread: true, kind: .query))
        #expect(!CatchUpEligibility.canOffer(status: .available, hasUnread: true, kind: .server))
        #expect(!CatchUpEligibility.canOffer(status: .available, hasUnread: false, kind: .channel))
        #expect(!CatchUpEligibility.canOffer(status: .deviceNotEligible, hasUnread: true, kind: .channel))
    }

    // MARK: Display items

    @Test func theCardSitsRightAfterTheMarker() {
        let lines = [line(0), line(1), line(2)]
        var options = MessageDisplayOptions(unreadMarkerAfter: start.addingTimeInterval(30))
        options.catchUpCardAfter = start.addingTimeInterval(30)
        var builder = MessageDisplayBuilder(options: options)
        builder.append(contentsOf: lines)
        let ids = Array(builder.result).map(\.id)
        guard let marker = ids.firstIndex(of: .unreadMarker) else {
            Issue.record("no unread marker")
            return
        }
        #expect(ids[marker + 1] == .catchUpCard)
        #expect(ids[marker + 2] == .line(lines[1].id))
        #expect(builder.result.catchUpCardScrollTarget == .unreadMarker)
    }

    /// Losing focus marks everything read, so the live marker goes: the
    /// card stays where its stretch starts.
    @Test func theCardStaysWhenTheMarkerGoes() {
        let lines = [line(0), line(1), line(2)]
        var options = MessageDisplayOptions(unreadMarkerAfter: nil)
        options.catchUpCardAfter = start.addingTimeInterval(30)
        var builder = MessageDisplayBuilder(options: options)
        builder.append(contentsOf: lines)
        let ids = Array(builder.result).map(\.id)
        #expect(!ids.contains(.unreadMarker))
        #expect(ids.dropFirst() == [.line(lines[0].id), .catchUpCard, .line(lines[1].id), .line(lines[2].id)])
        #expect(builder.result.catchUpCardScrollTarget == .catchUpCard)
    }

    /// A line arriving while the window is inactive puts a new marker
    /// further down; the card keeps its place above it.
    @Test func theCardStaysWhenTheMarkerMoves() {
        let lines = [line(0), line(1), line(2), line(3)]
        var options = MessageDisplayOptions(unreadMarkerAfter: start.addingTimeInterval(150))
        options.catchUpCardAfter = start.addingTimeInterval(30)
        var builder = MessageDisplayBuilder(options: options)
        builder.append(contentsOf: lines)
        #expect(Array(builder.result).map(\.id).dropFirst() == [
            .line(lines[0].id), .catchUpCard, .line(lines[1].id), .line(lines[2].id), .unreadMarker, .line(lines[3].id),
        ])
        #expect(builder.result.catchUpCardScrollTarget == .catchUpCard)
    }

    /// The card's first lines were dropped from memory: it waits at the top.
    @Test func anAnchorOutOfMemoryPutsTheCardAtTheTop() {
        let lines = [line(10), line(11)]
        var options = MessageDisplayOptions(unreadMarkerAfter: nil)
        options.catchUpCardAfter = start
        var builder = MessageDisplayBuilder(options: options)
        builder.append(contentsOf: lines)
        let ids = Array(builder.result).map(\.id)
        #expect(ids.first.map { if case .day = $0 { true } else { false } } == true)
        #expect(ids.dropFirst() == [.catchUpCard, .line(lines[0].id), .line(lines[1].id)])
    }

    @Test func noCardNoAnchor() {
        let options = MessageDisplayOptions(unreadMarkerAfter: start.addingTimeInterval(30))
        var builder = MessageDisplayBuilder(options: options)
        builder.append(contentsOf: [line(0), line(1)])
        #expect(!Array(builder.result).contains { $0.id == .catchUpCard })
        #expect(builder.result.catchUpCardScrollTarget == nil)
    }

    @Test func newLinesKeepTheCardInPlace() {
        let cache = MessageDisplayCache()
        var lines = [line(0), line(1)]
        var options = MessageDisplayOptions(unreadMarkerAfter: nil)
        options.catchUpCardAfter = start.addingTimeInterval(30)
        _ = cache.items(for: lines, options: options)
        lines.append(line(2))
        let ids = Array(cache.items(for: lines, options: options)).map(\.id)
        #expect(ids.filter { $0 == .catchUpCard }.count == 1)
        #expect(ids.firstIndex(of: .catchUpCard) == ids.firstIndex(of: .line(lines[1].id)).map { $0 - 1 })
        #expect(cache.rebuildCount == 1)
    }

    @Test func closingTheCardRebuildsWithoutIt() {
        let cache = MessageDisplayCache()
        let lines = [line(0), line(1)]
        var options = MessageDisplayOptions(unreadMarkerAfter: start.addingTimeInterval(30))
        options.catchUpCardAfter = start.addingTimeInterval(30)
        #expect(cache.items(for: lines, options: options).contains(id: .catchUpCard))
        options.catchUpCardAfter = nil
        #expect(!cache.items(for: lines, options: options).contains(id: .catchUpCard))
    }

    // MARK: Text

    @Test func copiesAsPlainText() {
        let summary = CatchUpSummary(
            overview: "Theme talk.",
            topics: [
                CatchUpTopic(title: "Theme engine", summary: "It landed.", participants: ["kenji", "ada"], firstLineID: nil),
                CatchUpTopic(title: "Review", summary: "", participants: [], firstLineID: nil),
            ],
            addressedToYou: ["wren asked you to review the PR."],
            messageCount: 42,
            isComplete: true
        )
        #expect(CatchUpActions.plainText(summary, bufferName: "#vela", messageCount: 42) == """
        While you were away in #vela · 42 messages

        Theme talk.

        • Theme engine — It landed. (kenji, ada)
        • Review

        You were mentioned:
        • wren asked you to review the PR.
        """)
    }

    @Test func labels() {
        #expect(CatchUpActions.messagesLabel(1) == "1 message")
        #expect(CatchUpActions.messagesLabel(42) == "42 messages")
        #expect(CatchUpActions.participantsLabel(["a", "b", "c", "d", "e"]) == "a, b and 3 others")
        #expect(CatchUpActions.participantsLabel(["a", "b"]) == "a and b")
    }

    @Test func thresholdMenuKeepsACustomValue() {
        #expect(IntelligenceCatchUpSection.options(including: 25).map(\.value) == [10, 25, 50, 100])
        #expect(IntelligenceCatchUpSection.options(including: 1).map(\.label) == ["1 new message", "10 new messages", "25 new messages", "50 new messages", "100 new messages"])
        #expect(IntelligenceCatchUpSection.options(including: 40).map(\.value) == [10, 25, 40, 50, 100])
    }
}
