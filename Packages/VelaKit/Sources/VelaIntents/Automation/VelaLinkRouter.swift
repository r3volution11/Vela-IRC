// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaCore

/// Follows `vela://` links (see ``VelaLink``). It only ever shows things:
/// it has no way to send a message, run a command or answer the page that
/// opened the link. A link Vela can't follow (malformed, an unknown
/// channel, a name on several networks) brings Vela forward with a short
/// notice saying why, and does nothing else.
@MainActor
public final class VelaLinkRouter {
    /// What following a link did, for tests and the notice.
    public enum Outcome: Equatable, Sendable {
        case shown
        /// Didn't follow it, for this reason (also shown as a notice).
        case refused(String)
        /// Ignored: the same link again, straight away.
        case throttled
    }

    private let automation: VelaAutomation
    private let now: () -> ContinuousClock.Instant
    private var last: (url: URL, at: ContinuousClock.Instant)?

    /// The same link opened again within this long is ignored, so a page
    /// can't pile up windows by opening one link over and over.
    static let repeatInterval: Duration = .seconds(1)

    public init(automation: VelaAutomation, now: @escaping () -> ContinuousClock.Instant = { ContinuousClock.now }) {
        self.automation = automation
        self.now = now
    }

    /// Follows `url`, if it's a Vela link (`vela://` or `vela-dev://`).
    @discardableResult
    public func open(_ url: URL) -> Outcome {
        let time = now()
        if let last, last.url == url, time - last.at < Self.repeatInterval { return .throttled }
        last = (url, time)
        guard let link = VelaLink.parse(url) else {
            return refuse("Vela doesn't know what to do with that link.")
        }
        return follow(link)
    }

    /// Follows a link already parsed.
    @discardableResult
    public func follow(_ link: VelaLink) -> Outcome {
        do {
            try perform(link)
            return .shown
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "Vela couldn't follow that link."
            return refuse(message)
        }
    }

    private func perform(_ link: VelaLink) throws {
        switch link {
        case .show:
            automation.presenter?.activate()
        case .open(let reference):
            let (_, buffer) = try automation.conversationOpeningQuery(reference)
            automation.show(buffer)
        case .join(let channel, let network):
            let session = try joinNetwork(network)
            try automation.offerToJoin(channel, on: session)
        case .catchUp(let reference):
            let target: (session: NetworkSession, buffer: BufferModel)
            if let reference {
                target = try automation.conversation(reference)
            } else if let busiest = automation.busiestUnread {
                target = busiest
            } else {
                automation.presenter?.activate()
                automation.presenter?.notice("You're all caught up.")
                return
            }
            do {
                try automation.openCatchUp(target.buffer, session: target.session)
            } catch {
                // Still worth showing the conversation, with why there's no card.
                automation.show(target.buffer)
                throw error
            }
        case .recap(let recap):
            var conversation: BufferID?
            var network: UUID?
            if let reference = recap.conversation {
                conversation = try automation.conversation(reference).buffer.id
            } else if let name = recap.network {
                network = try automation.network(name).id
            }
            let scope = automation.recapScope(conversation: conversation, network: network, person: recap.person, span: recap.span)
            try automation.openRecap(scope)
        case .draft(let reference, let text):
            let (_, buffer) = try automation.conversationOpeningQuery(reference)
            automation.show(buffer, draft: text)
        case .search(let query, let scope):
            switch scope {
            case nil:
                automation.search(query)
            case .network(let name):
                automation.search(query, networkID: try automation.network(name).id)
            case .conversation(let reference):
                automation.search(query, bufferID: try automation.conversation(reference).buffer.id)
            }
        }
    }

    /// The network a join link means: the one named, else the one you're
    /// looking at, else your only network.
    private func joinNetwork(_ name: String?) throws -> NetworkSession {
        if let name { return try automation.network(name) }
        let sessions = automation.app.automationSessions
        if let selected = automation.app.selectedSession, sessions.contains(where: { $0 === selected }) { return selected }
        if sessions.count == 1 { return sessions[0] }
        throw AutomationError.needsNetwork
    }

    private func refuse(_ message: String) -> Outcome {
        automation.presenter?.activate()
        automation.presenter?.notice(message)
        return .refused(message)
    }
}
