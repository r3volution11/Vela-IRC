// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaFoundation
import VelaStore
@testable import VelaUI

@Suite("Timestamp placement")
struct TimestampPlacementTests {
    private func message(
        _ layout: ChatLayout,
        _ position: TimestampPosition,
        continuation: Bool = false,
        hovered: Bool = false,
        show: Bool = true
    ) -> TimestampPlacement {
        .message(layout: layout, position: position, isContinuation: continuation, isHovered: hovered, showTimestamps: show)
    }

    @Test func classicAndColumnsShowEveryTimeWhereThePositionSays() {
        let expected: [TimestampPosition: TimestampSlot] = [
            .left: .leadingColumn, .right: .trailingColumn, .top: .above, .bottom: .below,
        ]
        for layout in [ChatLayout.classic, .columns] {
            for (position, slot) in expected {
                // Grouping and hovering don't matter: every row has its time.
                for continuation in [false, true] {
                    for hovered in [false, true] {
                        let placement = message(layout, position, continuation: continuation, hovered: hovered)
                        #expect(placement == TimestampPlacement(slot: slot, isVisible: true), "\(layout) \(position)")
                    }
                }
            }
        }
    }

    @Test func groupedShowsTheFirstMessagesTimeWhereThePositionSays() {
        #expect(message(.grouped, .top) == TimestampPlacement(slot: .header, isVisible: true))
        #expect(message(.grouped, .left) == TimestampPlacement(slot: .gutter, isVisible: true))
        #expect(message(.grouped, .right) == TimestampPlacement(slot: .trailingColumn, isVisible: true))
        #expect(message(.grouped, .bottom) == TimestampPlacement(slot: .below, isVisible: true))
        // Hovering the first message changes nothing.
        for position in TimestampPosition.allCases {
            #expect(message(.grouped, position, hovered: true) == message(.grouped, position))
        }
    }

    @Test func groupedContinuationsShowTheirTimeOnHover() {
        // In the margin, as always, unless times are at the right edge.
        for position in [TimestampPosition.left, .top, .bottom] {
            #expect(message(.grouped, position, continuation: true) == TimestampPlacement(slot: .gutter, isVisible: false))
            #expect(message(.grouped, position, continuation: true, hovered: true) == TimestampPlacement(slot: .gutter, isVisible: true))
        }
        #expect(message(.grouped, .right, continuation: true) == TimestampPlacement(slot: .trailingColumn, isVisible: false))
        #expect(message(.grouped, .right, continuation: true, hovered: true) == TimestampPlacement(slot: .trailingColumn, isVisible: true))
    }

    @Test func timestampsOffHidesThemEverywhere() {
        for layout in ChatLayout.allCases {
            for position in TimestampPosition.allCases {
                for continuation in [false, true] {
                    for hovered in [false, true] {
                        #expect(message(layout, position, continuation: continuation, hovered: hovered, show: false) == .hidden)
                    }
                }
                #expect(TimestampPlacement.event(layout: layout, position: position, showTimestamps: false) == .hidden)
            }
        }
        #expect(TimestampPlacement.hidden.slot == nil)
    }

    @Test func eventsUseTheColumnsOrFollowTheirText() {
        func event(_ layout: ChatLayout, _ position: TimestampPosition) -> TimestampSlot? {
            TimestampPlacement.event(layout: layout, position: position, showTimestamps: true).slot
        }
        // Today's look by default.
        #expect(event(.classic, .left) == .leadingColumn)
        #expect(event(.columns, .left) == .leadingColumn)
        #expect(event(.grouped, .top) == .inline)
        // Right is the same right-edge column as messages.
        for layout in ChatLayout.allCases {
            #expect(event(layout, .right) == .trailingColumn)
        }
        // No extra line per join: the time follows the text.
        for layout in ChatLayout.allCases {
            #expect(event(layout, .top) == .inline)
            #expect(event(layout, .bottom) == .inline)
        }
        // Grouped events keep their icon in the margin.
        #expect(event(.grouped, .left) == .inline)
        for layout in ChatLayout.allCases {
            for position in TimestampPosition.allCases {
                #expect(TimestampPlacement.event(layout: layout, position: position, showTimestamps: true).isVisible)
            }
        }
    }

    @Test func groupedMarginHoldsTimesExceptWithRight() {
        #expect(TimestampPlacement.groupedGutterHoldsTimes(position: .top, showTimestamps: true))
        #expect(TimestampPlacement.groupedGutterHoldsTimes(position: .left, showTimestamps: true))
        #expect(TimestampPlacement.groupedGutterHoldsTimes(position: .bottom, showTimestamps: true))
        #expect(!TimestampPlacement.groupedGutterHoldsTimes(position: .right, showTimestamps: true))
        #expect(!TimestampPlacement.groupedGutterHoldsTimes(position: .top, showTimestamps: false))
    }

    @MainActor
    @Test func chatStyleReadsEachLayoutsPosition() throws {
        let settings = SettingsStore(fileURL: Self.temporarySettingsURL(), watchForChanges: false)
        var style = ChatStyle(settings: settings)
        #expect(style.classicTimestampPosition == .left)
        #expect(style.groupedTimestampPosition == .top)
        #expect(style.columnsTimestampPosition == .left)
        let plain = ChatStyle()
        #expect(plain.classicTimestampPosition == .left && plain.groupedTimestampPosition == .top && plain.columnsTimestampPosition == .left)

        settings[.chatTimestampPositionClassic] = .bottom
        settings[.chatTimestampPositionColumns] = .right
        style = ChatStyle(settings: settings)
        #expect(style.timestampPosition(for: .classic) == .bottom)
        #expect(style.timestampPosition(for: .grouped) == .top)
        #expect(style.timestampPosition(for: .columns) == .right)
        style.layout = .columns
        #expect(style.timestampPosition == .right)
        style.layout = .classic
        #expect(style.timestampPosition == .bottom)
    }

    @MainActor
    @Test func columnsKeepTheirLeftTimeColumnOnlyForLeft() {
        var style = ChatStyle()
        style.layout = .columns
        let left = ColumnsMetrics(style: style)
        #expect(left.timeWidth > 0)
        #expect(left.nickX == left.timeWidth + left.timeGap)
        for position in [TimestampPosition.right, .top, .bottom] {
            style.columnsTimestampPosition = position
            let metrics = ColumnsMetrics(style: style)
            #expect(metrics.timeWidth == 0, "\(position)")
            #expect(metrics.nickX == 0)
            #expect(metrics.textX == left.textX - left.nickX)
        }
        style.columnsTimestampPosition = .left
        style.showTimestamps = false
        #expect(ColumnsMetrics(style: style).timeWidth == 0)
    }

    @MainActor
    @Test func paletteCommandsSetTheCurrentLayoutsPosition() throws {
        let settings = SettingsStore(fileURL: Self.temporarySettingsURL(), watchForChanges: false)
        var commands = VelaCommandCatalog.timestampPositionCommands(settings)
        #expect(commands.map(\.paletteTitle) == [
            "Chat: Timestamps on the Left",
            "Chat: Timestamps on the Right",
            "Chat: Timestamps at the Top",
            "Chat: Timestamps at the Bottom",
        ])
        #expect(Set(commands.map(\.id)).count == 4)
        // Modern by default, with times beside the name.
        #expect(commands.map(\.isChecked) == [false, false, true, false])

        commands[3].perform()
        #expect(settings[.chatTimestampPositionGrouped] == .bottom)
        #expect(settings[.chatTimestampPositionClassic] == .left, "Other layouts keep theirs")

        settings[.chatLayout] = .columns
        commands = VelaCommandCatalog.timestampPositionCommands(settings)
        #expect(commands.map(\.isChecked) == [true, false, false, false])
        commands[1].perform()
        #expect(settings[.chatTimestampPositionColumns] == .right)
        #expect(settings[.chatTimestampPositionGrouped] == .bottom)

        // With timestamps off nothing is checked, and choosing one shows them.
        settings[.chatShowTimestamps] = false
        commands = VelaCommandCatalog.timestampPositionCommands(settings)
        #expect(commands.allSatisfy { $0.isChecked == false })
        commands[0].perform()
        #expect(settings[.chatShowTimestamps])
        #expect(settings[.chatTimestampPositionColumns] == .left)
    }

    private static func temporarySettingsURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "VelaUITests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "settings.json")
    }
}
