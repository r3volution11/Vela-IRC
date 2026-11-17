// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

// Message translation, on this Mac. The chat (VelaUI) asks through
// `TranslationQueue`, which batches lines by language and hands them to a
// `MessageTranslator`: Apple's Translation framework in the app
// (`LiveMessageTranslator`), canned text in demo mode and tests
// (`CannedTranslator`).

/// A source and target language.
nonisolated public struct TranslationPair: Hashable, Sendable, CustomStringConvertible {
    public var source: Locale.Language
    public var target: Locale.Language

    public init(source: Locale.Language, target: Locale.Language) {
        self.source = source
        self.target = target
    }

    public var description: String { "\(source.minimalIdentifier)→\(target.minimalIdentifier)" }
}

/// Whether a language pair can be translated on this Mac.
nonisolated public enum TranslationPairStatus: Equatable, Sendable {
    /// Both languages are on this Mac; translation starts at once.
    case installed
    /// Supported, but macOS has to download a language first (it asks).
    case needsDownload
    case unsupported
}

nonisolated public enum TranslationFailure: Error, Equatable, Sendable, LocalizedError {
    /// The Translation framework can't translate between these languages.
    case unsupportedPair
    /// A language isn't on this Mac and wasn't downloaded (the download was
    /// declined or failed).
    case notDownloaded
    case cancelled
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedPair: "Translation between these languages isn't available."
        case .notDownloaded: "The language isn't downloaded."
        case .cancelled: "Translation was cancelled."
        case .failed(let message): message
        }
    }
}

/// Translates chat text.
public protocol MessageTranslator: AnyObject {
    /// Whether `source` can be translated into `target`, and whether that
    /// needs a download first.
    func status(from source: Locale.Language, to target: Locale.Language) async -> TranslationPairStatus

    /// Translations of `texts`, in the same order. Errors are
    /// ``TranslationFailure``s.
    func translate(_ texts: [String], from source: Locale.Language, to target: Locale.Language) async throws -> [String]

    /// The languages it translates between, for the "Translate into" picker.
    func supportedLanguages() async -> [Locale.Language]
}
