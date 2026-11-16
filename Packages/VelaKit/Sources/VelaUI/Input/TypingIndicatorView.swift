// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaTheme

/// "alice is typing…" above the composer, from IRCv3 `+typing`.
///
/// The line's height is always reserved, so the chat doesn't jump when
/// someone starts or stops typing. The dots animate unless Reduce Motion is on.
struct TypingIndicatorView: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let buffer: BufferModel

    static let height: CGFloat = 18

    var body: some View {
        let nicks = buffer.kind == .server ? [] : buffer.typingNicks
        HStack(spacing: 6) {
            if let message = Self.message(for: nicks) {
                TypingDots(animated: !reduceMotion)
                message
                    .font(style.font(size: max(9, style.fontSize - 2)))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .transition(.opacity)
            }
        }
        .foregroundStyle(theme[ThemeKey.typingForeground])
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height, alignment: .leading)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: nicks)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.plainMessage(for: nicks) ?? "")
        .accessibilityHidden(nicks.isEmpty)
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

/// Three dots that rise and fade in turn; static under Reduce Motion.
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
