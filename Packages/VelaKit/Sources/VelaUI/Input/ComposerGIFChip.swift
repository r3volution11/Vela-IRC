// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaMedia
import VelaTheme

/// A GIF picked for the message: shown as a chip in the message box, sent
/// as its link with whatever you type (`url` after the text). On IRC a GIF
/// is just its link; clients that show inline media load it from the
/// service.
struct ComposerGIF: Equatable, Identifiable {
    let id: String
    /// What's sent: the service's GIF, exactly as it gave it.
    let url: URL
    let title: String
    /// "KLIPY".
    let serviceName: String
    /// The chip's thumbnail.
    let stillURL: URL?
    let placeholder: Data?

    init(result: GIFSearchResult, provider: any GIFSearchProvider) {
        id = result.id
        url = result.shareURL
        title = result.title
        serviceName = provider.displayName
        stillURL = result.still(forPixelWidth: 96)?.url
        placeholder = result.placeholder
    }

    /// The message that's sent: the text, then the link.
    static func message(text: String, gif: ComposerGIF?) -> String {
        guard let gif else { return text }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return gif.url.absoluteString }
        // Trailing spaces and newlines don't push the link onto a line of its own.
        var body = text
        while let last = body.last, last.isWhitespace { body.removeLast() }
        return body + " " + gif.url.absoluteString
    }
}

/// The GIF chip at the top of the message box, like an attachment: a
/// thumbnail, "GIF" and its title, and × to take it out (so does Delete at
/// the start of the message).
struct ComposerGIFChip: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    @Environment(\.displayScale) private var displayScale
    @Environment(\.gifSearchServices) private var injectedServices
    let gif: ComposerGIF
    let onRemove: () -> Void

    @State private var thumbnail: CGImage?

    private static let thumbnailSize = CGSize(width: 48, height: 36)

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Rectangle().fill(theme[ThemeKey.chatHoverBackground])
                if let thumbnail {
                    Image(decorative: thumbnail, scale: displayScale).resizable().scaledToFill()
                } else if let placeholder = gif.placeholder.flatMap(NSImage.init(data:)) {
                    Image(nsImage: placeholder).resizable().scaledToFill()
                }
            }
            .frame(width: Self.thumbnailSize.width, height: Self.thumbnailSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                Text("GIF")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 3).fill(.black.opacity(0.6)))
                    .padding(3)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(gif.title.isEmpty ? "GIF" : gif.title)
                    .font(style.font(size: max(10, style.fontSize - 1), weight: .semibold))
                    .foregroundStyle(theme[ThemeKey.inputForeground])
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("Sent as a link · via \(gif.serviceName)")
                    .font(style.font(size: max(9, style.fontSize - 2)))
                    .foregroundStyle(theme[ThemeKey.inputPlaceholder])
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(theme[ThemeKey.inputIconForeground])
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Remove the GIF")
            .accessibilityLabel("Remove the GIF")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .help(gif.url.absoluteString)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("GIF: \(gif.title.isEmpty ? "untitled" : gif.title), via \(gif.serviceName). Sent with your message.")
        .accessibilityAction(named: "Remove the GIF", onRemove)
        .task(id: gif.id) {
            guard let url = gif.stillURL else { return }
            let loader = (injectedServices ?? .shared).previewLoader
            let pixels = Int(Self.thumbnailSize.width * max(1, displayScale))
            thumbnail = try? await loader.downsampledImage(url, maxPixelSize: pixels, maxBytes: GIFSearchServices.maxPreviewBytes)
        }
    }
}

/// The send button at the end of the message box: what Return does.
struct ComposerSendButton: View {
    @Environment(\.theme) private var theme
    let canSend: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up.circle.fill")
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(canSend ? theme[ThemeKey.accent] : theme[ThemeKey.inputIconForeground].opacity(0.45))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .help("Send (Return)")
        .accessibilityLabel("Send message")
    }
}
