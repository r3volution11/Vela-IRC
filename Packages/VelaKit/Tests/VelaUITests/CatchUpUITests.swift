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
        options.showsCatchUpCard = true
        var builder = MessageDisplayBuilder(options: options)
        builder.append(contentsOf: lines)
        let ids = Array(builder.result).map(\.id)
        guard let marker = ids.firstIndex(of: .unreadMarker) else {
            Issue.record("no unread marker")
            return
        }
        #expect(ids[marker + 1] == .catchUpCard)
        #expect(ids[marker + 2] == .line(lines[1].id))
    }

    @Test func noMarkerNoCard() {
        var options = MessageDisplayOptions(unreadMarkerAfter: nil)
        options.showsCatchUpCard = true
        var builder = MessageDisplayBuilder(options: options)
        builder.append(contentsOf: [line(0), line(1)])
        #expect(!Array(builder.result).contains { $0.id == .catchUpCard })
    }

    @Test func closingTheCardRebuildsWithoutIt() {
        let cache = MessageDisplayCache()
        let lines = [line(0), line(1)]
        var options = MessageDisplayOptions(unreadMarkerAfter: start.addingTimeInterval(30))
        options.showsCatchUpCard = true
        #expect(cache.items(for: lines, options: options).contains(id: .catchUpCard))
        options.showsCatchUpCard = false
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
