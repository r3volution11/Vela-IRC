// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaIntelligence
import VelaStore
import VelaTheme

/// A provider waiting for your OK before Vela sends it messages, and what
/// to do once you give it (summarize again).
struct AIConsentRequest: Identifiable {
    let id = UUID()
    let providerID: String
    let onAllow: @MainActor () -> Void
}

/// What the consent sheet says, exactly: what's sent, what never is, where
/// it goes and under whose policy, and who pays. Pure, so it's tested.
enum AIConsentText {
    static func title(_ entry: AIProviderEntry) -> String {
        "Send messages to \(entry.name)?"
    }

    static func intro(_ entry: AIProviderEntry) -> String {
        "To catch you up or write a Recap with \(entry.name), Vela sends it:"
    }

    static let sent = "The text and nicks of the messages you ask about, and your own nick."
    static let neverSent = "Never the names of channels, networks or servers, or your account."

    /// Where it goes, and whose rules apply.
    static func destination(_ entry: AIProviderEntry) -> String {
        guard entry.kind == .openAICompatible else {
            var text = "\(entry.name) handles them under its data policy, and the usage is billed to your API key."
            if entry.kind == .gemini {
                text += " On Gemini's free tier, Google may use what's sent to improve its products."
            }
            return text
        }
        let address = entry.apiBaseURL.map(hostAndPort) ?? "the address you entered"
        switch entry.serverLocation {
        case .thisMac: return "They go to the server at \(address), on this Mac."
        case .localNetwork: return "They go to the server at \(address), on your network. Its owner's rules apply."
        case .internet: return "They go to the server at \(address), over the internet. Its owner's rules apply."
        }
    }

    static func footer(_ entry: AIProviderEntry) -> String {
        "Vela asks once for \(entry.name). You can take it back in Settings → Intelligence."
    }

    static func hostAndPort(_ url: URL) -> String {
        guard let host = url.host() else { return url.absoluteString }
        return url.port.map { "\(host):\($0)" } ?? host
    }
}

/// The sheet shown the first time a provider would be sent messages:
/// exactly what goes, what never does, where to, under whose policy, and
/// that the usage is billed to your key. Allow remembers it for the
/// provider (`consent` in its `intelligence.providers` entry) and runs
/// the summary; Cancel sends nothing.
struct AIConsentSheet: View {
    @Environment(IntelligenceServices.self) private var intelligence
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let request: AIConsentRequest

    var body: some View {
        let models = intelligence.models
        Group {
            if let entry = models.providers.first(where: { $0.id == request.providerID }) {
                content(entry)
            } else {
                // Removed meanwhile.
                Color.clear.frame(width: 1, height: 1).onAppear { dismiss() }
            }
        }
        .background(theme[ThemeKey.popoverBackground])
    }

    private func content(_ entry: AIProviderEntry) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: entry.kind == .openAICompatible ? "server.rack" : "sparkles")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(theme[ThemeKey.accentText])
                    .accessibilityHidden(true)
                Text(AIConsentText.title(entry))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme[ThemeKey.popoverForeground])
                    .accessibilityAddTraits(.isHeader)
            }
            Text(AIConsentText.intro(entry))
                .font(.system(size: 13))
                .foregroundStyle(theme[ThemeKey.popoverForeground])
            VStack(alignment: .leading, spacing: 8) {
                bullet(AIConsentText.sent, systemImage: "text.bubble")
                bullet(AIConsentText.neverSent, systemImage: "eye.slash")
            }
            Text(AIConsentText.destination(entry))
                .font(.system(size: 12.5))
                .foregroundStyle(theme[ThemeKey.popoverForeground])
                .fixedSize(horizontal: false, vertical: true)
            if let policy = entry.kind.dataPolicyURL {
                SettingsLinkButton("\(entry.kind.displayName)'s data policy", systemImage: "arrow.up.right.square") {
                    NSWorkspace.shared.open(policy)
                }
                .accessibilityHint("Opens it in your browser")
            }
            Text(AIConsentText.footer(entry))
                .font(.system(size: 11.5))
                .foregroundStyle(theme[ThemeKey.popoverForeground].opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(ThemedButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Allow and Continue") {
                    intelligence.models.grantConsent(entry.id)
                    dismiss()
                    request.onAllow()
                }
                .buttonStyle(ThemedButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
        .accessibilityElement(children: .contain)
    }

    private func bullet(_ text: String, systemImage: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12))
                .foregroundStyle(theme[ThemeKey.accentText])
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(theme[ThemeKey.popoverForeground])
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
