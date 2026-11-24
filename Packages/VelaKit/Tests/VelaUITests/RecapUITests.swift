// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Foundation
import SwiftUI
import Testing
@testable import VelaCore
@testable import VelaIntelligence
import VelaStore
import VelaTheme
@testable import VelaUI

/// Where Recap is offered and what it opens: the Go menu and palette, the
/// user menu, names and notes, and the window's first render.
@MainActor
@Suite("Recap commands and window", .serialized)
struct RecapUITests {
    private func demo() async throws -> (AppModel, NetworkSession, BufferModel) {
        let app = AppModel.demo()
        await app.ready()
        let libera = try #require(app.sessions.first { $0.displayName == "Libera.Chat" })
        let vela = try #require(libera.buffer(named: "#vela"))
        app.select(vela)
        return (app, libera, vela)
    }

    // MARK: Commands

    @Test func recapOpensTheSelectedChannel() async throws {
        let (app, libera, vela) = try await demo()
        var opened: [RecapWindowValue] = []
        let command = VelaCommandCatalog.recap(app: app, intelligence: .demo()) { opened.append($0) }
        #expect(command.isEnabled)
        #expect(command.shortcut == VelaCommandCatalog.Shortcuts.recap)
        #expect(command.paletteTitle == "Buffer: Recap…")
        command.perform()
        #expect(opened == [RecapWindowValue(scope: RecapScope(place: .buffer(vela.id), span: .sinceUnread, output: .summary))])

        // From a network's console, the network.
        app.select(libera.serverBuffer)
        opened = []
        VelaCommandCatalog.recap(app: app, intelligence: .demo()) { opened.append($0) }.perform()
        #expect(opened.first?.scope.place == .network(libera.id))
    }

    @Test func withoutAppleIntelligenceItOpensTheLog() async throws {
        let (app, _, _) = try await demo()
        var opened: [RecapWindowValue] = []
        let offline = IntelligenceServices(availability: .fixed(.turnedOff), summarizer: CannedSummarizer())
        let command = VelaCommandCatalog.recap(app: app, intelligence: offline) { opened.append($0) }
        // A log needs no Apple Intelligence, so it's still offered.
        #expect(command.isEnabled)
        command.perform()
        #expect(opened.first?.scope.output == .log)
    }

    @Test func turnedOffItsGone() async throws {
        let (app, _, vela) = try await demo()
        app.settings[.intelligenceRecap] = false
        defer { app.settings[.intelligenceRecap] = true }
        #expect(!VelaCommandCatalog.recap(app: app, intelligence: .demo()) { _ in }.isEnabled)
        #expect(VelaCommandCatalog.recapCommands(app: app, intelligence: .demo()) { _ in }.isEmpty)
        let session = try #require(app.session(for: vela.id.networkID))
        let menu = UserMenuActions(app: app, uiState: UIState(), session: session, buffer: vela).menu(for: [UserMenuTarget(nick: "kenji")])
        #expect(!menu.titles.contains { $0.hasPrefix("Recap") })
    }

    @Test func thePalettesOtherRecaps() async throws {
        let (app, libera, _) = try await demo()
        var opened: [RecapWindowValue] = []
        let commands = VelaCommandCatalog.recapCommands(app: app, intelligence: .demo()) { opened.append($0) }
        #expect(commands.map(\.paletteTitle) == ["Buffer: Recap Conversations with…", "Network: Recap Libera.Chat…", "Network: Recap All Networks…"])
        for command in commands { command.perform() }
        #expect(opened.map(\.scope.place) == [.network(libera.id), .network(libera.id), .everywhere])
        #expect(opened.map(\.choosesPerson) == [true, false, false])
    }

    @Test func theUserMenuOffersAPersonsRecap() async throws {
        let (app, libera, vela) = try await demo()
        let actions = UserMenuActions(app: app, uiState: UIState(), session: libera, buffer: vela)
        let menu = actions.menu(for: [UserMenuTarget(nick: "kenji")])
        #expect(menu.item(.recap)?.title == "Recap Conversations with kenji…")
        #expect(menu.titles.prefix(4) == ["Message", "Mention", "Whois", "Ping"])
        // Not for yourself, or for several people at once.
        #expect(actions.menu(for: [UserMenuTarget(nick: "doug", isSelf: true)]).item(.recap) == nil)
        #expect(actions.menu(for: [UserMenuTarget(nick: "a"), UserMenuTarget(nick: "b")]).item(.recap) == nil)
    }

    @Test func theShortcutIsFree() {
        let recap = VelaCommandCatalog.Shortcuts.recap
        #expect(ShortcutGlyphs.string(for: recap) == "⇧⌘R")
        let taken: [KeyboardShortcut] = [
            VelaCommandCatalog.Shortcuts.commandPalette, VelaCommandCatalog.Shortcuts.goToConversation,
            VelaCommandCatalog.Shortcuts.reopenClosed, VelaCommandCatalog.Shortcuts.emojiAndGIFs,
            VelaCommandCatalog.Shortcuts.toggleMemberList, VelaCommandCatalog.Shortcuts.addNetwork,
            VelaCommandCatalog.Shortcuts.closeWindow, VelaCommandCatalog.Shortcuts.selectTheme,
        ]
        #expect(!taken.contains(recap))
    }

    // MARK: Names and notes

    @Test func titlesAndSubtitles() async throws {
        let (app, libera, vela) = try await demo()
        #expect(RecapActions.title(for: RecapScope(place: .buffer(vela.id)), app: app) == "Recap of #vela")
        #expect(RecapActions.title(for: RecapScope(place: .network(libera.id)), app: app) == "Recap of Libera.Chat")
        #expect(RecapActions.title(for: RecapScope(place: .everywhere), app: app) == "Recap of all networks")
        #expect(RecapActions.title(for: RecapScope(place: .network(libera.id), person: "wren"), app: app) == "Recap of wren")
        #expect(RecapActions.placeDetail(RecapScope(place: .network(libera.id), person: "wren"), app: app) == "Libera.Chat")
        #expect(RecapActions.fileName("Recap of #vela") == "Recap of vela.md")
        let format = RecapFormat()
        let subtitle = RecapActions.subtitle(RecapScope(place: .buffer(vela.id), span: .last(minutes: 240)), input: nil, speakers: 0, app: app, format: format)
        #expect(subtitle == "Libera.Chat · Last 4 hours")
    }

    @Test func notesSayWhatsMissing() {
        let id = BufferID(networkID: UUID(), foldedName: "#vela")
        let since = Date(timeIntervalSince1970: 1_800_000_000)
        let conversation = RecapConversation(
            id: id, name: "#vela", networkName: "Libera.Chat", isChannel: true, ownNick: "doug",
            lines: (0..<2_100).map { RecapLine(time: since.addingTimeInterval(Double($0)), nick: "a", text: "x") },
            availableSince: since, startsBeforeHistory: true
        )
        let input = RecapInput(scope: RecapScope(place: .buffer(id)), conversations: [conversation], requestedStart: nil, end: since, matchingLines: 12_000)
        let format = RecapFormat(now: since)
        let notes = RecapActions.notes(for: input, output: .summary, format: format)
        #expect(notes.count == 3)
        #expect(notes[0].hasPrefix("Vela has #vela back to "))
        #expect(notes[0].contains("Save message history is off"))
        #expect(notes[1] == "Shows the newest 10,000 of 12,000 matching messages.")
        #expect(notes[2].hasPrefix("The summary reads the latest 2,000 of these 2,100 messages."))
        // A log reads them all.
        #expect(RecapActions.notes(for: input, output: .log, format: format).count == 2)
    }

    /// Asking before a long Recap names the model that will read it.
    @Test func askingFirstNamesTheModel() {
        let apple = RecapPlan(passes: 4, transcriptTokens: 20_000, estimatedSeconds: 120)
        #expect(RecapSummaryView.confirmationDetail(apple, messages: 2_000).hasPrefix("Apple Intelligence reads 2,000 messages in 4 passes."))
        let label = AIModelLabel(providerID: "ollama", providerName: "Ollama", modelID: "llama3", modelName: "llama3")
        let provider = RecapPlan(passes: 1, transcriptTokens: 20_000, estimatedSeconds: 90, venue: .provider(label))
        let detail = RecapSummaryView.confirmationDetail(provider, messages: 2_000)
        #expect(detail.hasPrefix("llama3 (Ollama) reads 2,000 messages in one pass."))
        #expect(!detail.contains("Apple Intelligence"))
    }

    @Test func theCardSaysWhatARecapAdds() {
        #expect(CatchUpCardView.fullRecapHelp(messageCount: 1_240).hasPrefix("This card covers the latest 600 of 1,240 messages."))
        #expect(CatchUpCardView.fullRecapHelp(messageCount: 40).hasPrefix("A fuller report"))
    }

    // MARK: Performance

    /// Reading, filtering and laying out a Recap of 5,000 messages: what
    /// runs off the main thread, and the window's first render, which is
    /// lazy. Prints the times; the bounds are loose, for a slow CI Mac.
    @Test func fiveThousandMessages() async throws {
        let (app, libera, vela) = try await demo()
        let cast = ["kenji", "ada", "theo", "priya", "lukas", "marisol", "wren", "nadia"]
        let start = Date().addingTimeInterval(-6 * 3600)
        vela.insertSorted((0..<5_000).map { index in
            ChatLine(
                msgid: "p\(index)",
                time: start.addingTimeInterval(Double(index) * 4),
                kind: .message,
                nick: cast[index % cast.count],
                text: index % 50 == 0
                    ? "doug: can you look at https://github.com/r3volution11/Vela-IRC/pull/\(index)?"
                    : "message \(index) about the \u{02}theme\u{02} engine, the release and wren's sidebar",
                isHistory: true
            )
        })
        let clock = ContinuousClock()
        let gatherer = RecapGatherer(app: app)

        var input = RecapInput(scope: RecapScope(place: .everywhere), conversations: [], requestedStart: nil, end: Date())
        let gather = await clock.measure {
            input = await gatherer.gather(RecapScope(place: .network(libera.id), span: .last(minutes: 480)))
        }
        #expect(input.lineCount >= 5_000)
        let person = await clock.measure {
            _ = await gatherer.gather(RecapScope(place: .network(libera.id), person: "wren", span: .last(minutes: 480)))
        }
        var findings = RecapFindings()
        let found = clock.measure { findings = RecapFindings(input) }
        #expect(findings.forYou.count == RecapFindings.maximumForYou)
        let format = RecapFormat()
        let rows = clock.measure { _ = RecapLogRows(input, format: format) }
        let transcript = clock.measure { _ = RecapTranscript(input) }
        let summary = try CannedSummarizer.recapSummary(for: input)
        let markdown = clock.measure {
            _ = RecapMarkdown.log(header: RecapMarkdown.Header(title: "Recap", subtitle: ""), input: input, format: format)
            _ = RecapMarkdown.summary(header: RecapMarkdown.Header(title: "Recap", subtitle: ""), findings: findings, summary: summary, format: format)
        }

        // The window's first render, for the log and the summary.
        var renders: [String: Duration] = [:]
        for output in [RecapScope.Output.log, .summary] {
            let session = RecapSession(
                scope: RecapScope(place: .network(libera.id), span: .last(minutes: 480), output: output),
                gather: { _ in input },
                summarizer: CannedSummarizer(stepDelay: .zero),
                status: { .available }
            )
            session.start()
            #expect(await eventually(timeout: .seconds(10)) { session.phase == .ready && session.summaryPhase != .estimating })
            // 2,000 messages on a 4,096-token model: it asks first.
            if case .confirming = session.summaryPhase { session.confirm() }
            #expect(await eventually(timeout: .seconds(10)) { output == .log || session.summaryPhase == .done })
            let (window, host, first) = host(session, app: app)
            try await Task.sleep(for: .milliseconds(400))
            // Drawing what's on screen once the log's rows are laid out.
            let settled = clock.measure {
                window.contentView?.layoutSubtreeIfNeeded()
                if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: rep)
                }
            }
            renders["\(output) first"] = first
            renders["\(output) settled"] = settled
            window.orderOut(nil)
            window.contentView = nil
            session.close()
        }

        print("""
        Recap, 5,000 messages in #vela (plus the demo's other channels):
          gather (snapshot + filter, off the main thread): \(gather)
          gather for one person: \(person)
          findings (for you, links, people): \(found)
          log rows: \(rows)
          transcript for Apple Intelligence (2,000 newest): \(transcript)
          Markdown (log and summary): \(markdown)
          window first layout, log: \(renders["log first"]!), then drawing the rows on screen: \(renders["log settled"]!)
          window first layout, summary: \(renders["summary first"]!), then drawing it: \(renders["summary settled"]!)
        """)
        #expect(gather < .seconds(2))
        #expect(found < .seconds(2))
        #expect(renders["log settled"]! < .seconds(2))
        #expect(renders["summary settled"]! < .seconds(2))
    }

    private func eventually(timeout: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
        await RunningDeadline.wait(timeout: timeout, until: condition)
    }

    /// The Recap window's content in an offscreen window that's never
    /// shown, and how long its first layout took.
    private func host(_ session: RecapSession, app: AppModel) -> (NSWindow, NSView, Duration) {
        let themeStore = ThemeStore(
            userThemesDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("VelaRecap-\(UUID().uuidString)"),
            settings: ThemeSettings(settings: app.settings)
        )
        let size = CGSize(width: 780, height: 900)
        let view = RecapWindowContent(session: session, choosesPerson: .constant(false))
            .velaEnvironment(app: app, themeStore: themeStore, uiState: UIState(), services: SceneServices(intelligence: .demo()), isPrimary: false)
            .frame(width: size.width, height: size.height)
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -9000, y: -9000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let first = ContinuousClock().measure {
            window.contentView = host
            window.orderFrontRegardless()
            window.contentView?.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
        }
        return (window, host, first)
    }
}
