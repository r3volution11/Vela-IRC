// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaCore
import VelaIntelligence
import VelaIRC
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

    /// Asked for explicitly, so offered whenever Catch me up is on and
    /// Apple Intelligence is ready, new messages or not: with nothing new,
    /// choosing it says why (or shows the latest summary again).
    @Test func menusAndThePaletteAreOfferedWhileCatchUpIsOn() {
        #expect(CatchUpEligibility.canOffer(isEnabled: true, status: .available, kind: .channel))
        #expect(CatchUpEligibility.canOffer(isEnabled: true, status: .available, kind: .query))
        #expect(!CatchUpEligibility.canOffer(isEnabled: true, status: .available, kind: .server))
        #expect(!CatchUpEligibility.canOffer(isEnabled: true, status: .deviceNotEligible, kind: .channel))
        #expect(!CatchUpEligibility.canOffer(isEnabled: false, status: .available, kind: .channel))
    }

    @Test func thePaletteSaysWhatItWillDo() {
        #expect(CatchUpEligibility.paletteDetail(hasUnread: true, hasEarlierSummary: true) == nil)
        #expect(CatchUpEligibility.paletteDetail(hasUnread: true, hasEarlierSummary: false) == nil)
        #expect(CatchUpEligibility.paletteDetail(hasUnread: false, hasEarlierSummary: true) == "earlier summary")
        #expect(CatchUpEligibility.paletteDetail(hasUnread: false, hasEarlierSummary: false) == "nothing new")
    }

    @Test func nothingNewSaysWhenTheButtonComesBack() {
        #expect(CatchUpEligibility.nothingNewDetail(threshold: 25, showsNewLine: true)
            == "Catch me up summarizes the messages you missed. Its button appears on the New line when 25 or more messages are new.")
        #expect(CatchUpEligibility.nothingNewDetail(threshold: 1, showsNewLine: true).hasSuffix("when a new message arrives."))
        #expect(CatchUpEligibility.nothingNewDetail(threshold: 0, showsNewLine: true).hasSuffix("when a new message arrives."))
        let noLine = CatchUpEligibility.nothingNewDetail(threshold: 25, showsNewLine: false)
        #expect(!noLine.contains("New line"))
        #expect(noLine.contains("Ask again"))
    }

    /// A card left from an earlier stretch doesn't hide the button for
    /// messages that came after it.
    @Test func aCardForAnEarlierStretchLetsTheButtonBack() {
        let end = start.addingTimeInterval(600)
        #expect(CatchUpEligibility.cardHidesButton(isRunning: true, coversThrough: end, marker: end.addingTimeInterval(60)))
        #expect(CatchUpEligibility.cardHidesButton(isRunning: false, coversThrough: end, marker: start))
        #expect(!CatchUpEligibility.cardHidesButton(isRunning: false, coversThrough: end, marker: end))
        #expect(!CatchUpEligibility.cardHidesButton(isRunning: false, coversThrough: end, marker: end.addingTimeInterval(60)))
        // A "nothing new" card covers nothing.
        #expect(!CatchUpEligibility.cardHidesButton(isRunning: false, coversThrough: nil, marker: end))
    }

    // MARK: The card's words

    private func summary(_ overview: String = "", progress: CatchUpProgress? = nil, isRevising: Bool = false) -> CatchUpSummary {
        CatchUpSummary(overview: overview, topics: [], addressedToYou: [], messageCount: 600, isComplete: false, progress: progress, isRevising: isRevising)
    }

    @Test func theCardSaysHowFarAlongItIs() {
        #expect(CatchUpCardView.statusText(nil, messageCount: 250) == "Reading 250 messages…")
        #expect(CatchUpCardView.statusText(summary(), messageCount: 250) == "Reading 250 messages…")
        #expect(CatchUpCardView.statusText(summary(progress: .init(completed: 0, total: 8)), messageCount: 600) == "Reading… 1 of 8")
        #expect(CatchUpCardView.statusText(summary(progress: .init(completed: 2, total: 8)), messageCount: 600) == "Reading… 3 of 8")
        #expect(CatchUpCardView.statusText(summary(progress: .init(completed: 8, total: 8)), messageCount: 600) == "Writing the summary…")
        #expect(CatchUpCardView.revisingText(summary("Half", isRevising: true)) == "Finishing…")
        #expect(CatchUpCardView.revisingText(summary("Half", progress: .init(completed: 1, total: 3), isRevising: true)) == "Finishing… 2 of 3")
        #expect(CatchUpCardView.revisingText(summary("Half", progress: .init(completed: 3, total: 3), isRevising: true)) == "Finishing…")
    }

    @Test func theFooterSaysWhatWasSkipped() {
        let note = "Summarized on this Mac by Apple Intelligence. May contain mistakes."
        var done = CatchUpSummary(overview: "x", topics: [], addressedToYou: [], messageCount: 200, isComplete: true)
        #expect(CatchUpCardView.footerText(done, messageCount: 200) == note)
        #expect(CatchUpCardView.footerText(nil, messageCount: 200) == note)
        done.skippedMessages = 40
        #expect(CatchUpCardView.footerText(done, messageCount: 200) == "Skipped 40 messages that Apple Intelligence wouldn't summarize. " + note)
        done.messageCount = 600
        #expect(CatchUpCardView.footerText(done, messageCount: 900)
            == "Covers the latest 600 messages. Skipped 40 messages that Apple Intelligence wouldn't summarize. " + note)
    }

    // MARK: With the app model

    private func demo() throws -> (app: AppModel, session: NetworkSession, vela: BufferModel, swift: BufferModel, services: IntelligenceServices) {
        let app = AppModel.demo()
        let session = try #require(app.sessions.first)
        let vela = try #require(session.buffer(named: "#vela"))
        let swift = try #require(session.buffer(named: "#swift"))
        let services = IntelligenceServices(availability: .fixed(.available), summarizer: CannedSummarizer(stepDelay: .milliseconds(40)))
        return (app, session, vela, swift, services)
    }

    private func say(_ text: String, in channel: String, to session: NetworkSession) {
        session.handle(.message(IRCMessage(line: ":alice!a@host PRIVMSG \(channel) :\(text)")!, batch: nil))
    }

    private func eventually(timeout: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    /// Going to another channel while a summary is written, then back:
    /// the card is there, finished, and Catch Me Up still shows it after
    /// the channel has been read.
    @Test func stillOfferedAfterLeavingAndReturning() async throws {
        let (app, session, vela, swift, services) = try demo()
        let store = services.catchUp
        app.select(vela)
        for index in 1...5 { say("swift news \(index)", in: "#swift", to: session) }
        #expect(swift.unreadCount > 0)

        CatchUpActions.open(swift, session: session, app: app, store: store)
        #expect(app.selectedBufferID == swift.id)
        let card = try #require(store.card(for: swift.id))
        #expect(card.isRunning)

        // Off to #vela while it's written (MainWindowView's part).
        app.select(vela)
        store.selectionChanged(to: vela.id) { _ in true }
        #expect(store.card(for: swift.id) === card)
        #expect(await eventually { if case .done = card.phase { true } else { false } })

        // Back in #swift: read now, but the card is still there.
        app.select(swift)
        store.selectionChanged(to: swift.id) { _ in true }
        #expect(!CatchUpActions.hasUnread(swift, app: app))
        #expect(store.card(for: swift.id) === card)

        // Dismissed, it's still one click away.
        store.dismiss(swift.id)
        let commands = VelaCommandCatalog.catchUpCommands(app: app, intelligence: services)
        #expect(commands.map(\.id) == ["buffer.catchUp"])
        #expect(commands.first?.detail == "earlier summary")
        commands.first?.perform()
        let reopened = try #require(store.card(for: swift.id))
        if case .done(let summary) = reopened.phase {
            #expect(summary.messageCount == card.messageCount)
        } else {
            Issue.record("expected the earlier summary at once, got \(reopened.phase)")
        }
    }

    /// Nothing new and nothing summarized yet: the card says so instead of
    /// the command doing nothing.
    @Test func nothingNewOpensACardThatSaysSo() throws {
        let (app, session, vela, _, services) = try demo()
        app.select(vela)
        session.markRead(vela)
        app.select(try #require(session.buffer(named: "#swift")))
        app.select(vela)
        #expect(!CatchUpActions.hasUnread(vela, app: app))

        let commands = VelaCommandCatalog.catchUpCommands(app: app, intelligence: services)
        #expect(commands.first?.detail == "nothing new")
        commands.first?.perform()
        let card = try #require(services.catchUp.card(for: vela.id))
        #expect(card.isNothingNew)
        // At the end of the conversation.
        #expect(card.anchor == vela.lines.last?.time)
    }

    /// `intelligence.catchUp` off: no button, no menu item, no palette
    /// command (Siri's answer is tested with the intents).
    @Test func theSettingHidesEveryEntryPoint() throws {
        let (app, _, vela, _, services) = try demo()
        app.select(vela)
        #expect(!VelaCommandCatalog.catchUpCommands(app: app, intelligence: services).isEmpty)

        app.settings[.intelligenceCatchUp] = false
        #expect(VelaCommandCatalog.catchUpCommands(app: app, intelligence: services).isEmpty)
        #expect(!CatchUpEligibility.canOffer(isEnabled: app.settings[.intelligenceCatchUp], status: .available, kind: .channel))
        #expect(!CatchUpEligibility.showsButton(isEnabled: app.settings[.intelligenceCatchUp], status: .available, unreadLines: 500, threshold: 25))
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

    /// With the New line turned off, the card still opens where the unread
    /// lines start, just without the line above it.
    @Test func theCardSitsAtTheFirstUnreadLineWhenTheMarkerIsHidden() {
        let lines = [line(0), line(1), line(2)]
        var options = MessageDisplayOptions(unreadMarkerAfter: start.addingTimeInterval(30), showsUnreadMarker: false)
        options.catchUpCardAfter = start.addingTimeInterval(30)
        var builder = MessageDisplayBuilder(options: options)
        builder.append(contentsOf: lines)
        let ids = Array(builder.result).map(\.id)
        #expect(!ids.contains(.unreadMarker))
        #expect(ids.dropFirst() == [.line(lines[0].id), .catchUpCard, .line(lines[1].id), .line(lines[2].id)])
        #expect(builder.result.catchUpCardScrollTarget == .catchUpCard)
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

    /// The button lives on the New line; with the line off, the footer
    /// says where Catch me up is instead.
    @Test func settingsFooterFollowsTheNewLine() {
        #expect(IntelligenceCatchUpSection.footer(showsNewLine: true).hasPrefix("A button on the New line"))
        let off = IntelligenceCatchUpSection.footer(showsNewLine: false)
        #expect(off.contains("New line is off"))
        #expect(off.contains("Right-click a channel"))
        #expect(off.contains("command palette"))
    }
}
