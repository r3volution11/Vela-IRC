// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Testing
import VelaCore
@testable import VelaUI

/// Which keys do what in the messages (`MessageKeyCommand`), and where the
/// selection goes (`MessageSelection`).
@Suite("Message keys and selection")
struct MessageKeyCommandTests {
    private func command(
        _ characters: String,
        _ modifiers: NSEvent.ModifierFlags = [],
        keyCode: UInt16 = 0,
        ignoring: String? = nil
    ) -> MessageKeyCommand? {
        MessageKeyCommand.command(
            keyCode: keyCode,
            characters: characters,
            charactersIgnoringModifiers: ignoring ?? characters,
            modifiers: modifiers
        )
    }

    private func key(_ function: Int) -> String { String(Character(UnicodeScalar(UInt32(function))!)) }

    @Test func arrowsPagesAndEnds() {
        // Arrow keys come with the function and number pad flags, which
        // don't count as modifiers.
        #expect(command(key(NSUpArrowFunctionKey), [.function, .numericPad], keyCode: 126) == .previous)
        #expect(command(key(NSDownArrowFunctionKey), [.function, .numericPad], keyCode: 125) == .next)
        #expect(command(key(NSPageUpFunctionKey), .function, keyCode: 116) == .pageUp)
        #expect(command(key(NSPageDownFunctionKey), .function, keyCode: 121) == .pageDown)
        #expect(command(key(NSHomeFunctionKey), .function, keyCode: 115) == .first)
        #expect(command(key(NSEndFunctionKey), .function, keyCode: 119) == .last)
        // ⌥↑ and the like are someone else's.
        #expect(command(key(NSUpArrowFunctionKey), [.option, .function], keyCode: 126) == nil)
        #expect(command(key(NSDownArrowFunctionKey), [.command, .function], keyCode: 125) == nil)
    }

    @Test func lettersActOnTheMessage() {
        #expect(command("r", keyCode: 15) == .reply)
        #expect(command("e", keyCode: 14) == .react)
        #expect(command("c", keyCode: 8) == .copy)
        #expect(command("u", keyCode: 32) == .userMenu)
        #expect(command("t", keyCode: 17) == .translate)
        // Caps Lock on.
        #expect(command("R", .capsLock, keyCode: 15) == .reply)
        #expect(command("c", .command, keyCode: 8) == .copy)
    }

    @Test func returnSpaceAndEscape() {
        #expect(command("\r", keyCode: 36) == .activate)
        #expect(command("\u{3}", .numericPad, keyCode: 76) == .activate)
        #expect(command(" ", keyCode: 49) == .showMenu)
        #expect(command(key(NSF10FunctionKey), [.shift, .function], keyCode: 109) == .showMenu)
        #expect(command(key(NSF10FunctionKey), .function, keyCode: 109) == nil)
        #expect(command(key(NSMenuFunctionKey), .function, keyCode: 110) == .showMenu)
        #expect(command("\u{1b}", keyCode: 53) == .leave)
    }

    @Test func otherCharactersAreTyped() {
        #expect(command("x", keyCode: 7) == .type)
        #expect(command("R", .shift, keyCode: 15) == .type)
        #expect(command("?", .shift, keyCode: 44) == .type)
        #expect(command("é", keyCode: 0) == .type)
        // ⌥E starts an accent: nothing typed yet, but it's typing.
        #expect(command("", .option, keyCode: 14, ignoring: "e") == .type)
    }

    @Test func shortcutsAndNavigationKeysAreLeftAlone() {
        #expect(command("\t", keyCode: 48) == nil)
        #expect(command("\u{19}", .shift, keyCode: 48) == nil)
        #expect(command("\u{7f}", keyCode: 51) == nil)
        #expect(command(key(NSLeftArrowFunctionKey), .function, keyCode: 123) == nil)
        #expect(command(key(NSF6FunctionKey), .function, keyCode: 97) == nil)
        #expect(command("l", .command, keyCode: 37) == nil)
        #expect(command("2", [.command, .option], keyCode: 19) == nil)
        #expect(command("r", .control, keyCode: 15) == nil)
    }
}

@MainActor
@Suite("Selecting messages")
struct MessageSelectionTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func line(_ kind: ChatLineKind, _ nick: String, _ text: String, _ minute: Int) -> ChatLine {
        ChatLine(time: start.addingTimeInterval(Double(minute) * 60), kind: kind, nick: nick, text: text)
    }

    /// A day divider, a message, a run of two joins, a mode change, two
    /// messages, a lone part.
    private func items() -> (DisplayItems, [ChatLine]) {
        let lines = [
            line(.message, "ann", "first", 0),
            line(.join, "bob", "bob joined", 1),
            line(.join, "cy", "cy joined", 2),
            line(.message, "ann", "second", 3),
            line(.mode, "ChanServ", "ChanServ sets mode +o ann", 4),
            line(.message, "dee", "third", 5),
            line(.part, "bob", "bob left", 6),
        ]
        var builder = MessageDisplayBuilder(options: MessageDisplayOptions())
        builder.append(contentsOf: lines)
        return (builder.result, lines)
    }

    @Test func messagesAndRunsAreSelectedEventsSkipped() throws {
        let (items, lines) = items()
        let selectable = items.filter(MessageSelection.isSelectable).map(\.id)
        #expect(selectable == [.line(lines[0].id), .membershipRun(lines[1].id), .line(lines[3].id), .line(lines[5].id)])
        let newest = try #require(MessageSelection.newest(in: items))
        #expect(items[newest].id == .line(lines[5].id))
        let oldest = try #require(MessageSelection.oldest(in: items))
        #expect(items[oldest].id == .line(lines[0].id))
    }

    @Test func stepsStopAtTheEnds() throws {
        let (items, lines) = items()
        let newest = try #require(MessageSelection.newest(in: items))
        let up = MessageSelection.step(from: newest, by: -1, in: items)
        // Past the mode change.
        #expect(items[up].id == .line(lines[3].id))
        #expect(items[MessageSelection.step(from: up, by: -1, in: items)].id == .membershipRun(lines[1].id))
        #expect(items[MessageSelection.step(from: newest, by: -10, in: items)].id == .line(lines[0].id))
        #expect(MessageSelection.step(from: newest, by: 3, in: items) == newest)
    }

    @Test func startsAtTheNewestMessageOrTheLowestInView() throws {
        let (items, lines) = items()
        let newest = try #require(MessageSelection.initial(in: items, visible: [], showsNewest: true))
        #expect(items[newest].id == .line(lines[5].id))
        // Scrolled up: the bottom-most message in view, not a run below it.
        let visible: [DisplayItemID] = [.line(lines[0].id), .membershipRun(lines[1].id)]
        let inView = try #require(MessageSelection.initial(in: items, visible: visible, showsNewest: false))
        #expect(items[inView].id == .line(lines[0].id))
        // Only a run in view: the run.
        let runOnly = try #require(MessageSelection.initial(in: items, visible: [.membershipRun(lines[1].id)], showsNewest: false))
        #expect(items[runOnly].id == .membershipRun(lines[1].id))
    }

    @Test func aPageIsWhatsInViewLessOne() {
        let (items, lines) = items()
        let visible: [DisplayItemID] = [.membershipRun(lines[1].id), .line(lines[3].id), .line(lines[4].id), .line(lines[5].id), .end]
        // A run and two messages in view (the mode change doesn't count).
        #expect(MessageSelection.pageSize(visible: visible, in: items) == 2)
        #expect(MessageSelection.pageSize(visible: [.line(lines[5].id)], in: items) == 1)
    }
}
