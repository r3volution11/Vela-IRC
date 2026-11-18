// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaCore
import VelaStore
@testable import VelaUI

@MainActor
@Suite("Where the message list lands")
struct ListLandingTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func line(_ minutes: Double, nick: String = "alice") -> ChatLine {
        ChatLine(time: start.addingTimeInterval(minutes * 60), kind: .message, nick: nick, text: "hi")
    }

    private func items(_ lines: [ChatLine], marker: Date?, showsMarker: Bool) -> DisplayItems {
        var builder = MessageDisplayBuilder(options: MessageDisplayOptions(unreadMarkerAfter: marker, showsUnreadMarker: showsMarker))
        builder.append(contentsOf: lines)
        return builder.result
    }

    // MARK: Opening

    @Test func firstUnreadLandsAtTheUnreadLines() {
        #expect(ListLanding.onOpen(openAt: .firstUnread, revealsCatchUpCard: false, unreadTarget: .unreadMarker) == .unread(.unreadMarker))
        let id = UUID()
        #expect(ListLanding.onOpen(openAt: .firstUnread, revealsCatchUpCard: false, unreadTarget: .line(id)) == .unread(.line(id)))
        // Nothing unread: the newest line, scrolled to for real (the bottom
        // the list starts at is estimated, and can be past the last row).
        #expect(ListLanding.onOpen(openAt: .firstUnread, revealsCatchUpCard: false, unreadTarget: nil) == .bottom)
    }

    /// Show newest: the bottom, whatever is unread, so no pill appears.
    @Test func newestAlwaysLandsAtTheBottom() {
        #expect(ListLanding.onOpen(openAt: .newest, revealsCatchUpCard: false, unreadTarget: .unreadMarker) == .bottom)
        #expect(ListLanding.onOpen(openAt: .newest, revealsCatchUpCard: false, unreadTarget: .line(UUID())) == .bottom)
        // Nothing unread: there too.
        #expect(ListLanding.onOpen(openAt: .newest, revealsCatchUpCard: false, unreadTarget: nil) == .bottom)
    }

    /// Catch me up from a context menu or the palette is asked for, so
    /// it's shown either way.
    @Test func anAskedForCatchUpCardWins() {
        for openAt in ChatOpenPosition.allCases {
            #expect(ListLanding.onOpen(openAt: openAt, revealsCatchUpCard: true, unreadTarget: .unreadMarker) == .catchUpCard)
            #expect(ListLanding.onOpen(openAt: openAt, revealsCatchUpCard: true, unreadTarget: nil) == .catchUpCard)
        }
    }

    // MARK: Coming back to Vela

    @Test func comingBackWithNewestSettlesAtTheBottom() {
        #expect(ListLanding.onWindowActivated(openAt: .newest, isPinned: true, isUserScrolling: false) == .bottom)
    }

    /// A reader who scrolled up keeps their place (the pill counts what
    /// arrived), and a gesture in progress is never interrupted.
    @Test func comingBackKeepsAPlaceTheReaderChose() {
        #expect(ListLanding.onWindowActivated(openAt: .newest, isPinned: false, isUserScrolling: false) == .stay)
        #expect(ListLanding.onWindowActivated(openAt: .newest, isPinned: true, isUserScrolling: true) == .stay)
    }

    /// First unread: coming back to Vela never moves the list (as before).
    @Test func comingBackWithFirstUnreadStays() {
        for pinned in [true, false] {
            #expect(ListLanding.onWindowActivated(openAt: .firstUnread, isPinned: pinned, isUserScrolling: false) == .stay)
        }
    }

    // MARK: Unread target

    @Test func targetIsTheMarkerWhenItsDrawn() {
        let lines = [line(0), line(1), line(2)]
        let marker = start.addingTimeInterval(30)
        #expect(ListLanding.unreadTarget(in: items(lines, marker: marker, showsMarker: true), after: marker) == .unreadMarker)
    }

    /// With the New line hidden, Jump to first unread lands on the first
    /// unread line itself.
    @Test func targetIsTheFirstUnreadLineWhenTheMarkerIsHidden() {
        let lines = [line(0), line(1), line(2)]
        let marker = start.addingTimeInterval(30)
        #expect(ListLanding.unreadTarget(in: items(lines, marker: marker, showsMarker: false), after: marker) == .line(lines[1].id))
    }

    @Test func noTargetWhenNothingIsUnread() {
        let lines = [line(0), line(1)]
        #expect(ListLanding.unreadTarget(in: items(lines, marker: nil, showsMarker: true), after: nil) == nil)
        // A read position after every line.
        let late = start.addingTimeInterval(600)
        #expect(ListLanding.unreadTarget(in: items(lines, marker: late, showsMarker: false), after: late) == nil)
    }
}

@MainActor
@Suite("Unread palette commands")
struct UnreadCommandTests {
    @Test func commandsToggleBothSettings() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "VelaUITests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "settings.json")
        let settings = SettingsStore(fileURL: url, watchForChanges: false)

        var commands = VelaCommandCatalog.unreadCommands(settings)
        #expect(commands.map(\.paletteTitle) == ["Chat: Open Channels at Newest Messages", "Chat: Show New Line"])
        #expect(commands.map(\.isChecked) == [false, true], "First unread and the New line by default")
        #expect(Set(commands.map(\.id)).count == 2)

        commands[0].perform()
        #expect(settings[.chatOpenAt] == .newest)
        commands[1].perform()
        #expect(settings[.chatShowUnreadMarker] == false)
        commands = VelaCommandCatalog.unreadCommands(settings)
        #expect(commands.map(\.isChecked) == [true, false])

        commands[0].perform()
        commands[1].perform()
        #expect(settings[.chatOpenAt] == .firstUnread)
        #expect(settings[.chatShowUnreadMarker])
    }
}
