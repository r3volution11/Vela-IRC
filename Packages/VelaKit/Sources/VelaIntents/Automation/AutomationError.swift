// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaCore

/// Why an automation (an AppleScript command, a `vela://` link) couldn't do
/// what it was asked. The descriptions are what AppleScript reports and
/// what a link's notice says; ``scriptErrorNumber`` is the AppleScript
/// error number, part of Vela's scripting interface, so it never changes.
nonisolated public enum AutomationError: Error, Equatable, LocalizedError {
    case unknownNetwork(String)
    /// More than one network has that name.
    case ambiguousNetwork(String)
    /// You have several networks and none was named.
    case needsNetwork
    case unknownConversation(String)
    /// The name is on more than one network: say which.
    case ambiguousConversation(String)
    case notConnected(network: String)
    case notJoined(channel: String, network: String)
    /// Network consoles take commands, not messages.
    case serverBuffer(network: String)
    case emptyMessage
    /// More lines than the message box sends without asking.
    case tooManyLines(Int, limit: Int)
    /// More IRC messages than one command may send.
    case messageTooLong(Int, limit: Int)
    /// More characters than a draft may have (`draft message`).
    case draftTooLong(Int, limit: Int)
    /// More characters than a search may have (`search`).
    case queryTooLong(Int, limit: Int)
    case invalidChannelName(String)
    case noConnectedNetworks
    /// Catch me up or Recap is turned off in Settings.
    case turnedOff(String)
    /// The model Catch me up uses can't run (Apple Intelligence, when it
    /// isn't one of your own providers'), and why.
    case intelligenceUnavailable(String)
    /// Vela isn't ready to be scripted (it's still starting, or quitting).
    case notReady

    public var errorDescription: String? {
        switch self {
        case .unknownNetwork(let name): "Vela doesn't have a network called “\(name)”."
        case .ambiguousNetwork(let name): "More than one network is called “\(name)”: use its id."
        case .needsNetwork: "Say which network: you have more than one."
        case .unknownConversation(let name): "Vela couldn't find \(name)."
        case .ambiguousConversation(let name): "\(name) is on more than one network: say which."
        case .notConnected(let network): "You're not connected to \(network)."
        case .notJoined(let channel, let network): "You're not in \(channel) on \(network)."
        case .serverBuffer(let network): "You can't send messages to the \(network) console."
        case .emptyMessage: "There's nothing to send."
        case .tooManyLines(let count, let limit):
            "That's \(count) lines. The message box asks before sending more than \(limit); add “allowing multiple lines true” to send them."
        case .messageTooLong(let count, let limit):
            "That would be \(count) IRC messages; Vela sends at most \(limit) at once."
        case .draftTooLong(let count, let limit):
            "That's \(count.formatted()) characters; a draft can have at most \(limit.formatted())."
        case .queryTooLong(let count, let limit):
            "That's \(count.formatted()) characters; a search can have at most \(limit.formatted())."
        case .invalidChannelName(let name): "“\(name)” isn't a channel name."
        case .noConnectedNetworks: "You're not connected to any networks."
        case .turnedOff(let feature): "\(feature) is turned off in Vela's settings."
        case .intelligenceUnavailable(let detail): detail
        case .notReady: "Vela isn't ready yet. Try again in a moment."
        }
    }

    /// The AppleScript error number: -1728 (“can't get”) for something
    /// that isn't there, Vela's own numbers from 1000 for the rest.
    public var scriptErrorNumber: Int {
        switch self {
        case .unknownNetwork, .unknownConversation: -1728
        case .ambiguousNetwork, .ambiguousConversation, .needsNetwork: 1001
        case .notConnected, .noConnectedNetworks: 1002
        case .notJoined: 1003
        case .emptyMessage: 1004
        case .tooManyLines, .messageTooLong, .draftTooLong, .queryTooLong: 1005
        case .serverBuffer: 1006
        case .turnedOff: 1007
        case .intelligenceUnavailable: 1008
        case .invalidChannelName: 1009
        case .notReady: 1010
        }
    }

    /// `error` as one of these, if it's one of Vela's own.
    static func wrapping(_ error: any Error) -> any Error {
        guard let error = error as? AppActionError else { return error }
        return switch error {
        case .unknownBuffer: AutomationError.unknownConversation("that channel")
        case .unknownNetwork: AutomationError.unknownNetwork("that network")
        case .serverBuffer(let network): AutomationError.serverBuffer(network: network)
        case .notConnected(let network): AutomationError.notConnected(network: network)
        case .notJoined(let channel, let network): AutomationError.notJoined(channel: channel, network: network)
        case .noConnectedNetworks: AutomationError.noConnectedNetworks
        case .emptyMessage: AutomationError.emptyMessage
        case .invalidChannelName(let name): AutomationError.invalidChannelName(name)
        case .messageNotFound(let buffer): AutomationError.unknownConversation("that message in \(buffer)")
        }
    }
}
