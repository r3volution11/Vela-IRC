// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import SwiftUI
import VelaCore
import VelaTheme

// ┌──────────────────────────────────────────────────────────────────────┐
// │ FUTURE: file uploads from the composer (ROADMAP: "Uploads").         │
// │                                                                      │
// │ Planned providers: IRCv3 FILEHOST (soju advertises an upload URL in  │
// │ ISUPPORT) and a user-configured custom uploader. Nothing implements  │
// │ this yet, so `InputAttachments.provider(for:)` returns nil and the   │
// │ paperclip slot in `InputBar` stays hidden.                           │
// └──────────────────────────────────────────────────────────────────────┘

/// Uploads a file and returns a URL to post in the message.
protocol InputAttachmentProvider {
    /// Shown in the paperclip's tooltip, e.g. "Upload via soju".
    var displayName: String { get }
    /// Largest accepted file, if the service has a limit.
    var maxFileSize: Int? { get }
    func upload(_ fileURL: URL, for buffer: BufferModel, session: NetworkSession) async throws -> URL
}

enum InputAttachments {
    /// The uploader to use for `session`. None exists yet.
    static func provider(for session: NetworkSession) -> (any InputAttachmentProvider)? {
        nil
    }
}

/// The paperclip button at the leading edge of the composer. Hidden until an
/// `InputAttachmentProvider` is available for the session.
struct AttachmentSlot: View {
    @Environment(\.theme) private var theme
    let session: NetworkSession

    var body: some View {
        if let provider = InputAttachments.provider(for: session) {
            Button {
                // FUTURE: present an open panel, then call provider.upload(_:for:session:)
                // and insert the returned URL into the composer.
            } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme[ThemeKey.inputIconForeground])
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .disabled(true)
            .help(provider.displayName)
            .accessibilityLabel("Attach a file")
        }
    }
}
