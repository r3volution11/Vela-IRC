// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaStore

// MARK: - Chat logs

/// Sessions report lines to ``chatLogs``; channels and networks can be
/// left out of the logs (`logging.excludedBuffers`).
extension AppModel {
    public func session(_ session: NetworkSession, didAdd line: ChatLine, to buffer: BufferModel) {
        chatLogs.record(line, in: buffer, session: session)
    }

    public func session(
        _ session: NetworkSession,
        didRedact line: ChatLine,
        by nick: String?,
        reason: String?,
        at time: Date,
        isHistory: Bool,
        in buffer: BufferModel
    ) {
        chatLogs.recordRedaction(of: line, by: nick, reason: reason, at: time, isHistory: isHistory, in: buffer, session: session)
        savedMessagesObserver?.messageRedacted(line.id, time: line.time, in: buffer.id)
    }

    /// Whether `bufferID` is left out of chat logs, by itself or through
    /// its network.
    public func isLogExcluded(_ bufferID: BufferID) -> Bool {
        BufferScopeList(settings[.loggingExcludedBuffers]).contains(bufferID)
    }

    /// Whether every buffer of a network is left out (`"<network>/*"`).
    public func isLogExcluded(network networkID: UUID) -> Bool {
        BufferScopeList(settings[.loggingExcludedBuffers]).containsNetwork(networkID)
    }

    /// Leaves one buffer out of chat logs, or logs it again. A buffer stays
    /// out while its whole network is.
    public func setLogExcluded(_ excluded: Bool, for bufferID: BufferID) {
        var list = BufferScopeList(settings[.loggingExcludedBuffers])
        list.set(excluded, for: bufferID)
        settings[.loggingExcludedBuffers] = list.entries
    }

    public func setLogExcluded(_ excluded: Bool, network networkID: UUID) {
        var list = BufferScopeList(settings[.loggingExcludedBuffers])
        list.set(excluded, forNetwork: networkID)
        settings[.loggingExcludedBuffers] = list.entries
    }
}

/// Hosts that don't keep chat logs (tests) ignore the lines.
extension SessionHost {
    public func session(_ session: NetworkSession, didAdd line: ChatLine, to buffer: BufferModel) {}

    public func session(
        _ session: NetworkSession,
        didRedact line: ChatLine,
        by nick: String?,
        reason: String?,
        at time: Date,
        isHistory: Bool,
        in buffer: BufferModel
    ) {}
}
