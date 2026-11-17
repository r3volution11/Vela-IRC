// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppIntents
import Foundation
import VelaCore

/// An error Siri and Shortcuts show as is.
struct IntentFailure: Error, CustomLocalizedStringResourceConvertible {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    init(_ error: AppActionError) {
        self.message = error.errorDescription ?? "Vela couldn't do that."
    }

    var localizedStringResource: LocalizedStringResource { "\(message)" }

    /// `error` in words Siri can say, if it's one of Vela's own.
    static func wrapping(_ error: any Error) -> any Error {
        if let error = error as? AppActionError { return IntentFailure(error) }
        return error
    }
}

extension AppModel {
    /// The open buffer behind `entity`, or an error Siri can say.
    func target(for entity: ChannelEntity) throws -> (session: NetworkSession, buffer: BufferModel) {
        guard let id = entity.bufferID, let target = lookup(id), target.buffer.kind != .server else {
            throw IntentFailure(.unknownBuffer)
        }
        return target
    }

    /// The session behind `entity`, or an error Siri can say.
    func session(for entity: NetworkEntity) throws -> NetworkSession {
        guard let session = session(for: entity.id) else { throw IntentFailure(.unknownNetwork) }
        return session
    }
}

enum IntentText {
    /// "Libera.Chat", "Libera.Chat and OFTC", "Libera.Chat, OFTC and Ergo".
    nonisolated static func list(_ names: [String]) -> String {
        names.formatted(.list(type: .and))
    }

    /// "1 mention" / "3 mentions".
    nonisolated static func count(_ value: Int, _ singular: String, _ plural: String) -> String {
        "\(value) \(value == 1 ? singular : plural)"
    }
}

extension NetworkSession {
    /// `name` case-folded the way this network compares names.
    func foldName(_ name: String) -> String {
        isupport.caseMapping.fold(name)
    }
}
