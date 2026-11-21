// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaMedia
import VelaStore
import VelaTheme

/// The message box picker's tabs.
enum ComposerPickerTab: String, CaseIterable {
    case emoji
    case gifs

    var title: String {
        switch self {
        case .emoji: "Emoji"
        case .gifs: "GIFs"
        }
    }

    private static let defaultsKey = "Vela.composerPickerTab"

    /// The tab used last: the picker opens on it. Usage, not a preference,
    /// so it's in UserDefaults like the recent emoji.
    static var remembered: ComposerPickerTab {
        get { UserDefaults.standard.string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? .emoji }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }
}

/// The message box's emoji and GIF picker, in a popover from the smiley
/// button (⇧⌘E): Emoji and GIFs tabs over one search field, which has the
/// focus. ↑↓←→ move through the grid, Return picks, Tab or ⌃Tab switches
/// tabs, Esc closes.
///
/// Nothing about GIFs is made until the GIFs tab is shown: opening on the
/// Emoji tab sends nothing anywhere. With `gifs.enabled` off there's no
/// GIFs tab at all.
struct ComposerPickerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.gifSearchServices) private var injectedServices
    @Environment(\.openURL) private var openURL
    /// Inserts an emoji at the caret.
    let onEmoji: (String) -> Void
    /// Puts a GIF in the message box.
    let onGIF: (GIFSearchResult, any GIFSearchProvider) -> Void
    /// Esc: closes, and the message box gets the focus back.
    let onClose: () -> Void
    /// Opens Settings → Media at GIFs (after closing).
    let onOpenSettings: () -> Void

    @State private var tab = ComposerPickerTab.remembered
    @State private var query = ""
    @State private var emojiSelection: EmojiGridItem?
    @State private var hovered: EmojiGridItem?
    @State private var frequent = EmojiRecents.frequent()
    @State private var gifs: GIFPickerModel?

    static let emojiColumns = 9
    static let emojiCell: CGFloat = 36
    static let width: CGFloat = CGFloat(emojiColumns) * emojiCell + CGFloat(emojiColumns - 1) * 2 + 24
    /// The grid area under the search field, the same on both tabs.
    static let gridHeight: CGFloat = 292

    private var services: GIFSearchServices { injectedServices ?? .shared }
    /// Only in development builds for now (`GIFAvailability`), and only when turned on.
    private var gifsEnabled: Bool { GIFAvailability.isOn(in: app.settings) }
    /// The tab on screen: Emoji whenever GIFs are off.
    var shownTab: ComposerPickerTab { gifsEnabled ? tab : .emoji }

    var body: some View {
        // Only the Emoji tab needs the emoji.
        let emoji = shownTab == .emoji ? EmojiGridContent(query: query, frequent: frequent, columns: Self.emojiColumns) : nil
        VStack(spacing: 0) {
            if gifsEnabled {
                tabBar
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
            }
            PickerSearchBox(
                text: $query,
                placeholder: placeholder,
                accessibilityLabel: shownTab == .gifs ? placeholder : "Search emoji",
                onTextChange: textChanged
            ) { key in
                handle(key, emoji: emoji)
            }
            .padding(.horizontal, 12)
            .padding(.top, gifsEnabled ? 8 : 12)
            .padding(.bottom, 8)
            if let emoji {
                // The category bar (28 pt) and its line are part of the grid area.
                EmojiGridView(content: emoji, selection: $emojiSelection, hovered: $hovered, cellSize: Self.emojiCell, height: Self.gridHeight - 29) {
                    pickEmoji($0)
                }
                Rectangle().fill(theme[ThemeKey.popoverBorder]).frame(height: 1)
                EmojiFooter(emoji: (hovered ?? emojiSelection)?.emoji, prompt: "Pick an emoji") {
                    NSApp.orderFrontCharacterPalette(nil)
                }
            } else {
                Rectangle().fill(theme[ThemeKey.popoverBorder]).frame(height: 1)
                gifContent
                    .frame(width: Self.width, height: Self.gridHeight - 1)
                Rectangle().fill(theme[ThemeKey.popoverBorder]).frame(height: 1)
                if let gifs {
                    GIFAttributionBar(provider: gifs.provider) {
                        openURL(gifs.provider.websiteURL(for: GIFPickerModel.query(for: query)))
                    }
                }
            }
        }
        .frame(width: Self.width)
        .background(theme[ThemeKey.popoverBackground])
        .onAppear { if shownTab == .gifs { showGIFs() } }
        .onDisappear(perform: closeGIFs)
        .onChange(of: shownTab) { _, newTab in
            if newTab == .gifs { showGIFs() } else { gifs?.stop() }
        }
        // Another service or rating: start over with it.
        .onChange(of: app.settings[.gifsProvider]) { _, _ in restartGIFs() }
        .onChange(of: app.settings[.gifsRating]) { _, _ in restartGIFs() }
    }

    private var placeholder: String {
        shownTab == .gifs ? (gifs?.provider.searchPlaceholder ?? "Search GIFs") : "Search emoji"
    }

    // MARK: Tabs

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(ComposerPickerTab.allCases, id: \.self) { item in
                let selected = shownTab == item
                Button {
                    select(item)
                } label: {
                    Text(item.title)
                        .font(.system(size: 12, weight: selected ? .semibold : .medium))
                        .foregroundStyle(theme[selected ? ThemeKey.popoverForeground : ThemeKey.chatSecondaryForeground])
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(selected ? theme[ThemeKey.chatSelectionBackground] : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(item.title) (Tab switches)")
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                .accessibilityLabel("\(item.title) tab")
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme[ThemeKey.inputBackground])
        )
    }

    private func select(_ newTab: ComposerPickerTab) {
        guard gifsEnabled || newTab == .emoji, tab != newTab else { return }
        tab = newTab
        ComposerPickerTab.remembered = newTab
    }

    // MARK: Keys

    private func handle(_ key: PaletteKey, emoji: EmojiGridContent?) -> Bool {
        switch key {
        case .tab:
            if gifsEnabled { select(shownTab == .emoji ? .gifs : .emoji) }
            return true
        case .cancel:
            onClose()
            return true
        default:
            break
        }
        if let emoji {
            if let move = GridMove(key) {
                emojiSelection = emoji.moved(from: emojiSelection, move)
                return true
            }
            if key == .submit {
                if let pick = emojiSelection?.emoji ?? (emoji.isSearching ? emoji.first?.emoji : nil) { pickEmoji(pick) }
                return true
            }
        } else {
            guard let gifs else { return key == .submit }
            if let move = GridMove(key) {
                gifs.move(move, columns: GIFGridView.columns)
                return true
            }
            if key == .submit {
                if gifs.submit(text: query) { return true }
                if let result = gifs.selectedResult {
                    pick(result, gifs.provider)
                } else if !gifs.results.isEmpty {
                    gifs.selection = 0
                }
                return true
            }
        }
        return false
    }

    private func textChanged(_ text: String) {
        emojiSelection = nil
        if shownTab == .gifs {
            gifs?.textChanged(text)
        } else if let emoji = EmojiCatalog.characterViewerPick(in: text) {
            // The Character Viewer put its pick in the search field.
            pickEmoji(emoji)
        }
    }

    private func pickEmoji(_ emoji: String) {
        EmojiRecents.record(emoji)
        onEmoji(emoji)
    }

    private func pick(_ result: GIFSearchResult, _ provider: any GIFSearchProvider) {
        onGIF(result, provider)
    }

    // MARK: GIFs

    @ViewBuilder
    private var gifContent: some View {
        if let gifs {
            switch gifs.status {
            case .unavailable(let problem):
                GIFMessageView(message: GIFMessage(problem: problem), onSettings: onOpenSettings)
            case .failed(let error):
                GIFMessageView(
                    message: GIFMessage(error: error, setup: gifs.setup),
                    retryAvailableAt: gifs.retryAvailableAt,
                    onRetry: { gifs.retry() },
                    onSettings: onOpenSettings
                )
            case .empty:
                GIFMessageView(message: GIFMessage(
                    systemImage: "magnifyingglass",
                    title: "No GIFs for “\(gifs.shownQuery.text ?? query)”",
                    message: "Try other words."
                ))
            case .loading where gifs.results.isEmpty:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading GIFs")
            case .loading, .results:
                GIFGridView(
                    model: gifs,
                    services: services,
                    animates: app.settings[.gifsAnimatePreviews],
                    width: Self.width,
                    height: Self.gridHeight
                ) { result in
                    pick(result, gifs.provider)
                }
            }
        }
    }

    /// The GIFs tab is on screen: its model is made now, the first time.
    private func showGIFs() {
        if gifs == nil {
            let model = GIFPickerModel(
                setup: services.setup(for: app.settings[.gifsProvider]),
                rating: app.settings[.gifsRating],
                services: services
            )
            services.modelStarted(model)
            gifs = model
        }
        gifs?.show(text: query)
    }

    private func restartGIFs() {
        guard let gifs else { return }
        gifs.stop()
        self.gifs = nil
        if shownTab == .gifs { showGIFs() }
    }

    private func closeGIFs() {
        guard gifs != nil else { return }
        services.pickerClosed()
    }
}

/// Under the GIFs: "Powered by KLIPY" (as KLIPY's and GIPHY's terms ask)
/// and "View on KLIPY", which opens the search (or what's trending) on the
/// service's site.
struct GIFAttributionBar: View {
    @Environment(\.theme) private var theme
    let provider: any GIFSearchProvider
    let onViewOnSite: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text(provider.attribution)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme[ThemeKey.chatSecondaryForeground])
                .accessibilityAddTraits(.isStaticText)
            Spacer(minLength: 8)
            Button(action: onViewOnSite) {
                HStack(spacing: 3) {
                    Text(provider.viewOnSiteTitle)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .bold))
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(theme[ThemeKey.accentText])
                .underline(hovering)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .onHover { hovering = $0 }
            .help("Open this search on \(provider.displayName) in your browser")
            .accessibilityAddTraits(.isLink)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
    }
}

/// The smiley at the end of the message box: opens the picker (as ⇧⌘E does).
/// Like the send button beside it, it's the accent color while the message
/// box is active (`isActive`: typing, or the picker open) and muted otherwise.
struct ComposerPickerButton: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app
    @Binding var isPresented: Bool
    let isActive: Bool

    var body: some View {
        let labels = Self.labels(showsGIFs: GIFAvailability.isOn(in: app.settings))
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: SolidSmiley.name)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(theme[isActive ? ThemeKey.accent : ThemeKey.inputIconForeground])
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(labels.help)
        .accessibilityLabel(labels.label)
        .accessibilityHint(labels.hint)
    }

    /// The tooltip, and VoiceOver's label and hint. GIFs are mentioned only
    /// while the picker has them (``GIFAvailability/isOn(in:)``), so never
    /// in a release for now.
    static func labels(showsGIFs: Bool) -> (help: String, label: String, hint: String) {
        showsGIFs
            ? ("Emoji & GIFs (⇧⌘E)", "Emoji and GIFs", "Opens the emoji and GIF picker")
            : ("Emoji (⇧⌘E)", "Emoji", "Opens the emoji picker")
    }
}

/// The solid smiley: a filled face with its eyes and smile cut out. Which
/// symbol draws that has changed between macOS versions: on macOS 27,
/// `face.smiling` is solid and `face.smiling.fill` (now another name for
/// `face.smiling.inverse`) is the outline. So the first time it's needed,
/// it draws each once, small, and takes the one that's filled in.
enum SolidSmiley {
    static let name: String = candidates.first { isSolid($0) } ?? candidates[0]

    static let candidates = ["face.smiling", "face.smiling.inverse"]

    /// Whether `symbol` is filled in at a cheek: inside the face, clear of
    /// the eyes and the smile, where an outline face is empty.
    static func isSolid(_ symbol: String) -> Bool {
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 32, weight: .regular)),
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 48, pixelsHigh: 48, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ),
            let context = NSGraphicsContext(bitmapImageRep: rep)
        else { return false }
        let size = image.size
        let scale = min(48 / size.width, 48 / size.height)
        let drawn = NSSize(width: size.width * scale, height: size.height * scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: (48 - drawn.width) / 2, y: (48 - drawn.height) / 2, width: drawn.width, height: drawn.height))
        NSGraphicsContext.restoreGraphicsState()
        return (rep.colorAt(x: 11, y: 24)?.alphaComponent ?? 0) > 0.5
    }
}
