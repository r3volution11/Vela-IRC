// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import SwiftUI
import Testing
@testable import VelaCore
import VelaIntelligence
import VelaStore
import VelaTheme
@testable import VelaUI

/// What the message list keeps between updates so rows stay cheap to build,
/// and that it still notices when they must change.
@MainActor
@Suite("Message row caching")
struct MessageRowCachingTests {
    private let session = NetworkSession(config: NetworkConfig(name: "Libera", host: "irc.test", nick: "doug"), database: nil)
    private let buffer = BufferModel(id: BufferID(networkID: UUID(), foldedName: "#vela"), name: "#vela", kind: .channel)

    private func makeController() -> MessageListController {
        MessageListController(buffer: buffer, session: session)
    }

    private func options(nick: String) -> MessageTextOptions {
        MessageTextOptions(renderFormatting: true, selfNick: nick, channelTypes: ["#"])
    }

    private func isMentioned(_ name: String, in rendered: RenderedText, palette: MessageTextPalette) -> Bool {
        guard let range = rendered.attributed.range(of: name) else { return false }
        return rendered.attributed[range].runs.allSatisfy { $0.foregroundColor == palette.mention }
    }

    // MARK: Mentions after a nick change

    /// Rows skip updates while their item is unchanged; a nick change
    /// re-renders the text, so rows must see a change too, or mentions of
    /// the old nick stay highlighted and the new one's don't.
    @Test func aNickChangeRunsRowsAgainWithNewMentions() {
        let controller = makeController()
        let palette = MessageTextPalette.cached(theme: .fallbackLight, style: ChatStyle())
        let line = ChatLine(kind: .message, nick: "wren", text: "doug, have you seen what doug_ posted?")

        let first = controller.prepareText(palette: palette, options: options(nick: "doug"))
        #expect(isMentioned("doug", in: controller.textCache.rendered(line), palette: palette))
        // Nothing changed: same generation, rows skip.
        #expect(controller.prepareText(palette: palette, options: options(nick: "doug")) == first)

        let second = controller.prepareText(palette: palette, options: options(nick: "doug_"))
        #expect(second != first)
        let item = DisplayItem.line(LineItem(line: line, isContinuation: false, reply: nil))
        #expect(DisplayItemRow(item: item, textGeneration: first) != DisplayItemRow(item: item, textGeneration: second))
        #expect(DisplayItemRow(item: item, textGeneration: second) == DisplayItemRow(item: item, textGeneration: second))

        let rendered = controller.textCache.rendered(line)
        #expect(isMentioned("doug_", in: rendered, palette: palette))
        #expect(!isMentioned("doug", in: rendered, palette: palette))
    }

    @Test func theSamePaletteIsReusedUntilTheThemeOrFontChanges() {
        let style = ChatStyle()
        let light = MessageTextPalette.cached(theme: .fallbackLight, style: style)
        #expect(MessageTextPalette.cached(theme: .fallbackLight, style: style) == light)
        #expect(light == MessageTextPalette(theme: .fallbackLight, style: style))

        let dark = MessageTextPalette.cached(theme: .fallbackDark, style: style)
        #expect(dark != light)
        #expect(dark == MessageTextPalette(theme: .fallbackDark, style: style))

        var mono = style
        mono.monospaceFontFamily = "Menlo"
        #expect(MessageTextPalette.cached(theme: .fallbackDark, style: mono).monospaceFont == mono.monospaceFont)
    }

    // MARK: Accessibility

    @Test func renderedTextCarriesItsLinksForVoiceOver() {
        let palette = MessageTextPalette.cached(theme: .fallbackLight, style: ChatStyle())
        let rendered = MessageTextRenderer.render("see https://swift.org in #vela", palette: palette, options: options(nick: "doug"))
        #expect(rendered.linkRuns.map(\.title) == ["https://swift.org", "#vela"])
        #expect(rendered.linkRuns.first?.url.absoluteString == "https://swift.org")
        #expect(MessageTextRenderer.render("no links here", palette: palette, options: options(nick: "doug")).linkRuns.isEmpty)
    }

    @Test func labelsAreMadeOncePerLineUntilItChanges() {
        let controller = makeController()
        var line = ChatLine(kind: .message, nick: "wren", text: "hello")
        var made = 0
        func label() -> String {
            controller.accessibilityLabel(for: line) {
                made += 1
                return "label \(made)"
            }
        }
        #expect(label() == "label 1")
        #expect(label() == "label 1")
        line.isRedacted = true
        #expect(label() == "label 2")
        line.text = "edited"
        #expect(label() == "label 3")
        #expect(made == 3)
    }

    // MARK: Hover while scrolling

    @Test func hoverWaitsForTheScrollToEnd() {
        let controller = makeController()
        let a = UUID(), b = UUID(), c = UUID()
        var hovered: [UUID: Bool] = [:]
        func hover(_ row: UUID, _ hovering: Bool) {
            controller.hoverChanged(hovering, row: row) { hovered[row] = $0 }
        }

        hover(a, true)
        #expect(hovered[a] == true)

        controller.scrollPhaseChanged(isUserScrolling: true)
        // Leaving applies at once; rows passing under the pointer don't.
        hover(a, false)
        #expect(hovered[a] == false)
        hover(b, true)
        hover(b, false)
        hover(c, true)
        #expect(hovered[b] == false || hovered[b] == nil)
        #expect(hovered[c] == nil)

        // The row the pointer rests on when the scroll ends shows it.
        controller.scrollPhaseChanged(isUserScrolling: false)
        #expect(hovered[c] == true)
        #expect(hovered[b] != true)
    }

    @Test func aRowLeftDuringTheScrollIsNotHoveredAfterIt() {
        let controller = makeController()
        let row = UUID()
        var hovered: Bool?
        controller.scrollPhaseChanged(isUserScrolling: true)
        controller.hoverChanged(true, row: row) { hovered = $0 }
        controller.hoverChanged(false, row: row) { hovered = $0 }
        controller.scrollPhaseChanged(isUserScrolling: false)
        #expect(hovered == false)
    }

    // MARK: Small caches

    @Test func runSummariesFollowTheRunAsItGrows() {
        let controller = makeController()
        let alice = ChatLine(kind: .join, nick: "alice", text: "alice joined")
        let bob = ChatLine(kind: .join, nick: "bob", text: "bob joined")
        #expect(controller.summary(of: MembershipRun(lines: [alice])) == MembershipSummary.text(for: [alice]))
        #expect(controller.summary(of: MembershipRun(lines: [alice, bob])) == MembershipSummary.text(for: [alice, bob]))
    }

    @Test func dayLabelsFollowTheLocale() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 12))!
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 12))!
        let english = DayLabel.text(for: date, now: now, calendar: calendar, locale: Locale(identifier: "en_US"))
        let french = DayLabel.text(for: date, now: now, calendar: calendar, locale: Locale(identifier: "fr_FR"))
        #expect(english == "Tuesday, November 10")
        #expect(french != english)
        // Asked again, the same.
        #expect(DayLabel.text(for: date, now: now, calendar: calendar, locale: Locale(identifier: "en_US")) == english)
    }

    @Test func timestampColumnsFollowTheFormat() {
        var style = ChatStyle()
        style.timestampPattern = "HH:mm"
        let short = TimestampMetrics.columnWidth(style: style, bracketed: false)
        #expect(TimestampMetrics.columnWidth(style: style, bracketed: false) == short)
        #expect(TimestampMetrics.columnWidth(style: style, bracketed: true) > short)
        style.timestampPattern = "HH:mm:ss"
        #expect(TimestampMetrics.columnWidth(style: style, bracketed: false) > short)
    }
}
