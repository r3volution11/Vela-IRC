// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Why one of your providers couldn't write a summary, or why Vela didn't
/// ask it to, in words the Catch me up card, a Recap and Siri show as
/// they are. A failure never falls back to another provider: the card
/// offers Try with Apple Intelligence instead, when Apple's model can run.
nonisolated public struct AIProviderFailure: Error, Sendable, Hashable {
    public enum Reason: Sendable, Hashable {
        /// No internet connection.
        case offline
        /// Nothing answered at the address (a custom server that isn't
        /// running, say).
        case unreachable
        case timedOut
        /// The key was turned down (401, 403, or Gemini's invalid key).
        case badKey
        /// The provider needs a key and there's none in the Keychain.
        case missingKey
        /// Out of credit, or over a spending or usage limit.
        case quota
        /// Too many requests, still after waiting as asked.
        case rateLimited
        /// The provider is overloaded or failing (5xx), still after retries.
        case overloaded
        /// It refused, or its safety filters stopped it.
        case declined
        /// The model isn't offered to this account (or doesn't exist).
        case modelNotFound
        /// It answered with no text.
        case emptyResponse
        /// You haven't agreed to send it messages yet: nothing was sent.
        case needsConsent
        /// Turned off in Settings → Intelligence.
        case providerOff
        /// The chosen model's provider isn't set up any more.
        case providerMissing
        /// Anything else, with the provider's own message (trimmed).
        case other(String)
    }

    public var providerID: String
    /// "Anthropic", or a custom server's name.
    public var providerName: String
    public var reason: Reason
    /// The model it was asked for, where it matters (``Reason/modelNotFound``).
    public var modelID: String?

    public init(providerID: String, providerName: String, reason: Reason, modelID: String? = nil) {
        self.providerID = providerID
        self.providerName = providerName
        self.reason = reason
        self.modelID = modelID
    }

    /// One or two sentences for the card, a Recap and Siri.
    public var message: String {
        let name = providerName
        switch reason {
        case .offline:
            return "Couldn't reach \(name). Check your internet connection."
        case .unreachable:
            return "Couldn't connect to \(name). Make sure the server is running and its address is right in Settings → Intelligence."
        case .timedOut:
            return "\(name) took too long to answer."
        case .badKey:
            return "\(name) didn't accept your API key. Check it in Settings → Intelligence."
        case .missingKey:
            return "There's no API key for \(name). Add one in Settings → Intelligence."
        case .quota:
            return "Your \(name) account is out of credit or over its usage limit."
        case .rateLimited:
            return "\(name) is limiting requests right now. Try again in a moment."
        case .overloaded:
            return "\(name) is busy or having problems. Try again in a moment."
        case .declined:
            return "\(name) declined to summarize this conversation."
        case .modelNotFound:
            let model = modelID.map { " \($0)" } ?? ""
            return "\(name) doesn't offer the model\(model) to your account. Choose another in Settings → Intelligence."
        case .emptyResponse:
            return "\(name) didn't return a summary."
        case .needsConsent:
            return "Vela needs your OK before it sends messages to \(name)."
        case .providerOff:
            return "\(name) is turned off in Settings → Intelligence."
        case .providerMissing:
            return "The model chosen for this isn't set up any more. Choose another in Settings → Intelligence."
        case .other(let detail):
            return "\(name) couldn't do it: \(detail)"
        }
    }

    /// Settings → Intelligence can fix it (a key, a server address, a
    /// model, a provider that's off).
    public var isFixedInSettings: Bool {
        switch reason {
        case .badKey, .missingKey, .providerOff, .providerMissing, .modelNotFound, .unreachable: true
        default: false
        }
    }

    /// A provider's message as shown: one line, at most 200 characters.
    static func trimmed(_ message: String) -> String {
        let line = message.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return line.count > 200 ? String(line.prefix(199)) + "…" : line
    }
}

nonisolated extension CatchUpError {
    /// The provider failure, when it's one.
    public var providerFailure: AIProviderFailure? {
        if case .provider(let failure) = self { failure } else { nil }
    }

    /// Waiting for your OK to send messages to a provider.
    public var needsConsent: Bool {
        providerFailure?.reason == .needsConsent
    }
}
