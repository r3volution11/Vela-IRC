// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaMedia
import VelaStore
import VelaTheme

/// Settings → Media → GIFs: GIF search on or off, the service and your own
/// key for it (kept in the Keychain), the content rating, and whether
/// previews play.
struct GIFSettingsSection: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.gifSearchServices) private var injectedServices

    /// Where a key is entered (never shown back).
    @State private var keyDraft = ""
    /// Whether a key of your own is saved, per service (read when shown).
    @State private var savedKeys: [GIFService: Bool] = [:]
    @State private var keyError: String?

    static let klipyKeyURL = URL(string: "https://partner.klipy.com")!
    static let giphyKeyURL = URL(string: "https://developers.giphy.com/dashboard/")!

    private var services: GIFSearchServices { injectedServices ?? .shared }

    var body: some View {
        @Bindable var settings = app.settings
        let service = settings[.gifsProvider]

        SettingsSection(
            "GIFs",
            footer: "GIF search sends what you type, and your IP address, to \(service == .klipy ? "KLIPY" : "GIPHY"). Previews load from them too. Nothing is sent until you open the GIFs tab, and nothing at all while this is off."
        ) {
            SettingsToggle(
                "Search GIFs",
                detail: "A GIFs tab next to Emoji in the message box's picker (⇧⌘E). A GIF is sent as its link.",
                isOn: $settings[.gifsEnabled]
            )
            if settings[.gifsEnabled] {
                SettingsSegmentedRow(
                    title: "Service",
                    detail: service == .klipy
                        ? "KLIPY works with the key built into Vela, or your own."
                        : "GIPHY needs your own key.",
                    selection: $settings[.gifsProvider],
                    options: [(.klipy, "KLIPY"), (.giphy, "GIPHY")]
                )
                keyRow(for: service)
                if service == .giphy {
                    trackingNote
                }
                SettingsMenuRow(
                    title: "Content rating",
                    detail: "The most explicit GIFs search shows.",
                    selection: $settings[.gifsRating],
                    options: [(.g, "G: everyone"), (.pg, "PG"), (.pg13, "PG-13"), (.r, "R: adults")]
                )
                SettingsToggle(
                    "Play previews",
                    detail: "GIFs in the picker play while they're in view. Off shows still images.",
                    isOn: $settings[.gifsAnimatePreviews]
                )
            }
        }
        .id("gifs")
        .onAppear(perform: readSavedKeys)
        .onChange(of: service) { _, _ in
            keyDraft = ""
            keyError = nil
        }
    }

    // MARK: Keys

    private func keyRow(for service: GIFService) -> some View {
        let name = service == .klipy ? "KLIPY" : "GIPHY"
        let saved = savedKeys[service] ?? false
        return VStack(alignment: .leading, spacing: 8) {
            SettingsRow(
                "Your own \(name) key",
                detail: saved
                    ? "Saved in your Keychain. GIF search uses it\(service == .klipy ? " instead of Vela's" : "")."
                    : (service == .klipy
                        ? "Optional. With your own free key, your searches don't count against the limit everyone using Vela's key shares."
                        : "Required for GIPHY.")
            ) {
                if saved {
                    Button("Remove") { saveKey(nil, for: service) }
                        .buttonStyle(ThemedButtonStyle())
                        .accessibilityLabel("Remove your \(name) key")
                } else {
                    HStack(spacing: 6) {
                        ThemedTextField("Paste your key", text: $keyDraft, isSecure: true, monospaced: true, accessibilityName: "Your \(name) key") {
                            saveKey(keyDraft, for: service)
                        }
                        .frame(width: 190)
                        Button("Save") { saveKey(keyDraft, for: service) }
                            .buttonStyle(ThemedButtonStyle(prominent: true))
                            .themedDisabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            if let keyError {
                SettingsCallout(.error, "Couldn't save the key", message: keyError)
                    .padding(.horizontal, 14)
            }
            howToGetAKey(service)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private func howToGetAKey(_ service: GIFService) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(service == .klipy
                ? "Get a free KLIPY key: sign in at partner.klipy.com, choose Add Platform, and copy the key it shows."
                : "Get a GIPHY key: create an app (choose API) on GIPHY's developer dashboard, and copy its key.")
                .font(.system(size: 11.5))
                .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            SettingsLinkButton(service == .klipy ? "partner.klipy.com" : "GIPHY Developers", systemImage: "arrow.up.right.square") {
                NSWorkspace.shared.open(service == .klipy ? Self.klipyKeyURL : Self.giphyKeyURL)
            }
            .fixedSize()
        }
    }

    private var trackingNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "eye")
                .font(.system(size: 12))
                .foregroundStyle(theme[ThemeKey.statusWarning])
                .accessibilityHidden(true)
            Text("GIPHY's links include a tracking token, and everyone who sees the GIF in the channel loads it from GIPHY with that token.")
                .font(.system(size: 11.5))
                .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private func readSavedKeys() {
        for service in GIFService.allCases {
            savedKeys[service] = services.keys.key(for: service) != nil
        }
    }

    private func saveKey(_ key: String?, for service: GIFService) {
        do {
            try services.keys.setKey(key, for: service)
            keyError = nil
            keyDraft = ""
            savedKeys[service] = services.keys.key(for: service) != nil
        } catch {
            keyError = String(describing: error)
        }
    }
}
