// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaTheme

/// "alice is typing…" at the bottom of the message list, from IRCv3 `+typing`.
///
/// It floats over the list rather than taking a row of its own, so nobody
/// typing costs no space. `MessageListView` keeps it mounted, fades it in
/// and out with `isShown` and makes room under the last message while it
/// shows (see `ListEndSpacing`). `onActiveChange` reports when someone
/// starts typing or everyone stops (`animated` is false for the first
/// report); the list owns `isShown` so the line, the room for it and the
/// scroll position move in one animation. The last names stay up while the
/// line fades out. The dots animate unless Reduce Motion is on.
struct TypingIndicatorView: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let buffer: BufferModel
    let isShown: Bool
    let onActiveChange: (_ active: Bool, _ animated: Bool) -> Void

    /// The names on the line: the current ones, or the last ones while it fades out.
    @State private var shownNicks: [String] = []

    var body: some View {
        let nicks = buffer.kind == .server ? [] : buffer.typingNicks
        line
            .foregroundStyle(theme[ThemeKey.typingForeground])
            .padding(.trailing, style.rowHorizontalPadding)
            .padding(.top, ListEndSpacing.typingLineTopPadding)
            .padding(.bottom, ListEndSpacing.typingLineBottomPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { band }
            .devTag(
                "Typing line",
                tokens: [ThemeKey.typingForeground],
                font: style.font(size: max(9, style.fontSize - 2)),
                padding: EdgeInsets(
                    top: ListEndSpacing.typingLineTopPadding, leading: 0,
                    bottom: ListEndSpacing.typingLineBottomPadding, trailing: style.rowHorizontalPadding
                )
            )
            .opacity(isShown ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.plainMessage(for: nicks) ?? "")
            .accessibilityHidden(nicks.isEmpty)
            .onChange(of: nicks, initial: true) { old, new in
                if !new.isEmpty {
                    // Cross-fade only names changing on a line that's showing;
                    // appearing, the line moves as a whole.
                    let crossFade = isShown && !old.isEmpty && !reduceMotion
                    withAnimation(crossFade ? .easeOut(duration: 0.15) : nil) { shownNicks = new }
                }
                if old.isEmpty != new.isEmpty || old == new {
                    // `old == new` only on the first call.
                    onActiveChange(!new.isEmpty, old != new)
                }
            }
    }

    /// Placed like an event row: in the grouped layout the dots sit in the
    /// gutter and the names line up with the messages; otherwise both start
    /// at the rows' leading edge.
    @ViewBuilder
    private var line: some View {
        let dots = TypingDots(animated: isShown && !reduceMotion)
        // A blank line keeps the height (which the list measures) the same
        // before anyone has typed.
        let text = (Self.message(for: shownNicks) ?? Text(verbatim: " "))
            .font(style.font(size: max(9, style.fontSize - 2)))
            .lineLimit(1)
            .truncationMode(.tail)
        if style.layout == .grouped {
            let metrics = GroupedMetrics(style: style)
            HStack(spacing: metrics.spacing) {
                dots.frame(width: metrics.gutter, alignment: style.showAvatars ? .center : .trailing)
                text
            }
            .padding(.leading, metrics.leading)
        } else {
            HStack(spacing: 6) {
                dots
                text
            }
            .padding(.leading, style.rowHorizontalPadding)
        }
    }

    /// The chat background behind the line, fading in over its top
    /// padding, so it reads cleanly over messages when the list is scrolled
    /// up. (At the bottom it only covers the room made for it.)
    private var band: some View {
        let background = theme[ThemeKey.chatBackground]
        return VStack(spacing: 0) {
            LinearGradient(colors: [background.opacity(0), background], startPoint: .top, endPoint: .bottom)
                .frame(height: ListEndSpacing.typingLineTopPadding)
            background
        }
    }

    static func message(for nicks: [String]) -> Text? {
        switch nicks.count {
        case 0:
            return nil
        case 1:
            return Text("\(nickText(nicks[0])) is typing…")
        case 2:
            return Text("\(nickText(nicks[0])) and \(nickText(nicks[1])) are typing…")
        default:
            return Text("Several people are typing…")
        }
    }

    static func plainMessage(for nicks: [String]) -> String? {
        switch nicks.count {
        case 0: nil
        case 1: "\(nicks[0]) is typing"
        case 2: "\(nicks[0]) and \(nicks[1]) are typing"
        default: "Several people are typing"
        }
    }

    private static func nickText(_ nick: String) -> Text {
        Text(nick).fontWeight(.semibold)
    }
}

/// Three dots that rise and fade in turn; static under Reduce Motion (and
/// while the line is hidden).
private struct TypingDots: View {
    let animated: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animated)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<3, id: \.self) { index in
                    let phase = animated ? Self.phase(time: time, index: index) : 0.5
                    Circle()
                        .frame(width: 4, height: 4)
                        .opacity(0.35 + 0.65 * phase)
                        .offset(y: -2 * phase)
                }
            }
        }
        .frame(width: 18, height: 8)
        .accessibilityHidden(true)
    }

    /// 0…1 pulse, each dot a third of a cycle behind the previous one.
    private static func phase(time: TimeInterval, index: Int) -> Double {
        let period = 1.2
        let t = (time / period - Double(index) * 0.18).truncatingRemainder(dividingBy: 1)
        let wrapped = t < 0 ? t + 1 : t
        // A short bump in the first ~40% of the cycle, flat otherwise.
        guard wrapped < 0.4 else { return 0 }
        return sin(wrapped / 0.4 * .pi)
    }
}
