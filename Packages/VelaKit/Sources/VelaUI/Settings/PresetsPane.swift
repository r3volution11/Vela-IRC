// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaStore
import VelaTheme

/// Settings → Presets: a window layout, a message style and a density,
/// chosen independently (``PresetAxis``). Each row writes only its own
/// settings, in one change; the theme and everything else stay as they are.
/// A row whose settings were changed by hand says "Customized", and picking
/// a choice again resets just that row.
///
/// The pictures are `LayoutSchematic` drawings in the current theme and with
/// the current settings, so each card shows what you'd get; the preview at
/// the bottom is the live chat style.
struct PresetsPane: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    let navigate: (SettingsPane) -> Void

    var body: some View {
        let settings = app.settings
        SettingsPage(
            "Presets",
            subtitle: "Choose where things live, how messages look and how much room they get. Each row changes only its own settings, never your theme or anything else."
        ) {
            PresetAxisSection(axis: .windowLayout, settings: settings, navigate: navigate) { current in
                PresetChoicePicker(axis: .windowLayout, current: current, arrangement: PresetCardGrid(minimumItemWidth: 112, spacing: 10)) { choice in
                    settings.choose(choice)
                } item: { choice, state in
                    PresetChoiceCard(choice: choice, state: state) {
                        LayoutSchematic(config: Self.config(for: choice, settings: settings), theme: theme)
                    }
                }
            }

            PresetAxisSection(axis: .messageStyle, settings: settings, navigate: navigate) { current in
                PresetChoicePicker(axis: .messageStyle, current: current, arrangement: PresetCardGrid(minimumItemWidth: 140, spacing: 10)) { choice in
                    settings.choose(choice)
                } item: { choice, state in
                    PresetChoiceCard(choice: choice, state: state) {
                        LayoutSchematic(config: Self.config(for: choice, settings: settings), theme: theme, scope: .messages)
                    }
                }
            }

            PresetAxisSection(axis: .density, settings: settings, navigate: navigate) { current in
                DensityControl(current: current) { choice in
                    settings.choose(choice)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Preview")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme[ThemeKey.settingsForeground])
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 4)
                MessageSamplePreview()
                Text("With your theme, font and other message settings. Density never changes the font size: use ⌘+ and ⌘−, or Settings → Messages.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Make it yours")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme[ThemeKey.settingsForeground])
                    .accessibilityAddTraits(.isHeader)
                Text("Everything a row sets can be changed on its own, and settings no row mentions, like media and unread messages, are never touched.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    SettingsLinkButton("Layout", systemImage: SettingsPane.layout.systemImage) { navigate(.layout) }
                    SettingsLinkButton("Messages", systemImage: SettingsPane.messages.systemImage) { navigate(.messages) }
                    SettingsLinkButton("Media", systemImage: SettingsPane.media.systemImage) { navigate(.media) }
                    SettingsLinkButton("Themes", systemImage: SettingsPane.appearance.systemImage) { navigate(.appearance) }
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 4)
        }
    }

    /// The drawing for `choice`: the current settings with the choice's on
    /// top, without media (it's about the arrangement, and small).
    static func config(for choice: PresetChoice, settings: SettingsStore) -> LayoutSchematicConfig {
        var config = LayoutSchematicConfig(choice: choice, settings: settings)
        config.showMedia = false
        return config
    }
}

// MARK: - Sections

/// An axis's title, "Customized" when its settings match no choice, its
/// picker, and under it what was customized, with a link to where.
private struct PresetAxisSection<Picker: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorSchemeContrast) private var contrast
    let axis: PresetAxis
    let settings: SettingsStore
    let navigate: (SettingsPane) -> Void
    @ViewBuilder let picker: (PresetChoice?) -> Picker

    var body: some View {
        let current = settings.currentChoice(for: axis)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(axis.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme[ThemeKey.settingsForeground])
                if current == nil {
                    SettingsPill(text: "Customized", prominent: contrast == .increased, tinted: contrast != .increased)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            // "Window layout, customized": no choice is selected, and why.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(current == nil ? "\(axis.title), customized" : axis.title)
            .accessibilityAddTraits(.isHeader)

            picker(current)

            if current == nil {
                let pane = PresetCustomization.pane(for: axis)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(PresetCustomization.note(for: axis, settings: settings))
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    SettingsLinkButton("Fine-tune in \(pane.title)") { navigate(pane) }
                        .fixedSize()
                        .help("Open Settings → \(pane.title)")
                }
                .padding(.horizontal, 4)
            }
        }
    }
}

/// What "Customized" means for an axis, in words.
@MainActor
enum PresetCustomization {
    /// The pane where an axis's settings can be changed one by one.
    static func pane(for axis: PresetAxis) -> SettingsPane {
        switch axis {
        case .windowLayout: .layout
        case .messageStyle, .density: .messages
        }
    }

    /// "Customized: tabs at the bottom of the window. …"
    static func note(for axis: PresetAxis, settings: SettingsStore) -> String {
        switch axis {
        case .windowLayout:
            let what = settings[.navigationStyle] == .tabs && settings[.tabsPlacement] == .bottom
                ? "tabs at the bottom of the window"
                : "a layout of your own"
            return "Customized: \(what). Pick a layout to switch to it."
        case .messageStyle:
            let layout: String = switch settings[.chatLayout] {
            case .grouped: "the Modern layout"
            case .classic: "the Classic IRC layout"
            case .columns: "the Columns layout"
            }
            let font = settings[.chatMonospace] ? "in a monospaced font" : "without the monospaced font"
            return "Customized: \(layout) \(font). Picking a style sets both the layout and the font."
        case .density:
            let line = SettingsFormat.points(settings[.chatLineSpacing])
            let message = SettingsFormat.points(settings[.chatMessageSpacing])
            return "Customized: \(line) between lines and \(message) between messages. Picking a density sets both."
        }
    }
}

// MARK: - Picker

/// How an item is drawn.
struct PresetItemState: Equatable {
    var isSelected: Bool
    /// The keyboard is on it (the row has the focus).
    var isHighlighted: Bool
}

/// The keys of a row of choices: ← and → (↑ and ↓ too) move to the one
/// beside, stopping at the ends, Home and End to the first and last.
enum PresetKeyboard {
    enum Move: Equatable {
        case previous, next, first, last
    }

    /// The index `move` goes to from `index` among `count` choices; from
    /// none, forward moves start at the first and backward ones at the last.
    static func target(_ move: Move, from index: Int?, count: Int) -> Int? {
        guard count > 0 else { return nil }
        switch move {
        case .previous: return index.map { max(0, $0 - 1) } ?? count - 1
        case .next: return index.map { min(count - 1, $0 + 1) } ?? 0
        case .first: return 0
        case .last: return count - 1
        }
    }

    static func move(for key: KeyEquivalent) -> Move? {
        switch key {
        case .leftArrow, .upArrow: .previous
        case .rightArrow, .downArrow: .next
        case .home: .first
        case .end: .last
        default: nil
        }
    }
}

/// One row of choices: one stop for Tab, ← and → move the keyboard between
/// them (drawn with a ring), and Space or Return picks. Clicking picks at
/// once. VoiceOver reads each choice as a button, selected or not, and says
/// what was picked.
///
/// Picking writes the settings without an animation: the main window then
/// lays itself out once, not on every frame of a transition.
private struct PresetChoicePicker<Item: View, Arrangement: Layout>: View {
    let axis: PresetAxis
    let current: PresetChoice?
    let arrangement: Arrangement
    let choose: (PresetChoice) -> Void
    @ViewBuilder let item: (PresetChoice, PresetItemState) -> Item

    @FocusState private var isFocused: Bool
    @State private var highlighted: Int?

    var body: some View {
        let choices = axis.choices
        arrangement {
            ForEach(Array(choices.enumerated()), id: \.element.id) { index, choice in
                let isSelected = choice == current
                Button {
                    pick(choice)
                    // A click leaves no ring behind.
                    isFocused = false
                } label: {
                    item(choice, PresetItemState(isSelected: isSelected, isHighlighted: isFocused && highlighted == index))
                }
                .buttonStyle(PresetPressStyle())
                .focusable(false)
                .help(choice.summary)
                .accessibilityLabel(choice.name)
                .accessibilityHint(choice.summary)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .home, .end, .space, .return]) { press in
            handle(press.key, in: choices)
        }
        .onChange(of: isFocused) { _, focused in
            if focused { highlighted = choices.firstIndex { $0 == current } ?? 0 }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(axis.title)
    }

    private func handle(_ key: KeyEquivalent, in choices: [PresetChoice]) -> KeyPress.Result {
        if key == .space || key == .return {
            guard let highlighted, choices.indices.contains(highlighted) else { return .ignored }
            pick(choices[highlighted])
            return .handled
        }
        guard let move = PresetKeyboard.move(for: key),
              let target = PresetKeyboard.target(move, from: highlighted, count: choices.count)
        else { return .ignored }
        highlighted = target
        let choice = choices[target]
        KeyboardAnnouncement.post("\(choice.name)\(choice == current ? ", selected" : ""), \(target + 1) of \(choices.count)")
        return .handled
    }

    private func pick(_ choice: PresetChoice) {
        if choice != current { choose(choice) }
        KeyboardAnnouncement.post("\(axis.title): \(choice.name)")
    }
}

/// A pressed card or segment dips slightly, unless Reduce Motion is on.
private struct PresetPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// Equal-width columns: all the items in one row when they fit at
/// `minimumItemWidth`, else half as many per row, else one. Every item in
/// a row gets the row's height, so cards line up.
struct PresetCardGrid: Layout {
    var minimumItemWidth: CGFloat
    var spacing: CGFloat

    /// How many columns `count` items get in `width`.
    func columns(forWidth width: CGFloat, count: Int) -> Int {
        guard count > 1 else { return max(count, 1) }
        for candidate in [count, (count + 1) / 2] {
            let needed = CGFloat(candidate) * minimumItemWidth + CGFloat(candidate - 1) * spacing
            if needed <= width { return candidate }
        }
        return 1
    }

    private struct Measured {
        var columns: Int
        var itemWidth: CGFloat
        var rowHeights: [CGFloat]
    }

    private func measure(width: CGFloat, subviews: Subviews) -> Measured {
        let columns = columns(forWidth: width, count: subviews.count)
        let itemWidth = max(0, (width - CGFloat(columns - 1) * spacing) / CGFloat(columns))
        var rowHeights: [CGFloat] = []
        for (index, subview) in subviews.enumerated() {
            let height = subview.sizeThatFits(ProposedViewSize(width: itemWidth, height: nil)).height
            if index % columns == 0 {
                rowHeights.append(height)
            } else {
                rowHeights[rowHeights.count - 1] = max(rowHeights[rowHeights.count - 1], height)
            }
        }
        return Measured(columns: columns, itemWidth: itemWidth, rowHeights: rowHeights)
    }

    private func width(for proposal: ProposedViewSize, count: Int) -> CGFloat {
        if let width = proposal.width, width.isFinite { return width }
        return CGFloat(count) * minimumItemWidth + CGFloat(max(0, count - 1)) * spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = width(for: proposal, count: subviews.count)
        let measured = measure(width: width, subviews: subviews)
        let height = measured.rowHeights.reduce(0, +) + spacing * CGFloat(max(0, measured.rowHeights.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let measured = measure(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for (row, height) in measured.rowHeights.enumerated() {
            for column in 0..<measured.columns {
                let index = row * measured.columns + column
                guard subviews.indices.contains(index) else { break }
                let x = bounds.minX + CGFloat(column) * (measured.itemWidth + spacing)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: measured.itemWidth, height: height)
                )
            }
            y += height + spacing
        }
    }
}

// MARK: - Cards

/// A picture card: the drawing, the name with a selection mark, and a line
/// about it. Selected: an accent border and tint. The keyboard's ring is
/// drawn outside it in the theme's focus color.
private struct PresetChoiceCard<Picture: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let choice: PresetChoice
    let state: PresetItemState
    @ViewBuilder let picture: () -> Picture

    @State private var isHovered = false

    private static var radius: CGFloat { 10 }

    var body: some View {
        let highContrast = contrast == .increased
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        VStack(alignment: .leading, spacing: 7) {
            picture()
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(theme[highContrast ? ThemeKey.settingsSecondaryForeground : ThemeKey.settingsBorder].opacity(highContrast ? 0.7 : 1))
                )
                .overlay(alignment: .topTrailing) {
                    if state.isSelected {
                        SelectedBadge()
                            .offset(x: 5, y: -5)
                            .transition(reduceMotion ? .identity : .scale(scale: 0.6).combined(with: .opacity))
                    }
                }
            Text(choice.name)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(theme[state.isSelected ? ThemeKey.accentText : ThemeKey.settingsForeground])
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(choice.summary)
                .font(.system(size: 11))
                .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            ZStack {
                shape.fill(theme[ThemeKey.settingsControlBackground])
                shape.fill(fillTint)
            }
        }
        .overlay(shape.strokeBorder(borderColor(highContrast: highContrast), lineWidth: borderWidth(highContrast: highContrast)))
        .overlay {
            if state.isHighlighted {
                RoundedRectangle(cornerRadius: Self.radius + 3, style: .continuous)
                    .strokeBorder(theme[ThemeKey.focusBorder], lineWidth: 2.5)
                    .padding(-4)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(shape)
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: state)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
        .devTag(
            "Preset card",
            tokens: [ThemeKey.settingsControlBackground, state.isSelected ? ThemeKey.accent : ThemeKey.settingsBorder, ThemeKey.settingsForeground, ThemeKey.settingsSecondaryForeground],
            font: .system(size: 12.5, weight: .semibold),
            padding: EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        )
    }

    private var fillTint: Color {
        if state.isSelected { return theme[ThemeKey.accent].opacity(0.08) }
        if isHovered { return theme[ThemeKey.settingsForeground].opacity(0.03) }
        return .clear
    }

    private func borderColor(highContrast: Bool) -> Color {
        if state.isSelected { return theme[ThemeKey.accent] }
        if isHovered { return theme[ThemeKey.settingsSecondaryForeground].opacity(highContrast ? 1 : 0.55) }
        return highContrast ? theme[ThemeKey.settingsSecondaryForeground].opacity(0.8) : theme[ThemeKey.settingsBorder]
    }

    private func borderWidth(highContrast: Bool) -> CGFloat {
        if state.isSelected { return highContrast ? 3 : 2 }
        return highContrast ? 1.5 : 1
    }
}

/// The check on a selected card's picture: an accent disc, ringed in the
/// card's color so it stands off the drawing.
private struct SelectedBadge: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(theme[ThemeKey.accentForeground])
            .frame(width: 18, height: 18)
            .background(Circle().fill(theme[ThemeKey.accent]))
            .padding(2)
            .background(Circle().fill(theme[ThemeKey.settingsControlBackground]))
            .accessibilityHidden(true)
    }
}

// MARK: - Density

/// Compact, Standard and Comfortable as one segmented control in the
/// theme's colors, each with a little drawing of its spacing. With spacing
/// of your own, no segment is selected.
private struct DensityControl: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorSchemeContrast) private var contrast
    let current: PresetChoice?
    let choose: (PresetChoice) -> Void

    var body: some View {
        let highContrast = contrast == .increased
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        PresetChoicePicker(axis: .density, current: current, arrangement: HStackLayout(spacing: 3), choose: choose) { choice, state in
            DensitySegment(choice: choice, state: state)
        }
        .padding(3)
        .background(shape.fill(theme[ThemeKey.settingsControlBackground]))
        .overlay(shape.strokeBorder(theme[highContrast ? ThemeKey.settingsSecondaryForeground : ThemeKey.settingsBorder], lineWidth: highContrast ? 1.5 : 1))
        .devTag("Density control", tokens: [ThemeKey.settingsControlBackground, ThemeKey.settingsBorder, ThemeKey.accent])
    }
}

private struct DensitySegment: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let choice: PresetChoice
    let state: PresetItemState

    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6.5, style: .continuous)
        let foreground = state.isSelected ? theme[ThemeKey.accentForeground] : theme[ThemeKey.settingsForeground]
        HStack(spacing: 8) {
            DensityGlyph(gap: Self.glyphGap(for: choice), color: foreground)
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
            Text(choice.name)
                .font(.system(size: 12, weight: state.isSelected ? .semibold : .medium))
                .foregroundStyle(foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .padding(.horizontal, 6)
        .background(shape.fill(background))
        .overlay {
            if state.isHighlighted {
                shape.strokeBorder(theme[ThemeKey.focusBorder], lineWidth: 2)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(shape)
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: state)
    }

    private var background: Color {
        if state.isSelected { return theme[ThemeKey.accent] }
        if isHovered { return theme[ThemeKey.settingsForeground].opacity(0.06) }
        return .clear
    }

    /// The drawing's gap between lines, from the choice's message spacing:
    /// about 1, 3 and 5 points.
    static func glyphGap(for choice: PresetChoice) -> CGFloat {
        guard case .number(let spacing) = choice.values[SettingKey<Double>.chatMessageSpacing.key] else { return 3 }
        return min(5.5, 0.75 + spacing / 4)
    }
}

/// Three lines of "text" `gap` points apart, centered.
private struct DensityGlyph: View {
    let gap: CGFloat
    let color: Color

    var body: some View {
        Canvas { context, size in
            let thickness: CGFloat = 1.5
            let widths: [CGFloat] = [1, 0.62, 0.84]
            let total = thickness * 3 + gap * 2
            var y = (size.height - total) / 2
            for width in widths {
                let rect = CGRect(x: 0, y: y, width: size.width * width, height: thickness)
                context.fill(Path(roundedRect: rect, cornerRadius: thickness / 2), with: .color(color))
                y += thickness + gap
            }
        }
    }
}
