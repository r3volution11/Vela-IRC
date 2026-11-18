// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import VelaStore

/// Where in a row its time is drawn. See ``TimestampPlacement``.
nonisolated enum TimestampSlot: Equatable, Sendable {
    /// Classic and columns: the fixed-width column before the nick.
    case leadingColumn
    /// Grouped: the margin left of the text, where hover times go (under
    /// the avatar when avatars show).
    case gutter
    /// Grouped: beside the name in the group's header.
    case header
    /// A fixed-width column at the right edge, level with the first line,
    /// so times line up down the list.
    case trailingColumn
    /// A small line above the text.
    case above
    /// A small line below the text and its translation, above link
    /// previews and reactions, so it stays with the words it dates.
    case below
    /// Event rows: small, right after the text.
    case inline
}

/// Where a row draws its time, from the layout, the layout's
/// ``TimestampPosition`` and, in the grouped layout, the row's place in its
/// group. Pure, so the rules are tested without views.
///
/// - Classic and columns: every message shows its time where the position
///   puts it.
/// - Grouped: only a group's first message shows its time in the chosen
///   place (Top is beside the name, as Vela always did). The others keep
///   theirs for hovering: in the margin, or at the right edge with Right.
///   Bottom goes below the first message rather than the whole group:
///   that's the message it dates, and the end of a group moves whenever a
///   new message joins it.
/// - Event rows: Left and Right are the same columns as messages. Top and
///   Bottom would give every join its own extra line, so the time follows
///   the text instead, as the grouped layout always showed events.
nonisolated struct TimestampPlacement: Equatable, Sendable {
    /// Nil when the row draws no time and keeps no room for one.
    var slot: TimestampSlot?
    /// False for a hover time while the row isn't hovered: it keeps its
    /// room, so hovering moves nothing, but isn't drawn.
    var isVisible: Bool

    static let hidden = TimestampPlacement(slot: nil, isVisible: false)

    /// A message, action or notice row.
    static func message(
        layout: ChatLayout,
        position: TimestampPosition,
        isContinuation: Bool,
        isHovered: Bool,
        showTimestamps: Bool
    ) -> TimestampPlacement {
        guard showTimestamps else { return .hidden }
        switch layout {
        case .classic, .columns:
            let slot: TimestampSlot = switch position {
            case .left: .leadingColumn
            case .right: .trailingColumn
            case .top: .above
            case .bottom: .below
            }
            return TimestampPlacement(slot: slot, isVisible: true)
        case .grouped:
            if isContinuation {
                return TimestampPlacement(slot: position == .right ? .trailingColumn : .gutter, isVisible: isHovered)
            }
            let slot: TimestampSlot = switch position {
            case .left: .gutter
            case .right: .trailingColumn
            case .top: .header
            case .bottom: .below
            }
            return TimestampPlacement(slot: slot, isVisible: true)
        }
    }

    /// An event row (join, topic change, server message…) or a collapsed
    /// run of membership events.
    static func event(layout: ChatLayout, position: TimestampPosition, showTimestamps: Bool) -> TimestampPlacement {
        guard showTimestamps else { return .hidden }
        let slot: TimestampSlot = switch (layout, position) {
        case (_, .right): .trailingColumn
        case (.classic, .left), (.columns, .left): .leadingColumn
        // Grouped events keep their icon in the margin, so their time
        // stays after the text.
        default: .inline
        }
        return TimestampPlacement(slot: slot, isVisible: true)
    }

    /// Whether the grouped layout's margin holds times (hover times, and
    /// the first message's with Left), so it must be wide enough for one.
    /// With Right they're all at the right edge.
    static func groupedGutterHoldsTimes(position: TimestampPosition, showTimestamps: Bool) -> Bool {
        showTimestamps && position != .right
    }
}
